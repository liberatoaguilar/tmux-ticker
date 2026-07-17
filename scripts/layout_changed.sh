#!/usr/bin/env bash
# layout_changed.sh — resurrect missing marquees; never touch other plugins' panes.
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$CURRENT_DIR/variables.sh"; . "$CURRENT_DIR/helpers.sh"

ticker_enabled || exit 0
WINDOW_ID="$1"; [ -n "$WINDOW_ID" ] || exit 0
window_has_marquee "$WINDOW_ID" || "$CURRENT_DIR/create_marquee.sh" "$WINDOW_ID"
# deliberately does NOT inspect/resize panes it doesn't own — orthogonal ownership
# (ticker owns the top row via -y) avoids the resize-storm race.
