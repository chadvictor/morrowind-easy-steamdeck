#!/usr/bin/env bash
# Installer-owned profiles. No shell evaluation of saved paths or configuration.
MES_APP=org.openmw.OpenMW
MES_VERSION=0.4.0-preview.1

mes_error() { printf '\nError: %s\n' "$*" >&2; return 1; }
mes_flatpak() { env -u LD_PRELOAD -u LD_LIBRARY_PATH flatpak "$@"; }

mes_require_system() {
    [[ $(uname -s) == Linux ]] || { mes_error 'Run this installer on your Steam Deck in Desktop Mode.'; return 1; }
    [[ $(uname -m) == x86_64 ]] || { mes_error 'This preview supports x86_64 Steam Deck / Linux only.'; return 1; }
    [[ $EUID != 0 ]] || { mes_error 'Run as your normal user. Do not use sudo.'; return 1; }
    local tool
    for tool in bash awk grep cp mv mkdir mktemp date cat chmod cmp pgrep ps realpath head tail od wc sha256sum dirname basename rm rmdir find flatpak sleep; do
        command -v "$tool" >/dev/null || { mes_error "Missing $tool. Stock SteamOS includes the required tools; see docs/troubleshooting.md."; return 1; }
    done
    [[ $MES_BASE == /* && $MES_BASE != *$'\n'* && $MES_BASE != *$'\r'* ]] || {
        mes_error 'The installation location must be an absolute, single-line path.'; return 1;
    }
}

mes_require_game_closed() {
    local processes line
    processes=$(ps -A -o comm=) || { mes_error 'Cannot check running games; close OpenMW and retry.'; return 1; }
    while IFS= read -r line; do
        line=${line##*/}; line=${line//[[:space:]]/}
        case $line in openmw|openmw.exe|openmw-launcher|openmw-launcher.exe)
            mes_error 'Close OpenMW and its launcher, then try again.'; return 1;;
        esac
    done <<< "$processes"
}

mes_install_engine() {
    printf '\nInstalling the current stable OpenMW from Flathub for your user.\n'
    printf 'The first download includes the Linux runtime and can be several GB.\n\n'
    mes_flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || return
    mes_flatpak install --user --noninteractive -y flathub "$MES_APP//stable" || return
    # "install" is a no-op for an existing install; explicitly update just this app.
    mes_flatpak update --user --noninteractive -y "$MES_APP//stable" || return
    mes_check_engine
}

mes_check_engine() {
    local version
    version=$(mes_flatpak run --user --branch=stable --command=openmw "$MES_APP" --version) || return
    printf '\n%s\n' "$version"
    [[ $version =~ OpenMW[[:space:]]+(version[[:space:]]+)?0\.51\.[0-9]+ ]] || {
        mes_error 'This controller profile is checked against OpenMW 0.51.x. Download a newer installer for other engine versions. Your existing profile has not been changed.'
        return 1
    }
}

mes_settings() {
    local preset=$1 controller=$2 scale=$3 font=$4 distance=$5 shadows=$6 water=$7
    local ptbr=${8:-false} aniso=8 locale_settings='' subtitle_settings=''
    if [[ $ptbr == true ]]; then locale_settings='preferred locales = pt_BR, en'; subtitle_settings='subtitles = true'; fi
    [[ $preset == quality ]] && aniso=16
    cat <<EOF
# Morrowind Easy Steam Deck $MES_VERSION — curated starting point, not a benchmark.
[Video]
resolution x = 1280
resolution y = 800
window mode = 1
minimize on focus loss = false
vsync mode = 0
framerate limit = 0
antialiasing = 0

[Camera]
field of view = 75
viewing distance = $distance

[Terrain]
distant terrain = true
object paging = true

[General]
anisotropy = $aniso
$locale_settings

[Shaders]
lighting method = shaders

[Shadows]
enable shadows = $shadows
actor shadows = $shadows
player shadows = $shadows
object shadows = $shadows
terrain shadows = false
shadow map resolution = 1024
maximum shadow map distance = 4096

[Water]
shader = $water
refraction = $water
reflection detail = 1
rtt size = 512

[GUI]
scaling factor = $scale
font size = $font
controller menus = $controller
controller tooltips = $controller
$subtitle_settings

[Input]
enable controller = $controller
joystick dead zone = 0.15
gamepad cursor speed = 0.65
EOF
}

mes_active_profile() {
    local id
    [[ -f $MES_BASE/active ]] || return 1
    IFS= read -r id < "$MES_BASE/active" || return 1
    [[ $id =~ ^[0-9]{8}T[0-9]{6}-[0-9]+$ && -d $MES_BASE/profiles/$id ]] || {
        mes_error 'Invalid active profile. Use the installer to create a new profile.'; return 1;
    }
    printf '%s\n' "$MES_BASE/profiles/$id"
}

mes_copy_controller_helper() {
    local stage=$1 helper=${MES_NATIVE_LIBRARY:-$MES_LIB_DIR/../assets/libmes-controller-text.so} expected actual
    [[ -s $helper && -s $helper.sha256 ]] || {
        mes_error 'The controller helper is missing. Download the complete installer from Releases.'; return 1;
    }
    read -r expected _ < "$helper.sha256" || return
    actual=$(sha256sum < "$helper") || return
    [[ $expected =~ ^[0-9a-f]{64}$ && ${actual%% *} == "$expected" ]] || {
        mes_error 'The controller helper checksum failed. Download the installer again.'; return 1;
    }
    cp -- "$helper" "$stage/libmes-controller-text.so" || return
    printf '%s  libmes-controller-text.so\n' "$expected" > "$stage/controller-helper.sha256" || return
    local keyboard="$MES_LIB_DIR/../assets/keyboard"
    (cd -- "$keyboard" && sha256sum --check --status ../keyboard-files.sha256) || {
        mes_error 'The keyboard interface checksum failed. Download the installer again.'; return 1;
    }
    mkdir -p -- "$stage/keyboard/scripts/mes" || return
    cp -- "$keyboard/mes_keyboard.omwscripts" "$stage/keyboard/" || return
    cp -- "$keyboard/scripts/mes/keyboard.lua" "$keyboard/scripts/mes/keyboard_layout.lua" "$stage/keyboard/scripts/mes/" || return
    cp -- "$MES_LIB_DIR/../assets/keyboard-files.sha256" "$stage/keyboard-files.sha256" || return
}

mes_create_profile() {
    local game=$1 preset=$2 controller=$3 scale=$4 font=$5 distance=$6 shadows=$7 water=$8 encoding=$9
    local ptbr=${10:-false} id stage previous file data ini stem ext mod='' save_group=userdata previous_group
    [[ $ptbr == true || $ptbr == false ]] || return 1
    case $preset in balanced|battery|quality) ;; *) return 1;; esac
    case "$controller:$shadows:$water" in *[!a-z:]*) return 1;; esac
    for file in "$controller" "$shadows" "$water"; do [[ $file == true || $file == false ]] || return 1; done
    case $scale in 1.0|1.25|1.5) ;; *) return 1;; esac
    case $font in 16|18) ;; *) return 1;; esac
    case $distance in 8192|16384|24576) ;; *) return 1;; esac
    case $encoding in win1250|win1251|win1252) ;; *) return 1;; esac
    game=$(steam_validate_morrowind "$game") || return
    data=$(_steam_child "$game" 'Data Files' dir) || return
    ini=$(_steam_child "$game" 'Morrowind.ini') || return
    mes_require_game_closed || return
    if [[ $ptbr == true ]]; then
        mes_ptbr_check_game "$data" || return
        mes_ptbr_check_engine || return
        mod=$(mes_ptbr_fetch) || return
        encoding=win1252
        save_group=userdata-ptbr
    fi
    mkdir -p -- "$MES_BASE/profiles" "$MES_BASE/$save_group/data" || return
    id="$(date -u +%Y%m%dT%H%M%S)-$BASHPID$RANDOM"
    stage="$MES_BASE/profiles/$id"
    mkdir -- "$stage" || { mes_error 'A profile with this timestamp already exists. Wait a second and retry.'; return 1; }
    # Import only INI defaults; game-file order and archives below are intentional.
    : > "$stage/import.cfg" || return
    mes_flatpak run --user --branch=stable --command=openmw-iniimporter "$MES_APP" \
        --ini "$ini" --cfg "$stage/import.cfg" --encoding "$encoding" --no-archives \
        > "$stage/import.log" 2>&1 || { mes_error "INI import failed. Details: $stage/import.log"; return 1; }
    # The upstream importer can report an error while returning success.
    if ! grep -q '^fallback=' "$stage/import.cfg" || grep -qi 'ERROR:' "$stage/import.log"; then
        mes_error "INI import did not produce a usable configuration. Details: $stage/import.log"; return 1
    fi
    if [[ $ptbr == true ]]; then
        mes_ptbr_fallbacks "$stage/import.cfg" "$mod/Extras/openmw-fallbacks.cfg" > "$stage/fallbacks.cfg" || return
    else grep '^fallback=' "$stage/import.cfg" > "$stage/fallbacks.cfg" || return; fi
    {
        printf '# Generated by Morrowind Easy Steam Deck. Game data is supplied by launch.sh.\n'
        printf 'replace=config\nreplace=content\nreplace=fallback-archive\nencoding=%s\n' "$encoding"
        # Only fallback values are accepted from the original INI; never import external config paths.
        cat -- "$stage/fallbacks.cfg"
        printf 'fallback-archive=Morrowind.bsa\nfallback-archive=Tribunal.bsa\nfallback-archive=Bloodmoon.bsa\n'
        printf 'content=Morrowind.esm\ncontent=Tribunal.esm\ncontent=Bloodmoon.esm\n'
    } > "$stage/openmw.cfg" || return
    if [[ $ptbr == true ]]; then
        printf 'content=Morrowind_PTBR.esp\n' >> "$stage/openmw.cfg" || return
        printf '%s\n' "$mod/Data Files" > "$stage/mod-data-path" || return
        printf '%s\n' "$MES_PTBR_VERSION" > "$stage/ptbr-version" || return
        cp -- "$MES_LIB_DIR/../assets/ptbr-files.sha256" "$MES_LIB_DIR/../assets/ptbr-masters.sha256" "$stage/" || return
    fi
    mes_settings "$preset" "$controller" "$scale" "$font" "$distance" "$shadows" "$water" "$ptbr" > "$stage/settings.cfg" || return
    if [[ $controller == true ]]; then
        cp -- "$MES_LIB_DIR/../assets/input_v3.xml" "$stage/input_v3.xml" || return
        mes_copy_controller_helper "$stage" || return
        printf 'content=mes_keyboard.omwscripts\n' >> "$stage/openmw.cfg" || return
    fi
    printf '%s\n' "$game" > "$stage/game-path" || return
    printf '%s\n' "$data" > "$stage/data-path" || return
    printf '%s\n' "$save_group" > "$stage/save-group" || return
    : > "$stage/required-files" || return
    for stem in Morrowind Tribunal Bloodmoon; do
        for ext in esm bsa; do
            _steam_child "$data" "$stem.$ext" >> "$stage/required-files" || return
        done
    done
    if [[ $ptbr == true ]]; then
        for ext in esp cel mrk top; do printf '%s\n' "$mod/Data Files/Morrowind_PTBR.$ext" >> "$stage/required-files" || return; done
    fi
    printf 'preset=%s\ncontroller=%s\nscale=%s\nfont=%s\ndistance=%s\nshadows=%s\nwater=%s\nencoding=%s\nptbr=%s\n' \
        "$preset" "$controller" "$scale" "$font" "$distance" "$shadows" "$water" "$encoding" "$ptbr" > "$stage/choices.txt" || return
    if previous=$(mes_active_profile); then
        previous_group=userdata
        if [[ -f $previous/save-group ]]; then IFS= read -r previous_group < "$previous/save-group" || return; fi
        if [[ $previous_group == "$save_group" ]]; then
            for file in global_storage.bin player_storage.bin; do
                [[ ! -f $previous/$file ]] || cp -- "$previous/$file" "$stage/$file" || return
            done
        fi
    fi
    # Publish last. Failed imports/settings never replace an existing active profile.
    cp -- "$MES_LIB_DIR/../src/launch.sh" "$MES_BASE/launch.sh.new" || return
    chmod 700 "$MES_BASE/launch.sh.new" || return
    mv -f -- "$MES_BASE/launch.sh.new" "$MES_BASE/launch.sh" || return
    printf '%s\n' "$id" > "$MES_BASE/active.new" || return
    mv -f -- "$MES_BASE/active.new" "$MES_BASE/active" || return
    printf '\nProfile ready: %s\nPrevious profiles are retained. Saves: %s/%s/saves\n' "$stage" "$MES_BASE" "$save_group"
}

mes_launch_options() {
    # Double-quoted shell argument, then VDF escaping is the Steam library's job.
    local path="$MES_BASE/launch.sh"
    path=${path//\\/\\\\}; path=${path//\"/\\\"}; path=${path//\$/\\\$}; path=${path//\`/\\\`}
    printf 'bash "%s" %%command%%\n' "$path"
}
