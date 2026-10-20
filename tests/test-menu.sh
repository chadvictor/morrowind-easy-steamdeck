#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2317
# UI fixtures call these mocks indirectly; no real Steam settings are opened.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
export MES_LIB_DIR="$root/lib" MES_SOURCE="$temp/manage.sh"
# shellcheck source=../src/main.sh
source "$root/src/main.sh" --help >/dev/null
MES_BASE="$temp/owned setup"
fixture_steam="$temp/Steam"
fixture_id=20261019T120000-123
mkdir -p "$MES_BASE/profiles/$fixture_id" "$fixture_steam/userdata/111/config"
MES_SOURCE="$MES_BASE/manage.sh"
printf '#!/usr/bin/env bash\n# Test fixture only.\n' > "$MES_SOURCE"
printf '%s\n' "$fixture_id" > "$MES_BASE/active"
config="$fixture_steam/userdata/111/config/localconfig.vdf"
printf '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "22320" { "Other" "keep" } } } } } }\n' > "$config"
cp "$config" "$temp/before"
steam_roots() { printf '%s\n' "$fixture_steam"; }
ps() { printf 'bash\n'; }
# A new account has no LaunchOptions token: this is a normal first-install path.
# The real sourced function is used here; the setup-only mock is defined later.
# shellcheck disable=SC2218
mes_connect_ui <<< $'1\ny\nn' > "$temp/menu.log"
[[ $(steam_get_launch_options "$config") == "$(mes_launch_options)" ]]
grep -q 'Connected' "$temp/menu.log"
steam_restore_launch_options "$MES_BASE/steam-backup" >/dev/null
if steam_get_launch_options "$config" >/dev/null; then printf 'FAIL: added LaunchOptions remains\n'; exit 1
else [[ $? == 4 ]]; fi
grep -q '"Other" "keep"' "$config"
# Removing an inserted token may retain its surrounding whitespace.
cp "$config" "$temp/before"
# Inputs like 08 must not become Bash octal arithmetic errors or alter an account.
# shellcheck disable=SC2218
if mes_connect_ui <<< '08' > "$temp/invalid.log" 2>&1; then printf 'FAIL: invalid index accepted\n'; exit 1; fi
cmp "$config" "$temp/before"
# Manual instructions remain available while Steam and its keyboard are open.
ps() { printf 'steam\n'; }
# shellcheck disable=SC2218
mes_connect_ui <<< $'1\nm' > "$temp/open.log"
cmp "$config" "$temp/before"
grep -q 'Launch Options' "$temp/open.log"
grep -Fq '%command%' "$MES_BASE/steam-launch-options.txt"
printf 'PASS: first connection menu, restore, invalid indices and running-Steam manual fallback\n'
ps() { printf 'bash\n'; }

# Exercise the real setup dialogue through stdin; only its external actions are
# mocked. The profile mock records the exact positional API and persists the
# language choice so the next menu run must read it through mes_active_profile.
mes_find_game_ui() { MES_GAME="$temp/fixture game"; }
mes_install_engine() { printf 'install\n' >> "$temp/setup-calls"; }
mes_create_profile() {
    [[ $# == 10 ]] || { printf 'FAIL: setup did not supply ten profile arguments\n' >&2; return 1; }
    printf '%s\n' "$@" > "$temp/setup-args"
    printf 'ptbr=%s\n' "${10}" > "$MES_BASE/profiles/$fixture_id/choices.txt"
}
mes_connect_ui() { printf 'connect\n' >> "$temp/setup-calls"; }

mes_setup_ui <<< 'I' > "$temp/setup-default.log"
mapfile -t setup_args < "$temp/setup-args"
[[ ${setup_args[0]} == "$temp/fixture game" && ${setup_args[8]} == win1252 && ${setup_args[9]} == false ]]
[[ $(grep -m 1 -F 'Brazilian Portuguese (PT-BR)' "$temp/setup-default.log") == *false ]]
grep -qx 'ptbr=false' "$MES_BASE/profiles/$fixture_id/choices.txt"
printf 'PASS: setup leaves PT-BR off by default and passes false as argument ten\n'

# Start with a different encoding, enable option 9, then try option 8 again.
# The blank line answers the lock message's pause; it must not open the picker.
mes_setup_ui <<< $'8\n3\n9\n8\n\nI' > "$temp/setup-on.log"
mapfile -t setup_args < "$temp/setup-args"
[[ ${setup_args[8]} == win1252 && ${setup_args[9]} == true ]]
grep -Fq 'PT-BR uses Windows-1252 for game data. Turn PT-BR off to change this.' "$temp/setup-on.log"
[[ $(grep -c 'Encoding \[1\]:' "$temp/setup-on.log") == 1 ]]
grep -qx 'ptbr=true' "$MES_BASE/profiles/$fixture_id/choices.txt"
printf 'PASS: option 9 enables PT-BR, forces Windows-1252 and locks its encoding picker\n'

# The next run starts enabled from the recorded profile. Disabling option 9
# reopens the encoding picker and must pass false to the profile API.
mes_setup_ui <<< $'9\n8\n2\nI' > "$temp/setup-off.log"
mapfile -t setup_args < "$temp/setup-args"
[[ $(grep -m 1 -F 'Brazilian Portuguese (PT-BR)' "$temp/setup-off.log") == *true ]]
[[ ${setup_args[8]} == win1250 && ${setup_args[9]} == false ]]
grep -qx 'ptbr=false' "$MES_BASE/profiles/$fixture_id/choices.txt"
[[ $(cat "$temp/setup-calls") == $'install\nconnect\ninstall\nconnect\ninstall\nconnect' ]]
cmp "$config" "$temp/before"
printf 'PASS: setup remembers PT-BR, disables it through option 9 and unlocks encoding\n'
