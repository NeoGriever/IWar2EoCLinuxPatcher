#!/usr/bin/env bash
# Console front end for the complete, selectable I-War 2 patch package.
set -uo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
APP_ID="${IW2_STEAM_APP_ID:-359630}"
TARGET_DIR=''
TARGET_SOURCE=''
PATH_MESSAGE=''
TARGET_IS_STEAM=0
TARGET_STEAM_LIBRARY=''
TARGET_PROTON_PREFIX=''
TARGET_RUNTIME_DIR=''
CPU_SPEED_STATUS=''

RESET=$'\e[0m'
GRAY=$'\e[38;5;245m'
LIGHT_GRAY=$'\e[38;5;252m'
YELLOW=$'\e[38;5;220m'
GREEN=$'\e[38;5;46m'
CYAN=$'\e[38;5;51m'
WHITE=$'\e[97m'
SPINNER_FRAMES=(⠈ ⠐ ⠠ ⢀ ⢁ ⢂ ⢄ ⣀ ⣁ ⣂ ⣄ ⣌ ⣔ ⣤ ⣬ ⣴ ⣵ ⣶ ⣷ ⣿ ⢿ ⠿ ⡻ ⠻ ⢛ ⠛ ⠝ ⡙ ⠙ ⠩ ⢉ ⠉ ⠊ ⠌ ⡈ ⠈ ⠐ ⠠ ⢀ ⠀ ⡀ ⣄ ⢦ ⠳ ⠙ ⠈ ⠁ ⠋ ⠞ ⡴ ⣠ ⢀ ⡀ ⡄ ⡆ ⠇ ⠋ ⠙ ⠸ ⢰ ⣠ ⣄ ⡆ ⠇ ⠋ ⠙ ⠸ ⢰ ⣠ ⣄ ⡆ ⠇ ⠋ ⠙ ⠸ ⢰ ⣠ ⣄ ⡆ ⠇ ⠋ ⠙ ⠸ ⢰ ⢡ ⢃ ⠇ ⡆ ⣄ ⣠ ⢰ ⠸ ⠙ ⠋ ⠇ ⡆ ⣄ ⣠ ⢰ ⠸ ⠙ ⠋ ⠇ ⡆ ⣄ ⣠ ⢰ ⠸ ⠙ ⠋ ⠇ ⡆ ⣄ ⣠ ⢰ ⠸ ⠙ ⠋ ⠇ ⡆ ⣄ ⣠ ⢰ ⠸ ⠙ ⠋ ⠇ ⡆ ⡄ ⡀ ⠀ ⠉ ⠒ ⠤ ⣀ ⠀ ⣀ ⠤ ⠒ ⠉ ⠀ ⠉ ⠒ ⠤ ⣀ ⠀ ⣀ ⠤ ⠒ ⠉ ⠀ ⢸ ⣇ ⡀ ⠰ ⢎ ⡱ ⠆ ⢠ ⡼ ⠯ ⠽ ⢧ ⡄ ⢸ ⣏ ⡱ ⠆ ⢸ ⡇ ⢸ ⡏ ⠑ ⢺ ⡇ ⠰ ⢎ ⣡ ⡄ ⠉ ⠒ ⠤ ⣀ ⠀ ⣀ ⠤ ⠒ ⠉ ⠀ ⠉ ⠒ ⠤ ⣀ ⠀ ⣀ ⠤ ⠒ ⠉ ⠀)

# Every task starts deselected.  Dependencies are still resolved immediately
# when the user selects an option.
install_german=0
convert_audio=0
install_nocd=0
install_cpu_speed_fix=0
configure_mouse=0
configure_widescreen=0
resolution=''
video_mode=''
video_aspect=''
video_language=''
resolved_video_aspect=''
resolved_video_language=''
install_gamescope_launcher=0
use_fullscreen=0
gamescope_backend=''
use_gamescope_mouse_sensitivity=0
selected_item='change_path'

declare -a ITEM_ORDER=(change_path german audio nocd cpu_speed mouse widescreen 720p 1080p 1440p 4k videos_none videos_settings videos_manual video_standard video_widescreen video_english video_german gamescope_launcher backend_auto backend_wayland backend_sdl gamescope_mouse_sensitivity fullscreen apply)
declare -a TASK_IDS=()
declare -a TASK_STATES=()
operation_log=''
progress_file=''
cursor_hidden=0
loading_pid=''

# Minimum interval between repeated W/S or arrow-key navigation steps.
# The first press and a direction change are always accepted immediately.
NAV_REPEAT_US="${IW2_NAV_REPEAT_US:-150000}"
LAST_NAV_US=0
LAST_NAV_DIRECTION=''
PENDING_KEY=''

navigation_allowed() {
    local direction="$1" stamp sec usec now
    [[ "$NAV_REPEAT_US" =~ ^[0-9]+$ ]] || NAV_REPEAT_US=80000

    stamp="${EPOCHREALTIME:-}"
    [[ -n "$stamp" ]] || stamp="$(date +%s.%6N)"
    stamp="${stamp/,/.}"
    IFS=. read -r sec usec <<< "$stamp"
    usec="${usec}000000"
    usec="${usec:0:6}"
    now=$(( 10#$sec * 1000000 + 10#$usec ))

    if [[ "$direction" == "$LAST_NAV_DIRECTION" ]] &&
       (( LAST_NAV_US != 0 && now - LAST_NAV_US < NAV_REPEAT_US )); then
        return 1
    fi

    LAST_NAV_US=$now
    LAST_NAV_DIRECTION="$direction"
    return 0
}

coalesce_navigation_repeats() {
    local direction="$1" first second key

    while IFS= read -r -s -n1 -t 0.001 first; do
        key=none
        if [[ "$first" == $'\e' ]]; then
            second=''
            IFS= read -r -s -n2 -t 0.003 second || true
            case "$second" in
                '[A') key=up ;;
                '[B') key=down ;;
                '[C') key=right ;;
                '[D') key=left ;;
                *) key=escape ;;
            esac
        elif [[ -z "$first" || "$first" == $'\n' || "$first" == $'\r' ]]; then
            key=activate
        elif [[ "$first" == ' ' ]]; then
            key=activate
        else
            case "$first" in
                w|W) key=up ;;
                s|S) key=down ;;
                a|A) key=left ;;
                d|D) key=right ;;
                *) key=none ;;
            esac
        fi

        if [[ "$key" == "$direction" || "$key" == none ]]; then
            continue
        fi

        PENDING_KEY="$key"
        return 0
    done
}


