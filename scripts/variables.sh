#!/usr/bin/env bash
# variables.sh — user-facing options + internal markers.
# Namespaced so superchat can coexist with other tmux plugins.

# user-facing (override in .tmux.conf); read via get_tmux_option
default_api="https://superchat.aguilabs.com"   # @superchat-api
default_toggle_key="a"                          # @superchat-toggle-key  (prefix + a)
default_position="top"                          # @superchat-position : top | off
default_height="1"                              # @superchat-height (rows)
default_poll_s="0.12"                           # scroll frame interval
default_fetch_s="2"                             # /api/slot re-fetch interval
default_flags="auto"                            # @superchat-flags : auto | on | off — emoji team
                                                # flags in WC items (auto: macOS + tmux<3.6 only;
                                                # they flicker on tmux 3.6+, poor glyphs on Linux)

# internal markers / options (namespaced to coexist with other plugins)
MARQUEE_MARKER="@superchat_marquee"
RENDER_PID_OPTION="@superchat_render_pid"
ENABLED_OPTION="@superchat_enabled"
LAST_REFRESH_OPTION="@superchat_last_refresh_ms"
REFRESH_DEBOUNCE_MS="50"
