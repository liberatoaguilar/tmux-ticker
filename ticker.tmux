#!/usr/bin/env bash
# ticker.tmux — TPM entry: hooks for all-windows presence + toggle keybind
# Coexists with other pane-owning tmux plugins via orthogonal geometry,
# distinct pane markers, and APPENDED hooks (-ga) so we don't clobber other plugins' hooks.
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$CURRENT_DIR/scripts/variables.sh"; . "$CURRENT_DIR/scripts/helpers.sh"
S="$CURRENT_DIR/scripts"

[ "$(get_tmux_option @ticker-position "$default_position")" = "off" ] && exit 0
key="$(get_tmux_option @ticker-toggle-key "$default_toggle_key")"

# cross-window presence. Use -ga (APPEND) so we don't clobber other plugins' handlers on the
# same hook names — tmux runs every appended command for that hook, in order. The hooks
# use `run-shell -b` (background) so window creation never blocks on the marquee spawn.
tmux set-hook -ga after-new-window       "run-shell -b '$S/create_marquee.sh #{window_id}'"
tmux set-hook -ga after-new-session      "run-shell -b '$S/create_marquee.sh #{window_id}'"
tmux set-hook -ga window-layout-changed  "run-shell -b '$S/layout_changed.sh #{window_id}'"
tmux set-hook -ga session-window-changed "run-shell -b '$S/refresh.sh'"
tmux set-hook -ga window-renamed         "run-shell -b '$S/refresh.sh'"

tmux bind-key "$key" run-shell "$S/toggle.sh"

# Make styled marquee messages render: enable 24-bit truecolor passthrough (so colors
# and the rainbow palette arrive exact instead of being quantized) and italics (tmux
# strips \E[3m unless the terminal advertises sitm). Appended with -as/-ga so we never
# clobber the user's or other plugins' settings; harmless on terminals that ignore them.
# (Blink, \E[5m, is up to the outer terminal — many disable it; that's expected.)
tmux set -as terminal-overrides ',*:Tc:sitm=\E[3m:ritm=\E[23m' 2>/dev/null
tmux set -as terminal-features ',*:RGB' 2>/dev/null

# populate existing windows on load
tmux list-windows -a -F '#{window_id}' | while read -r w; do
  tmux run-shell -b "$S/create_marquee.sh $w"
done