loading_spinner() {
    local spinner=0

    while :; do
        printf '\r   %b%s%b Loading ...' \
            "$YELLOW" \
            "${SPINNER_FRAMES[$((spinner % ${#SPINNER_FRAMES[@]}))]}" \
            "$RESET"
        spinner=$((spinner + 1))
        sleep 0.09
    done
}

start_loading_screen() {
    begin_frame
    clear_screen
    header
    printf '\n'
    end_frame

    loading_spinner &
    loading_pid=$!
}

stop_loading_screen() {
    if [[ -n "$loading_pid" ]]; then
        kill "$loading_pid" 2>/dev/null || true
        wait "$loading_pid" 2>/dev/null || true
        loading_pid=''
    fi
    printf '\r\e[2K'
}

begin_frame() { printf '\e[?2026h'; }
end_frame() { printf '\e[?2026l'; }
clear_screen() { printf '\e[2J\e[H'; }
hide_cursor() { printf '\e[?25l'; cursor_hidden=1; }
show_cursor() { printf '%b\e[?2026l\e[?25h' "$RESET"; }

cleanup() {
    if [[ -n "$loading_pid" ]]; then
        kill "$loading_pid" 2>/dev/null || true
        wait "$loading_pid" 2>/dev/null || true
        loading_pid=''
    fi
    [[ -n "$progress_file" ]] && rm -f -- "$progress_file"
    [[ -n "$operation_log" ]] && rm -f -- "$operation_log"
    (( cursor_hidden )) && show_cursor
}
trap cleanup EXIT
trap 'exit 130' INT TERM

header() {
    printf '%b┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓%b\n' "$GREEN" "$RESET"
    printf '%b┃%b   Independence War 2: The Edge of Chaos   %b┃%b\n' "$GREEN" "$WHITE" "$GREEN" "$RESET"
    printf '%b┃%b             Ultimate  Patcher             %b┃%b\n' "$GREEN" "$WHITE" "$GREEN" "$RESET"
    printf '%b┃%b                          v1.0             %b┃%b\n' "$GREEN" "$WHITE" "$GREEN" "$RESET"
    printf '%b┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛%b\n' "$GREEN" "$RESET"
    printf 'This patcher contains fixes, configurations\n'
    printf 'and replacements for the Game\n'
    printf '   "Independence War 2: The Edge of Chaos"\n\n'
}

