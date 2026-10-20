#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Mocks are called indirectly by the production libraries and generated launcher.
# shellcheck disable=SC2329
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TEST_BASE=$(realpath -e -- "${TMPDIR:-/tmp}")
TEST_ROOT=$(mktemp -d "$TEST_BASE/mes-translation-tests.XXXXXXXX")
case $(realpath -e -- "$TEST_ROOT") in "$TEST_BASE"/mes-translation-tests.*) ;; *) exit 99;; esac
trap 'rm -rf -- "$TEST_ROOT"' EXIT
passed=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { passed=$((passed + 1)); printf 'ok %d - %s\n' "$passed" "$*"; }
equal() { [[ $1 == "$2" ]] || fail "${3:-values differ}"; }
reject() { if "$@" > "$TEST_ROOT/rejected.out" 2> "$TEST_ROOT/rejected.err"; then fail "unexpected success: $*"; fi; }
clean_failed_fetch() {
    [[ ! -e $MES_BASE/mods/ptbr-$MES_PTBR_VERSION ]] || fail 'failed fetch published a cache'
    if compgen -G "$MES_BASE/mods/.ptbr-download.*" >/dev/null; then fail 'failed fetch left staging files'; fi
}

# Copy the code and assets before changing fixture master hashes. Production pins
# are never edited; no commercial masters or real Steam/Flatpak files are needed.
PRODUCTION_PINS=$(sha256sum "$ROOT/assets/ptbr-masters.sha256" "$ROOT/assets/ptbr-files.sha256")
mkdir -p "$TEST_ROOT/project/lib" "$TEST_ROOT/project/assets" "$TEST_ROOT/project/src" "$TEST_ROOT/bin"
cp "$ROOT/lib/core.sh" "$ROOT/lib/steam.sh" "$ROOT/lib/translation.sh" "$ROOT/lib/ptbr-fallbacks.awk" "$TEST_ROOT/project/lib/"
cp "$ROOT/assets/ptbr-masters.sha256" "$ROOT/assets/ptbr-files.sha256" "$ROOT/assets/input_v3.xml" "$TEST_ROOT/project/assets/"
cp "$ROOT/assets/keyboard-files.sha256" "$TEST_ROOT/project/assets/"
cp -R "$ROOT/assets/keyboard" "$TEST_ROOT/project/assets/"
cp "$ROOT/src/launch.sh" "$TEST_ROOT/project/src/"
export MES_LIB_DIR="$TEST_ROOT/project/lib"
export MES_NATIVE_LIBRARY=${MES_NATIVE_LIBRARY:-$ROOT/dist/libmes-controller-text.so}
# shellcheck source=../lib/core.sh
source "$MES_LIB_DIR/core.sh"
# shellcheck source=../lib/steam.sh
source "$MES_LIB_DIR/steam.sh"
# shellcheck source=../lib/translation.sh
source "$MES_LIB_DIR/translation.sh"
MAIN_BASE="$TEST_ROOT/Installed profile with spaces \$literal"
export MES_BASE=$MAIN_BASE

