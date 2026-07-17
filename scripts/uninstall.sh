#!/usr/bin/env bash
# uninstall.sh — disable the ticker and remove only OUR contribution.
# Kill all @ticker_marquee panes,
# disable the plugin, and unbind the toggle key. We intentionally do NOT `set-hook -gu`
# the shared hook names (that would clear the whole hook array, including other plugins'
# appended handlers) — our disabled handlers self-exit via ticker_enabled().
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$CURRENT_DIR/variables.sh"; . "$CURRENT_DIR/helpers.sh"

set_tmux_option @ticker_enabled 0
list_marquee_panes | while read -r p; do tmux kill-pane -t "$p" 2>/dev/null; done

key="$(get_tmux_option @ticker-toggle-key "$default_toggle_key")"
tmux unbind-key "$key" 2>/dev/null || true
tmux display-message "ticker uninstalled"