section_heading() {
    local text="$1" width=$(( ${#1} + 4 ))
    local line
    line="$(repeat_char "$width" '━')"
    printf '%b┏%s┓%b\n' "$GREEN" "$line" "$RESET"
    printf '%b┃%b  %s  %b┃%b\n' "$GREEN" "$WHITE" "$text" "$GREEN" "$RESET"
    printf '%b┗%s┛%b\n' "$GREEN" "$line" "$RESET"
}

game_directory_is_valid() {
    [[ -n "${1:-}" && -f "$1/EdgeOfChaos.exe" && -f "$1/resource.zip" ]]
}

vdf_value() {
    local file="$1" key="$2"
    sed -nE "s/^[[:space:]]*\"${key}\"[[:space:]]*\"([^\"]*)\".*$/\1/p" "$file" | head -n 1
}

steam_roots() {
    local home_dir="${HOME:-/tmp}"
    [[ -n "${IW2_STEAM_ROOT:-}" ]] && printf '%s\n' "$IW2_STEAM_ROOT"
    printf '%s\n' \
        "$home_dir/.local/share/Steam" \
        "$home_dir/.steam/steam" \
        "$home_dir/.steam/root" \
        "$home_dir/.var/app/com.valvesoftware.Steam/.local/share/Steam"
}

game_dir_from_library() {
    local library="$1" manifest install_dir candidate
    manifest="$library/steamapps/appmanifest_${APP_ID}.acf"
    [[ -f "$manifest" ]] || return 1
    install_dir="$(vdf_value "$manifest" installdir)"
    [[ -n "$install_dir" ]] || return 1
    candidate="$library/steamapps/common/$install_dir"
    game_directory_is_valid "$candidate" || return 1
    cd -- "$candidate" && pwd -P
}

detect_steam_game_dir() {
    local steam_root library_file library game_dir
    local -a libraries=()
    local seen=$'\n'

    while IFS= read -r steam_root; do
        [[ -d "$steam_root" ]] || continue
        library_file="$steam_root/steamapps/libraryfolders.vdf"
        libraries=("$steam_root")
        if [[ -f "$library_file" ]]; then
            while IFS= read -r library; do
                [[ -n "$library" ]] && libraries+=("$library")
            done < <(sed -nE 's/^[[:space:]]*"path"[[:space:]]*"([^"]*)".*$/\1/p' "$library_file")
        fi
        for library in "${libraries[@]}"; do
            [[ "$seen" == *$'\n'"$library"$'\n'* ]] && continue
            seen+="$library"$'\n'
            game_dir="$(game_dir_from_library "$library" 2>/dev/null)" || continue
            printf '%s\n' "$game_dir"
            return 0
        done
    done < <(steam_roots)
    return 1
}

steam_library_for_game_dir() {
    local game_dir="$1" common_dir steamapps_dir library manifest install_dir candidate canonical
    common_dir="$(dirname -- "$game_dir")"
    steamapps_dir="$(dirname -- "$common_dir")"
    [[ "$(basename -- "$common_dir")" == common && "$(basename -- "$steamapps_dir")" == steamapps ]] || return 1

    library="$(dirname -- "$steamapps_dir")"
    manifest="$library/steamapps/appmanifest_${APP_ID}.acf"
    [[ -f "$manifest" ]] || return 1

    install_dir="$(vdf_value "$manifest" installdir)"
    [[ -n "$install_dir" ]] || return 1

    candidate="$library/steamapps/common/$install_dir"
    canonical="$(cd -- "$candidate" 2>/dev/null && pwd -P)" || return 1
    [[ "$canonical" == "$game_dir" ]] || return 1

    printf '%s\n' "$library"
}

set_game_directory() {
    local requested="$1" canonical library
    canonical="$(cd -- "$requested" 2>/dev/null && pwd -P)" || {
        PATH_MESSAGE="The selected folder no longer exists."
        return 1
    }
    game_directory_is_valid "$canonical" || {
        PATH_MESSAGE='The selected EdgeOfChaos.exe is not in a valid IW2 installation.'
        return 1
    }

    TARGET_DIR="$canonical"
    TARGET_IS_STEAM=0
    TARGET_STEAM_LIBRARY=''
    TARGET_PROTON_PREFIX=''
    TARGET_RUNTIME_DIR="$TARGET_DIR/.iwar2-linux-patcher"

    # A path change must never inherit the automatically selected Proton prefix
    # from the previously selected installation.
    unset IW2_PROTON_PREFIX
    export IW2_TARGET_IS_STEAM=0
    export IW2_TARGET_STEAM_LIBRARY=''
    export IW2_RUNTIME_DIR="$TARGET_RUNTIME_DIR"

    library="$(steam_library_for_game_dir "$TARGET_DIR" 2>/dev/null || true)"
    if [[ -n "$library" ]]; then
        TARGET_IS_STEAM=1
        TARGET_STEAM_LIBRARY="$library"
        TARGET_PROTON_PREFIX="$library/steamapps/compatdata/$APP_ID/pfx"

        export IW2_TARGET_IS_STEAM=1
        export IW2_TARGET_STEAM_LIBRARY="$TARGET_STEAM_LIBRARY"
        export IW2_PROTON_PREFIX="$TARGET_PROTON_PREFIX"
    fi

    PATH_MESSAGE=''
    return 0
}

detect_initial_game_directory() {
    local detected
    if [[ -n "${IW2_GAME_DIR:-}" ]]; then
        set_game_directory "$IW2_GAME_DIR" && { TARGET_SOURCE='IW2_GAME_DIR'; return 0; }
        return 1
    fi
    detected="$(detect_steam_game_dir)" || {
        PATH_MESSAGE="No valid Steam installation for App ${APP_ID} was detected."
        return 1
    }
    set_game_directory "$detected" || return 1
    TARGET_SOURCE=steam
}

choose_game_directory() {
    local initial_dir="${TARGET_DIR:-${HOME:-/tmp}}" executable=''
    if command -v kdialog >/dev/null 2>&1; then
        executable="$(kdialog --title 'Select EdgeOfChaos.exe' --getopenfilename "$initial_dir" 'EdgeOfChaos.exe (EdgeOfChaos.exe)' 2>/dev/null)" || return 0
    elif command -v zenity >/dev/null 2>&1; then
        executable="$(zenity --file-selection --title='Select EdgeOfChaos.exe' --filename="$initial_dir/" --file-filter='EdgeOfChaos.exe | EdgeOfChaos.exe' 2>/dev/null)" || return 0
    else
        PATH_MESSAGE='No supported file dialog was found (KDialog or Zenity is required).'
        return 1
    fi
    [[ -n "$executable" ]] || return 0
    if [[ "$(basename -- "$executable")" != EdgeOfChaos.exe ]]; then
        PATH_MESSAGE='Please select the EdgeOfChaos.exe file.'
        return 1
    fi
    set_game_directory "$(dirname -- "$executable")" || return 1
    TARGET_SOURCE=manual
}

detect_cpu_speed_fix_default() {
    local checker check_output tsc_hz will_overflow display_rate
    checker="${IW2_CPU_SPEED_CHECKER:-$PATCH_DIR/modules/check-cpu-speed-fix.sh}"
    check_output="$("$checker" 2>&1)" || {
        CPU_SPEED_STATUS='CPU timing-counter check unavailable; CPU Speed Fix remains a manual choice.'
        return 1
    }
    tsc_hz="$(sed -nE 's/^tsc_hz=([0-9]+)$/\1/p' <<<"$check_output" | head -n 1)"
    will_overflow="$(sed -nE 's/^will_overflow_u32=([01])$/\1/p' <<<"$check_output" | head -n 1)"
    if [[ ! "$tsc_hz" =~ ^[0-9]+$ || ! "$will_overflow" =~ ^[01]$ ]]; then
        CPU_SPEED_STATUS='CPU timing-counter check returned an invalid result; CPU Speed Fix remains a manual choice.'
        return 1
    fi
    display_rate="$(awk -v hertz="$tsc_hz" 'BEGIN { printf "%.3f GHz", hertz / 1000000000 }')"
    if [[ "$will_overflow" == 1 ]]; then
        install_cpu_speed_fix=1
        CPU_SPEED_STATUS="TSC: ${display_rate}; 32-bit counter overflows, selected automatically."
    else
        install_cpu_speed_fix=0
        CPU_SPEED_STATUS="TSC: ${display_rate}; below the 32-bit overflow threshold."
    fi
}

sync_dependencies() {
    if (( install_german )); then
        convert_audio=0
    fi
    if (( configure_widescreen )); then
        [[ -n "$resolution" ]] || resolution=720p
    else
        resolution=''
    fi
    case "$video_mode" in
        ''|none|settings|manual) ;;
        *) video_mode='' ;;
    esac
    if [[ "$video_mode" == manual ]]; then
        [[ "$video_aspect" == standard || "$video_aspect" == widescreen ]] || video_aspect=standard
        [[ "$video_language" == english || "$video_language" == german ]] || video_language=english
    else
        video_aspect=''
        video_language=''
    fi
    # Steam launch options are an external Steam-client change. Never keep
    # that task selected for a standalone/test copy.
    if (( ! TARGET_IS_STEAM )); then
        install_gamescope_launcher=0
    fi

    if (( install_gamescope_launcher )); then
        [[ -n "$gamescope_backend" ]] || gamescope_backend=auto
    else
        gamescope_backend=''
        use_gamescope_mouse_sensitivity=0
        use_fullscreen=0
    fi
}

item_enabled() {
    case "$1" in
        change_path|german|nocd|cpu_speed|mouse|widescreen|videos_none|videos_settings|videos_manual) return 0 ;;
        gamescope_launcher) (( TARGET_IS_STEAM )) ;;
        audio) (( ! install_german )) ;;
        720p|1080p|1440p|4k) (( configure_widescreen )) ;;
        video_standard|video_widescreen|video_english|video_german) [[ "$video_mode" == manual ]] ;;
        backend_auto|backend_wayland|backend_sdl|gamescope_mouse_sensitivity|fullscreen) (( install_gamescope_launcher )) ;;
        apply) has_selected_tasks && game_directory_is_valid "$TARGET_DIR" ;;
        *) return 1 ;;
    esac
}

