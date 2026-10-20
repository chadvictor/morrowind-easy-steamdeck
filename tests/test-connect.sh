#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Mocks are called from sourced UI/library functions. Some real sourced functions
# are exercised before a later test replaces them with a failure mock.
# shellcheck disable=SC2329,SC2317,SC2218
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TEST_BASE=$(realpath -e -- "${TMPDIR:-/tmp}")
TEST_ROOT=$(mktemp -d "$TEST_BASE/mes-connect-tests.XXXXXXXX")
case $(realpath -e -- "$TEST_ROOT") in "$TEST_BASE"/mes-connect-tests.*) ;; *) exit 99;; esac
trap 'rm -rf -- "$TEST_ROOT"' EXIT
export MES_LIB_DIR="$ROOT/lib" MES_SOURCE="$TEST_ROOT/manage.sh"
# shellcheck source=../src/main.sh
source "$ROOT/src/main.sh" --help >/dev/null
passed=0
fixture=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { passed=$((passed + 1)); printf 'ok %d - %s\n' "$passed" "$*"; }
equal() { [[ $1 == "$2" ]] || fail "${3:-values differ}"; }
new_fixture() {
    fixture=$((fixture + 1))
    MES_BASE="$TEST_ROOT/case-$fixture/profile"
    MES_SOURCE="$MES_BASE/manage.sh"
    STEAM_ROOT="$TEST_ROOT/case-$fixture/Steam"
    export MES_TEST_TRACE="$TEST_ROOT/case-$fixture/trace" MES_TEST_STEAM_STATE="$TEST_ROOT/case-$fixture/state"
    mkdir -p "$MES_BASE/profiles/20261019T120000-123" "$STEAM_ROOT/userdata/111/config" "$STEAM_ROOT/userdata/222/config"
    printf '20261019T120000-123\n' > "$MES_BASE/active"
    CONFIG="$STEAM_ROOT/userdata/222/config/localconfig.vdf"
    OTHER_CONFIG="$STEAM_ROOT/userdata/111/config/localconfig.vdf"
    printf '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "22320" { "LaunchOptions" "old value" "Other" "keep" } } } } } }\n' > "$CONFIG"
    cp -- "$CONFIG" "$OTHER_CONFIG"
    cp -- "$CONFIG" "$MES_BASE/before.vdf"
    : > "$MES_TEST_TRACE"
    printf 'open\n' > "$MES_TEST_STEAM_STATE"
    WAIT_ACTION=close
    MES_FINISH_AFTER_CONNECT=false
}
steam_roots() { printf '%s\n' "$STEAM_ROOT"; }
ps() {
    case $(cat "$MES_TEST_STEAM_STATE") in
        open) printf 'steam\nsteamwebhelper\n';;
        closed) printf 'bash\n';;
        *) return 1;;
    esac
}
mes_ask() {
    [[ $(cat "$MES_TEST_STEAM_STATE") == open ]] || fail "keyboard input requested after Steam closed: $1"
    printf 'ask\n' >> "$MES_TEST_TRACE"
    printf '%s' "$1"
    IFS= read -r REPLY || return 1
}
mes_pause() { fail 'outer menu requested Enter after the connection step'; }
mes_require_system() { :; }
sleep() {
    equal "$1" 1 'unexpected wait interval'
    printf 'wait\n' >> "$MES_TEST_TRACE"
    # A user's exit can flush the same value, a new value, or malformed data.
    case $WAIT_ACTION in
        same) printf '\n// Steam flushed unrelated preferences\n' >> "$CONFIG";;
        changed|empty)
            local value='changed in Steam'
            [[ $WAIT_ACTION != empty ]] || value=''
            _steam_vdf set "$CONFIG" "$value" > "$MES_BASE/flushed.vdf"
            cp -- "$MES_BASE/flushed.vdf" "$CONFIG";;
        malformed) printf '"broken" {' > "$CONFIG";;
    esac
    printf 'closed\n' > "$MES_TEST_STEAM_STATE"
}

# The real reopening helper executes this private stub through nohup. Waiting
# for this short-lived child lets assertions observe the async launch reliably.
mkdir -p "$TEST_ROOT/bin"
cat > "$TEST_ROOT/bin/steam" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'reopen:%s\n' "$(cat "$MES_TEST_STEAM_STATE")" >> "$MES_TEST_TRACE"
MOCK
chmod +x "$TEST_ROOT/bin/steam"
export PATH="$TEST_ROOT/bin:$PATH"

