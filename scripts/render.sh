#!/usr/bin/env bash
# render.sh — continuous scroll + periodic /api/slot fetch + /api/beat (carousel-derived).
# Long-lived loop in the marquee pane. Stores $$ in @superchat_render_pid so refresh.sh
# can SIGUSR1 it; hides the cursor; restores it on exit. Renders INERT text only —
# nothing here is ever executed.
#
# Styling: the /api/slot message carries { bold, italic, rainbow, color } — the
# same flags the compose UI offers. We compose a full SGR sequence per frame so
# every style actually renders in the terminal (v1.0 only honored color).
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$CURRENT_DIR/variables.sh"; . "$CURRENT_DIR/helpers.sh"

API="$(get_tmux_option @superchat-api "$default_api")"
POLL="$(get_tmux_option @superchat-poll-s "$default_poll_s")"
FETCH="$(get_tmux_option @superchat-fetch-s "$default_fetch_s")"
IID="$("$CURRENT_DIR/install_id.sh")"
RST=$'\033[0m'

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

last_beat=0; last_fetch=0; i=0; text=""
bold=false; italic=false; rainbow=false
color="$(sgr_compose '' '#4a7abb')"
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
    elif [ -z "$text" ]; then
      text="tmux-superchat"
    fi
    last_fetch=$now
  fi
  if [ $((now - last_beat)) -ge 30 ]; then
    curl -fsS --max-time 2 -XPOST "$API/api/beat" -H "x-install-id: $IID" >/dev/null 2>&1 &
    last_beat=$now
  fi
  if [ "$rainbow" = "true" ]; then
    draw_frame_rainbow "$text" "$i"
  else
    draw_frame "$text" "$color" "$i"
  fi
  i=$((i + 1))
  sleep "$POLL" & wait $! 2>/dev/null   # USR1 interrupts the sleep -> immediate refetch
done
