#!/usr/bin/env bash
# tmux-ticker installer — fetches the plugin into ~/.config/tmux-ticker and
# prints the line to add to ~/.tmux.conf. First-party curl|bash, same category as
# rustup / homebrew / TPM: a readable, unobfuscated script you fetched over HTTPS.
#
# It also doubles as the install-event emitter: os/arch only, fired best-effort so
# telemetry never blocks the install. The install NAMES NO ID — the server mints
# one and hands back the signed token this install echoes from then on.
#
# Requires: bash, curl, tar. The marquee additionally needs jq at runtime
# (render.sh falls back to a static message when jq is absent).
set -euo pipefail

DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-ticker"
API="${TICKER_API:-https://ticker.aguilabs.com}"
mkdir -p "$DIR"

# Fetch the plugin at a PINNED tag (never main). v1.0.1 = the first tag carrying the
# token contract (scripts/install_id.sh as the token store, `x-ticker-token` in
# render.sh) — push the tag to the plugin repo BEFORE deploying the server's
# install.sh. A tag older than that still works: its beats 401 and, once it is
# updated, self-heal.
curl -fsSL https://github.com/liberatoaguilar/tmux-ticker/archive/refs/tags/v1.0.1.tar.gz \
  | tar -xz --strip-components=1 -C "$DIR"

# Fire the install event — anonymous, best-effort, never blocks the install.
# /api/event is also the ISSUING route: its reply carries the presence token this
# install must echo on every later /api/beat (`x-ticker-token`), so we capture the
# body instead of discarding it and store the token 0600 in $DIR/token. The shape
# gate keeps a garbled/hostile body out of the file. If this call never lands
# (offline, proxied, blocked) nothing is lost: the marquee's first beat gets a 401
# carrying a fresh token and stores it then. This is why the install NEVER invents
# an id of its own — a caller-chosen id was the primary key of a service-key write.
RESP="$(curl -fsS -X POST "$API/api/event" \
  -H 'content-type: application/json' \
  -d "{\"type\":\"install\",\"os\":\"$(uname -s)\",\"arch\":\"$(uname -m)\"}" 2>/dev/null || true)"
TOKEN="$(printf '%s' "$RESP" |
  sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
case "$TOKEN" in
  t1.*.*) ( umask 077; printf '%s' "$TOKEN" > "$DIR/token" ) && chmod 600 "$DIR/token" ;;
  *) : ;;   # no token in hand — the first beat bootstraps one
esac

echo "Installed to $DIR"
echo "Add to ~/.tmux.conf:  run-shell $DIR/ticker.tmux"
echo "Toggle:  prefix + a"