item_checked() {
    case "$1" in
        german) (( install_german )) ;;
        audio) (( convert_audio )) ;;
        nocd) (( install_nocd )) ;;
        cpu_speed) (( install_cpu_speed_fix )) ;;
        mouse) (( configure_mouse )) ;;
        widescreen) (( configure_widescreen )) ;;
        720p|1080p|1440p|4k) [[ "$resolution" == "$1" ]] ;;
        videos_none) [[ "$video_mode" == none ]] ;;
        videos_settings) [[ "$video_mode" == settings ]] ;;
        videos_manual) [[ "$video_mode" == manual ]] ;;
        video_standard) [[ "$video_aspect" == standard ]] ;;
        video_widescreen) [[ "$video_aspect" == widescreen ]] ;;
        video_english) [[ "$video_language" == english ]] ;;
        video_german) [[ "$video_language" == german ]] ;;
        gamescope_launcher) (( install_gamescope_launcher )) ;;
        backend_auto) [[ "$gamescope_backend" == auto ]] ;;
        backend_wayland) [[ "$gamescope_backend" == wayland ]] ;;
        backend_sdl) [[ "$gamescope_backend" == sdl ]] ;;
        gamescope_mouse_sensitivity) (( use_gamescope_mouse_sensitivity )) ;;
        fullscreen) (( use_fullscreen )) ;;
        *) return 1 ;;
    esac
}

has_selected_tasks() {
    (( install_german || convert_audio || install_nocd || install_cpu_speed_fix || configure_mouse )) || display_configuration_requested || video_install_requested
}

display_configuration_requested() {
    (( configure_widescreen || install_gamescope_launcher ))
}

video_install_requested() {
    [[ "$video_mode" == settings || "$video_mode" == manual ]]
}

resolve_video_selection() {
    resolved_video_aspect=''
    resolved_video_language=''
    case "$video_mode" in
        settings)
            if (( configure_widescreen )); then resolved_video_aspect=widescreen; else resolved_video_aspect=standard; fi
            if (( install_german )); then resolved_video_language=german; else resolved_video_language=english; fi
            ;;
        manual)
            resolved_video_aspect="$video_aspect"
            resolved_video_language="$video_language"
            ;;
    esac
    [[ "$resolved_video_aspect" == standard || "$resolved_video_aspect" == widescreen ]] || return 1
    [[ "$resolved_video_language" == english || "$resolved_video_language" == german ]] || return 1
}

indicator() {
    if [[ "$selected_item" == "$1" ]]; then
        printf '%b➤%b' "$CYAN" "$RESET"
    else
        printf ' '
    fi
}

checkbox_symbol() {
    local enabled="$1"
    local checked="$2"
    if (( enabled && checked )); then printf '▣';
    elif (( enabled )); then printf '□';
    elif (( checked )); then printf '▩';
    else printf '▤'; fi
}

item_color() {
    local enabled="$1"
    local checked="$2"
    if (( enabled && checked )); then printf '%s' "$GREEN";
    elif (( enabled )); then printf '%s' "$YELLOW";
    elif (( checked )); then printf '%s' "$LIGHT_GRAY";
    else printf '%s' "$GRAY"; fi
}

checkbox_line() {
    local id="$1"
    local text="$2"
    local indent="${3:-2}"
    local enabled=0 checked=0
    item_enabled "$id" && enabled=1
    item_checked "$id" && checked=1
    printf '%*s%s %b%s %s%b\n' "$indent" '' "$(indicator "$id")" \
        "$(item_color "$enabled" "$checked")" "$(checkbox_symbol "$enabled" "$checked")" "$text" "$RESET"
}

radio_line() {
    local id="$1"
    local text="$2"
    local indent="${3:-5}"
    local enabled=0 checked=0 icon color
    item_enabled "$id" && enabled=1
    item_checked "$id" && checked=1
    if (( checked )); then icon='●'; else icon='◯'; fi
    color="$(item_color "$enabled" "$checked")"
    printf '%*s%s %b%s %s%b\n' "$indent" '' "$(indicator "$id")" "$color" "$icon" "$text" "$RESET"
}

