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
[[ -f $base/active ]] || fail 'No active profile. Run the installer again.'
IFS= read -r id < "$base/active"
[[ $id =~ ^[0-9]{8}T[0-9]{6}-[0-9]+$ ]] || fail 'Invalid profile. Run the installer again.'
profile="$base/profiles/$id"
[[ -s $profile/openmw.cfg && -s $profile/data-path && -s $profile/required-files ]] || fail 'Profile incomplete. Run the installer again.'
IFS= read -r data < "$profile/data-path"
while IFS= read -r file; do
    [[ -f $file ]] || fail "Cannot find ${file##*/}. Reinsert/mount the SD card or run setup to select the game folder again."
done < "$profile/required-files"
command -v flatpak >/dev/null || fail 'Flatpak is missing. Launch from native Steam on SteamOS. Flatpak Steam is not supported in this preview.'
mkdir -p -- "$base/userdata/data"
rm -f -- "$base/last-launch-error.txt"
# Steam can pass host library paths unsuitable for Flatpak. Keep Steam Input,
# display, audio, and Gamescope environment; remove only loader overrides.
exec env -u LD_PRELOAD -u LD_LIBRARY_PATH flatpak run --user --branch=stable \
    --command=openmw org.openmw.OpenMW --replace=config --config="$profile" \
    --user-data="$base/userdata" --data-local="$base/userdata/data" --data="$data" \
    > "$base/launch.log" 2>&1
