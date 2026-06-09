#!/usr/bin/env bash
# uninstall.sh — disable superchat and remove only OUR contribution.
# Kill all @superchat_marquee panes,
# disable the plugin, and unbind the toggle key. We intentionally do NOT `set-hook -gu`
# the shared hook names (that would clear the whole hook array, including other plugins'
# appended handlers) — our disabled handlers self-exit via superchat_enabled().
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$CURRENT_DIR/variables.sh"; . "$CURRENT_DIR/helpers.sh"

set_tmux_option @superchat_enabled 0
list_marquee_panes | while read -r p; do tmux kill-pane -t "$p" 2>/dev/null; done

key="$(get_tmux_option @superchat-toggle-key "$default_toggle_key")"
tmux unbind-key "$key" 2>/dev/null || true
tmux display-message "superchat uninstalled"
