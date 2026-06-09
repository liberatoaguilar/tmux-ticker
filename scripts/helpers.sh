#!/usr/bin/env bash
# helpers.sh — option + pane helpers.

get_tmux_option() {
  local v
  v="$(tmux show-option -gqv "$1" 2>/dev/null)"
  [ -z "$v" ] && echo "$2" || echo "$v"
}

set_tmux_option() { tmux set-option -g "$1" "$2"; }

get_pane_option() {
  local v
  v="$(tmux show-option -pqv -t "$1" "$2" 2>/dev/null)"
  [ -z "$v" ] && echo "$3" || echo "$v"
}

set_pane_option() { tmux set-option -p -t "$1" "$2" "$3"; }

find_marquee_pane() {
  tmux list-panes -t "$1" -F '#{pane_id} #{@superchat_marquee}' 2>/dev/null | awk '$2=="1"{print $1; exit}'
}

window_has_marquee() { [ -n "$(find_marquee_pane "$1")" ]; }

list_marquee_panes() {
  tmux list-panes -a -F '#{pane_id} #{@superchat_marquee}' 2>/dev/null | awk '$2=="1"{print $1}'
}

superchat_enabled() {
  [ "$(get_tmux_option @superchat_enabled 1)" = "1" ] && [ "$(get_tmux_option @superchat-position top)" != "off" ]
}

# Current epoch milliseconds (for the refresh debounce). BSD/macOS `date` does NOT
# support %N/%3N (it emits a literal "N"), so `date +%s%3N` yields a corrupt value
# that breaks the debounce arithmetic. Prefer perl (ms
# precision, ~0-2ms), then python3, and fall back to seconds*1000 only as a last
# resort (1s resolution — coarser but still-correct debounce). Always prints a clean integer.
now_ms() {
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time; print(int(time.time()*1000))'
  else
    echo $(( $(date +%s) * 1000 ))
  fi
}
