#!/usr/bin/env bash
# Original Steam discovery and reversible app-22320 Launch Options integration.
# SPDX-License-Identifier: MIT
# Source this library; it does not change shell flags or touch Steam on import.
# Requires Bash 4+, awk and GNU coreutils/procps as provided by SteamOS.

_MES_STEAM_LIB_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

steam_error() { printf 'Steam: %s\n' "$*" >&2; }

_steam_line_path() {
    [[ -n ${1-} && $1 != *$'\n'* && $1 != *$'\r'* && $1 != *$'\t'* ]] || {
        steam_error 'Empty paths or paths containing tabs/newlines need manual setup.'; return 1;
    }
}

_steam_vdf() {
    local action=${1:?} file=${2:?} value=${3-} parser last final=0 size
    parser=${STEAM_VDF_AWK:-${MES_LIB_DIR:-$_MES_STEAM_LIB_DIR}/steam-vdf.awk}
    [[ -r $parser && -f $file && -r $file ]] || { steam_error 'Cannot read the VDF file/parser.'; return 1; }
    size=$(wc -c < "$file") || return 1
    (( size <= 16777216 )) || { steam_error 'VDF exceeds the 16 MiB automatic-edit limit.'; return 1; }
    last=$(tail -c 1 -- "$file" | od -An -tu1) || return 1
    [[ ${last//[[:space:]]/} == 10 ]] && final=1
    LC_ALL=C STEAM_VDF_ACTION=$action STEAM_VDF_VALUE=$value STEAM_VDF_FINAL_NL=$final \
        awk -f "$parser" "$file"
}

# Existing native and Flatpak roots, canonical paths, one per line; no filesystem scan.
steam_roots() (
    local home=${1:-$HOME} xdg candidate canonical
    local -A seen=()
    xdg=$home/.local/share
    [[ $home == "$HOME" ]] && xdg=${XDG_DATA_HOME:-$xdg}
    for candidate in "$xdg/Steam" "$home/.steam/steam" "$home/.steam/root" \
        "$home/.var/app/com.valvesoftware.Steam/.local/share/Steam" \
        "$home/.var/app/com.valvesoftware.Steam/data/Steam" \
        "$home/.var/app/com.valvesoftware.Steam/.steam/steam"; do
        [[ -d $candidate/steamapps || -d $candidate/userdata ]] || continue
        canonical=$(realpath -e -- "$candidate") || continue
        _steam_line_path "$canonical" || continue
        [[ ${seen[$canonical]+yes} ]] && continue
        seen[$canonical]=1
        printf '%s\n' "$canonical"
    done
)

steam_kind() {
    case ${1:?} in */.var/app/com.valvesoftware.Steam/*) printf 'flatpak\n';; *) printf 'native\n';; esac
}

# Root plus current/legacy libraryfolders entries. Includes SD-card libraries.
steam_libraries() (
    local root=${1:?} candidate canonical entries='' vdf
    local -A seen=()
    [[ -d $root ]] || { steam_error 'Steam root does not exist.'; return 1; }
    for vdf in "$root/steamapps/libraryfolders.vdf" "$root/config/libraryfolders.vdf"; do
        [[ -f $vdf ]] || continue
        entries=$(_steam_vdf libraries "$vdf") || return
        break
    done
    while IFS= read -r candidate; do
        [[ -d $candidate/steamapps ]] || continue
        canonical=$(realpath -e -- "$candidate") || continue
        _steam_line_path "$canonical" || continue
        [[ ${seen[$canonical]+yes} ]] && continue
        seen[$canonical]=1
        printf '%s\n' "$canonical"
    done <<< "$root${entries:+$'\n'$entries}"
)

# A case-insensitive child lookup; reject Linux case-collision ambiguities.
_steam_child() (
    local parent=${1:?} wanted=${2,,} type=${3:-file} path base found=''
    shopt -s nullglob
    for path in "$parent"/*; do
        base=${path##*/}
        [[ ${base,,} == "$wanted" ]] || continue
        if [[ $type == dir ]]; then [[ -d $path ]] || continue
        else [[ -f $path && -s $path && -r $path ]] || continue; fi
        [[ -z $found ]] || { steam_error "Ambiguous case variants: $wanted"; return 1; }
        found=$path
    done
    [[ -n $found ]] || return 1
    printf '%s\n' "$found"
)

# Validate Steam GOTY data presence and file signatures, not archive completeness.
# Accept either the game directory or its Data Files directory for manual fallback.
steam_validate_morrowind() (
    local game=${1:?} base data file stem signature
    _steam_line_path "$game" || return
    [[ -d $game ]] || { steam_error 'Game directory does not exist.'; return 1; }
    game=$(realpath -e -- "$game") || return
    base=${game##*/}
    [[ ${base,,} == 'data files' ]] && game=${game%/*}
    data=$(_steam_child "$game" 'Data Files' dir) || { steam_error 'Data Files directory is missing.'; return 1; }
    _steam_child "$game" 'Morrowind.ini' >/dev/null || { steam_error 'Morrowind.ini is missing or empty.'; return 1; }
    for stem in Morrowind Tribunal Bloodmoon; do
        file=$(_steam_child "$data" "$stem.esm") || { steam_error "Missing/empty $stem.esm."; return 1; }
        signature=$(head -c 4 -- "$file") || return
        [[ $signature == TES3 ]] || { steam_error "Invalid TES3 header: $stem.esm"; return 1; }
        file=$(_steam_child "$data" "$stem.bsa") || { steam_error "Missing/empty $stem.bsa."; return 1; }
        signature=$(od -An -N4 -tx1 -- "$file") || return
        [[ ${signature//[[:space:]]/} == 00010000 ]] || { steam_error "Invalid Morrowind BSA header: $stem.bsa"; return 1; }
    done
    printf '%s\n' "$game"
)

# TSV: Steam-root, library-root, validated game-root. Multiple matches stay explicit.
steam_find_morrowind() (
    local roots root libraries library manifest name game
    roots=$(steam_roots "${1:-$HOME}") || return
    while IFS= read -r root; do
        [[ -n $root ]] || continue
        libraries=$(steam_libraries "$root") || continue
        while IFS= read -r library; do
            [[ -n $library ]] || continue
            manifest=$library/steamapps/appmanifest_22320.acf
            [[ -f $manifest ]] || continue
            name=$(_steam_vdf installdir "$manifest") || continue
            [[ -n $name && $name != . && $name != .. && $name != */* && $name != *\\* ]] || {
                steam_error 'Ignoring an unsafe installdir in the app manifest.'; continue;
            }
            game=$(steam_validate_morrowind "$library/steamapps/common/$name") || continue
            printf '%s\t%s\t%s\n' "$root" "$library" "$game"
        done <<< "$libraries"
    done <<< "$roots"
)

steam_account_config() {
    local root=${1:?} account=${2-} file
    [[ $account =~ ^[0-9]+$ ]] || { steam_error 'Select an explicit numeric Steam account ID.'; return 1; }
    file=$root/userdata/$account/config/localconfig.vdf
    [[ -f $file && ! -L $file && -r $file ]] || {
        steam_error 'This account has no readable regular localconfig.vdf. Open Steam once first.'; return 1;
    }
    realpath -e -- "$file"
}

# TSV: account ID and config path. The caller must explicitly select an account.
steam_accounts() (
    local root=${1:?} dir id file
    shopt -s nullglob
    for dir in "$root"/userdata/*; do
        [[ -d $dir ]] || continue
        id=${dir##*/}
        [[ $id =~ ^[0-9]+$ && $id != 0 ]] || continue
        file=$(steam_account_config "$root" "$id") || continue
        _steam_line_path "$file" || continue
        printf '%s\t%s\n' "$id" "$file"
    done
)

# Prints the exact decoded one-line value. Exit 4 = absent; exit 0 may mean empty.
steam_get_launch_options() { _steam_vdf get "${1:?}"; }

steam_require_closed() {
    local processes line
    processes=$(ps -A -o comm=) || { steam_error 'Cannot check running processes; use manual Launch Options.'; return 1; }
    while IFS= read -r line; do
        line=${line##*/}; line=${line,,}; line=${line//[[:space:]]/}
        case $line in
            steam|steam.exe|steam.sh|steamwebhelper|steamwebhelper.exe|steamservice|steamservice.exe)
                steam_error 'Steam is running. Exit Steam completely, then choose Connect Steam again. No process was stopped.'
                return 1;;
        esac
    done <<< "$processes"
}

_steam_option_matches() {
    local file=${1:?} present=${2:?} expected=${3-} actual rc
    if actual=$(steam_get_launch_options "$file"); then
        [[ $present == 1 && $actual == "$expected" ]]
    else
        rc=$?
        [[ $rc == 4 && $present == 0 ]]
    fi
}

_steam_write_status() {
    local state=${1:?} status=${2:?} temp
    temp=$(mktemp "$state/.status.XXXXXX") || return
    if printf '%s\n' "$status" > "$temp" && mv -f -- "$temp" "$state/status"; then return 0; fi
    rm -f -- "$temp"
    return 1
}

_steam_archive_state() {
    local state=${1:?} archive name
    archive=$(mktemp -d "$state/history.XXXXXXXX") || return
    for name in root account target before-present before-options installed-options localconfig.before status; do
        [[ -f $state/$name && ! -L $state/$name ]] || { steam_error 'Incomplete previous connection state.'; return 1; }
    done
    for name in root account target before-present before-options installed-options localconfig.before status; do
        mv -- "$state/$name" "$archive/$name" || return
    done
}

# Mutates only the chosen account and app 22320. The TUI obtains approval first.
# STATE_DIR is private persistent state, containing the original full-file backup.
# It may be reused after a successful restore; old records are retained in history.*.
steam_set_launch_options() (
    umask 077
    local root=${1:?} account=${2:?} options=${3:?} state=${4:?}
    local target lock='' snapshot='' changed='' before='' present=0 rc status='' archive_state=0
    _steam_line_path "$root" && _steam_line_path "$state" && _steam_line_path "$options" || return
    root=$(realpath -e -- "$root") || return
    target=$(steam_account_config "$root" "$account") || return
    steam_require_closed || return
    lock=$target.morrowind-easy-steamdeck.lock
    mkdir -- "$lock" 2>/dev/null || { steam_error "Connection is locked: $lock (check for another installer)."; return 1; }
    trap '[[ -z $snapshot ]] || rm -f -- "$snapshot"; [[ -z $changed ]] || rm -f -- "$changed"; rmdir -- "$lock" 2>/dev/null || :' EXIT
    [[ ! -L $state ]] || { steam_error 'Connection state must not be a symlink.'; return 1; }
    if [[ -d $state ]]; then
        [[ -f $state/status ]] || { steam_error 'Connection state is incomplete; keep its backup and use a new state directory.'; return 1; }
        status=$(cat -- "$state/status") || return
        if [[ $status == restored ]]; then
            archive_state=1
        elif [[ $status == installed || $status == prepared ]]; then
            [[ $(cat -- "$state/target") == "$target" && $(cat -- "$state/installed-options") == "$options" ]] || {
                steam_error 'A different connection already uses this state. Restore it before reconnecting.'; return 1;
            }
            if _steam_option_matches "$target" 1 "$options"; then
                _steam_write_status "$state" installed || return
                printf '%s\n' "$state"; return 0
            fi
            steam_error 'Connection changed or was interrupted. Restore this connection before retrying.'; return 1
        else steam_error 'Unknown connection state; no Steam file was changed.'; return 1; fi
    fi
    snapshot=$(mktemp "$target.mes-before.XXXXXX") || return
    changed=$(mktemp "$target.mes-after.XXXXXX") || return
    cp -- "$target" "$snapshot" || return
    if before=$(steam_get_launch_options "$snapshot"); then present=1
    else rc=$?; [[ $rc == 4 ]] || return "$rc"; fi
    _steam_vdf set "$snapshot" "$options" > "$changed" || return
    _steam_option_matches "$changed" 1 "$options" || { steam_error 'Launch Options validation failed.'; return 1; }
    if (( archive_state )); then _steam_archive_state "$state" || return
    else mkdir -p -- "$state" || return; fi
    chmod 700 -- "$state" || return
    cp -- "$snapshot" "$state/localconfig.before" || return
    printf '%s' "$root" > "$state/root" || return
    printf '%s' "$account" > "$state/account" || return
    printf '%s' "$target" > "$state/target" || return
    printf '%s' "$present" > "$state/before-present" || return
    printf '%s' "$before" > "$state/before-options" || return
    printf '%s' "$options" > "$state/installed-options" || return
    _steam_write_status "$state" prepared || return
    chmod --reference="$target" "$changed" || return
    steam_require_closed || return
    cmp -s -- "$target" "$snapshot" || { steam_error 'Steam configuration changed concurrently; nothing was written to Steam.'; return 1; }
    mv -f -- "$changed" "$target" || return
    changed=''
    _steam_write_status "$state" installed || { steam_error 'Options were written; state remains prepared and can be restored.'; return 1; }
    printf '%s\n' "$state"
)

# Restores only LaunchOptions, retaining changes in every other key/application.
# Never copies the full backup over Steam settings; conflicting options are refused.
steam_restore_launch_options() (
    umask 077
    local state=${1:?} root account target saved_target expected before present status
    local lock='' snapshot='' changed='' name
    _steam_line_path "$state" || return
    [[ -d $state && ! -L $state ]] || { steam_error 'Connection state does not exist.'; return 1; }
    for name in root account target before-present before-options installed-options localconfig.before status; do
        [[ -f $state/$name && ! -L $state/$name ]] || { steam_error 'Connection state is incomplete.'; return 1; }
    done
    root=$(cat -- "$state/root"); account=$(cat -- "$state/account"); saved_target=$(cat -- "$state/target")
    expected=$(cat -- "$state/installed-options"); before=$(cat -- "$state/before-options")
    present=$(cat -- "$state/before-present"); status=$(cat -- "$state/status")
    [[ $present == 0 || $present == 1 ]] || { steam_error 'Invalid previous-option state.'; return 1; }
    [[ $status == installed || $status == prepared || $status == restored ]] || { steam_error 'Invalid connection status.'; return 1; }
    target=$(steam_account_config "$root" "$account") || return
    [[ $target == "$saved_target" ]] || { steam_error 'Steam profile moved; refusing to restore a different file.'; return 1; }
    steam_require_closed || return
    lock=$target.morrowind-easy-steamdeck.lock
    mkdir -- "$lock" 2>/dev/null || { steam_error 'Another installer is using this Steam profile.'; return 1; }
    trap '[[ -z $snapshot ]] || rm -f -- "$snapshot"; [[ -z $changed ]] || rm -f -- "$changed"; rmdir -- "$lock" 2>/dev/null || :' EXIT
    if _steam_option_matches "$target" "$present" "$before"; then
        _steam_write_status "$state" restored || return
        printf '%s\n' "$state"; return 0
    fi
    [[ $status != restored ]] || { steam_error 'Options changed after restore; they were left untouched.'; return 1; }
    _steam_option_matches "$target" 1 "$expected" || {
        steam_error 'Launch Options were edited after connecting. Keep the current value or restore manually; other settings were left untouched.'; return 1;
    }
    snapshot=$(mktemp "$target.mes-before.XXXXXX") || return
    changed=$(mktemp "$target.mes-after.XXXXXX") || return
    cp -- "$target" "$snapshot" || return
    _steam_option_matches "$snapshot" 1 "$expected" || { steam_error 'Launch Options changed before the restore snapshot.'; return 1; }
    if [[ $present == 1 ]]; then _steam_vdf set "$snapshot" "$before" > "$changed" || return
    else _steam_vdf remove "$snapshot" > "$changed" || return; fi
    _steam_option_matches "$changed" "$present" "$before" || { steam_error 'Restored options failed validation.'; return 1; }
    chmod --reference="$target" "$changed" || return
    steam_require_closed || return
    cmp -s -- "$target" "$snapshot" || { steam_error 'Configuration changed concurrently; restore was cancelled.'; return 1; }
    mv -f -- "$changed" "$target" || return
    changed=''
    _steam_write_status "$state" restored || { steam_error 'Options are restored; rerun to finish the state record.'; return 1; }
    printf '%s\n' "$state"
)