render_menu_body() {
    header
    section_heading 'Current game path'

    if game_directory_is_valid "$TARGET_DIR"; then
        printf '  %b"%s/"%b\n' "$WHITE" "$TARGET_DIR" "$RESET"
    else
        printf '  %bNo valid Independence War 2 installation selected.%b\n' "$YELLOW" "$RESET"
    fi

    printf '  %s %bChange path ...%b\n' \
        "$(indicator change_path)" "$YELLOW" "$RESET"

    [[ -z "$PATH_MESSAGE" ]] || \
        printf '  %b%s%b\n' "$YELLOW" "$PATH_MESSAGE" "$RESET"

    printf '\n'

    section_heading 'Installation settings'

    checkbox_line german 'Install german Game-data'
    checkbox_line audio 'Convert Audio-Files to work under Linux'
    checkbox_line nocd 'Install No-CD-Fix'
    checkbox_line cpu_speed 'Install CPU Speed Fix'

    [[ -z "$CPU_SPEED_STATUS" ]] || \
        printf '       %b%s%b\n' "$GRAY" "$CPU_SPEED_STATUS" "$RESET"

    checkbox_line mouse 'Configure mouse ship controls'
    checkbox_line widescreen 'Configure game-settings for 16:9'

    radio_line 720p '720p'
    radio_line 1080p '1080p'
    radio_line 1440p '1440p'
    radio_line 4k '4k'

    printf '\n     %bVideo variants:%b\n' "$WHITE" "$RESET"

    radio_line videos_none "Don't change videos"
    radio_line videos_settings 'Install videos based on settings'
    radio_line videos_manual 'Install manually selected videos'
    radio_line video_standard 'Install 4:3 videos' 8
    radio_line video_widescreen 'Install 16:9 videos' 8
    radio_line video_english 'Install English videos' 8
    radio_line video_german 'Install German videos' 8

    checkbox_line gamescope_launcher 'Set Gamescope as Steam launch option'

    printf '     %bGamescope backend:%b\n' "$WHITE" "$RESET"

    radio_line backend_auto 'Auto-detect for the current desktop session'
    radio_line backend_wayland 'Force native Wayland backend'
    radio_line backend_sdl 'Force SDL backend'

    checkbox_line gamescope_mouse_sensitivity \
        'Use slow Gamescope mouse sensitivity (-s 0.045)'

    checkbox_line fullscreen 'Use fullscreen'

    printf '\n'

    local action_color="$GRAY"
    item_enabled apply && action_color="$GREEN"

    printf ' %s %bPatch my game.%b\n\n' \
        "$(indicator apply)" "$action_color" "$RESET"

    printf '%bArrow keys / W S:%b Move   %bA D / Enter / Space:%b Select   %bEsc:%b Exit\n' \
        "$GRAY" "$RESET" "$GRAY" "$RESET" "$GRAY" "$RESET"

    printf '%bDisabled options are resolved automatically from the selected dependencies.%b\n' \
        "$GRAY" "$RESET"
}

menu_screen() {
    local frame marker=$'\x1e'
    frame="$(
        render_menu_body
        printf '%s' "$marker"
    )"
    frame="${frame%$marker}"
    begin_frame
    printf '\e[2J\e[H%s' "$frame"
    end_frame
}

move_selection() {
    local direction="$1"
    local -a available=()
    local item index=-1 i
    for item in "${ITEM_ORDER[@]}"; do
        item_enabled "$item" && available+=("$item")
    done
    for i in "${!available[@]}"; do
        [[ "${available[$i]}" == "$selected_item" ]] && { index="$i"; break; }
    done
    if (( index < 0 )); then
        selected_item="${available[0]}"
        return 0
    fi
    if (( direction < 0 )); then
        index=$(( (index - 1 + ${#available[@]}) % ${#available[@]} ))
    else
        index=$(( (index + 1) % ${#available[@]} ))
    fi
    selected_item="${available[$index]}"
}

toggle_selected() {
    case "$selected_item" in
        change_path) choose_game_directory ;;
        german) install_german=$(( ! install_german )) ;;
        audio) convert_audio=$(( ! convert_audio )) ;;
        nocd) install_nocd=$(( ! install_nocd )) ;;
        cpu_speed) install_cpu_speed_fix=$(( ! install_cpu_speed_fix )) ;;
        mouse) configure_mouse=$(( ! configure_mouse )) ;;
        widescreen) configure_widescreen=$(( ! configure_widescreen )) ;;
        720p|1080p|1440p|4k) resolution="$selected_item" ;;
        videos_none) video_mode=none ;;
        videos_settings) video_mode=settings ;;
        videos_manual) video_mode=manual ;;
        video_standard) video_aspect=standard ;;
        video_widescreen) video_aspect=widescreen ;;
        video_english) video_language=english ;;
        video_german) video_language=german ;;
        gamescope_launcher) install_gamescope_launcher=$(( ! install_gamescope_launcher )) ;;
        backend_auto) gamescope_backend=auto ;;
        backend_wayland) gamescope_backend=wayland ;;
        backend_sdl) gamescope_backend=sdl ;;
        gamescope_mouse_sensitivity) use_gamescope_mouse_sensitivity=$(( ! use_gamescope_mouse_sensitivity )) ;;
        fullscreen) use_fullscreen=$(( ! use_fullscreen )) ;;
        apply) execute_tasks; return ;;
    esac
    sync_dependencies
    item_enabled "$selected_item" || selected_item='change_path'
}

read_key() {
    local first second=''
    IFS= read -r -s -n1 first || return 1
    if [[ "$first" == $'\e' ]]; then
        IFS= read -r -s -n2 -t 0.03 second || true
        case "$second" in
            '[A') printf 'up' ;;
            '[B') printf 'down' ;;
            '[C') printf 'right' ;;
            '[D') printf 'left' ;;
            *) printf 'escape' ;;
        esac
    elif [[ -z "$first" || "$first" == $'\n' || "$first" == $'\r' ]]; then
        printf 'activate'
    elif [[ "$first" == ' ' ]]; then
        printf 'activate'
    else
        case "$first" in
            w|W) printf 'up' ;;
            s|S) printf 'down' ;;
            a|A) printf 'left' ;;
            d|D) printf 'right' ;;
            *) printf 'none' ;;
        esac
    fi
}

