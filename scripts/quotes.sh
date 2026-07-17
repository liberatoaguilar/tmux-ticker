#!/usr/bin/env bash
# quotes.sh — per-machine singleton daemon. Polls Finnhub with the USER'S OWN
# key (FINNHUB_API_KEY) and writes a render-ready carousel cache the renderer
# reads. Quotes go straight from Finnhub to this machine; no Aguilabs server is
# ever involved. Wire format is byte-identical to src/lib/markets/carousel.ts
# (buildMarketsCarousel): kinds quote_hero/quote/mkt_closed, the two-space gaps,
# the ·/− tag ALWAYS LAST. bash 3.2 (no associative arrays, no ${v,,}).
#
#   quotes.sh CACHE_FILE SYMBOLS_CSV HERO WATCH_PID
#     CACHE_FILE    JSON cache path; the pidfile is CACHE_FILE.pid
#     SYMBOLS_CSV   comma-separated user symbols, e.g. NVDA,MSFT,AMD,TSLA
#     HERO          symbol pinned first with the gold ★ (may be empty)
#     WATCH_PID     tmux server PID; each loop iteration `kill -0`s it or exits
#
# QUOTES_ONESHOT=1 runs a single fetch cycle then exits (tests).
set -u
LC_NUMERIC=C
export LC_NUMERIC