new_fixture
mes_main <<< $'2\n2\ny\ny' > "$MES_BASE/run.log"
wait
equal "$(steam_get_launch_options "$CONFIG")" "$(mes_launch_options)"
cmp -- "$OTHER_CONFIG" "$MES_BASE/before.vdf"
cmp -- "$MES_BASE/steam-backup/localconfig.before" "$MES_BASE/before.vdf"
equal "$(cat "$MES_TEST_TRACE")" $'ask\nask\nask\nask\nwait\nreopen:closed'
[[ $MES_FINISH_AFTER_CONNECT == true ]] || fail 'enclosing menu was not told to finish'
! grep -q 'Press Enter to continue' "$MES_BASE/run.log" || fail 'post-close Enter prompt remained'
ok 'all consent precedes exit; only the chosen account changes; Steam reopens without another keystroke'

new_fixture
mes_connect_ui <<< $'2\ny\nn' > "$MES_BASE/run.log"
wait
equal "$(steam_get_launch_options "$CONFIG")" "$(mes_launch_options)"
equal "$(cat "$MES_TEST_TRACE")" $'ask\nask\nask\nwait'
[[ $MES_FINISH_AFTER_CONNECT == true ]] || fail 'no-reopen path would return to a keyboard prompt'
ok 'the preselected no-reopen option finishes without keyboard input or launching Steam'

new_fixture
mes_connect_ui <<< $'2\nn' > "$MES_BASE/run.log"
equal "$(cat "$MES_TEST_STEAM_STATE")" open
cmp -- "$CONFIG" "$MES_BASE/before.vdf"
[[ $MES_FINISH_AFTER_CONNECT == false && ! -e $MES_BASE/steam-backup ]] || fail 'cancel started a connection'
equal "$(cat "$MES_TEST_TRACE")" $'ask\nask'
ok 'declining consent keeps Steam open and leaves configuration untouched'

new_fixture
mes_connect_ui <<< $'2\nm' > "$MES_BASE/run.log"
cmp -- "$CONFIG" "$MES_BASE/before.vdf"
[[ $MES_FINISH_AFTER_CONNECT == false ]] || fail 'manual fallback entered the automatic wait'
grep -Fq '%command%' "$MES_BASE/steam-launch-options.txt" || fail 'manual command missing'
equal "$(cat "$MES_TEST_STEAM_STATE")" open
ok 'manual instructions remain available before Steam exits'

new_fixture
WAIT_ACTION=same
mes_connect_ui <<< $'2\ny\nn' > "$MES_BASE/run.log"
equal "$(steam_get_launch_options "$CONFIG")" "$(mes_launch_options)"
grep -Fq '// Steam flushed unrelated preferences' "$CONFIG" || fail 'unrelated exit-time edit lost'
grep -Fq '// Steam flushed unrelated preferences' "$MES_BASE/steam-backup/localconfig.before" || fail 'backup did not capture final closed state'
ok 'an exit-time flush with unchanged LaunchOptions is accepted and preserved in the backup'

new_fixture
WAIT_ACTION=changed
mes_main <<< $'2\n2\ny\ny' > "$MES_BASE/run.log" 2>&1
wait
equal "$(steam_get_launch_options "$CONFIG")" 'changed in Steam'
[[ ! -e $MES_BASE/steam-backup ]] || fail 'changed preview value was written over'
grep -Fq 'Launch Options changed after the preview' "$MES_BASE/run.log" || fail 'preview conflict not explained'
grep -Fxq 'reopen:closed' "$MES_TEST_TRACE" || fail 'Steam did not reopen after conflict'
ok 'a value changed during exit cancels the write and still finishes/reopens without a prompt'

new_fixture
_steam_vdf remove "$CONFIG" > "$MES_BASE/absent.vdf"
cp -- "$MES_BASE/absent.vdf" "$CONFIG"
WAIT_ACTION=empty
if mes_connect_ui <<< $'2\ny\nn' > "$MES_BASE/run.log" 2>&1; then fail 'absent-to-empty preview change was accepted'; fi
equal "$(steam_get_launch_options "$CONFIG")" ''
[[ ! -e $MES_BASE/steam-backup ]] || fail 'presence change was written over'
ok 'preview comparison distinguishes an absent value from an empty value'