task_label() {
    case "$1" in
        german) printf 'Install german Game-data' ;;
        audio) printf 'Convert Audio-Files to work under Linux' ;;
        nocd) printf 'Install No-CD-Fix' ;;
        cpu-speed) printf 'Install CPU Speed Fix' ;;
        mouse) printf 'Configure mouse ship controls' ;;
        display) printf 'Configure game display' ;;
        german-data-downloads) printf 'Download and verify German game data' ;;
        german-video-downloads) printf 'Download and verify German story videos' ;;
        video-downloads) printf 'Download and verify selected videos' ;;
        videos) printf 'Install %s %s videos' "$resolved_video_language" "$resolved_video_aspect" ;;
        steam-launcher) printf 'Set Gamescope as Steam launch option' ;;
    esac
}

build_tasks() {
    TASK_IDS=()
    (( install_german )) && TASK_IDS+=(german-data-downloads)
    # Without a complete video selection, the German base-data patch needs
    # only its three language-specific original 4:3 cinematics.  With a full
    # video selection, that later task is the single authoritative source.
    if (( install_german )) && ! video_install_requested; then
        TASK_IDS+=(german-video-downloads)
    fi
    if video_install_requested; then
        resolve_video_selection || return 1
        # Download and validate before any game files are backed up or modified.
        TASK_IDS+=(video-downloads)
    fi
    # All preceding tasks only download and verify external inputs. The CPU
    # fix is therefore the first selected task that may change the game.
    (( install_cpu_speed_fix )) && TASK_IDS+=(cpu-speed)
    (( convert_audio )) && TASK_IDS+=(audio)
    (( install_german )) && TASK_IDS+=(german)
    (( install_nocd )) && TASK_IDS+=(nocd)
    (( configure_mouse )) && TASK_IDS+=(mouse)
    display_configuration_requested && TASK_IDS+=(display)
    if video_install_requested; then
        TASK_IDS+=(videos)
    fi
    (( install_gamescope_launcher )) && TASK_IDS+=(steam-launcher)
    TASK_STATES=()
    local _
    for _ in "${TASK_IDS[@]}"; do TASK_STATES+=(pending); done
}

repeat_char() {
    local count="$1" character="$2" output=''
    while (( count > 0 )); do output+="$character"; ((count -= 1)); done
    printf '%s' "$output"
}

progress_bar() {
    local current="$1" total="$2" width=21 units full rem empty fractional=''
    (( total > 0 )) || total=1
    (( current < 0 )) && current=0
    (( current > total )) && current="$total"
    units=$(( current * width * 8 / total ))
    full=$(( units / 8 ))
    rem=$(( units % 8 ))
    case "$rem" in
        1) fractional='▏' ;; 2) fractional='▎' ;; 3) fractional='▍' ;; 4) fractional='▌' ;;
        5) fractional='▋' ;; 6) fractional='▊' ;; 7) fractional='▉' ;;
    esac
    empty=$(( width - full ))
    (( rem > 0 )) && empty=$(( empty - 1 ))
    printf '<%b%s%s%b%s>' "$GREEN" "$(repeat_char "$full" '█')" "$fractional" "$GRAY" "$(repeat_char "$empty" ' ')"
}

task_icon() {
    local state="$1" spinner="$2"
    case "$state" in
        done) printf '%b✓%b' "$GREEN" "$RESET" ;;
        active) printf '%b%s%b' "$YELLOW" "${SPINNER_FRAMES[$((spinner % ${#SPINNER_FRAMES[@]}))]}" "$RESET" ;;
        *) printf '%b▹%b' "$YELLOW" "$RESET" ;;
    esac
}

render_execution_body() {
    local active_index="$1" spinner="$2" step_current="$3" step_total="$4"
    local total_tasks="${#TASK_IDS[@]}" completed=0 overall_current i state id next=''
    for state in "${TASK_STATES[@]}"; do [[ "$state" == done ]] && ((completed += 1)); done
    overall_current=$(( completed * 1000 ))
    if (( active_index >= 0 && active_index < total_tasks )); then
        (( step_total > 0 )) || step_total=1
        overall_current=$(( overall_current + step_current * 1000 / step_total ))
    fi
    header
    printf '%bSelected tasks:%b\n\n' "$WHITE" "$RESET"
    for i in "${!TASK_IDS[@]}"; do
        id="${TASK_IDS[$i]}"
        state="${TASK_STATES[$i]}"
        printf '   %s %s\n' "$(task_icon "$state" "$spinner")" "$(task_label "$id")"
    done
    printf '\nProgress: %s  %3d%%\n' "$(progress_bar "$overall_current" "$(( total_tasks * 1000 ))")" "$(( overall_current * 100 / (total_tasks * 1000) ))"
    if (( active_index >= 0 && active_index < total_tasks )); then
        printf 'Current Task: %s\n' "$(task_label "${TASK_IDS[$active_index]}")"
    fi
    for i in "${!TASK_IDS[@]}"; do
        if [[ "${TASK_STATES[$i]}" == pending ]]; then next="${TASK_IDS[$i]}"; break; fi
    done
    [[ -n "$next" ]] && printf 'Next Task: %s\n' "$(task_label "$next")"
}

execution_screen() {
    local frame marker=$'\x1e'
    frame="$(
        render_execution_body "$@"
        printf '%s' "$marker"
    )"
    frame="${frame%$marker}"
    begin_frame
    printf '\e[2J\e[H%s' "$frame"
    end_frame
}

