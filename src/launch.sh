#!/usr/bin/env bash
# Steam app 22320 calls this with %command%. Those Windows/Proton arguments
# are intentionally ignored: the native Linux OpenMW process is launched below.
set -euo pipefail
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
fail() {
    printf '\nMorrowind Easy Steam Deck: %s\n' "$1" >&2
    printf '%s\n' "$1" > "$base/last-launch-error.txt"
    if command -v kdialog >/dev/null && [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
        kdialog --title 'Morrowind Easy Steam Deck' --error "$1" || true
    fi
    exit 1
}
verify_translation() (
    local mod_root=${mod_data%/Data Files} unusual files expected name file actual match count=0
    [[ $mod_root != "$mod_data" && -d $mod_root && ! -L $mod_root ]] || return 1
    cd -- "$mod_root" || return
    unusual=$(find . ! -type f ! -type d -printf x -quit) || return
    [[ -z $unusual ]] || return 1
    files=$(find . -type f -printf x) || return
    [[ ${#files} == 57 ]] || return 1
    sha256sum --check --status "$profile/ptbr-files.sha256" || return
    # Resolve original names case-insensitively, just as setup does.
    while read -r expected name; do
        [[ -n $name ]] || continue
        match=''
        for file in "$data"/*; do
            actual=${file##*/}
            if [[ ${actual,,} == "${name,,}" ]]; then
                [[ -z $match && -f $file ]] || return 1
                match=$file
            fi
        done
        [[ -n $match ]] || return 1
        actual=$(sha256sum < "$match") || return
        [[ ${actual%% *} == "$expected" ]] || return 1
        count=$((count + 1))
    done < "$profile/ptbr-masters.sha256"
    [[ $count == 3 ]]
)
[[ -f $base/active ]] || fail 'No active profile. Run the installer again.'
IFS= read -r id < "$base/active"
[[ $id =~ ^[0-9]{8}T[0-9]{6}-[0-9]+$ ]] || fail 'Invalid profile. Run the installer again.'
profile="$base/profiles/$id"
[[ -s $profile/openmw.cfg && -s $profile/data-path && -s $profile/required-files ]] || fail 'Profile incomplete. Run the installer again.'
IFS= read -r data < "$profile/data-path"
while IFS= read -r file; do
    [[ -f $file ]] || fail "Cannot find ${file##*/}. Reinsert/mount the SD card or run setup to restore the selected game/translation files."
done < "$profile/required-files"
save_group=userdata
if [[ -f $profile/save-group ]]; then IFS= read -r save_group < "$profile/save-group" || fail 'Invalid save directory setting.'; fi
case $save_group in userdata|userdata-ptbr) ;; *) fail 'Invalid save directory setting. Run setup again.';; esac
data_args=("--data=$data")
if [[ -f $profile/mod-data-path ]]; then
    IFS= read -r mod_data < "$profile/mod-data-path" || fail 'Invalid translation directory setting.'
    [[ -s $mod_data/Morrowind_PTBR.esp ]] || fail 'PT-BR translation files are missing. Run setup again.'
    data_args+=("--data=$mod_data")
fi
command -v flatpak >/dev/null || fail 'Flatpak is missing. Launch from native Steam on SteamOS. Flatpak Steam is not supported in this preview.'
if [[ -f $profile/mod-data-path ]]; then
    verify_translation || fail 'The PT-BR package or original game masters changed. Restore the supported English Steam GOTY files, or move the modified PT-BR cache aside and rerun setup. Your saves are preserved.'
    # Local data overrides --data directories. Do not let an extra mod silently
    # bypass the reviewed translation/master combination.
    if [[ -e $base/$save_group/data || -L $base/$save_group/data ]]; then
        [[ -d $base/$save_group/data && ! -L $base/$save_group/data ]] || fail 'PT-BR local data must be an ordinary empty directory.'
        extra=$(find "$base/$save_group/data" ! -type d -printf x -quit) || fail 'Cannot inspect PT-BR local data.'
        [[ -z $extra ]] || fail "PT-BR does not support extra local data. Move files out of $base/$save_group/data and retry; keep your saves folder."
    fi
    version=$(env -u LD_PRELOAD -u LD_LIBRARY_PATH flatpak run --user --branch=stable \
        --command=openmw org.openmw.OpenMW --version) || fail 'Cannot check the OpenMW version. Run setup again.'
    [[ $version =~ OpenMW[[:space:]]+(version[[:space:]]+)?0\.51\.0([[:space:]]|$) ]] || fail 'This PT-BR release requires OpenMW 0.51.0 exactly. Get an installer with a translation reviewed for the updated engine, or turn PT-BR off for your original-language saves.'
fi
engine_command=(--command=openmw org.openmw.OpenMW)
keyboard_env=()
if [[ -f $profile/keyboard-files.sha256 ]]; then
    [[ -f $profile/controller-helper.sha256 ]] || fail 'The keyboard helper is missing. Run setup again.'
    [[ -d $profile/keyboard && ! -L $profile/keyboard ]] || fail 'The keyboard interface is missing. Run setup again.'
    unexpected=$(find "$profile/keyboard" ! -type f ! -type d -printf x -quit) || fail 'Cannot check the keyboard interface.'
    files=$(find "$profile/keyboard" -type f -printf x) || fail 'Cannot check the keyboard interface.'
    [[ -z $unexpected && ${#files} == 3 ]] || fail 'The keyboard interface changed. Run setup again.'
    (cd -- "$profile/keyboard" && sha256sum --check --status "$profile/keyboard-files.sha256") || fail 'The keyboard interface checksum failed. Run setup again.'
    data_args+=("--data=$profile/keyboard")
    keyboard_env=(--env=MES_VIRTUAL_KEYBOARD=1)
fi
if [[ -e $profile/controller-helper.sha256 ]]; then
    [[ -s $profile/libmes-controller-text.so ]] || fail 'The controller helper is missing. Run setup again.'
    read -r expected helper_name < "$profile/controller-helper.sha256" || fail 'Invalid controller helper checksum. Run setup again.'
    [[ $expected =~ ^[0-9a-f]{64}$ && $helper_name == libmes-controller-text.so ]] || fail 'Invalid controller helper checksum. Run setup again.'
    actual=$(sha256sum < "$profile/libmes-controller-text.so")
    [[ ${actual%% *} == "$expected" ]] || fail 'The controller helper changed. Run setup again to restore it.'
    # ld.so splits LD_PRELOAD on spaces, even inside a quoted environment value.
    # Use a relative basename from the profile, and pass all paths as arguments.
    # Set the preload inside the sandbox only; never inject it into Flatpak.
    # shellcheck disable=SC2016
    engine_command=(--command=sh org.openmw.OpenMW -c
        'cd -- "$1" || exit; shift; export LD_PRELOAD=./libmes-controller-text.so; exec openmw "$@"'
        mes-openmw "$profile")
fi
mkdir -p -- "$base/$save_group/data"
rm -f -- "$base/last-launch-error.txt"
# Steam can pass host library paths unsuitable for Flatpak. Keep Steam Input,
# display, audio, and Gamescope environment; remove only loader overrides.
exec env -u LD_PRELOAD -u LD_LIBRARY_PATH flatpak run --user --branch=stable \
    --env=SDL_GRAB_KEYBOARD=0 "${keyboard_env[@]}" "${engine_command[@]}" --replace=config --config="$profile" \
    --user-data="$base/$save_group" --data-local="$base/$save_group/data" "${data_args[@]}" \
    > "$base/launch.log" 2>&1
