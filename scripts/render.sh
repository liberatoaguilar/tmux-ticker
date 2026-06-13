#!/usr/bin/env bash
# render.sh — continuous scroll + periodic /api/slot fetch + /api/beat (carousel-derived).
# Long-lived loop in the marquee pane. Stores $$ in @superchat_render_pid so refresh.sh
# can SIGUSR1 it; hides the cursor; restores it on exit. Renders INERT text only —
# nothing here is ever executed.
#
# Styling: the /api/slot message carries { bold, italic, rainbow, color } — the
# same flags the compose UI offers. We compose a full SGR sequence per frame so
# every style actually renders in the terminal (v1.0 only honored color).
#
# World Cup carousel (v1.2): /api/slot may also carry `.carousel` — render-ready
# items ({kind,key,seg[],segPlain[]}, tones pitch|gold|chalk|alert|dim). When
# present we rotate 3 WC items : 1 slot item (the slot keeps the exact v1.0 paid/
# house render path above), each dwelling ~6-10s. An unseen `goal` key interrupts
# immediately with the product's ONLY flash. Missing/empty carousel ⇒ pure v1.0
# behavior, so old servers without the field keep working.
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$CURRENT_DIR/variables.sh"; . "$CURRENT_DIR/helpers.sh"

API="$(get_tmux_option @superchat-api "$default_api")"
POLL="$(get_tmux_option @superchat-poll-s "$default_poll_s")"
FETCH="$(get_tmux_option @superchat-fetch-s "$default_fetch_s")"
IID="$("$CURRENT_DIR/install_id.sh")"
RST=$'\033[0m'

# Emoji team flags: @superchat-flags auto|on|off (auto: on for Darwin only —
# Linux terminal flag glyphs are unreliable). Decided ONCE at startup: `seg` and
# `segPlain` are never mixed within a process.
case "$(get_tmux_option @superchat-flags "$default_flags")" in
  on)  SEGF="seg" ;;
  off) SEGF="segPlain" ;;
  *)   if [ "$(uname 2>/dev/null)" = "Darwin" ]; then SEGF="seg"; else SEGF="segPlain"; fi ;;
esac

# Truecolor detection. Inside tmux $COLORTERM is frequently unset even when the
# terminal supports 24-bit, which would drop us to a 16-color path that collapses
# the rainbow palette into ~3 buckets. So: truecolor if $COLORTERM says so, OR if
# the terminal exposes >=256 colors (tmux-256color/xterm-256color) — emitting 24-bit
# then lets tmux map to the best the outer terminal can do. superchat.tmux also
# enables the Tc/RGB passthrough so the colors arrive exact.
TRUECOLOR=0
case "$COLORTERM" in
  truecolor | 24bit) TRUECOLOR=1 ;;
esac
[ "$TRUECOLOR" = 0 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 256 ] && TRUECOLOR=1

# Nord aurora+frost palette for rainbow mode (per-character cycling).
RB_PALETTE=( "#bf616a" "#d08770" "#ebcb8b" "#a3be8c" "#88c0d0" "#81a1c1" "#b48ead" )

trap ':' USR1                       # USR1 interrupts the sleep -> immediate refetch
trap 'printf "\033[?25h"' EXIT      # restore cursor
printf '\033[?25l'                  # hide cursor

set_pane_option "$(tmux display-message -p '#{pane_id}')" "$RENDER_PID_OPTION" "$$"

