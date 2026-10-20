#!/usr/bin/env bash
# Sourced by the release bundle after its libraries have been unpacked.
# shellcheck source=../lib/core.sh
source "$MES_LIB_DIR/core.sh"
# shellcheck source=../lib/steam.sh
source "$MES_LIB_DIR/steam.sh"
# shellcheck source=../lib/translation.sh
source "$MES_LIB_DIR/translation.sh"
MES_BASE=${XDG_DATA_HOME:-$HOME/.local/share}/morrowind-easy-steamdeck
export STEAM_VDF_AWK="$MES_LIB_DIR/steam-vdf.awk"

mes_header() {
    if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR:-} ]]; then
        printf '\033[2J\033[H\033[38;5;179m'
    fi
    printf '\n  MORROWIND\n  EASY STEAM DECK\n'
    [[ ! -t 1 || ${TERM:-dumb} == dumb || -n ${NO_COLOR:-} ]] || printf '\033[0m'
    printf '  %s  |  Native OpenMW · No sudo\n' "$MES_VERSION"
    printf '  ------------------------------------------------------------\n\n'
}
mes_pause() { printf '\nPress Enter to continue... '; IFS= read -r _ || return 1; }
mes_ask() { printf '%s' "$1"; IFS= read -r REPLY || return 1; }

