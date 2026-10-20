#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Mocks below are invoked indirectly by the sourced library.
# Older versions report the same indirect mock calls as SC2317.
# shellcheck disable=SC2329,SC2317
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=../lib/steam.sh
source "$SCRIPT_DIR/../lib/steam.sh"
TEST_BASE=$(realpath -e -- "${TMPDIR:-/tmp}")
TEST_ROOT=$(mktemp -d "$TEST_BASE/mes-steam-tests.XXXXXXXX")
# A recursive cleanup is limited to the new test directory, never a Steam profile.
case $(realpath -e -- "$TEST_ROOT") in "$TEST_BASE"/mes-steam-tests.*) ;; *) exit 99;; esac
trap 'rm -rf -- "$TEST_ROOT"' EXIT
passed=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { passed=$((passed + 1)); printf 'ok %d - %s\n' "$passed" "$*"; }
equal() { [[ $1 == "$2" ]] || fail "${3:-values differ}"; }
reject() { if "$@" > "$TEST_ROOT/rejected.out" 2> "$TEST_ROOT/rejected.err"; then fail "unexpected success: $*"; fi; }
vdf_quote() { local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; printf '"%s"' "$s"; }

# Process guards are tested through fake ps output. Subsequent tests only touch fixtures.
ps() { printf 'steam\nbash\n'; }
reject steam_require_closed
ps() { printf 'steamwebhelper\n'; }
reject steam_require_closed
ps() { return 1; }
reject steam_require_closed
ps() { printf 'bash\nkwin_wayland\n'; }
# Older ShellCheck versions confuse the imported function with the later mock.
# shellcheck disable=SC2218
steam_require_closed
unset -f ps
ok 'running native/Flatpak Steam and an unavailable process check are refused'
steam_require_closed() { :; }

FAKE_HOME=$TEST_ROOT/home
ROOT=$FAKE_HOME/.local/share/Steam
SD=$TEST_ROOT/'SD Card "portable"'/SteamLibrary
FLATPAK=$FAKE_HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam
mkdir -p "$ROOT/steamapps" "$SD/steamapps/common/Morrowind/Data Files" "$FLATPAK/steamapps"
GAME=$SD/steamapps/common/Morrowind
printf '[General]\nLanguage=English\n' > "$GAME/Morrowind.ini"
for stem in Morrowind Tribunal Bloodmoon; do
    printf 'TES3\0\0\0\0\0\0\0\0\0\0\0\0' > "$GAME/Data Files/$stem.esm"
    printf '\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > "$GAME/Data Files/$stem.bsa"
done
{
    printf '"libraryfolders"\n{\n"0" { "path" '; vdf_quote "$ROOT"; printf ' }\n'
    printf '"1" { "path" '; vdf_quote "$SD"; printf ' "apps" { "22320" "1" } }\n}\n'
} > "$ROOT/steamapps/libraryfolders.vdf"
printf '"AppState" { "appid" "22320" "installdir" "Morrowind" }' > "$SD/steamapps/appmanifest_22320.acf"
equal "$(steam_roots "$FAKE_HOME" | wc -l | tr -d '[:space:]')" 2
equal "$(steam_kind "$FLATPAK")" flatpak
equal "$(steam_kind "$ROOT")" native
ok 'native and Flatpak roots are discovered without scanning arbitrary drives'
equal "$(steam_libraries "$ROOT" | tail -n 1)" "$(realpath -e "$SD")"
equal "$(steam_find_morrowind "$FAKE_HOME")" "$(realpath -e "$ROOT")"$'\t'"$(realpath -e "$SD")"$'\t'"$(realpath -e "$GAME")"
ok 'quoted SD-card path and app-22320 manifest resolve to validated game data'
equal "$(steam_validate_morrowind "$GAME/Data Files")" "$(realpath -e "$GAME")"
ok 'manual Data Files fallback resolves to the game root'
printf 'BAD!' > "$GAME/Data Files/Bloodmoon.bsa"
reject steam_validate_morrowind "$GAME"
printf '\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > "$GAME/Data Files/Bloodmoon.bsa"
mv "$GAME/Morrowind.ini" "$GAME/Morrowind.ini.off"
reject steam_validate_morrowind "$GAME"
mv "$GAME/Morrowind.ini.off" "$GAME/Morrowind.ini"
ok 'missing INI and incorrect BSA headers are rejected'
cp "$SD/steamapps/appmanifest_22320.acf" "$TEST_ROOT/manifest.good"
printf '"AppState" { "appid" "22320" "installdir" "../../escape" }' > "$SD/steamapps/appmanifest_22320.acf"
equal "$(steam_find_morrowind "$FAKE_HOME" 2>/dev/null)" ''
printf '"AppState" { "appid" "999" "installdir" "Morrowind" }' > "$SD/steamapps/appmanifest_22320.acf"
equal "$(steam_find_morrowind "$FAKE_HOME" 2>/dev/null)" ''
cp "$TEST_ROOT/manifest.good" "$SD/steamapps/appmanifest_22320.acf"
ok 'wrong app IDs and manifest path traversal are ignored'
cp "$ROOT/steamapps/libraryfolders.vdf" "$TEST_ROOT/libraries.good"
{ printf '"LibraryFolders" { "0" '; vdf_quote "$ROOT"; printf ' "1" '; vdf_quote "$SD"; printf ' }'; } > "$ROOT/steamapps/libraryfolders.vdf"
equal "$(steam_libraries "$ROOT" | tail -n 1)" "$(realpath -e "$SD")"
cp "$TEST_ROOT/libraries.good" "$ROOT/steamapps/libraryfolders.vdf"
ok 'legacy scalar libraryfolders format is supported'

