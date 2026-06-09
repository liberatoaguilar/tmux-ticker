#!/usr/bin/env bash
# refresh.sh — debounced SIGUSR1 to every marquee.
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$CURRENT_DIR/variables.sh"; . "$CURRENT_DIR/helpers.sh"

# Global per-server debounce to avoid SIGUSR1 storms on rapid events. now_ms() is
# portable (BSD/macOS `date` lacks %N); see helpers.sh.
now="$(now_ms)"
last="$(get_tmux_option "$LAST_REFRESH_OPTION" 0)"
[ "$((now - last))" -lt "$REFRESH_DEBOUNCE_MS" ] && exit 0
set_tmux_option "$LAST_REFRESH_OPTION" "$now"

list_marquee_panes | while read -r p; do
  pid="$(get_pane_option "$p" "$RENDER_PID_OPTION" "")"
  [ -n "$pid" ] && kill -USR1 "$pid" 2>/dev/null
done

# Never exit non-zero from a tmux hook: a failure surfaces as the pane dropping
# into view-mode. Swallow the loop's status.
exit 0