mes_find_game_ui() {
    local row root _library game choice
    local -a games=()
    printf 'Looking in your Steam libraries (internal drive and mounted SD cards)...\n'
    while IFS=$'\t' read -r root _library game; do
        [[ -n $game ]] && games+=("$game")
    done < <(steam_find_morrowind "$HOME")
    if ((${#games[@]})); then
        printf '\nFound:\n'
        for row in "${!games[@]}"; do printf '  %s) %s\n' "$((row+1))" "${games[$row]}"; done
        mes_ask $'\nChoose a folder [1], or type M to paste a different path: ' || return
        choice=${REPLY:-1}
        if [[ $choice =~ ^[1-9][0-9]{0,3}$ ]] && ((choice <= ${#games[@]})); then
            MES_GAME=${games[$((choice-1))]}; return 0
        fi
    fi
    printf '\nIn Dolphin, open the Morrowind folder, click the address bar and copy its full path.\n'
    printf 'You can also paste the path to its Data Files folder. No quotes are needed.\n'
    mes_ask 'Full folder path (blank cancels): ' || return
    [[ -n $REPLY ]] || return 1
    # Accept the common copy-as-location form with surrounding double quotes.
    [[ $REPLY != \"*\" ]] || REPLY=${REPLY:1:${#REPLY}-2}
    MES_GAME=$(steam_validate_morrowind "$REPLY") || {
        mes_error 'This is not a complete Steam Morrowind GOTY installation. Install/verify it in Steam, then try again.'; return 1;
    }
}

mes_manual_connection() {
    printf '\nIn Steam: Morrowind > Properties > General > Launch Options\n'
    printf 'Replace the field with this entire line:\n\n'
    mes_launch_options
    printf '\nKeep %%command%% at the end. No sudo and no Proton command are needed.\n'
    printf 'Use the Steam Input template "Gamepad with Joystick Trackpad" (see the guide).\n'
    mkdir -p -- "$MES_BASE"
    mes_launch_options > "$MES_BASE/steam-launch-options.txt"
    printf '\nA copy is saved at:\n%s/steam-launch-options.txt\n' "$MES_BASE"
}

mes_wait_for_steam_exit() {
    local timeout=${1:-180} started=$SECONDS
    while ! steam_require_closed >/dev/null 2>&1; do
        (( SECONDS - started < timeout )) || return 1
        sleep 1 || return
    done
}

mes_finish_connection() {
    local reopen=$1
    if [[ $reopen == true ]] && steam_require_closed >/dev/null 2>&1; then
        if command -v steam >/dev/null && command -v nohup >/dev/null; then
            # Detach from this terminal; Steam restores its on-screen keyboard.
            nohup steam </dev/null >/dev/null 2>&1 &
            printf '\nReopening Steam as requested.\n'
        else
            printf '\nOpen Steam by tapping its desktop icon. Automatic reopening is unavailable.\n'
        fi
    elif [[ $reopen != true ]]; then
        printf '\nSteam will stay closed. Tap its desktop icon when you are ready.\n'
    fi
    printf 'This step is finished. You can close this installer window; no Enter is needed.\n'
}

mes_connect_ui() {
    MES_FINISH_AFTER_CONNECT=false
    mes_active_profile >/dev/null || { mes_error 'Run setup first.'; return 1; }
    local root account row choice old rc old_present=false current current_present=false reopen=true options
    local -a roots=() accounts=()
    while IFS= read -r root; do
        case $root in */.var/app/com.valvesoftware.Steam/*) continue;; esac
        roots+=("$root")
    done < <(steam_roots "$HOME")
    if ((${#roots[@]} == 0)); then
        printf '\nNative Steam was not found. Flatpak Steam is not supported by this preview.\n'
        printf 'Use the Steam client supplied with SteamOS.\n'; return 1
    fi
    printf '\nKeep Steam open while choosing the account and options below.\n'
    printf 'Steam + X stops working when Steam exits. We will collect every answer first.\n'
    root=${roots[0]}
    if ((${#roots[@]} > 1)); then
        for row in "${!roots[@]}"; do printf '  %s) %s\n' "$((row+1))" "${roots[$row]}"; done
        mes_ask 'Steam installation [1]: ' || return
        choice=${REPLY:-1}
        [[ $choice =~ ^[1-9][0-9]{0,3}$ ]] && ((choice <= ${#roots[@]})) || return 1
        root=${roots[$((choice-1))]}
    fi
    while IFS=$'\t' read -r account row; do [[ -n $account ]] && accounts+=("$account"); done < <(steam_accounts "$root")
    ((${#accounts[@]})) || { mes_error 'Sign in to Steam once so it creates your account settings, then retry while Steam stays open.'; return 1; }
    printf '\nSteam: %s\n' "$root"
    printf 'Choose the account whose Morrowind Play button should use OpenMW.\n'
    for row in "${!accounts[@]}"; do printf '  %s) Steam account folder %s\n' "$((row+1))" "${accounts[$row]}"; done
    mes_ask 'Account [1]: ' || return
    choice=${REPLY:-1}
    [[ $choice =~ ^[1-9][0-9]{0,3}$ ]] && ((choice <= ${#accounts[@]})) || return 1
    account=${accounts[$((choice-1))]}
    if old=$(steam_get_launch_options "$root/userdata/$account/config/localconfig.vdf"); then old_present=true
    else rc=$?; [[ $rc == 4 ]] || return "$rc"; old=''; fi
    options=$(mes_launch_options) || return
    printf '\nCurrent Launch Options: %s\nNew Launch Options: ' "${old:-(empty)}"
    printf '%s\n' "$options"
    mes_ask $'\nApply with a backup? [Y/n/M for manual instructions]: ' || return
    case $REPLY in n|N|no|NO) return 0;; m|M) mes_manual_connection; return;; esac
    mes_ask 'Reopen Steam automatically when this step finishes? [Y/n]: ' || return
    case $REPLY in n|N|no|NO) reopen=false;; esac

    # No stdin reads after this point. This also tells the enclosing setup/menu
    # to finish without mes_pause, even after a timeout or an unsuccessful write.
    MES_FINISH_AFTER_CONNECT=true
    printf '\nAll choices are collected. Now choose Steam > Exit Steam in Desktop Mode.\n'
    printf 'Leave this window open. Waiting up to 3 minutes; no more typing is needed.\n'
    if ! mes_wait_for_steam_exit; then
        mes_error 'Could not confirm that Steam exited within 3 minutes. No connection was written.'
        mes_manual_connection
        mes_finish_connection "$reopen"
        return 1
    fi
    # Steam may flush preferences while exiting. Do not overwrite a value that
    # differs from the one the user reviewed, including absent versus empty.
    if current=$(steam_get_launch_options "$root/userdata/$account/config/localconfig.vdf"); then current_present=true
    else
        rc=$?
        if [[ $rc != 4 ]]; then
            mes_error 'Cannot read the closed Steam account settings. No connection was written.'
            mes_manual_connection
            mes_finish_connection "$reopen"
            return "$rc"
        fi
        current=''
    fi
    if [[ $current_present != "$old_present" || $current != "$old" ]]; then
        mes_error 'Launch Options changed after the preview. They were left untouched. Run Connect Steam again to review the current value.'
        mes_manual_connection
        mes_finish_connection "$reopen"
        return 1
    fi
    if ! steam_set_launch_options "$root" "$account" "$options" "$MES_BASE/steam-backup"; then
        mes_manual_connection
        mes_finish_connection "$reopen"
        return 1
    fi
    printf '\nConnected. Press Play on Morrowind in Steam.\n'
    printf 'Set Steam Input to a gamepad template before playing.\n'
    mes_finish_connection "$reopen"
}

mes_restore_ui() {
    MES_FINISH_AFTER_CONNECT=false
    local reopen=true rc=0
    [[ -s $MES_BASE/steam-backup/status && -f $MES_BASE/steam-backup/before-options ]] || {
        mes_error 'No automatic connection backup was found. Use Steam Properties to undo a manual connection.'; return 1;
    }
    printf '\nKeep Steam open for these choices. Restore the backed-up Morrowind Launch Options:\n'
    cat -- "$MES_BASE/steam-backup/before-options"
    mes_ask $'\nRestore? [Y/n]: ' || return
    case $REPLY in n|N|no|NO) return 0;; esac
    mes_ask 'Reopen Steam automatically when this step finishes? [Y/n]: ' || return
    case $REPLY in n|N|no|NO) reopen=false;; esac
    MES_FINISH_AFTER_CONNECT=true
    printf '\nNow choose Steam > Exit Steam. Waiting up to 3 minutes; no more typing is needed.\n'
    if mes_wait_for_steam_exit; then
        steam_restore_launch_options "$MES_BASE/steam-backup" || rc=$?
        [[ $rc != 0 ]] || printf '\nPrevious Launch Options restored.\n'
    else
        mes_error 'Steam did not exit. No restore was written.'
        rc=1
    fi
    mes_finish_connection "$reopen"
    return "$rc"
}

mes_setup_ui() {
    mes_header
    printf 'SET UP YOUR ADVENTURE\n\n'
    printf 'Requires your own Steam Morrowind GOTY installation and an internet connection.\n'
    printf 'This Steam Deck preview has not yet been tested on physical Deck hardware.\n\n'
    mes_find_game_ui || return
    local preset=balanced controller=true scale=1.25 font=18 distance=16384 shadows=false water=true encoding=win1252
    local choice ptbr=false previous
    if previous=$(mes_active_profile); then
        if [[ -f $previous/choices.txt ]] && grep -qx 'ptbr=true' "$previous/choices.txt"; then ptbr=true; fi
    fi
    while :; do
        mes_header
        printf 'Game: %s\n\n' "$MES_GAME"
        printf '  1  Graphics preset      %s\n' "$preset"
        printf '  2  Controller + UI      %s\n' "$controller"
        printf '  3  Interface scale      %s\n' "$scale"
        printf '  4  Text size            %s\n' "$font"
        printf '  5  View distance        %s units\n' "$distance"
        printf '  6  Shadows              %s\n' "$shadows"
        printf '  7  Shader water         %s\n' "$water"
        printf '  8  Game text encoding   %s\n' "$encoding"
        printf '  9  Brazilian Portuguese (PT-BR)   %s\n\n' "$ptbr"
        printf '  I  Install / apply this setup\n  B  Back\n\n'
        printf '1280 x 800 · FOV 75 · modern lighting · distant terrain\n'
        printf 'Use the Steam Deck performance menu to choose your FPS limit.\n'
        if [[ $controller == true ]]; then
            printf 'Name fields: hold View + tap Y to suggest a name, then A to confirm.\n'
            printf 'Stuck in a screen? Hold View + Menu for 3 seconds to quit (unsaved progress is lost).\n'
        fi
        printf 'Reapplying creates a fresh settings/bindings profile; old profiles and saves remain.\n'
        if [[ $ptbr == true ]]; then
            printf 'PT-BR: English GOTY + OpenMW 0.51.0 required. Start a NEW game.\n'
            printf 'PT-BR saves stay separate. No existing campaign is converted.\n'
        fi
        mes_ask $'\nChoice [I]: ' || return
        choice=${REPLY:-I}
        case $choice in
            1)
                printf '\n1) Balanced: 2-cell view, shader water, no shadows (default)\n'
                printf '2) Battery: 1-cell view, simple water, no shadows\n'
                printf '3) Quality: 3-cell view, shader water, nearby shadows\n'
                mes_ask 'Preset [1]: ' || return
                case ${REPLY:-1} in
                    1) preset=balanced; distance=16384; shadows=false; water=true;;
                    2) preset=battery; distance=8192; shadows=false; water=false;;
                    3) preset=quality; distance=24576; shadows=true; water=true;;
                esac;;
            2) if [[ $controller == true ]]; then controller=false; else controller=true; fi;;
            3) case $scale in 1.0) scale=1.25;; 1.25) scale=1.5;; *) scale=1.0;; esac;;
            4) if [[ $font == 18 ]]; then font=16; else font=18; fi;;
            5) case $distance in 8192) distance=16384;; 16384) distance=24576;; *) distance=8192;; esac;;
            6) if [[ $shadows == true ]]; then shadows=false; else shadows=true; fi;;
            7) if [[ $water == true ]]; then water=false; else water=true; fi;;
            8)
                if [[ $ptbr == true ]]; then
                    printf '\nPT-BR uses Windows-1252 for game data. Turn PT-BR off to change this.\n'
                    mes_pause || return
                    continue
                fi
                printf '\n1) English / Western Europe (win1252)\n2) Central / Eastern Europe (win1250)\n3) Cyrillic (win1251)\n'
                mes_ask 'Encoding [1]: ' || return
                case ${REPLY:-1} in 1) encoding=win1252;; 2) encoding=win1250;; 3) encoding=win1251;; esac;;
            9) if [[ $ptbr == true ]]; then ptbr=false; else ptbr=true; encoding=win1252; fi;;
            i|I)
                mes_require_game_closed || return
                mes_install_engine || return
                mes_create_profile "$MES_GAME" "$preset" "$controller" "$scale" "$font" "$distance" "$shadows" "$water" "$encoding" "$ptbr" || return
                if [[ $MES_SOURCE != "$MES_BASE/manage.sh" ]]; then
                    cp -- "$MES_SOURCE" "$MES_BASE/manage.sh" || return
                    chmod 700 "$MES_BASE/manage.sh" || return
                fi
                printf '\nSetup complete. The next step connects your existing Steam Play button.\n'
                mes_connect_ui
                return;;
            b|B) return 0;;
        esac
    done
}

mes_diagnose() {
    printf 'Morrowind Easy Steam Deck %s\n' "$MES_VERSION"
    printf 'System: %s / %s\nInstall directory: %s\n' "$(uname -s)" "$(uname -m)" "$MES_BASE"
    if command -v flatpak >/dev/null; then mes_flatpak info --user "$MES_APP" || true; fi
    local profile save_group
    if profile=$(mes_active_profile); then
        printf '\nActive profile: %s\n' "$profile"
        cat -- "$profile/choices.txt"
        printf 'Game folder: '; cat -- "$profile/game-path"
        save_group=userdata
        if [[ -f $profile/save-group ]]; then IFS= read -r save_group < "$profile/save-group"; fi
        printf 'Saves: %s/%s/saves\n' "$MES_BASE" "$save_group"
        if [[ -f $profile/ptbr-version ]]; then printf 'PT-BR version: '; cat -- "$profile/ptbr-version"; fi
        if [[ -f $profile/controller-helper.sha256 ]]; then
            printf 'Controller text helper: '
            if (cd -- "$profile" && sha256sum --check --status controller-helper.sha256); then printf 'installed, checksum OK\n'
            else printf 'checksum FAILED; rerun setup\n'; fi
        else printf 'Controller text helper: not enabled in this profile\n'; fi
    else printf '\nNo active profile.\n'; fi
    printf '\nSteam libraries / installed game (read only):\n'
    steam_find_morrowind "$HOME" || true
    printf '\nThis report can include your username and folder paths. Review it before sharing.\n'
}

mes_main() {
    case ${1:-} in
        --version) printf '%s\n' "$MES_VERSION"; return;;
        --help|-h) printf 'Morrowind Easy Steam Deck\nRun with no arguments for setup, Steam connection and restore.\nOptions: --diagnose (read only), --version, --help\n'; return;;
        --diagnose) mes_diagnose; return;;
        '') ;;
        *) mes_error "Unknown option: $1"; return 1;;
    esac
    MES_FINISH_AFTER_CONNECT=false
    mes_require_system || return
    mkdir -p -- "$MES_BASE"
    # Atomic directory creation is available on stock SteamOS (no flock dependency).
    if ! mkdir -- "$MES_BASE/installer.lock" 2>/dev/null; then
        mes_error "Another installer is open, or an interrupted run left $MES_BASE/installer.lock. Close other installers; see troubleshooting before removing a stale lock."; return 1
    fi
    MES_LOCK="$MES_BASE/installer.lock"
    printf '%s\n' "$$" > "$MES_LOCK/pid"
    while :; do
        mes_header
        printf '  1  Set up / change graphics, controller and language\n'
        printf '  2  Connect the Steam Play button\n'
        printf '  3  Show manual Steam Launch Options\n'
        printf '  4  Restore previous Steam Launch Options\n'
        printf '  5  Diagnostics\n'
        printf '  Q  Quit\n'
        mes_ask $'\nChoice [1]: ' || return 0
        case ${REPLY:-1} in
            1) mes_setup_ui || printf '\nSetup stopped. Read the message above; you can retry safely.\n';;
            2) mes_connect_ui || printf '\nSteam connection did not finish. Read the message above.\n';;
            3) mes_manual_connection;;
            4) mes_restore_ui || printf '\nRestore was not applied. Read the message above.\n';;
            5) mes_diagnose;;
            q|Q) return 0;;
            *) continue;;
        esac
        [[ ${MES_FINISH_AFTER_CONNECT:-false} != true ]] || return 0
        mes_pause || return 0
    done
}
mes_main "$@"
