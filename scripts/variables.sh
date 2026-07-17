#!/usr/bin/env bash
# variables.sh — user-facing options + internal markers.
# Namespaced so the ticker can coexist with other tmux plugins.

# user-facing (override in .tmux.conf); read via get_tmux_option
default_api="https://ticker.aguilabs.com"       # @ticker-api
default_toggle_key="a"                          # @ticker-toggle-key  (prefix + a)
default_position="top"                          # @ticker-position : top | off
default_height="1"                              # @ticker-height (rows)
default_poll_s="0.12"                           # scroll frame interval
default_fetch_s="2"                             # /api/slot re-fetch interval
default_emoji="auto"                            # @ticker-emoji : auto | on | off — emoji glyphs in
                                                # carousel items. off ⇒ ASCII-only segPlain;
                                                # auto/on ⇒ emoji seg variants.
default_markets="on"                            # @ticker-markets : on | off — rotate the markets
                                                # carousel between slot messages (off ⇒ slot only)

# internal markers / options (namespaced to coexist with other plugins)
MARQUEE_MARKER="@ticker_marquee"
RENDER_PID_OPTION="@ticker_render_pid"
ENABLED_OPTION="@ticker_enabled"
LAST_REFRESH_OPTION="@ticker_last_refresh_ms"
REFRESH_DEBOUNCE_MS="50"
