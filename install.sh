#!/usr/bin/env bash
# tmux-ticker installer — fetches the plugin into ~/.config/tmux-ticker and
# prints the line to add to ~/.tmux.conf. First-party curl|bash, same category as
# rustup / homebrew / TPM: a readable, unobfuscated script you fetched over HTTPS.
#
# It also emits one anonymous install event (a random id + os/arch only, best-effort)
# so reach can be gauged; telemetry never blocks the install.
#
# Requires: bash, curl, tar. The marquee additionally needs jq at runtime
# (render.sh falls back to a static message when jq is absent).
set -euo pipefail

DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-ticker"
API="${TICKER_API:-https://ticker.aguilabs.com}"
mkdir -p "$DIR"

# Stable anonymous id — random bytes only. No fingerprinting, no machine name.
# `od -An -tx1` is portable across macOS/Linux (xxd isn't always installed).
[ -s "$DIR/id" ] || (head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$DIR/id")
ID="$(cat "$DIR/id")"

# Fetch the plugin at a PINNED tag (never main).
curl -fsSL https://github.com/liberatoaguilar/tmux-ticker/archive/refs/tags/v1.0.0.tar.gz \
  | tar -xz --strip-components=1 -C "$DIR"

# Fire the install event — anonymous, best-effort, never blocks the install.
curl -fsS -X POST "$API/api/event" \
  -H 'content-type: application/json' \
  -d "{\"install_id\":\"$ID\",\"type\":\"install\",\"os\":\"$(uname -s)\",\"arch\":\"$(uname -m)\"}" \
  >/dev/null 2>&1 || true

echo "Installed to $DIR"
echo "Add to ~/.tmux.conf:  run-shell $DIR/ticker.tmux"
echo "Toggle:  prefix + a"