for account in 111 222; do mkdir -p "$ROOT/userdata/$account/config"; done
CONFIG=$ROOT/userdata/111/config/localconfig.vdf
OTHER_CONFIG=$ROOT/userdata/222/config/localconfig.vdf
cat > "$CONFIG" <<'VDF'
// User settings: braces in a string and comments are not nesting.
"UserLocalConfigStore"
{
    "Software" { "Valve" { "Steam" { "apps" {
        "42" { "LaunchOptions" "KEEP OTHER GAME" }
        "22320" {
            "Notes" "quoted { brace } and \"word\" \\ path" // keep this
            "LaunchOptions" "gamemoderun %command% -foo \"two words\""
            "OtherValue" "before"
        }
    } } } }
}
VDF
cp "$CONFIG" "$OTHER_CONFIG"
cp "$CONFIG" "$TEST_ROOT/original.vdf"
equal "$(steam_accounts "$ROOT" | wc -l | tr -d '[:space:]')" 2
reject steam_account_config "$ROOT" '../111'
reject steam_account_config "$ROOT" ''
ok 'accounts remain explicit and invalid account IDs are refused'
equal "$(steam_get_launch_options "$CONFIG")" 'gamemoderun %command% -foo "two words"'
ok 'the parser decodes escaped quotes while ignoring braces inside strings'

# Intentionally literal hostile-looking text must never be shell-expanded.
# shellcheck disable=SC2016
OPTIONS='bash "/home/deck/a folder/launch.sh" %command% ; literal $(never-executed) & '
OPTIONS+="'apostrophe'"
STATE=$TEST_ROOT/state
steam_set_launch_options "$ROOT" 111 "$OPTIONS" "$STATE" >/dev/null
equal "$(steam_get_launch_options "$CONFIG")" "$OPTIONS"
cmp -s "$TEST_ROOT/original.vdf" "$STATE/localconfig.before" || fail 'backup differs'
cmp -s "$OTHER_CONFIG" "$TEST_ROOT/original.vdf" || fail 'other account changed'
sed '/"LaunchOptions" "gamemoderun/d' "$TEST_ROOT/original.vdf" > "$TEST_ROOT/outside.before"
sed '/"LaunchOptions" "bash/d' "$CONFIG" > "$TEST_ROOT/outside.after"
cmp -s "$TEST_ROOT/outside.before" "$TEST_ROOT/outside.after" || fail 'unrelated bytes changed'
ok 'one LaunchOptions token is changed; all other bytes and the other account survive'
cp "$CONFIG" "$TEST_ROOT/installed.vdf"
steam_set_launch_options "$ROOT" 111 "$OPTIONS" "$STATE" >/dev/null
cmp -s "$CONFIG" "$TEST_ROOT/installed.vdf" || fail 'reapply changed the config'
reject steam_set_launch_options "$ROOT" 111 'different options' "$STATE"
ok 'reapply is idempotent and a different active connection is refused'
steam_restore_launch_options "$STATE" >/dev/null
cmp -s "$CONFIG" "$TEST_ROOT/original.vdf" || fail 'existing-value round trip was not byte-exact'
steam_restore_launch_options "$STATE" >/dev/null
ok 'existing LaunchOptions restore is byte-exact and idempotent'

