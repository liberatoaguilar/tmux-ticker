#!/usr/bin/env bash
# install_id.sh — generate/read a stable per-install terminal id.
ID_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-ticker/id"
mkdir -p "$(dirname "$ID_FILE")"
# Prefer uuidgen; else portable random hex (od/urandom, as in install.sh). Never
# `date +%s%N` — BSD/macOS emit a literal "N", yielding malformed, collidable ids.
[ -s "$ID_FILE" ] || {
  if command -v uuidgen >/dev/null 2>&1; then uuidgen
  else head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n'; fi
} > "$ID_FILE"
cat "$ID_FILE"