new_fixture
WAIT_ACTION=malformed
if mes_connect_ui <<< $'2\ny\ny' > "$MES_BASE/run.log" 2>&1; then fail 'malformed closed configuration was accepted'; fi
wait
[[ ! -e $MES_BASE/steam-backup ]] || fail 'unreadable final config produced a backup transaction'
grep -Fxq 'reopen:closed' "$MES_TEST_TRACE" || fail 'Steam did not reopen after a parse failure'
ok 'an unreadable exit-time configuration cancels safely and restores access to Steam'

new_fixture
mkdir -- "$CONFIG.morrowind-easy-steamdeck.lock"
mes_main <<< $'2\n2\ny\ny' > "$MES_BASE/run.log" 2>&1
wait
cmp -- "$CONFIG" "$MES_BASE/before.vdf"
grep -Fxq 'reopen:closed' "$MES_TEST_TRACE" || fail 'Steam did not reopen after transaction refusal'
[[ $MES_FINISH_AFTER_CONNECT == true ]] || fail 'transaction failure returned to a keyboard prompt'
ok 'transaction refusal keeps existing options and exits the outer menu without Enter'

# The same finish signal must escape the full setup path, not only menu item 2.
mes_find_game_ui() { MES_GAME="$TEST_ROOT/fixture-game"; }
mes_install_engine() { :; }
mes_create_profile() { printf 'profile\n' >> "$MES_TEST_TRACE"; }
new_fixture
mes_main <<< $'1\nI\n2\ny\ny' > "$MES_BASE/run.log"
wait
equal "$(steam_get_launch_options "$CONFIG")" "$(mes_launch_options)"
[[ $MES_FINISH_AFTER_CONNECT == true ]] || fail 'setup did not propagate connection completion'
grep -Fxq 'profile' "$MES_TEST_TRACE" || fail 'setup did not run the profile action'
grep -Fxq 'reopen:closed' "$MES_TEST_TRACE" || fail 'Steam did not reopen from setup'
ok 'connection reached through full setup also exits without an outer Enter prompt'

# Test the real bounded waiter directly with no delay, including ps failure.
new_fixture
mes_connect_ui <<< $'2\ny\nn' > "$MES_BASE/connect.log"
printf 'open\n' > "$MES_TEST_STEAM_STATE"
: > "$MES_TEST_TRACE"
mes_main <<< $'4\ny\ny' > "$MES_BASE/restore.log"
wait
equal "$(steam_get_launch_options "$CONFIG")" 'old value'
equal "$(cat "$MES_TEST_TRACE")" $'ask\nask\nask\nwait\nreopen:closed'
ok 'restore collects all answers while Steam is open and finishes without Enter'

new_fixture
mes_connect_ui <<< $'2\ny\nn' > "$MES_BASE/connect.log"
printf 'open\n' > "$MES_TEST_STEAM_STATE"
WAIT_ACTION=changed
mes_main <<< $'4\ny\ny' > "$MES_BASE/restore.log" 2>&1
wait
equal "$(steam_get_launch_options "$CONFIG")" 'changed in Steam'
grep -Fxq 'reopen:closed' "$MES_TEST_TRACE" || fail 'Steam did not reopen after restore conflict'
ok 'a conflicting restore keeps the changed value and reopens Steam without further input'

new_fixture
if mes_wait_for_steam_exit 0; then fail 'waiter accepted a running Steam client'; fi
printf 'unknown\n' > "$MES_TEST_STEAM_STATE"
if mes_wait_for_steam_exit 0; then fail 'waiter accepted a failed process inspection'; fi
printf 'closed\n' > "$MES_TEST_STEAM_STATE"
mes_wait_for_steam_exit 0
ok 'the waiter has a bounded timeout and fails closed when process inspection is unavailable'

# Exercise enclosing-menu timeout handling without spending three minutes.
mes_wait_for_steam_exit() { return 1; }
new_fixture
mes_main <<< $'2\n2\ny\ny' > "$MES_BASE/run.log" 2>&1
wait
cmp -- "$CONFIG" "$MES_BASE/before.vdf"
equal "$(cat "$MES_TEST_STEAM_STATE")" open
! grep -q '^reopen:' "$MES_TEST_TRACE" || fail 'already-running Steam was launched again'
[[ ! -e $MES_BASE/steam-backup && $MES_FINISH_AFTER_CONNECT == true ]] || fail 'timeout changed the config or returned to keyboard input'
grep -Fq '%command%' "$MES_BASE/steam-launch-options.txt" || fail 'timeout lost the manual fallback'
ok 'timeout leaves Steam untouched, offers manual fallback and exits without a pause'

printf '\nAll %d connection checks passed. Only temporary fixtures were used.\n' "$passed"