# Reuse retains old records, then restore only the target while other settings evolve.
steam_set_launch_options "$ROOT" 111 "$OPTIONS" "$STATE" >/dev/null
compgen -G "$STATE/history.*/localconfig.before" >/dev/null || fail 'restore history missing'
sed 's/"OtherValue" "before"/"OtherValue" "after"/' "$CONFIG" > "$TEST_ROOT/changed.vdf"
cp "$TEST_ROOT/changed.vdf" "$CONFIG"
steam_restore_launch_options "$STATE" >/dev/null
sed 's/"OtherValue" "before"/"OtherValue" "after"/' "$TEST_ROOT/original.vdf" > "$TEST_ROOT/expected.vdf"
cmp -s "$CONFIG" "$TEST_ROOT/expected.vdf" || fail 'unrelated later edit lost'
ok 'state can be reused and restore preserves unrelated edits made later'
steam_set_launch_options "$ROOT" 111 "$OPTIONS" "$STATE" >/dev/null
_steam_vdf set "$CONFIG" 'user changed options' > "$TEST_ROOT/user-change.vdf"
cp "$TEST_ROOT/user-change.vdf" "$CONFIG"
reject steam_restore_launch_options "$STATE"
cmp -s "$CONFIG" "$TEST_ROOT/user-change.vdf" || fail 'conflicting option was overwritten'
ok 'a user LaunchOptions edit after installation is never overwritten by restore'

# Independent state for the remaining cases.
cp "$TEST_ROOT/original.vdf" "$CONFIG"
sed '/"LaunchOptions" "gamemoderun/d' "$CONFIG" > "$TEST_ROOT/absent.vdf"
cp "$TEST_ROOT/absent.vdf" "$CONFIG"
if steam_get_launch_options "$CONFIG"; then fail 'missing option returned present'; else equal "$?" 4; fi
steam_set_launch_options "$ROOT" 111 "$OPTIONS" "$TEST_ROOT/absent-state" >/dev/null
steam_restore_launch_options "$TEST_ROOT/absent-state" >/dev/null
if steam_get_launch_options "$CONFIG"; then fail 'restore did not remove added option'; else equal "$?" 4; fi
grep -F '"LaunchOptions" "KEEP OTHER GAME"' "$CONFIG" >/dev/null || fail 'other app lost'
ok 'missing LaunchOptions is inserted and removed without damaging other apps'
printf '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "42" { "LaunchOptions" "other" } } } } } }' > "$CONFIG"
steam_set_launch_options "$ROOT" 111 "$OPTIONS" "$TEST_ROOT/missing-app-state" >/dev/null
steam_restore_launch_options "$TEST_ROOT/missing-app-state" >/dev/null
if steam_get_launch_options "$CONFIG"; then fail 'missing app restore did not remove option'; else equal "$?" 4; fi
grep -F '"42" { "LaunchOptions" "other" }' "$CONFIG" >/dev/null || fail 'inline app lost'
ok 'a previously absent app object can be added; restore leaves a harmless empty object'

# Empty is different from absent; case-insensitive keys, CRLF and no-final-LF survive.
printf '"UserLocalConfigStore"\r\n{ "software" { "valve" { "steam" { "apps" { "22320" { "launchoptions" "" } } } } } }' > "$CONFIG"
cp "$CONFIG" "$TEST_ROOT/crlf-original"
equal "$(steam_get_launch_options "$CONFIG")" ''
steam_set_launch_options "$ROOT" 111 "$OPTIONS" "$TEST_ROOT/empty-state" >/dev/null
steam_restore_launch_options "$TEST_ROOT/empty-state" >/dev/null
cmp -s "$CONFIG" "$TEST_ROOT/crlf-original" || fail 'CRLF/final newline/empty value changed'
ok 'empty values, case-insensitive keys, CRLF and no terminal newline round-trip'

{ printf '\357\273\277'; cat "$TEST_ROOT/original.vdf"; } > "$CONFIG"
cp "$CONFIG" "$TEST_ROOT/bom-original"
steam_set_launch_options "$ROOT" 111 "$OPTIONS" "$TEST_ROOT/bom-state" >/dev/null
steam_restore_launch_options "$TEST_ROOT/bom-state" >/dev/null
cmp -s "$CONFIG" "$TEST_ROOT/bom-original" || fail 'UTF-8 BOM changed'
ok 'UTF-8 BOM is accepted and preserved byte-for-byte'

