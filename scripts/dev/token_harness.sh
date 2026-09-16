#!/usr/bin/env bash
# token_harness.sh — DEV ONLY, never sourced by the plugin. Exercises the CLIENT
# half of the presence-token contract (install_id.sh + install.sh) with curl
# stubbed on a shimmed PATH and $XDG_CONFIG_HOME sandboxed, the same idiom as
# render_harness.sh. Nothing here touches the network or the real config dir.
#
#   A  no stored token: the beat sends NO identifying header at all (the retired
#      `x-install-id` must never reappear), and the 401's `.token` is stored 0600.
#   B  stored token: the NEXT beat carries it as `x-ticker-token` and a 200 leaves
#      the stored token untouched (self-healing happens once, not every beat).
#   C  curl fails outright (offline): the beat is silent, exits 0, stores nothing.
#   D  401 without a `.token`: nothing is stored.
#   E  401 carrying a malformed token: the shape gate refuses it, nothing stored.
#   F  no jq on PATH: the sed fallback still extracts the token (the marquee's jq
#      dependency must not decide whether an install can ever be counted).
#   G  install.sh: POSTs /api/event with NO caller-chosen id, stores the returned
#      token 0600, and survives an /api/event that fails (the beat self-heals).
# Exit 0 = all assertions pass.
set -u
HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTS="$( cd "$HERE/.." && pwd )"      # scripts — the plugin's script dir
ROOT="$( cd "$SCRIPTS/.." && pwd )"      # repo root (holds the plugin's install.sh) —
                                          # one ".." fewer than the ticker's client/scripts/dev
                                          # copy: this repo's scripts/ sits directly under the
                                          # repo root, not nested under a client/ directory.

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/cfg"

fails=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (want [$3] got [$2])"; fi; }

# Portable "is this file mode 600?" — BSD stat and GNU stat disagree on flags.
mode_of() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null; }

# ---- stubs -----------------------------------------------------------------
# curl: records the full argv to $CALLS, then answers from STUB_CODE/STUB_BODY.
# It emulates the two curl behaviours the client depends on: `-w` appends the
# status code to stdout, and `-f` suppresses the body and exits 22 on >=400.
# STUB_EXIT forces a transport failure (offline) for calls matching STUB_FAIL_MATCH
# (every call by default), so one dead endpoint can be simulated in isolation.
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_CALLS"
case "$*" in ${STUB_FAIL_MATCH:-*}) [ "${STUB_EXIT:-0}" = "0" ] || exit "$STUB_EXIT" ;; esac
code="${STUB_CODE:-200}"
hard_fail=0
case "$*" in *" -f"*|-f*) [ "$code" -ge 400 ] && hard_fail=1 ;; esac
[ "$hard_fail" = "1" ] || printf '%s' "${STUB_BODY:-}"
case "$*" in *"-w"*) printf '\n%s' "$code" ;; esac
[ "$hard_fail" = "1" ] && exit 22
exit 0
EOF
# tar: install.sh pipes the pinned tarball into it; the extraction is not under test.
cat > "$TMP/bin/tar" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null 2>&1; exit 0
EOF
chmod +x "$TMP/bin/"*

CALLS="$TMP/calls.log"
export STUB_CALLS="$CALLS"
export XDG_CONFIG_HOME="$TMP/cfg"
TOKEN_FILE="$TMP/cfg/tmux-ticker/token"
GOOD='t1.0123456789abcdef0123456789abcdef.c2lnbmF0dXJl'
API="http://ticker.test"

reset() { : > "$CALLS"; rm -rf "$TMP/cfg"; mkdir -p "$TMP/cfg"; unset STUB_EXIT STUB_FAIL_MATCH; }
last_call() { tail -n 1 "$CALLS"; }

# The unit under test is sourced, not executed — install_id.sh is the token store.
# shellcheck source=../install_id.sh
. "$SCRIPTS/install_id.sh"

run_beat() { ( PATH="$TMP/bin:$PATH"; ticker_beat_once "$API" ); }

echo "--- A: no stored token -> no identifying header, 401's token stored 0600"
reset
STUB_CODE=401 STUB_BODY="{\"error\":\"token_required\",\"token\":\"$GOOD\"}" run_beat
c="$(last_call)"
case "$c" in *x-install-id*) fail "A: the retired x-install-id header was sent" ;; *) ok "A: no x-install-id" ;; esac
case "$c" in *x-ticker-token*) fail "A: sent a token header with no token" ;; *) ok "A: no token header" ;; esac
case "$c" in *"/api/beat"*) ok "A: beat posted" ;; *) fail "A: no /api/beat call" ;; esac
check "A: token stored" "$(cat "$TOKEN_FILE" 2>/dev/null)" "$GOOD"
check "A: token file is 0600" "$(mode_of "$TOKEN_FILE")" "600"