# sgr_compose ATTRS "#rrggbb" -> one composite SGR sequence.
# ATTRS is a pre-built "1;3;"-style attribute prefix (bold;italic), possibly
# empty. Truecolor when $COLORTERM is set, else a nearest-16 fallback by max channel.
sgr_compose() {
  local attrs="$1" hex="${2#\#}" r g b
  r=$((16#${hex:0:2})); g=$((16#${hex:2:2})); b=$((16#${hex:4:2}))
  if [ "$TRUECOLOR" = 1 ]; then
    printf '\033[%s38;2;%d;%d;%dm' "$attrs" "$r" "$g" "$b"
  else
    local c=36
    if   [ "$r" -ge "$g" ] && [ "$r" -ge "$b" ]; then c=31
    elif [ "$g" -ge "$r" ] && [ "$g" -ge "$b" ]; then c=32; fi
    printf '\033[%s%dm' "$attrs" "$c"
  fi
}

# WC tone palette (contract §6). Truecolor exact; the 16-color fallback is a FIXED
# table (pitch 32, gold 33, chalk 37, alert 31, dim 90) — sgr_compose's
# nearest-channel guess would land gold/chalk/dim on the wrong codes.
tone_sgr() {
  local hex="$1" r g b
  if [ "$TRUECOLOR" = 1 ]; then
    r=$((16#${hex:0:2})); g=$((16#${hex:2:2})); b=$((16#${hex:4:2}))
    printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
  else
    printf '\033[%dm' "$2"
  fi
}
T_PITCH="$(tone_sgr 1E7A3C 32)"; T_GOLD="$(tone_sgr D4A017 33)"
T_CHALK="$(tone_sgr F2F0E6 37)"; T_ALERT="$(tone_sgr E8413C 31)"; T_DIM="$(tone_sgr 6B7280 90)"
# Goal flash: full line inverted, alert bg + chalk fg — the ONLY flash in the
# product (paid styles keep their own distinct effects; nothing else ever blinks).
if [ "$TRUECOLOR" = 1 ]; then
  FLASH_SGR="$(printf '\033[48;2;232;65;60m\033[38;2;242;240;230m')"
else
  FLASH_SGR="$(printf '\033[41;97m')"
fi

# tone_of NAME — sets REPLY to the pre-composed SGR (no subshell; called at item
# build time). Unknown tones degrade to chalk so newer servers stay renderable.
tone_of() {
  case "$1" in
    pitch) REPLY="$T_PITCH" ;;
    gold)  REPLY="$T_GOLD" ;;
    alert) REPLY="$T_ALERT" ;;
    dim)   REPLY="$T_DIM" ;;
    *)     REPLY="$T_CHALK" ;;
  esac
}

fetch() { curl -fsS --max-time 2 "$API/api/slot" 2>/dev/null; }

