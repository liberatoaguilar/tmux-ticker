#!/usr/bin/env bash
# create_marquee.sh — idempotent per-window TOP 1-row pane.
# ticker owns the top row (-v), leaving other pane regions free.
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$CURRENT_DIR/variables.sh"; . "$CURRENT_DIR/helpers.sh"

WINDOW_ID="$1"; [ -n "$WINDOW_ID" ] || exit 0
ticker_enabled || exit 0
window_has_marquee "$WINDOW_ID" && exit 0

SERVER_PID="$(tmux display-message -p '#{pid}')"
# Deterministic lock name (server pid + window id) is INTENTIONAL: concurrent
# after-new-window / after-new-session hooks for the same window must collapse to
# ONE marquee. Do NOT switch to `mktemp -d` — a unique dir per call defeats the dedup.
LOCK_DIR="${TMPDIR:-/tmp}/ticker_${SERVER_PID}_${WINDOW_ID//[^a-zA-Z0-9]/_}"
mkdir "$LOCK_DIR" 2>/dev/null || exit 0          # another hook won the race
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
window_has_marquee "$WINDOW_ID" && exit 0        # recheck after lock

height="$(get_tmux_option @ticker-height "$default_height")"
pane_id="$(tmux split-window -vbfd -l "$height" -t "$WINDOW_ID" -P -F '#{pane_id}' \
  "$CURRENT_DIR/render.sh" 2>/dev/null || true)"
[ -n "$pane_id" ] && set_pane_option "$pane_id" "$MARQUEE_MARKER" 1