# round_half_up VALUE DECIMALS — fixed-decimal string that byte-matches JS
# Number.prototype.toFixed (the wire oracle in src/lib/markets/carousel.ts:
# price.toFixed(2), Math.abs(changePct).toFixed(1)). NOT `printf '%.Nf'`:
# printf rounds half-to-EVEN, toFixed rounds half AWAY from zero, so on an
# exact binary tie (e.g. dp=4.25 -> printf "4.2" but toFixed "4.3"; price
# 10.125 -> printf "10.12" vs toFixed "10.13") the two diverge and the wire
# string mismatches — quarter-percent moves and eighth-dollar prices hit this.
# We instead print the double at high precision (revealing its true decimal,
# so genuine ties show "...5000" while near-ties like 4.35=4.34999… don't),
# then round-half-up on the exact digits with integer math. VALUE must be
# non-negative (callers pass the price and |dp|). LC_NUMERIC=C keeps the "."
# separator the ${s%.*}/${s#*.} splits assume.
round_half_up() {
  local val="$1" f="$2" s ip frac keep rest first m
  s=$(printf "%.$((f + 20))f" "$val" 2>/dev/null) || return 1
  ip=${s%.*}; frac=${s#*.}
  keep=${frac:0:f}; rest=${frac:f}; first=${rest:0:1}
  m=$(( ip * (10 ** f) + 10#${keep:-0} ))
  [ -n "$first" ] && [ "$first" -ge 5 ] && m=$((m + 1))
  if [ "$f" -eq 0 ]; then printf '%d' "$m"
  else printf '%d.%0*d' $((m / (10 ** f))) "$f" $((m % (10 ** f))); fi
}

CACHE_FILE="${1:-}"
SYMBOLS_CSV="${2:-}"
HERO_RAW="${3:-}"
WATCH_PID="${4:-}"

DELAY_LABEL="15m delay"   # Task 2 owns the tmux option; the fetcher is fixed.

# 1. Key gate: silent no-op without a key — nothing is written.
[ -n "${FINNHUB_API_KEY:-}" ] || exit 0
# curl/jq are hard requirements; absent → silent no-op (nothing written).
command -v curl >/dev/null 2>&1 || exit 0
command -v jq   >/dev/null 2>&1 || exit 0

# 3. Symbol cleaning: uppercase, strip everything outside A-Z0-9.-, max 8 chars.
clean_symbol() {
  local s
  s=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9.-')
  printf '%s' "${s:0:8}"
}

HERO=$(clean_symbol "$HERO_RAW")

# Split CSV, drop empties, cap 12 total.
SYMS=""
_scount=0
_oIFS=$IFS
IFS=,
for _raw in $SYMBOLS_CSV; do
  IFS=$_oIFS
  _sym=$(clean_symbol "$_raw")
  IFS=,
  [ -n "$_sym" ] || continue
  SYMS="$SYMS $_sym"
  _scount=$((_scount + 1))
  [ "$_scount" -ge 12 ] && break
done
IFS=$_oIFS

# 2. Singleton via pidfile. A rare double-start is harmless: writes are atomic.
PIDFILE="${CACHE_FILE}.pid"
if [ -f "$PIDFILE" ]; then
  _old=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$_old" ] && kill -0 "$_old" 2>/dev/null; then
    exit 0
  fi
fi
echo $$ > "$PIDFILE" 2>/dev/null || exit 0

# 4. US market state (America/New_York, DST-safe via `TZ=... date`). Holiday /
# early-close lists ported verbatim from src/lib/markets/marketState.ts.
us_market_state() {
  local dow hm ymd close hmn closen
  dow=$(TZ=America/New_York date +%u)
  hm=$(TZ=America/New_York date +%H%M)
  ymd=$(TZ=America/New_York date +%F)
  [ "$dow" -ge 6 ] && { echo closed; return; }
  case " 2026-01-01 2026-01-19 2026-02-16 2026-04-03 2026-05-25 2026-06-19 2026-07-03 2026-09-07 2026-11-26 2026-12-25 " in
    *" $ymd "*) echo closed; return ;;
  esac
  close=1600
  case "$ymd" in
    2026-11-27|2026-12-24) close=1300 ;;
  esac
  hmn=$((10#$hm)); closen=$((10#$close))
  if [ "$hmn" -ge 930 ] && [ "$hmn" -lt "$closen" ]; then echo open; return; fi
  if [ "$hmn" -ge 400 ] && [ "$hmn" -lt 930 ];      then echo pre;  return; fi
  if [ "$hmn" -ge "$closen" ] && [ "$hmn" -lt 2000 ]; then echo post; return; fi
  echo closed
}

# Per-symbol fetch results (parallel indexed arrays, insertion order).
RSYM=(); RPRICE=(); RPCT=(); RDIR=(); NRES=0

# 6. Fetch one symbol; on success push (symbol, priceStr, pctStr, dir).
fetch_symbol() {
  local S="$1" resp line price dp dir pricestr abs pctstr
  resp=$(curl -sf --max-time 10 "https://finnhub.io/api/v1/quote?symbol=$S&token=$FINNHUB_API_KEY" 2>/dev/null)
  [ -n "$resp" ] || return 0
  # jq: emit "price<TAB>dp<TAB>dir" or "SKIP". Skip when c null/≤0. Derive dp
  # from pc when dp is null and pc>0. Non-numeric anything → skip.
  line=$(printf '%s' "$resp" | jq -r '
    (.c) as $c | (.dp) as $dp | (.pc) as $pc |
    if ($c|type) != "number" or $c <= 0 then "SKIP"
    else
      ( if ($dp|type) == "number" then $dp
        elif ($pc|type) == "number" and $pc > 0 then ($c - $pc) / $pc * 100
        else null end ) as $d2 |
      if ($d2|type) != "number" then "SKIP"
      else "\($c)\t\($d2)\t\( if $d2 >= 0.05 then "up" elif $d2 <= -0.05 then "down" else "flat" end )"
      end
    end' 2>/dev/null)
  [ -n "$line" ] || return 0
  [ "$line" = "SKIP" ] && return 0
  price=${line%%$'\t'*}; line=${line#*$'\t'}
  dp=${line%%$'\t'*};    dir=${line##*$'\t'}
  pricestr=$(round_half_up "$price" 2) || return 0
  abs=${dp#-}
  pctstr=$(round_half_up "$abs" 1) || return 0
  RSYM[$NRES]=$S; RPRICE[$NRES]=$pricestr; RPCT[$NRES]=$pctstr; RDIR[$NRES]=$dir
  NRES=$((NRES + 1))
}

# 7. One quote WireItem (kind quote_hero when hero=true). Mirrors quoteSegs():
# ★/* star (gold), chalk "SYM PRICE", the change seg, gold "  ·LABEL" last.
quote_item() {
  local sym="$1" price="$2" pct="$3" dir="$4" hero="$5"
  jq -cn --arg sym "$sym" --arg price "$price" --arg pct "$pct" \
         --arg dir "$dir" --arg label "$DELAY_LABEL" --argjson hero "$hero" '
    ( if   $dir == "up"   then {a:"▲", p:"+", tone:"pitch"}
      elif $dir == "down" then {a:"▼", p:"-", tone:"alert"}
      else                     {a:"",  p:"",  tone:"dim"}   end) as $c |
    { kind: (if $hero then "quote_hero" else "quote" end),
      key: ("q:" + $sym),
      seg: ( (if $hero then [{t:"★ ", tone:"gold"}] else [] end)
             + [ {t: ($sym + " " + $price), tone:"chalk"},
                 {t: (" " + $c.a + $pct + "%"), tone: $c.tone},
                 {t: ("  ·" + $label), tone:"gold"} ] ),
      segPlain: ( (if $hero then [{t:"* ", tone:"gold"}] else [] end)
             + [ {t: ($sym + " " + $price), tone:"chalk"},
                 {t: (" " + $c.p + $pct + "%"), tone: $c.tone},
                 {t: ("  -" + $label), tone:"gold"} ] ) }'
}

# 7. The single closed-market WireItem. Mirrors closedSegs(): dim price, gold
# "  ·mkt closed" tag — never a bare price.
closed_item() {
  local sym="$1" price="$2"
  jq -cn --arg sym "$sym" --arg price "$price" '
    { kind:"mkt_closed", key:"mkt:closed",
      seg:      [ {t:($sym+" "+$price), tone:"dim"}, {t:"  ·mkt closed", tone:"gold"} ],
      segPlain: [ {t:($sym+" "+$price), tone:"dim"}, {t:"  -mkt closed", tone:"gold"} ] }'
}

# Assemble the carousel (one compact JSON object per line, for `jq -s`).
build_items() {
  local state="$1" hidx=-1 i order emitted ci ishero
  if [ -n "$HERO" ]; then
    for ((i=0; i<NRES; i++)); do
      if [ "${RSYM[$i]}" = "$HERO" ]; then hidx=$i; break; fi
    done
  fi
  if [ "$state" = "closed" ]; then
    ci=0; [ "$hidx" -ge 0 ] && ci=$hidx
    closed_item "${RSYM[$ci]}" "${RPRICE[$ci]}"
    return
  fi
  order=""
  [ "$hidx" -ge 0 ] && order="$hidx"
  for ((i=0; i<NRES; i++)); do
    [ "$i" = "$hidx" ] && continue
    order="$order $i"
  done
  emitted=0
  for i in $order; do
    [ "$emitted" -ge 12 ] && break
    ishero=false; [ "$i" = "$hidx" ] && ishero=true
    quote_item "${RSYM[$i]}" "${RPRICE[$i]}" "${RPCT[$i]}" "${RDIR[$i]}" "$ishero"
    emitted=$((emitted + 1))
  done
}

# One fetch cycle. Returns 1 (no write) when every symbol failed — the caller
# keeps the previous cache and retries.
run_cycle() {
  local state="$1" items carousel now cache tmpf
  RSYM=(); RPRICE=(); RPCT=(); RDIR=(); NRES=0
  local S
  for S in $SYMS; do fetch_symbol "$S"; done
  [ "$NRES" -eq 0 ] && return 1   # 9. all failed → keep previous cache
  items=$(build_items "$state")
  carousel=$(printf '%s\n' "$items" | jq -s -c '.')
  now=$(date +%s)
  # 8. Build with jq -n so quoting is always safe; write atomically (temp + mv).
  cache=$(jq -n --argjson fetchedAt "$now" --arg marketState "$state" \
                --argjson carousel "$carousel" \
                '{fetchedAt:$fetchedAt, marketState:$marketState, carousel:$carousel}')
  tmpf="${CACHE_FILE}.tmp.$$"
  printf '%s\n' "$cache" > "$tmpf" && mv -f "$tmpf" "$CACHE_FILE"
}

# ---- run --------------------------------------------------------------------
if [ "${QUOTES_ONESHOT:-}" = "1" ]; then
  run_cycle "$(us_market_state)"
  rm -f "$PIDFILE" 2>/dev/null
  exit 0
fi

# 5. Poll interval by state; sleep in ≤60s slices so WATCH_PID death is noticed
# within a minute.
sleep_slices() {
  local total="$1" slept=0 chunk
  while [ "$slept" -lt "$total" ]; do
    kill -0 "$WATCH_PID" 2>/dev/null || exit 0
    chunk=$((total - slept)); [ "$chunk" -gt 60 ] && chunk=60
    sleep "$chunk"
    slept=$((slept + chunk))
  done
}

while :; do
  kill -0 "$WATCH_PID" 2>/dev/null || exit 0   # each iteration: watch the tmux server
  state=$(us_market_state)
  if run_cycle "$state"; then
    case "$state" in
      open)     interval=60 ;;
      pre|post) interval=300 ;;
      *)        interval=1800 ;;
    esac
  else
    interval=60   # 9. all symbols failed → 60s backoff, retry
  fi
  sleep_slices "$interval"
done
