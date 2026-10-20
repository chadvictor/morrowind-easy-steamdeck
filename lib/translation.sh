#!/usr/bin/env bash
# Optional, pinned upstream mod. Nothing from the download is executed.
MES_PTBR_VERSION=0.1.0-beta.2
MES_PTBR_URL=https://github.com/chadvictor/morrowind-traducao-ptbr/releases/download/v0.1.0-beta.2/morrowind-ptbr-openmw-mod-0.1.0-beta.2.zip
MES_PTBR_SHA256=ea76ae106c2f347fc4c7e0d776df7fedadf90debe1396010c44b2123b2bf7b62

mes_ptbr_check_game() {
    local data=$1 expected name file actual
    while read -r expected name; do
        [[ -n $name ]] || continue
        file=$(_steam_child "$data" "$name") || return
        actual=$(sha256sum < "$file") || return
        [[ ${actual%% *} == "$expected" ]] || {
            mes_error "PT-BR requires the supported English Steam GOTY masters. $name does not match. Select English in Steam's game properties and verify game files, or leave PT-BR off. No game files were changed."
            return 1
        }
    done < "$MES_LIB_DIR/../assets/ptbr-masters.sha256"
}

mes_ptbr_check_engine() {
    local version
    version=$(mes_flatpak run --user --branch=stable --command=openmw "$MES_APP" --version) || return
    [[ $version =~ OpenMW[[:space:]]+(version[[:space:]]+)?0\.51\.0([[:space:]]|$) ]] || {
        mes_error 'This PT-BR release requires OpenMW 0.51.0 exactly. Leave PT-BR off or use an installer with a translation reviewed for your engine.'; return 1;
    }
}

mes_ptbr_verify() (
    local directory=$1 unusual files
    [[ -d $directory && ! -L $directory ]] || return 1
    cd -- "$directory" || return
    unusual=$(find . ! -type f ! -type d -printf x -quit) || return
    [[ -z $unusual ]] || return 1
    files=$(find . -type f -printf x) || return
    [[ ${#files} == 57 ]] || return 1
    # Every shipped file, including resources, maps, extras and licenses.
    sha256sum --check --status "$MES_LIB_DIR/../assets/ptbr-files.sha256"
)

mes_ptbr_fetch() (
    umask 077
    local cache="$MES_BASE/mods/ptbr-$MES_PTBR_VERSION" download_stage='' actual extractor
    if [[ -e $cache || -L $cache ]]; then
        mes_ptbr_verify "$cache" || { mes_error "PT-BR cache is incomplete or modified: $cache. Move that folder aside and retry setup; the active profile was not changed."; return 1; }
        printf '%s\n' "$cache"; return 0
    fi
    command -v curl >/dev/null || { mes_error 'curl is needed for the optional PT-BR download; it is included with stock SteamOS.'; return 1; }
    if command -v bsdtar >/dev/null; then extractor=bsdtar
    elif command -v unzip >/dev/null; then extractor=unzip
    else mes_error 'A ZIP reader (bsdtar or unzip) is missing. Stock SteamOS supplies one; you can continue with PT-BR off.'; return 1; fi
    mkdir -p -- "$MES_BASE/mods" || return
    download_stage=$(mktemp -d "$MES_BASE/mods/.ptbr-download.XXXXXXXX") || return
    trap 'case $download_stage in "$MES_BASE/mods/".ptbr-download.*) rm -rf -- "$download_stage";; esac' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    printf '\nDownloading Brazilian Portuguese %s (about 4.5 MB)...\n' "$MES_PTBR_VERSION" >&2
    curl --fail --location --show-error --proto '=https' --proto-redir '=https' \
        --connect-timeout 20 --max-time 300 --retry 2 --output "$download_stage/mod.zip" "$MES_PTBR_URL" || return
    actual=$(sha256sum < "$download_stage/mod.zip") || return
    [[ ${actual%% *} == "$MES_PTBR_SHA256" ]] || { mes_error 'PT-BR download checksum mismatch. Nothing was extracted or activated. Please retry.'; return 1; }
    mkdir -- "$download_stage/unpacked" || return
    # The pinned ZIP was reviewed: ordinary files, no links/absolute/traversal paths.
    if [[ $extractor == bsdtar ]]; then
        bsdtar --no-same-owner --no-same-permissions -xf "$download_stage/mod.zip" -C "$download_stage/unpacked" || return
    else
        unzip -q "$download_stage/mod.zip" -d "$download_stage/unpacked" || return
    fi
    mes_ptbr_verify "$download_stage/unpacked/Morrowind-PTBR" || { mes_error 'The PT-BR package failed file verification. Your active profile was not changed.'; return 1; }
    mv -T -- "$download_stage/unpacked/Morrowind-PTBR" "$cache" || return
    printf '%s\n' "$cache"
)

mes_ptbr_fallbacks() {
    LC_ALL=C awk -f "$MES_LIB_DIR/ptbr-fallbacks.awk" "$2" "$1"
}