run_task_command() {
    case "$1" in
        german)
            if video_install_requested; then
                GERPATCH_GERMAN_GAME_DATA_PREPARED=1 GERPATCH_SKIP_GERMAN_STORY_VIDEOS=1 "$PATCH_DIR/apply-german-patch.sh" "$TARGET_DIR"
            else
                GERPATCH_GERMAN_GAME_DATA_PREPARED=1 GERPATCH_GERMAN_STORY_VIDEOS_PREPARED=1 "$PATCH_DIR/apply-german-patch.sh" "$TARGET_DIR"
            fi
            ;;
        audio) "$PATCH_DIR/modules/convert-audio.sh" "$TARGET_DIR" ;;
        nocd) "$PATCH_DIR/modules/install-nocd.sh" "$TARGET_DIR" ;;
        cpu-speed) "$PATCH_DIR/modules/install-cpu-speed-fix.sh" "$TARGET_DIR" ;;
        mouse) "$PATCH_DIR/modules/configure-mouse.sh" "$TARGET_DIR" ;;
        german-data-downloads) "$PATCH_DIR/modules/prepare-german-game-data.sh" ;;
        german-video-downloads) "$PATCH_DIR/modules/prepare-video-downloads.sh" german standard intro.bik midtro.bik Outro.bik ;;
        video-downloads) "$PATCH_DIR/modules/prepare-video-downloads.sh" "$resolved_video_language" "$resolved_video_aspect" ;;
        videos) "$PATCH_DIR/modules/install-videos.sh" "$TARGET_DIR" "$resolved_video_language" "$resolved_video_aspect" ;;
        display)
            local backend="${gamescope_backend:-auto}"
            if (( configure_widescreen )); then
                "$PATCH_DIR/modules/configure-display.sh" "$TARGET_DIR" "$resolution" "$use_fullscreen" "$backend" "$use_gamescope_mouse_sensitivity"
            else
                "$PATCH_DIR/modules/configure-display.sh" "$TARGET_DIR" keep "$use_fullscreen" "$backend" "$use_gamescope_mouse_sensitivity"
            fi
            ;;
        steam-launcher) "$PATCH_DIR/modules/configure-steam-gamescope-launcher.sh" "$TARGET_DIR" ;;
    esac
}

run_task() {
    local id="$1" index="$2" spinner=0 stage current total notice_file
    progress_file="$(mktemp)"
    operation_log="$(mktemp)"
    notice_file="$(mktemp)"
    printf 'starting|0|1\n' > "$progress_file"
    GERPATCH_PROGRESS_FILE="$progress_file" GERPATCH_NOTICE_FILE="$notice_file" run_task_command "$id" > "$operation_log" 2>&1 &
    local worker_pid=$!
    while kill -0 "$worker_pid" 2>/dev/null; do
        stage='starting'; current=0; total=1
        [[ -s "$progress_file" ]] && IFS='|' read -r stage current total < "$progress_file"
        [[ "$current" =~ ^[0-9]+$ ]] || current=0
        [[ "$total" =~ ^[1-9][0-9]*$ ]] || total=1
        execution_screen "$index" "$spinner" "$current" "$total"
        spinner=$((spinner + 1))
        sleep 0.09
    done
    if wait "$worker_pid"; then
        if [[ -s "$notice_file" ]]; then
            clear_screen
            header
            cat -- "$operation_log"
            printf '\nPress any key to continue.\n'
            IFS= read -r -s -n1 _ || true
        fi
        rm -f -- "$progress_file" "$operation_log" "$notice_file"
        progress_file=''
        operation_log=''
        return 0
    fi
    local log_dir="$PATCH_DIR/logs" error log_path
    mkdir -p -- "$log_dir"
    log_path="$log_dir/ultimate-patcher-$(date +%Y%m%d-%H%M%S)-${id}.log"
    cp -a -- "$operation_log" "$log_path"
    rm -f -- "$notice_file"
    error="$(tail -n 1 "$operation_log")"
    clear_screen
    header
    printf '%bTask failed:%b %s\n\n' "$YELLOW" "$RESET" "$(task_label "$id")"
    printf '%s\n\n' "$error"
    printf 'Detailed log: %s\n' "$log_path"
    printf 'Press any key to return to the menu.\n'
    IFS= read -r -s -n1 _ || true
    return 1
}

