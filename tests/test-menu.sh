#!/usr/bin/env bash
# shellcheck disable=SC2329
# UI fixtures call these mocks indirectly; no real Steam settings are opened.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
export MES_LIB_DIR="$root/lib" MES_SOURCE="$root/dist/install-morrowind.sh"
# shellcheck source=../src/main.sh
source "$root/src/main.sh" --help >/dev/null
MES_BASE="$temp/owned setup"
fixture_steam="$temp/Steam"
fixture_id=20261019T120000-123
mkdir -p "$MES_BASE/profiles/$fixture_id" "$fixture_steam/userdata/111/config"
printf '%s\n' "$fixture_id" > "$MES_BASE/active"
config="$fixture_steam/userdata/111/config/localconfig.vdf"
printf '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "22320" { "Other" "keep" } } } } } }\n' > "$config"
cp "$config" "$temp/before"
steam_roots() { printf '%s\n' "$fixture_steam"; }
ps() { printf 'bash\n'; }
pgrep() { return 1; }
# A new account has no LaunchOptions token: this is a normal first-install path.
mes_connect_ui <<< $'1\ny' > "$temp/menu.log"
[[ $(steam_get_launch_options "$config") == "$(mes_launch_options)" ]]
grep -q 'Connected' "$temp/menu.log"
steam_restore_launch_options "$MES_BASE/steam-backup" >/dev/null
if steam_get_launch_options "$config" >/dev/null; then printf 'FAIL: added LaunchOptions remains\n'; exit 1
else [[ $? == 4 ]]; fi
grep -q '"Other" "keep"' "$config"
# Removing an inserted token may retain its surrounding whitespace.
cp "$config" "$temp/before"
# Inputs like 08 must not become Bash octal arithmetic errors or alter an account.
if mes_connect_ui <<< '08' > "$temp/invalid.log" 2>&1; then printf 'FAIL: invalid index accepted\n'; exit 1; fi
cmp "$config" "$temp/before"
# If Steam is open, the menu offers manual instructions instead of a write.
pgrep() { return 0; }
mes_connect_ui </dev/null > "$temp/open.log"
cmp "$config" "$temp/before"
grep -q 'Steam is open' "$temp/open.log"
grep -Fq '%command%' "$MES_BASE/steam-launch-options.txt"
printf 'PASS: first connection menu, restore, invalid indices and running-Steam manual fallback\n'
