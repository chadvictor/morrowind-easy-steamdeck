#!/usr/bin/env bash
# The process mocks are invoked indirectly by the imported library.
# shellcheck disable=SC2329
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
export MES_LIB_DIR="$root/lib" STEAM_VDF_AWK="$root/lib/steam-vdf.awk"
export MES_NATIVE_LIBRARY=${MES_NATIVE_LIBRARY:-$root/dist/libmes-controller-text.so}
# shellcheck source=../lib/core.sh
source "$root/lib/core.sh"
# shellcheck source=../lib/steam.sh
source "$root/lib/steam.sh"
ps() { printf 'openmw\n'; }
if mes_require_game_closed >/dev/null 2>&1; then printf 'FAIL: accepted running engine\n'; exit 1; fi
ps() { return 1; }
if mes_require_game_closed >/dev/null 2>&1; then printf 'FAIL: ignored failed process check\n'; exit 1; fi
ps() { printf 'bash\n'; }
export MES_BASE="$temp/My profile \$literal" MES_TEST_ARGS="$temp/args"
mkdir -p "$temp/bin" "$temp/Games with spaces/Morrowind/Data Files"
game="$temp/Games with spaces/Morrowind"
printf '[General]\n' > "$game/Morrowind.ini"
for title in Morrowind Tribunal Bloodmoon; do
    printf 'TES3\0\0\0\0\0\0\0\0\0\0\0\0' > "$game/Data Files/$title.esm"
    printf '\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > "$game/Data Files/$title.bsa"
done
cat > "$temp/bin/flatpak" <<'MOCK'
#!/usr/bin/env bash
set -eu
command_name= cfg= version=false
for arg in "$@"; do
    case $arg in --command=*) command_name=${arg#*=};; --version) version=true;; esac
done
if [[ $version == true ]]; then printf 'OpenMW version %s\nRevision: fixture\n' "${MES_TEST_ENGINE_VERSION:-0.51.0}"; exit 0; fi
if [[ $command_name == openmw-iniimporter ]]; then
    while (($#)); do
        if [[ $1 == --cfg ]]; then shift; cfg=$1; fi
        shift
    done
    [[ ${MES_TEST_IMPORT_FAIL:-0} == 0 ]] || { printf 'ERROR: fixture import failure\n'; exit 0; }
    printf 'fallback=LightAttenuation_UseConstant,0\nconfig=/tmp/unwanted\ncontent=unwanted.esp\n' > "$cfg"
    exit 0
fi
printf '%s\n' "$@" > "$MES_TEST_ARGS"
MOCK
chmod +x "$temp/bin/flatpak"
export PATH="$temp/bin:$PATH"
mes_check_engine >/dev/null
if MES_TEST_ENGINE_VERSION=0.52.0 mes_check_engine >/dev/null 2>&1; then printf 'FAIL: accepted incompatible engine\n'; exit 1; fi
mes_create_profile "$game" balanced true 1.25 18 16384 false true win1252 >/dev/null
first=$(mes_active_profile)
[[ -s $first/input_v3.xml ]]
[[ -s $first/libmes-controller-text.so && -s $first/controller-helper.sha256 ]]
grep -q '^replace=config$' "$first/openmw.cfg"
grep -q '^font size = 18$' "$first/settings.cfg"
grep -q '^window mode = 1$' "$first/settings.cfg"
grep -q '^minimize on focus loss = false$' "$first/settings.cfg"
if grep -q '^config=\|unwanted.esp' "$first/openmw.cfg"; then printf 'FAIL: imported unwanted config\n'; exit 1; fi
[[ $(grep -c '^content=' "$first/openmw.cfg") == 3 ]]
# The native helper is scoped to OpenMW inside Flatpak, including paths with spaces.
bash "$MES_BASE/launch.sh" /untrusted/proton '$(touch INJECTED)'
grep -qx -- '--command=sh' "$MES_TEST_ARGS"
grep -qx -- '--env=SDL_GRAB_KEYBOARD=0' "$MES_TEST_ARGS"
grep -Fxq -- "$first" "$MES_TEST_ARGS"
# shellcheck disable=SC2016
grep -Fxq 'cd -- "$1" || exit; shift; export LD_PRELOAD=./libmes-controller-text.so; exec openmw "$@"' "$MES_TEST_ARGS"
cp "$first/libmes-controller-text.so" "$temp/helper.good"
printf 'corrupted\n' > "$first/libmes-controller-text.so"
rm -f "$MES_TEST_ARGS"
if bash "$MES_BASE/launch.sh" >/dev/null 2>&1; then printf 'FAIL: accepted corrupt helper\n'; exit 1; fi
[[ ! -e $MES_TEST_ARGS ]]
cp "$temp/helper.good" "$first/libmes-controller-text.so"
# Existing pre-helper profiles retain the direct launch path.
mv "$first/controller-helper.sha256" "$temp/helper.manifest"
bash "$MES_BASE/launch.sh"
grep -qx -- '--command=openmw' "$MES_TEST_ARGS"
mv "$temp/helper.manifest" "$first/controller-helper.sha256"
printf 'user save\n' > "$MES_BASE/userdata/saves-fixture"
printf 'preserved Lua preferences\n' > "$first/global_storage.bin"
export MES_TEST_IMPORT_FAIL=1
if mes_create_profile "$game" quality true 1.5 18 24576 true true win1252 >/dev/null 2>&1; then
    printf 'FAIL: importer failure reported success\n'; exit 1
fi
[[ $(mes_active_profile) == "$first" ]]
export MES_TEST_IMPORT_FAIL=0
mes_create_profile "$game" battery false 1.0 16 8192 false false win1252 >/dev/null
second=$(mes_active_profile)
[[ $first != "$second" && -f $first/openmw.cfg && ! -f $second/input_v3.xml ]]
[[ ! -e $second/controller-helper.sha256 && ! -e $second/libmes-controller-text.so ]]
cmp "$first/global_storage.bin" "$second/global_storage.bin"
grep -q 'user save' "$MES_BASE/userdata/saves-fixture"
grep -q '^enable controller = false$' "$second/settings.cfg"
# Run the actual generated launcher; original Proton arguments must never execute.
bash "$MES_BASE/launch.sh" /untrusted/proton '$(touch INJECTED)' '--config=/untrusted'
grep -q -- '--command=openmw' "$MES_TEST_ARGS"
grep -Fq -- "--data=$game/Data Files" "$MES_TEST_ARGS"
grep -Fq -- "--config=$second" "$MES_TEST_ARGS"
if grep -q 'untrusted\|INJECTED' "$MES_TEST_ARGS"; then printf 'FAIL: forwarded Proton args\n'; exit 1; fi
# Literal dollar signs must survive into Steam Launch Options, escaped for its shell.
# shellcheck disable=SC2016
[[ $(mes_launch_options) == *'\$literal/launch.sh" %command%' ]]
# Missing SD card and a corrupted active pointer fail before invoking the engine.
mv "$game/Data Files/Bloodmoon.bsa" "$game/Data Files/Bloodmoon.bsa.off"
if bash "$MES_BASE/launch.sh" >/dev/null 2>&1; then printf 'FAIL: launched with missing assets\n'; exit 1; fi
grep -q 'SD card' "$MES_BASE/last-launch-error.txt"
printf '../../outside\n' > "$MES_BASE/active"
if mes_active_profile >/dev/null 2>&1; then printf 'FAIL: accepted profile traversal\n'; exit 1; fi
printf 'PASS: version gate, isolated profiles, failure rollback, saved data, literal paths, native launch and missing SD card\n'
