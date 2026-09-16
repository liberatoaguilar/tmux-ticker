#!/usr/bin/env bash
# install_id.sh — the tmux client's presence TOKEN store (and the one beat that
# heals it). The filename is kept for plugin/tarball parity; what it holds is a
# token now, not an id.
#
# This file used to MINT the install id ($DIR/id) that render.sh sent as
# `x-install-id`. That header is retired: it named the primary key of a
# service-key upsert into `sc_presence`, so a caller could invent presence rows
# without bound and inflate the public `reach`. The SERVER mints the id now and
# hands it back inside an HMAC-signed token (`t1.<id>.<sig>`); the client only
# stores that token and echoes it in `x-ticker-token`. There is nothing for the
# client to generate here any more — a client that has nothing sends NO id header
# at all and lets the server issue one.
#
# Self-healing: a tokenless beat gets `401 {"error":"token_required","token":"t1…"}`.
# We store that token and the NEXT beat (~30s later) is counted. So an install that
# happened offline, or predates the token contract, converts itself on its own.
#
# Sourced by render.sh for its functions; also usable standalone:
#   ./install_id.sh          -> print the stored token (exit 1 when there is none)
#   ./install_id.sh <token>  -> store it 0600 and print it back
# Every path is best-effort and silent: nothing here may ever break the marquee.

# Where the token lives. Same directory the installer extracts the plugin into.
ticker_token_file() {
  printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/tmux-ticker/token"
}

# Print the stored token, or fail. A token is one opaque line; strip any stray
# whitespace so a hand-edited file can't smuggle a newline into a header.
ticker_token_read() {
  local f
  f="$(ticker_token_file)"
  [ -s "$f" ] || return 1
  tr -d ' \t\r\n' < "$f" 2>/dev/null
}

# Store a token 0600 (umask, then an explicit chmod, then an atomic rename so a
# concurrent reader never sees a half-written file). Refuses anything that isn't
# shaped like one of our tokens, so a hostile/garbled body can't land in the file
# and get replayed as a header forever.
ticker_token_store() {
  local tok f dir
  tok="$(printf '%s' "${1:-}" | tr -d ' \t\r\n')"
  case "$tok" in
    t1.*.*) ;;
    *) return 1 ;;
  esac
  f="$(ticker_token_file)"
  dir="${f%/*}"
  mkdir -p "$dir" 2>/dev/null || return 1
  ( umask 077; printf '%s' "$tok" > "$f.tmp" ) 2>/dev/null || return 1
  chmod 600 "$f.tmp" 2>/dev/null
  mv -f "$f.tmp" "$f" 2>/dev/null || return 1
  printf '%s' "$tok"
}

# Pull `.token` out of a JSON body. jq when it is installed (never hand-parse if
# we can help it); otherwise a narrow sed over our OWN server's one flat field —
# jq is optional at runtime and must not decide whether an install is ever counted.
ticker_token_from_json() {
  local body="${1:-}" tok=""
  if command -v jq >/dev/null 2>&1; then
    tok="$(printf '%s' "$body" | jq -r '.token // empty' 2>/dev/null)"
  fi
  [ -n "$tok" ] || tok="$(printf '%s' "$body" |
    sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  [ -n "$tok" ] || return 1
  printf '%s' "$tok"
}

# One presence beat against $1 (the API base). Sends the stored token when we have
# one and NOTHING that names a row when we don't. `-f` is deliberately absent: the
# 401 we bootstrap from carries the JSON we need and `-f` throws bodies away.
# Always returns 0 — the caller backgrounds this and the marquee never waits on it.
ticker_beat_once() {
  local api="${1:-}" tok resp code body new
  [ -n "$api" ] || return 0
  if tok="$(ticker_token_read)" && [ -n "$tok" ]; then
    resp="$(curl -sS --max-time 2 -XPOST "$api/api/beat" \
      -H "x-ticker-token: $tok" -w '\n%{http_code}' 2>/dev/null)" || return 0
  else
    resp="$(curl -sS --max-time 2 -XPOST "$api/api/beat" -w '\n%{http_code}' 2>/dev/null)" || return 0
  fi
  code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  [ "$code" = "401" ] || return 0
  new="$(ticker_token_from_json "$body")" || return 0
  ticker_token_store "$new" >/dev/null 2>&1 || return 0
  return 0
}

# Executed rather than sourced: read, or store $1.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ "$#" -gt 0 ]; then ticker_token_store "$1"; else ticker_token_read; fi
fi