# draw_frame TEXT COLOR INDEX — one colored scroll frame; flicker-free (\033[H … \033[K).
# Wraps the ribbon (text + separator) and slices a window of `cols-2` chars. COLOR is a
# full SGR sequence (attributes + foreground) applied to the whole window.
draw_frame() {
  local text="$1" color="$2" i="$3"
  local sep="   •   "
  local ribbon="${text}${sep}"
  local rlen=${#ribbon}
  [ "$rlen" -lt 1 ] && rlen=1
  local sz cols win out pos m take avail
  sz=$(stty size 2>/dev/null); cols=${sz#* }; [ -n "$cols" ] || cols=80
  win=$(( cols - 2 )); [ "$win" -lt 1 ] && win=1
  out=""; pos=$(( i % rlen ))
  local remaining=$win
  while [ "$remaining" -gt 0 ]; do
    m=$(( pos % rlen ))
    avail=$(( rlen - m ))
    take=$avail; [ "$take" -gt "$remaining" ] && take=$remaining
    out="${out}${ribbon:m:take}"
    remaining=$(( remaining - take ))
    pos=$(( pos + take ))
  done
  printf '\033[H %s%s%s\033[K' "$color" "$out" "$RST"
}

# draw_frame_rainbow TEXT INDEX — like draw_frame but colors each character by its
# ribbon position so the palette scrolls with the text. Uses the pre-built RB[] array
# (full SGR per palette entry, already carrying any bold/italic attrs), so the
# hot loop does no subshells.
draw_frame_rainbow() {
  local text="$1" i="$2"
  local sep="   •   "
  local ribbon="${text}${sep}"
  local rlen=${#ribbon}
  [ "$rlen" -lt 1 ] && rlen=1
  local sz cols win out pos m n k
  sz=$(stty size 2>/dev/null); cols=${sz#* }; [ -n "$cols" ] || cols=80
  win=$(( cols - 2 )); [ "$win" -lt 1 ] && win=1
  n=${#RB[@]}; [ "$n" -lt 1 ] && n=1
  out=""; pos=$(( i % rlen )); k=0
  while [ "$k" -lt "$win" ]; do
    m=$(( pos % rlen ))
    out="${out}${RB[$(( m % n ))]}${ribbon:m:1}"
    pos=$(( pos + 1 )); k=$(( k + 1 ))
  done
  printf '\033[H %s%s\033[K' "$out" "$RST"
}

# draw_frame_toned INDEX — the rainbow machinery generalized: CT[] maps each ribbon
# CHAR to its segment's tone SGR (built once per item in build_wc_item), so
# multi-segment items render multi-tone with no per-frame subshell work.
draw_frame_toned() {
  local i="$1"
  local rlen=${#TONED_RIBBON}
  [ "$rlen" -lt 1 ] && rlen=1
  local sz cols win out pos m k
  sz=$(stty size 2>/dev/null); cols=${sz#* }; [ -n "$cols" ] || cols=80
  win=$(( cols - 2 )); [ "$win" -lt 1 ] && win=1
  out=""; pos=$(( i % rlen )); k=0
  while [ "$k" -lt "$win" ]; do
    m=$(( pos % rlen ))
    out="${out}${CT[$m]}${TONED_RIBBON:m:1}"
    pos=$(( pos + 1 )); k=$(( k + 1 ))
  done
  printf '\033[H %s%s\033[K' "$out" "$RST"
}

# draw_frame_flash — the ~1s goal invert: the current goal's text, static (readable
# at a glance), padded to the window so the WHOLE line carries the alert bg.
# Padding counts CHARS; double-width emoji can overshoot slightly — same accepted
# stance as the scroll paths (\033[K cleans up after us).
draw_frame_flash() {
  local sz cols win out k len
  sz=$(stty size 2>/dev/null); cols=${sz#* }; [ -n "$cols" ] || cols=80
  win=$(( cols - 2 )); [ "$win" -lt 1 ] && win=1
  len=${#ITEM_TEXT}; [ "$len" -gt "$win" ] && len=$win
  out="${ITEM_TEXT:0:len}"; k=$len
  while [ "$k" -lt "$win" ]; do out="${out} "; k=$(( k + 1 )); done
  printf '\033[H %s%s%s\033[K' "$FLASH_SGR" "$out" "$RST"
}

# build_wc_item IDX — materialize one carousel item for the toned scroller, ONCE
# per item (never in the frame loop). Splits WC_SEGS[IDX] ("tone US text US …")
# and builds ITEM_TEXT (concatenated segments — the flash uses it), TONED_RIBBON
# (text + dim separator) and CT[] (one SGR per ribbon char; ${#}/${:} are CHAR
# semantics under the UTF-8 locale, so emoji and flags index cleanly).
build_wc_item() {
  local rest="${WC_SEGS[$1]}" tone t j L
  ITEM_TEXT=""; CT=()
  while [ -n "$rest" ]; do
    case "$rest" in
      *"$FS"*) tone="${rest%%"$FS"*}"; rest="${rest#*"$FS"}" ;;
      *) break ;;                                    # dangling tone with no text — drop
    esac
    case "$rest" in
      *"$FS"*) t="${rest%%"$FS"*}"; rest="${rest#*"$FS"}" ;;
      *) t="$rest"; rest="" ;;
    esac
    tone_of "$tone"
    L=${#t}; j=0
    while [ "$j" -lt "$L" ]; do CT+=( "$REPLY" ); j=$(( j + 1 )); done
    ITEM_TEXT="${ITEM_TEXT}${t}"
  done
  local sep="   •   "
  TONED_RIBBON="${ITEM_TEXT}${sep}"
  L=${#sep}; j=0
  while [ "$j" -lt "$L" ]; do CT+=( "$T_DIM" ); j=$(( j + 1 )); done
}

# parse_carousel — one jq pass flattens $json's .carousel into "kind US key US
# tone US text…" lines (US = 0x1f, jq-built so no escape ambiguity). explode/
# implode scrubs every control char from every field: C0 (including our
# separator), DEL, and C1 U+0080–U+009F — U+009B is a one-byte CSI and U+0085 a
# NEL, so they must never reach the terminal byte stream. The server sanitizes
# these too; this scrub is defense-in-depth and must hold on its own. Missing
# carousel / old server / jq error all land on wc_count=0 ⇒ v1.0 behavior.
parse_carousel() {
  WC_KIND=(); WC_KEY=(); WC_SEGS=(); wc_count=0
  local lines line kind rest key segs
  lines="$(printf '%s' "$json" | jq -r --arg segf "$SEGF" '
    (.carousel // [])[]?
    | [ (.kind // ""), (.key // ""), ((.[$segf] // [])[]? | (.tone // ""), (.t // "")) ]
    | map(tostring | explode | map(if . < 32 or (. >= 127 and . <= 159) then 32 else . end) | implode)
    | join([31] | implode)' 2>/dev/null)"
  [ -n "$lines" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    kind="${line%%"$FS"*}"; rest="${line#*"$FS"}"
    case "$rest" in
      *"$FS"*) key="${rest%%"$FS"*}"; segs="${rest#*"$FS"}" ;;
      *)       key="$rest"; segs="" ;;
    esac
    [ -n "$segs" ] || continue                       # no segments ⇒ nothing to render
    WC_KIND+=( "$kind" ); WC_KEY+=( "$key" ); WC_SEGS+=( "$segs" )
    wc_count=$(( wc_count + 1 ))
  done <<< "$lines"
}

# goal_seen KEY — membership test against the in-memory seen set. Plain indexed
# array + string equality: bash 3.2 (macOS default) has no associative arrays,
# and equality keeps untrusted keys out of any pattern/glob context.
goal_seen() {
  local k
  for k in "${SEEN_GOALS[@]}"; do [ "$k" = "$1" ] && return 0; done
  return 1
}

# check_goals — fire the flash for the first carousel goal this process hasn't
# shown. Runs at fetch granularity (2s) ⇒ "immediate" interrupt of whatever is
# dwelling. While a flash/hold is on screen, later goals stay unmarked and fire
# right after it — one full moment per goal, no flash pile-up. Seen/expired goals
# keep rotating as normal alert items while the server carries them.
check_goals() {
  case "$cur_type" in flash | hold) return 0 ;; esac
  local gi=0
  while [ "$gi" -lt "$wc_count" ]; do
    if [ "${WC_KIND[$gi]}" = "goal" ] && ! goal_seen "${WC_KEY[$gi]}"; then
      SEEN_GOALS+=( "${WC_KEY[$gi]}" )
      build_wc_item "$gi"
      cur_type="flash"; frames_left=$FLASH_FRAMES; f=0
      return 0
    fi
    gi=$(( gi + 1 ))
  done
  return 0
}

# start_item_frames RIBBON_CHARS — dwell = one pass of the ribbon across the
# window (rlen + win frames), clamped to 50..83 ⇒ ~6..10s at the 0.12s frame rate.
start_item_frames() {
  local sz cols win
  sz=$(stty size 2>/dev/null); cols=${sz#* }; [ -n "$cols" ] || cols=80
  win=$(( cols - 2 )); [ "$win" -lt 1 ] && win=1
  frames_left=$(( $1 + win ))
  [ "$frames_left" -lt 50 ] && frames_left=50
  [ "$frames_left" -gt 83 ] && frames_left=83
}

# advance_item — playlist step, called only when frames_left hits 0: flash → hold
# (alert line for the rest of the 10s), otherwise 3 WC items then 1 slot item.
# The slot item is the v1.0 paid/house path, untouched — its `i` keeps counting
# across dwells so the message resumes scrolling where it left off.
advance_item() {
  if [ "$cur_type" = "flash" ]; then
    cur_type="hold"; f=0; frames_left=$HOLD_FRAMES
    return
  fi
  if [ "$wc_run" -lt 3 ] && [ "$wc_count" -gt 0 ]; then
    build_wc_item $(( wc_pos % wc_count ))
    wc_pos=$(( (wc_pos + 1) % wc_count )); wc_run=$(( wc_run + 1 ))
    cur_type="wc"; f=0
    start_item_frames ${#TONED_RIBBON}
  else
    cur_type="slot"; wc_run=0
    start_item_frames $(( ${#text} + 7 ))            # +7: the "   •   " sep draw_frame appends
  fi
}

last_beat=0; last_fetch=0; i=0; text=""
bold=false; italic=false; rainbow=false
color="$(sgr_compose '' '#4a7abb')"

# Carousel playlist state — all in-memory: a fresh process re-learns goal keys by
# design (the seen set only stops the SAME process flashing a key twice).
FS="$(printf '\037')"               # US field separator (scrubbed from data in parse_carousel)
WC_KIND=(); WC_KEY=(); WC_SEGS=(); wc_count=0
SEEN_GOALS=()
cur_type=""                          # "" pick-next | wc | slot | flash | hold
frames_left=0; f=0                   # f = frame index within the current toned item
wc_pos=0; wc_run=0                   # next WC index; WC items shown since last slot item
FLASH_FRAMES=8                       # ~1s invert at the 0.12s frame rate
HOLD_FRAMES=75                       # rest of the ~10s goal hold (8 + 75 ≈ 10s)

while :; do
  now=$(date +%s)
  if [ $((now - last_fetch)) -ge "${FETCH%.*}" ] || [ -z "$text" ]; then
    json="$(fetch)"
    # jq is mandatory for SAFE JSON parsing: server text is only ever read as a jq
    # value and passed to printf as an ARGUMENT (never the format string, never
    # shell-eval'd). Without jq we skip the body and show a static default rather
    # than hand-parse untrusted content.
    if [ -n "$json" ] && command -v jq >/dev/null 2>&1; then
      text="$(printf '%s' "$json" | jq -r '.message.text // ""')"
      hex="$(printf '%s' "$json" | jq -r '.message.style.color // "#4a7abb"')"
      bold="$(printf '%s' "$json" | jq -r '.message.style.bold // false')"
      italic="$(printf '%s' "$json" | jq -r '.message.style.italic // false')"
      rainbow="$(printf '%s' "$json" | jq -r '.message.style.rainbow // false')"
      attrs=""
      [ "$bold" = "true" ]   && attrs="${attrs}1;"
      [ "$italic" = "true" ] && attrs="${attrs}3;"
      if [ "$rainbow" = "true" ]; then
        RB=(); for h in "${RB_PALETTE[@]}"; do RB+=( "$(sgr_compose "$attrs" "$h")" ); done
      else
        color="$(sgr_compose "$attrs" "$hex")"
      fi
      parse_carousel
      check_goals
    elif [ -z "$text" ]; then
      text="tmux-superchat"
    fi
    last_fetch=$now
  fi
  if [ $((now - last_beat)) -ge 30 ]; then
    curl -fsS --max-time 2 -XPOST "$API/api/beat" -H "x-install-id: $IID" >/dev/null 2>&1 &
    last_beat=$now
  fi
  if [ "$wc_count" -eq 0 ] && [ "$cur_type" != "flash" ] && [ "$cur_type" != "hold" ]; then
    # No WC items ⇒ pure v1.0: continuous wrapped scroll of the slot message.
    # (An in-flight goal flash/hold still completes off its cached build.)
    cur_type=""; frames_left=0; wc_run=0
    if [ "$rainbow" = "true" ]; then
      draw_frame_rainbow "$text" "$i"
    else
      draw_frame "$text" "$color" "$i"
    fi
    i=$(( i + 1 ))
  else
    [ "$frames_left" -le 0 ] && advance_item
    case "$cur_type" in
      flash) draw_frame_flash ;;
      slot)
        if [ "$rainbow" = "true" ]; then
          draw_frame_rainbow "$text" "$i"
        else
          draw_frame "$text" "$color" "$i"
        fi
        i=$(( i + 1 )) ;;
      *) draw_frame_toned "$f"; f=$(( f + 1 )) ;;   # wc items + the goal hold
    esac
    frames_left=$(( frames_left - 1 ))
  fi
  sleep "$POLL" & wait $! 2>/dev/null   # USR1 interrupts the sleep -> immediate refetch
done