execute_tasks() {
    sync_dependencies
    build_tasks
    (( ${#TASK_IDS[@]} > 0 )) || return 0
    if ! game_directory_is_valid "$TARGET_DIR"; then
        PATH_MESSAGE='Select a valid EdgeOfChaos.exe before applying changes.'
        return 1
    fi
    local i
    for i in "${!TASK_IDS[@]}"; do
        TASK_STATES[$i]=active
        execution_screen "$i" 0 0 1
        if run_task "${TASK_IDS[$i]}" "$i"; then
            TASK_STATES[$i]=done
        else
            TASK_STATES[$i]=pending
            return 1
        fi
    done
    execution_screen -1 0 1 1
    printf '\n%bAll selected tasks are complete.%b\nPress any key to exit.\n' "$GREEN" "$RESET"
    IFS= read -r -s -n1 _ || true
    return 0
}

self_test() {
    local test_root test_game detected test_checker screen_output
    test_root="$(mktemp -d)"
    test_game="$test_root/Library/steamapps/common/Independence War 2 - Edge of Chaos"
    mkdir -p -- "$test_game"
    touch "$test_game/EdgeOfChaos.exe" "$test_game/resource.zip"
    mkdir -p -- "$test_root/Steam/steamapps"
    printf '"libraryfolders"\n{\n    "0"\n    {\n        "path"\t\t"%s"\n    }\n}\n' "$test_root/Library" > "$test_root/Steam/steamapps/libraryfolders.vdf"
    printf '"AppState"\n{\n    "appid"\t\t"%s"\n    "installdir"\t\t"Independence War 2 - Edge of Chaos"\n}\n' "$APP_ID" > "$test_root/Library/steamapps/appmanifest_${APP_ID}.acf"
    detected="$(IW2_STEAM_ROOT="$test_root/Steam" detect_steam_game_dir)" || { rm -rf -- "$test_root"; return 1; }
    [[ "$detected" == "$test_game" ]] || { rm -rf -- "$test_root"; return 1; }
    rm -rf -- "$test_root"

    test_checker="$(mktemp)"
    printf '#!/usr/bin/env bash\nprintf "tsc_hz=5000000000\\nwill_overflow_u32=1\\n"\n' > "$test_checker"
    chmod 0755 -- "$test_checker"
    install_cpu_speed_fix=0
    IW2_CPU_SPEED_CHECKER="$test_checker" detect_cpu_speed_fix_default || { rm -f -- "$test_checker"; return 1; }
    (( install_cpu_speed_fix )) || { rm -f -- "$test_checker"; return 1; }
    printf '#!/usr/bin/env bash\nprintf "tsc_hz=3000000000\\nwill_overflow_u32=0\\n"\n' > "$test_checker"
    IW2_CPU_SPEED_CHECKER="$test_checker" detect_cpu_speed_fix_default || { rm -f -- "$test_checker"; return 1; }
    (( ! install_cpu_speed_fix )) || { rm -f -- "$test_checker"; return 1; }
    rm -f -- "$test_checker"

    install_german=0; convert_audio=0; install_nocd=0; install_cpu_speed_fix=0; configure_mouse=0
    configure_widescreen=0; resolution=''; install_gamescope_launcher=0; use_fullscreen=0
    gamescope_backend=''; use_gamescope_mouse_sensitivity=0
    video_mode=''; video_aspect=''; video_language=''; resolved_video_aspect=''; resolved_video_language=''
    sync_dependencies
    has_selected_tasks && return 1
    [[ "$selected_item" == change_path ]] || return 1
    item_enabled video_standard && return 1
    video_mode=manual; sync_dependencies
    item_enabled video_standard && item_checked video_standard && item_checked video_english || return 1
    video_aspect=widescreen; video_language=german; sync_dependencies
    resolve_video_selection && [[ "$resolved_video_aspect" == widescreen && "$resolved_video_language" == german ]] || return 1
    video_mode=settings; sync_dependencies
    item_enabled video_standard && return 1
    configure_widescreen=1; install_german=0; resolve_video_selection && [[ "$resolved_video_aspect" == widescreen && "$resolved_video_language" == english ]] || return 1
    install_german=1; resolve_video_selection && [[ "$resolved_video_language" == german ]] || return 1
    video_mode=''; configure_widescreen=0; install_german=0; sync_dependencies
    install_german=1; convert_audio=1
    sync_dependencies
    (( ! convert_audio )) || return 1
    TARGET_IS_STEAM=1
    install_gamescope_launcher=1; sync_dependencies
    item_enabled backend_auto && item_checked backend_auto && ! item_checked gamescope_mouse_sensitivity || return 1
    gamescope_backend=sdl; use_gamescope_mouse_sensitivity=1
    item_checked backend_sdl && ! item_checked backend_auto && item_checked gamescope_mouse_sensitivity || return 1
    display_configuration_requested || return 1
    install_german=0; convert_audio=0; install_nocd=0; install_cpu_speed_fix=0; configure_mouse=0
    configure_widescreen=0; resolution=''; install_gamescope_launcher=0; use_fullscreen=0
    gamescope_backend=''; use_gamescope_mouse_sensitivity=0
    video_mode=''; video_aspect=''; video_language=''
    install_german=0; convert_audio=1; install_nocd=1; configure_mouse=1
    sync_dependencies; build_tasks || return 1
    [[ "${TASK_IDS[*]}" == 'audio nocd mouse' ]] || return 1
    install_cpu_speed_fix=1
    sync_dependencies; build_tasks || return 1
    [[ "${TASK_IDS[*]}" == 'cpu-speed audio nocd mouse' ]] || return 1
    install_cpu_speed_fix=0
    install_german=1; convert_audio=0; install_nocd=0; configure_mouse=0
    sync_dependencies; build_tasks || return 1
    [[ "${TASK_IDS[*]}" == 'german-data-downloads german-video-downloads german' ]] || return 1
    video_mode=manual; video_aspect=standard; video_language=german
    sync_dependencies; build_tasks || return 1
    [[ "${TASK_IDS[*]}" == 'german-data-downloads video-downloads german videos' ]] || return 1
    install_german=0; video_language=english
    sync_dependencies; build_tasks || return 1
    [[ "${TASK_IDS[*]}" == 'video-downloads videos' ]] || return 1
    TASK_STATES[0]=active
    screen_output="$(execution_screen 0 3 1 4)"
    [[ "$screen_output" == $'\e[?2026h\e[2J\e[H'* ]] || return 1
    [[ "$screen_output" == *$'\e[?2026l' ]] || return 1
    [[ "$screen_output" == *'Selected tasks:'* && "$screen_output" == *'Current Task:'* && "$screen_output" == *'Next Task:'* ]] || return 1
    printf 'Ultimate Patcher dependency self-test passed.\n'
}

main() {
    if [[ "${1:-}" == --self-test ]]; then self_test; return; fi
    if [[ "${1:-}" == --help || $# -gt 1 ]]; then
        printf 'Usage: %s [IW2 installation directory]\n' "$(basename -- "$0")"
        return 0
    fi
    [[ -t 0 && -t 1 ]] || { printf 'This interactive patcher needs a terminal.\n' >&2; return 69; }
    [[ -x "$PATCH_DIR/apply-german-patch.sh" ]] || { printf 'German patch module is missing.\n' >&2; return 66; }

    hide_cursor
    start_loading_screen

    if (( $# == 1 )); then
        set_game_directory "$1" || {
            stop_loading_screen
            printf 'Not an Independence War 2 installation: %s\n' "$1" >&2
            return 66
        }
        TARGET_SOURCE=argument
    else
        detect_initial_game_directory || true
    fi

    detect_cpu_speed_fix_default || true
    stop_loading_screen
    local redraw=1 key
    while :; do
        if (( redraw )); then
            menu_screen
            redraw=0
        fi

        if [[ -n "$PENDING_KEY" ]]; then
            key="$PENDING_KEY"
            PENDING_KEY=''
        else
            key="$(read_key)" || break
        fi

        case "$key" in
            up)
                if navigation_allowed up; then
                    move_selection -1
                    redraw=1
                fi
                coalesce_navigation_repeats up
                ;;
            down)
                if navigation_allowed down; then
                    move_selection 1
                    redraw=1
                fi
                coalesce_navigation_repeats down
                ;;
            left|right|activate)
                if toggle_selected; then
                    [[ "$selected_item" == apply ]] && break
                fi
                redraw=1
                ;;
            escape) break ;;
        esac
    done
}
clear
main "$@"