for bad in \
    '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "22320" { "LaunchOptions" "x" "LaunchOptions" "y" } } } } } }' \
    '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "22320" {} "22320" {} } } } } }' \
    '"UserLocalConfigStore" { "Software" "wrong type" }' \
    '"UserLocalConfigStore" { "unterminated' \
    '#include "something.vdf"'; do
    printf '%s' "$bad" > "$CONFIG"
    cp "$CONFIG" "$TEST_ROOT/bad-original"
    reject steam_set_launch_options "$ROOT" 111 "$OPTIONS" "$TEST_ROOT/bad-state"
    cmp -s "$CONFIG" "$TEST_ROOT/bad-original" || fail 'bad file changed'
    [[ ! -e $TEST_ROOT/bad-state ]] || fail 'invalid parse created incomplete state'
done
ok 'duplicate target keys/apps, wrong types, malformed syntax and directives fail closed'

# Concurrent unrelated write between the snapshot and commit: must be preserved.
cp "$TEST_ROOT/original.vdf" "$CONFIG"
(
    calls=0
    steam_require_closed() { calls=$((calls + 1)); if (( calls == 2 )); then printf '\n// external edit\n' >> "$CONFIG"; fi; }
    reject steam_set_launch_options "$ROOT" 111 "$OPTIONS" "$TEST_ROOT/concurrent-state"
)
equal "$(steam_get_launch_options "$CONFIG")" 'gamemoderun %command% -foo "two words"'
grep -F '// external edit' "$CONFIG" >/dev/null || fail 'concurrent edit lost'
steam_restore_launch_options "$TEST_ROOT/concurrent-state" >/dev/null
ok 'concurrent Steam config writes cancel the commit and prepared-state recovery works'

cp "$TEST_ROOT/original.vdf" "$CONFIG"
(
    mv() { if [[ ${*: -1} == "$CONFIG" ]]; then return 1; fi; command mv "$@"; }
    reject steam_set_launch_options "$ROOT" 111 "$OPTIONS" "$TEST_ROOT/write-fail-state"
)
cmp -s "$CONFIG" "$TEST_ROOT/original.vdf" || fail 'failed rename changed config'
steam_restore_launch_options "$TEST_ROOT/write-fail-state" >/dev/null
ok 'failed atomic rename leaves original data and a recoverable backup'

(
    _steam_write_status() { [[ $2 != installed ]] || return 1; printf '%s\n' "$2" > "$1/status"; }
    reject steam_set_launch_options "$ROOT" 111 "$OPTIONS" "$TEST_ROOT/status-fail-state"
)
equal "$(steam_get_launch_options "$CONFIG")" "$OPTIONS"
steam_restore_launch_options "$TEST_ROOT/status-fail-state" >/dev/null
cmp -s "$CONFIG" "$TEST_ROOT/original.vdf" || fail 'prepared commit recovery failed'
ok 'a committed change with a failed status write can be restored safely'

mkdir "$CONFIG.morrowind-easy-steamdeck.lock"
reject steam_set_launch_options "$ROOT" 111 "$OPTIONS" "$TEST_ROOT/locked-state"
rmdir "$CONFIG.morrowind-easy-steamdeck.lock"
cmp -s "$CONFIG" "$TEST_ROOT/original.vdf" || fail 'lock refusal changed config'
ok 'an installer lock refuses a second writer'

steam_set_launch_options "$ROOT" 111 "$OPTIONS" "$TEST_ROOT/restore-race-state" >/dev/null
(
    calls=0
    steam_require_closed() { calls=$((calls + 1)); if (( calls == 2 )); then printf '\n// restore race\n' >> "$CONFIG"; fi; }
    reject steam_restore_launch_options "$TEST_ROOT/restore-race-state"
)
equal "$(steam_get_launch_options "$CONFIG")" "$OPTIONS"
grep -F '// restore race' "$CONFIG" >/dev/null || fail 'concurrent restore edit lost'
steam_restore_launch_options "$TEST_ROOT/restore-race-state" >/dev/null
grep -F '// restore race' "$CONFIG" >/dev/null || fail 'later restore lost unrelated edit'
ok 'concurrent changes also cancel restore, and a later retry preserves them'

# Equivalent Steam-required files in a manual folder need not have a manifest.
mkdir -p "$TEST_ROOT/manual"
cp -R "$GAME/Data Files" "$TEST_ROOT/manual/"
cp "$GAME/Morrowind.ini" "$TEST_ROOT/manual/"
equal "$(steam_validate_morrowind "$TEST_ROOT/manual")" "$(realpath -e "$TEST_ROOT/manual")"
ok 'manual source folders work without an appmanifest'

printf '\nAll %d Steam integration checks passed. No real Steam files were accessed or changed.\n' "$passed"