echo "--- B: stored token rides the next beat; a 200 leaves it alone"
: > "$CALLS"
STUB_CODE=200 STUB_BODY='{"ok":true}' run_beat
c="$(last_call)"
case "$c" in *"x-ticker-token: $GOOD"*) ok "B: token echoed" ;; *) fail "B: token not echoed ($c)" ;; esac
check "B: token unchanged" "$(cat "$TOKEN_FILE" 2>/dev/null)" "$GOOD"

echo "--- C: curl fails outright -> silent, exit 0, nothing changed"
: > "$CALLS"
STUB_EXIT=7 run_beat; rc=$?
check "C: beat_once exits 0" "$rc" "0"
check "C: token unchanged" "$(cat "$TOKEN_FILE" 2>/dev/null)" "$GOOD"

echo "--- D: 401 with no .token -> nothing stored"
reset
STUB_CODE=401 STUB_BODY='{"error":"token_required"}' run_beat
check "D: no token file" "$([ -e "$TOKEN_FILE" ] && echo yes || echo no)" "no"

echo "--- E: 401 with a malformed token -> shape gate refuses it"
reset
STUB_CODE=401 STUB_BODY='{"token":"not-a-ticker-token"}' run_beat
check "E: no token file" "$([ -e "$TOKEN_FILE" ] && echo yes || echo no)" "no"

echo "--- F: no jq on PATH -> the sed fallback still extracts the token"
reset
# A PATH holding ONLY the commands the token store needs — jq deliberately not
# among them, so `command -v jq` genuinely misses and the sed branch is the one
# under test. (Shadowing jq with a stub would not prove that.)
NOJQ="$TMP/nojq"; mkdir -p "$NOJQ"; cp "$TMP/bin/curl" "$NOJQ/curl"
for c in bash env tr sed head mkdir chmod mv rm; do ln -sf "$(command -v "$c")" "$NOJQ/$c"; done
STUB_CODE=401 STUB_BODY="{\"ok\":false,\"token\":\"$GOOD\"}" \
  env -i PATH="$NOJQ" HOME="$TMP/home" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    STUB_CALLS="$CALLS" STUB_CODE=401 STUB_BODY="{\"ok\":false,\"token\":\"$GOOD\"}" \
    "$(command -v bash)" -c '. "$1/install_id.sh"; command -v jq >/dev/null && exit 9; ticker_beat_once "$2"' _ "$SCRIPTS" "$API"
check "F: jq really was absent (exit != 9)" "$?" "0"
check "F: token stored without jq" "$(cat "$TOKEN_FILE" 2>/dev/null)" "$GOOD"

echo "--- G: install.sh stores the /api/event token and names no id"
reset
STUB_CODE=200 STUB_BODY="{\"ok\":true,\"token\":\"$GOOD\"}" \
  env PATH="$TMP/bin:$PATH" TICKER_API="$API" bash "$ROOT/install.sh" >/dev/null 2>&1
rc=$?
check "G: install.sh exits 0" "$rc" "0"
check "G: token stored" "$(cat "$TOKEN_FILE" 2>/dev/null)" "$GOOD"
check "G: token file is 0600" "$(mode_of "$TOKEN_FILE")" "600"
ev="$(grep '/api/event' "$CALLS" | tail -n 1)"
case "$ev" in *install_id*) fail "G: install.sh still names a caller-chosen id" ;; *) ok "G: no caller-chosen id" ;; esac
case "$ev" in *x-install-id*) fail "G: install.sh still sends x-install-id" ;; *) ok "G: no x-install-id header" ;; esac

echo "--- G2: /api/event unreachable -> install still succeeds, no token file"
reset
STUB_EXIT=7 STUB_FAIL_MATCH='*/api/event*' \
  env PATH="$TMP/bin:$PATH" TICKER_API="$API" bash "$ROOT/install.sh" >/dev/null 2>&1
check "G2: install.sh exits 0 offline" "$?" "0"
check "G2: no token file" "$([ -e "$TOKEN_FILE" ] && echo yes || echo no)" "no"

echo
if [ "$fails" -eq 0 ]; then echo "token_harness: ALL PASS"; exit 0; fi
echo "token_harness: $fails FAILED"; exit 1
