#!/usr/bin/env bash
# toggle.sh — global on/off across ALL windows (prefix + a).
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$CURRENT_DIR/variables.sh"; . "$CURRENT_DIR/helpers.sh"

if [ "$(get_tmux_option @superchat_enabled 1)" = "1" ]; then
  set_tmux_option @superchat_enabled 0
  list_marquee_panes | while read -r p; do tmux kill-pane -t "$p" 2>/dev/null; done
  tmux display-message "superchat off"
else
  set_tmux_option @superchat_enabled 1
  tmux list-windows -a -F '#{window_id}' | while read -r w; do "$CURRENT_DIR/create_marquee.sh" "$w"; done
  tmux display-message "superchat on"
fi