# Default CI path downloads the real pinned release once. A local ZIP argument
# avoids another network request during development, with the same digest check.
(($# <= 1)) || fail 'usage: test-translation.sh [path/to/pinned-mod.zip]'
ZIP=$TEST_ROOT/upstream.zip
if (($#)); then
    cp -- "$1" "$ZIP"
else
    command curl --fail --location --show-error --proto '=https' --proto-redir '=https' \
        --connect-timeout 20 --max-time 300 --retry 2 --output "$ZIP" "$MES_PTBR_URL"
fi
actual=$(sha256sum < "$ZIP")
equal "${actual%% *}" "$MES_PTBR_SHA256" 'test ZIP is not the pinned upstream release'
equal "$(wc -l < "$MES_LIB_DIR/../assets/ptbr-files.sha256" | tr -d '[:space:]')" 57 'unexpected payload manifest size'
ok 'the real release ZIP matches its pinned SHA-256 and 57-file manifest'

# Exercise production fetch/extraction, but replay the verified ZIP for each
# scenario. No downloaded scripts or executables are run.
CURL_LOG=$TEST_ROOT/curl-calls
FETCH_SOURCE=$ZIP
FETCH_FAIL=0
curl() {
    local output=''
    printf 'called\n' >> "$CURL_LOG"
    while (($#)); do
        if [[ $1 == --output ]]; then shift; output=$1; fi
        shift
    done
    [[ -n $output ]] || return 2
    if [[ $FETCH_FAIL == 1 ]]; then printf 'partial download' > "$output"; return 22; fi
    cp -- "$FETCH_SOURCE" "$output"
}
cache=$(mes_ptbr_fetch)
equal "$cache" "$MAIN_BASE/mods/ptbr-$MES_PTBR_VERSION"
mes_ptbr_verify "$cache"
[[ -s $cache/LICENSES/GPL-3.0.txt && -s $cache/Extras/launcher/fontes-qt/launcher_pt_BR.ts ]] || fail 'package notices/sources missing'
ok 'fetch publishes the complete verified package and preserves its notices and sources'
before_calls=$(wc -l < "$CURL_LOG")
FETCH_FAIL=1
equal "$(mes_ptbr_fetch)" "$cache"
equal "$(wc -l < "$CURL_LOG")" "$before_calls"
FETCH_FAIL=0
ok 'a verified cache is reused without a network call'

resource="$cache/Data Files/l10n/OMWEngine/pt_BR.yaml"
cp -- "$resource" "$TEST_ROOT/resource.good"
printf '\ncorruption\n' >> "$resource"
reject mes_ptbr_verify "$cache"
reject mes_ptbr_fetch
cp -- "$TEST_ROOT/resource.good" "$resource"
mv -- "$cache/LICENSE" "$TEST_ROOT/license.good"
reject mes_ptbr_verify "$cache"
mv -- "$TEST_ROOT/license.good" "$cache/LICENSE"
mes_ptbr_verify "$cache"
ok 'modified resources and missing package files make the cache unusable'

printf 'extra master must not override the supported game' > "$cache/Data Files/Morrowind.esm"
reject mes_ptbr_verify "$cache"
reject mes_ptbr_fetch
rm -- "$cache/Data Files/Morrowind.esm"
mes_ptbr_verify "$cache"
ok 'unlisted cache files cannot override the original masters'

MES_BASE=$TEST_ROOT/checksum-failure
printf 'not a ZIP' > "$TEST_ROOT/wrong-download"
FETCH_SOURCE=$TEST_ROOT/wrong-download
reject mes_ptbr_fetch
clean_failed_fetch
FETCH_SOURCE=$ZIP
ok 'a checksum mismatch never extracts or publishes a cache'

MES_BASE=$TEST_ROOT/network-failure
FETCH_FAIL=1
reject mes_ptbr_fetch
clean_failed_fetch
FETCH_FAIL=0
ok 'a failed partial download is removed without publishing a cache'

MES_BASE=$TEST_ROOT/extraction-failure
(
    # Older ShellCheck cannot trace these calls through mes_ptbr_fetch.
    # shellcheck disable=SC2317
    bsdtar() { return 2; }
    # shellcheck disable=SC2317
    unzip() { return 2; }
    reject mes_ptbr_fetch
)
clean_failed_fetch
ok 'an extraction failure leaves no active cache or staging directory'

MES_BASE=$TEST_ROOT/payload-failure
payload_manifest=$MES_LIB_DIR/../assets/ptbr-files.sha256
cp -- "$payload_manifest" "$TEST_ROOT/payload-manifest.good"
sed '1s/^[[:xdigit:]]/0/' "$TEST_ROOT/payload-manifest.good" > "$payload_manifest"
reject mes_ptbr_fetch
clean_failed_fetch
cp -- "$TEST_ROOT/payload-manifest.good" "$payload_manifest"
MES_BASE=$MAIN_BASE
ok 'a package that fails payload verification is never published'

extras=$cache/Extras/openmw-fallbacks.cfg
cat > "$TEST_ROOT/import.cfg" <<'IMPORT'
fallback=Question_1_Question,English question
fallback=Blood_Texture_Name_0,English blood
fallback=KeepOriginal,unmodified,comma-separated,value
config=/unwanted/config
content=unwanted.esp
IMPORT
mes_ptbr_fallbacks "$TEST_ROOT/import.cfg" "$extras" > "$TEST_ROOT/merged.cfg"
equal "$(grep -c '^fallback=' "$TEST_ROOT/merged.cfg")" 64
grep -Fxq 'fallback=KeepOriginal,unmodified,comma-separated,value' "$TEST_ROOT/merged.cfg" || fail 'unrelated fallback changed'
! grep -q $'\r' "$TEST_ROOT/merged.cfg" || fail 'CRLF was not normalized'
! grep -q '^config=\|^content=\|English question\|English blood' "$TEST_ROOT/merged.cfg" || fail 'unwanted importer content survived'
sed 's/\r$//' "$extras" | LC_ALL=C sort > "$TEST_ROOT/expected-fallbacks"
grep -v '^fallback=KeepOriginal,' "$TEST_ROOT/merged.cfg" | LC_ALL=C sort > "$TEST_ROOT/actual-fallbacks"
cmp -- "$TEST_ROOT/expected-fallbacks" "$TEST_ROOT/actual-fallbacks" || fail 'UTF-8 fallback values changed'
awk -F, 'seen[$1]++ { exit 1 }' "$TEST_ROOT/merged.cfg" || fail 'duplicate merged fallback'
ok 'all 63 UTF-8 translations replace matching keys once, preserving commas and unrelated settings'

cp -- "$TEST_ROOT/import.cfg" "$TEST_ROOT/duplicate-import.cfg"
printf 'fallback=KeepOriginal,duplicate\n' >> "$TEST_ROOT/duplicate-import.cfg"
reject mes_ptbr_fallbacks "$TEST_ROOT/duplicate-import.cfg" "$extras"
head -n 62 "$extras" > "$TEST_ROOT/short-extras.cfg"
reject mes_ptbr_fallbacks "$TEST_ROOT/import.cfg" "$TEST_ROOT/short-extras.cfg"
cp -- "$extras" "$TEST_ROOT/duplicate-extras.cfg"
head -n 1 "$extras" >> "$TEST_ROOT/duplicate-extras.cfg"
reject mes_ptbr_fallbacks "$TEST_ROOT/import.cfg" "$TEST_ROOT/duplicate-extras.cfg"
cp -- "$extras" "$TEST_ROOT/unexpected-extras.cfg"
printf 'config=/unwanted\n' >> "$TEST_ROOT/unexpected-extras.cfg"
reject mes_ptbr_fallbacks "$TEST_ROOT/import.cfg" "$TEST_ROOT/unexpected-extras.cfg"
ok 'duplicate, incomplete and unexpected fallback fragments fail closed'

game="$TEST_ROOT/Steam library/Morrowind"
mkdir -p "$game/Data Files"
printf '[General]\n' > "$game/Morrowind.ini"
for stem in Morrowind Tribunal Bloodmoon; do
    printf 'TES3\0\0\0\0fixture %s\n' "$stem" > "$game/Data Files/$stem.esm"
    printf '\x00\x01\x00\x00fixture %s\n' "$stem" > "$game/Data Files/$stem.bsa"
done
steam_validate_morrowind "$game" >/dev/null
reject mes_ptbr_check_game "$game/Data Files"
ok 'the real master pins reject a different game even with valid TES3/BSA signatures'
# Only these private fixture pins change; production master hashes remain intact.
{
    for stem in Morrowind Tribunal Bloodmoon; do
        actual=$(sha256sum < "$game/Data Files/$stem.esm")
        # MSYS sha256sum defaults to a binary '*' marker; the runtime manifest
        # contract uses two spaces and a plain filename on every platform.
        printf '%s  %s.esm\n' "${actual%% *}" "$stem"
    done
} > "$MES_LIB_DIR/../assets/ptbr-masters.sha256"
mes_ptbr_check_game "$game/Data Files"
cp -- "$game/Data Files/Tribunal.esm" "$TEST_ROOT/tribunal.good"
printf 'changed' >> "$game/Data Files/Tribunal.esm"
reject mes_ptbr_check_game "$game/Data Files"
cp -- "$TEST_ROOT/tribunal.good" "$game/Data Files/Tribunal.esm"
ok 'every master digest is checked against the selected manifest'

cat > "$TEST_ROOT/bin/flatpak" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
command_name='' cfg='' version=false
for arg in "$@"; do
    case $arg in --command=*) command_name=${arg#*=};; --version) version=true;; esac
done
if [[ $version == true ]]; then printf '%s\n' "${MES_TEST_ENGINE_VERSION:-OpenMW version 0.51.0}"; exit 0; fi
if [[ $command_name == openmw-iniimporter ]]; then
    while (($#)); do
        if [[ $1 == --cfg ]]; then shift; cfg=$1; fi
        shift
    done
    cp -- "$MES_TEST_IMPORT" "$cfg"
    if [[ ${MES_TEST_DUP_IMPORT:-0} == 1 ]]; then printf 'fallback=KeepOriginal,duplicate\n' >> "$cfg"; fi
    exit 0
fi
printf '%s\n' "$@" > "$MES_TEST_ARGS"
MOCK
chmod +x "$TEST_ROOT/bin/flatpak"
export PATH="$TEST_ROOT/bin:$PATH" MES_TEST_IMPORT="$TEST_ROOT/import.cfg" MES_TEST_ARGS="$TEST_ROOT/launch-args"
ps() { printf 'bash\n'; }
mes_ptbr_check_engine
MES_TEST_ENGINE_VERSION='OpenMW 0.51.0' mes_ptbr_check_engine
MES_TEST_ENGINE_VERSION='OpenMW version 0.51.1' reject mes_ptbr_check_engine
MES_TEST_ENGINE_VERSION='OpenMW version 0.52.0' reject mes_ptbr_check_engine
ok 'the translation accepts exactly OpenMW 0.51.0'

mes_create_profile "$game" balanced true 1.25 18 16384 false true win1251 false > "$TEST_ROOT/profile.out"
english=$(mes_active_profile)
equal "$(cat "$english/save-group")" userdata
mkdir -p "$MES_BASE/userdata/saves"
printf 'English campaign\n' > "$MES_BASE/userdata/saves/english.omwsave"
printf 'English Lua preferences\n' > "$english/global_storage.bin"
before_calls=$(wc -l < "$CURL_LOG")
mes_create_profile "$game" balanced true 1.25 18 16384 false true win1251 true > "$TEST_ROOT/profile.out"
portuguese=$(mes_active_profile)
equal "$(cat "$portuguese/save-group")" userdata-ptbr
equal "$(cat "$portuguese/mod-data-path")" "$cache/Data Files"
grep -qx 'encoding=win1252' "$portuguese/openmw.cfg" || fail 'PT-BR did not force Windows-1252'
grep -qx 'ptbr=true' "$portuguese/choices.txt" || fail 'PT-BR choice not saved'
equal "$(grep '^content=' "$portuguese/openmw.cfg")" $'content=Morrowind.esm\ncontent=Tribunal.esm\ncontent=Bloodmoon.esm\ncontent=Morrowind_PTBR.esp\ncontent=mes_keyboard.omwscripts'
equal "$(grep -c '^fallback=' "$portuguese/openmw.cfg")" 64
equal "$(wc -l < "$portuguese/required-files" | tr -d '[:space:]')" 10
awk '/^\[/ { section=$0 } /^preferred locales = pt_BR, en$/ { if (section != "[General]") exit 1; found=1 } END { if (!found) exit 1 }' "$portuguese/settings.cfg" || fail 'locale is missing or in the wrong section'
grep -qx 'subtitles = true' "$portuguese/settings.cfg" || fail 'PT-BR subtitles missing'
[[ ! -e $portuguese/global_storage.bin ]] || fail 'English Lua state crossed languages'
equal "$(wc -l < "$CURL_LOG")" "$before_calls"
mkdir -p "$MES_BASE/userdata-ptbr/saves"
printf 'Portuguese campaign\n' > "$MES_BASE/userdata-ptbr/saves/portuguese.omwsave"
ok 'enabling PT-BR activates the plugin, resources, locale and fallbacks in a separate save group'

# shellcheck disable=SC2016
bash "$MES_BASE/launch.sh" /untrusted/proton '$(touch NEVER_EXECUTE)' '--data=/untrusted'
equal "$(grep '^--data=' "$MES_TEST_ARGS")" "--data=$game/Data Files"$'\n'"--data=$cache/Data Files"$'\n'"--data=$portuguese/keyboard"
grep -Fxq -- "--user-data=$MES_BASE/userdata-ptbr" "$MES_TEST_ARGS" || fail 'PT-BR save path incorrect'
grep -Fxq -- "--data-local=$MES_BASE/userdata-ptbr/data" "$MES_TEST_ARGS" || fail 'PT-BR local data path incorrect'
! grep -q 'untrusted\|NEVER_EXECUTE' "$MES_TEST_ARGS" || fail 'Proton arguments were reused'
ok 'the generated launcher passes ordered data directories and isolated PT-BR userdata literally'

mes_create_profile "$game" balanced true 1.25 18 16384 false true win1252 false > "$TEST_ROOT/profile.out"
disabled=$(mes_active_profile)
equal "$(cat "$disabled/save-group")" userdata
[[ ! -e $disabled/mod-data-path && ! -e $disabled/ptbr-version ]] || fail 'translation metadata survived disable'
! grep -q 'Morrowind_PTBR\|pt_BR' "$disabled/openmw.cfg" "$disabled/settings.cfg" || fail 'translation still active'
grep -Fxq 'fallback=Question_1_Question,English question' "$disabled/openmw.cfg" || fail 'original fallback not restored'
equal "$(grep -c '^content=' "$disabled/openmw.cfg")" 4
bash "$MES_BASE/launch.sh"
equal "$(grep '^--data=' "$MES_TEST_ARGS")" "--data=$game/Data Files"$'\n'"--data=$disabled/keyboard"
grep -Fxq -- "--user-data=$MES_BASE/userdata" "$MES_TEST_ARGS" || fail 'English save path incorrect'
[[ -s $MES_BASE/userdata/saves/english.omwsave && -s $MES_BASE/userdata-ptbr/saves/portuguese.omwsave ]] || fail 'switching language lost a campaign'
ok 'disabling restores English configuration and launch arguments while preserving both campaigns'

mes_create_profile "$game" balanced true 1.5 18 16384 false true win1252 true > "$TEST_ROOT/profile.out"
reenabled=$(mes_active_profile)
equal "$(cat "$reenabled/save-group")" userdata-ptbr
equal "$(wc -l < "$CURL_LOG")" "$before_calls"
[[ -s $MES_BASE/userdata-ptbr/saves/portuguese.omwsave && -d $portuguese && -d $disabled ]] || fail 're-enabling lost previous data'
ok 're-enabling uses the verified cache and the existing Portuguese save directory'

MES_TEST_ENGINE_VERSION='OpenMW 0.51.1' reject mes_create_profile "$game" balanced true 1.25 18 16384 false true win1252 true
equal "$(mes_active_profile)" "$reenabled"
MES_TEST_DUP_IMPORT=1 reject mes_create_profile "$game" balanced true 1.25 18 16384 false true win1252 true
equal "$(mes_active_profile)" "$reenabled"
printf '\ncorrupt\n' >> "$resource"
reject mes_create_profile "$game" balanced true 1.25 18 16384 false true win1252 true
equal "$(mes_active_profile)" "$reenabled"
cp -- "$TEST_ROOT/resource.good" "$resource"
ok 'engine, fallback and cache failures never replace the active profile'

mv -- "$cache/Data Files/Morrowind_PTBR.top" "$TEST_ROOT/map.good"
rm -f -- "$MES_TEST_ARGS"
reject bash "$MES_BASE/launch.sh"
[[ ! -e $MES_TEST_ARGS ]] || fail 'engine ran with a missing localization map'
mv -- "$TEST_ROOT/map.good" "$cache/Data Files/Morrowind_PTBR.top"
printf '../../outside\n' > "$reenabled/save-group"
reject bash "$MES_BASE/launch.sh"
[[ ! -e $MES_TEST_ARGS ]] || fail 'engine accepted an unsafe save directory'
printf 'userdata-ptbr\n' > "$reenabled/save-group"
ok 'missing translation maps and unsafe save groups stop before the engine starts'

MES_TEST_ENGINE_VERSION='OpenMW version 0.51.1' reject bash "$MES_BASE/launch.sh"
[[ ! -e $MES_TEST_ARGS ]] || fail 'engine ran after an incompatible Flatpak update'
printf '\ncorrupt after setup\n' >> "$resource"
reject bash "$MES_BASE/launch.sh"
[[ ! -e $MES_TEST_ARGS ]] || fail 'engine ran with a modified translation resource'
cp -- "$TEST_ROOT/resource.good" "$resource"
printf 'changed after setup' >> "$game/Data Files/Tribunal.esm"
reject bash "$MES_BASE/launch.sh"
[[ ! -e $MES_TEST_ARGS ]] || fail 'engine ran with a modified master'
cp -- "$TEST_ROOT/tribunal.good" "$game/Data Files/Tribunal.esm"
printf 'extra after setup' > "$cache/Data Files/Morrowind.esm"
reject bash "$MES_BASE/launch.sh"
[[ ! -e $MES_TEST_ARGS ]] || fail 'engine ran with an unlisted overriding master'
rm -- "$cache/Data Files/Morrowind.esm"
bash "$MES_BASE/launch.sh"
[[ -s $MES_TEST_ARGS ]] || fail 'repaired package no longer launches'
ok 'each Portuguese launch rejects later engine updates, resource changes and master overrides'

mkdir -p "$MES_BASE/userdata-ptbr/data/empty/subdirectory"
printf 'local overlay' > "$MES_BASE/userdata-ptbr/data/empty/override.txt"
rm -f -- "$MES_TEST_ARGS"
reject bash "$MES_BASE/launch.sh"
[[ ! -e $MES_TEST_ARGS ]] || fail 'engine ran with an unverified local data overlay'
[[ -s $MES_BASE/userdata-ptbr/data/empty/override.txt ]] || fail 'local overlay was deleted'
rm -- "$MES_BASE/userdata-ptbr/data/empty/override.txt"
bash "$MES_BASE/launch.sh"
[[ -s $MES_TEST_ARGS ]] || fail 'empty local directories blocked startup'
ok 'local data overlays are refused without deletion while empty directories remain usable'

# A two-step move also changes case on case-insensitive Windows test hosts.
mv -- "$game/Data Files/Morrowind.esm" "$TEST_ROOT/case-master"
mv -- "$TEST_ROOT/case-master" "$game/Data Files/morrowind.esm"
mes_create_profile "$game" balanced true 1.25 18 16384 false true win1252 true > "$TEST_ROOT/profile.out"
case_profile=$(mes_active_profile)
grep -Fxq "$game/Data Files/morrowind.esm" "$case_profile/required-files" || fail 'actual master filename was not preserved'
rm -f -- "$MES_TEST_ARGS"
bash "$MES_BASE/launch.sh"
[[ -s $MES_TEST_ARGS ]] || fail 'accepted case variants failed at launch'
ok 'case-insensitive master discovery remains consistent between setup and launch'

equal "$(sha256sum "$ROOT/assets/ptbr-masters.sha256" "$ROOT/assets/ptbr-files.sha256")" "$PRODUCTION_PINS" 'production pins were modified'
ok 'production hash manifests remain unchanged'
printf '\nAll %d translation checks passed. No real game, Steam or Flatpak files were changed.\n' "$passed"
