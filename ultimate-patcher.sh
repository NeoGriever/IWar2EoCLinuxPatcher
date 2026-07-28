#!/usr/bin/env bash
# Console front end for the complete, selectable I-War 2 patch package.
set -uo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEFAULT_TARGET="$HOME/.local/share/Steam/steamapps/common/Independence War 2 - Edge of Chaos"
TARGET_DIR="${IW2_GAME_DIR:-$DEFAULT_TARGET}"

RESET=$'\e[0m'
GRAY=$'\e[38;5;245m'
LIGHT_GRAY=$'\e[38;5;252m'
YELLOW=$'\e[38;5;220m'
GREEN=$'\e[38;5;46m'
CYAN=$'\e[38;5;51m'
WHITE=$'\e[97m'
SPINNER_FRAMES=(⠇ ⠦ ⠴ ⠸ ⠙ ⠋)

# Every task starts deselected.  Dependencies are still resolved immediately
# when the user selects an option.
install_german=0
convert_audio=0
install_f14=0
fix_english=0
install_nocd=0
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
selected_item='german'

declare -a ITEM_ORDER=(german audio f14 english nocd mouse widescreen 720p 1080p 1440p 4k videos_none videos_settings videos_manual video_standard video_widescreen video_english video_german gamescope_launcher backend_auto backend_wayland backend_sdl gamescope_mouse_sensitivity fullscreen apply)
declare -a TASK_IDS=()
declare -a TASK_STATES=()
operation_log=''
progress_file=''
cursor_hidden=0

clear_screen() { printf '\e[2J\e[H'; }
hide_cursor() { printf '\e[?25l'; cursor_hidden=1; }
show_cursor() { printf '%b\e[?25h' "$RESET"; }

cleanup() {
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

sync_dependencies() {
    if (( install_german )); then
        convert_audio=0
        fix_english=0
    fi
    if (( ! install_f14 )); then
        fix_english=0
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
        german|f14|nocd|mouse|widescreen|videos_none|videos_settings|videos_manual|gamescope_launcher) return 0 ;;
        audio) (( ! install_german )) ;;
        english) (( install_f14 && ! install_german )) ;;
        720p|1080p|1440p|4k) (( configure_widescreen )) ;;
        video_standard|video_widescreen|video_english|video_german) [[ "$video_mode" == manual ]] ;;
        backend_auto|backend_wayland|backend_sdl|gamescope_mouse_sensitivity|fullscreen) (( install_gamescope_launcher )) ;;
        apply) has_selected_tasks ;;
        *) return 1 ;;
    esac
}

item_checked() {
    case "$1" in
        german) (( install_german )) ;;
        audio) (( convert_audio )) ;;
        f14) (( install_f14 )) ;;
        english) (( fix_english )) ;;
        nocd) (( install_nocd )) ;;
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
    (( install_german || convert_audio || install_f14 || fix_english || install_nocd || configure_mouse )) || display_configuration_requested || video_install_requested
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

menu_screen() {
    clear_screen
    header
    printf '%bSelect your Options:%b\n\n' "$WHITE" "$RESET"
    checkbox_line german 'Install german Game-data'
    checkbox_line audio 'Convert Audio-Files to work under Linux'
    checkbox_line f14 'Install Patch 14.6 from i-war2.com'
    checkbox_line english 'Fix english messages after 14.6-Patch'
    checkbox_line nocd 'Install No-CD-Fix'
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
    checkbox_line gamescope_mouse_sensitivity 'Use slow Gamescope mouse sensitivity (-s 0.045)'
    checkbox_line fullscreen 'Use fullscreen'
    printf '\n'
    local action_color="$GRAY"
    has_selected_tasks && action_color="$GREEN"
    printf ' %s %bPatch my game.%b\n\n' "$(indicator apply)" "$action_color" "$RESET"
    printf '%bArrow keys / W S:%b Move   %bA D / Enter / Space:%b Select   %bEsc:%b Exit\n' \
        "$GRAY" "$RESET" "$GRAY" "$RESET" "$GRAY" "$RESET"
    printf '%bDisabled options are resolved automatically from the selected dependencies.%b\n' "$GRAY" "$RESET"
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
    (( index >= 0 )) || index=0
    if (( direction < 0 )); then
        index=$(( (index - 1 + ${#available[@]}) % ${#available[@]} ))
    else
        index=$(( (index + 1) % ${#available[@]} ))
    fi
    selected_item="${available[$index]}"
}

toggle_selected() {
    case "$selected_item" in
        german) install_german=$(( ! install_german )) ;;
        audio) convert_audio=$(( ! convert_audio )) ;;
        f14) install_f14=$(( ! install_f14 )) ;;
        english) fix_english=$(( ! fix_english )) ;;
        nocd) install_nocd=$(( ! install_nocd )) ;;
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
    item_enabled "$selected_item" || selected_item='german'
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
        german|german-f14) printf 'Install german Game-data' ;;
        audio) printf 'Convert Audio-Files to work under Linux' ;;
        f14) printf 'Install Patch 14.6 from i-war2.com' ;;
        english) printf 'Fix english messages after 14.6-Patch' ;;
        nocd) printf 'Install No-CD-Fix' ;;
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
    (( convert_audio )) && TASK_IDS+=(audio)
    (( install_f14 )) && TASK_IDS+=(f14)
    if (( install_german )); then
        if (( install_f14 )); then TASK_IDS+=(german-f14); else TASK_IDS+=(german); fi
    fi
    (( fix_english )) && TASK_IDS+=(english)
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

execution_screen() {
    local active_index="$1" spinner="$2" step_current="$3" step_total="$4"
    local total_tasks="${#TASK_IDS[@]}" completed=0 overall_current i state id next=''
    for state in "${TASK_STATES[@]}"; do [[ "$state" == done ]] && ((completed += 1)); done
    overall_current=$(( completed * 1000 ))
    if (( active_index >= 0 && active_index < total_tasks )); then
        (( step_total > 0 )) || step_total=1
        overall_current=$(( overall_current + step_current * 1000 / step_total ))
    fi
    clear_screen
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

run_task_command() {
    case "$1" in
        german)
            if video_install_requested; then
                GERPATCH_GERMAN_GAME_DATA_PREPARED=1 GERPATCH_SKIP_GERMAN_STORY_VIDEOS=1 "$PATCH_DIR/apply-german-patch.sh" "$TARGET_DIR"
            else
                GERPATCH_GERMAN_GAME_DATA_PREPARED=1 GERPATCH_GERMAN_STORY_VIDEOS_PREPARED=1 "$PATCH_DIR/apply-german-patch.sh" "$TARGET_DIR"
            fi
            ;;
        german-f14)
            if video_install_requested; then
                GERPATCH_GERMAN_GAME_DATA_PREPARED=1 GERPATCH_SKIP_GERMAN_STORY_VIDEOS=1 "$PATCH_DIR/modules/install-german-after-f14.6.sh" "$TARGET_DIR"
            else
                GERPATCH_GERMAN_GAME_DATA_PREPARED=1 GERPATCH_GERMAN_STORY_VIDEOS_PREPARED=1 "$PATCH_DIR/modules/install-german-after-f14.6.sh" "$TARGET_DIR"
            fi
            ;;
        audio) "$PATCH_DIR/modules/convert-audio.sh" "$TARGET_DIR" ;;
        f14) "$PATCH_DIR/modules/install-f14.6.sh" "$TARGET_DIR" ;;
        english) "$PATCH_DIR/modules/fix-f14.6-english.sh" "$TARGET_DIR" ;;
        nocd) "$PATCH_DIR/modules/install-nocd.sh" "$TARGET_DIR" ;;
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
    local id="$1" index="$2" spinner=0 stage current total
    progress_file="$(mktemp)"
    operation_log="$(mktemp)"
    printf 'starting|0|1\n' > "$progress_file"
    GERPATCH_PROGRESS_FILE="$progress_file" run_task_command "$id" > "$operation_log" 2>&1 &
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
        rm -f -- "$progress_file" "$operation_log"
        progress_file=''
        operation_log=''
        return 0
    fi
    local log_dir="$PATCH_DIR/logs" error log_path
    mkdir -p -- "$log_dir"
    log_path="$log_dir/ultimate-patcher-$(date +%Y%m%d-%H%M%S)-${id}.log"
    cp -a -- "$operation_log" "$log_path"
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
    printf '\n%bAll selected tasks are complete.%b\nPress any key to return to the menu.\n' "$GREEN" "$RESET"
    IFS= read -r -s -n1 _ || true
}

self_test() {
    install_german=0; convert_audio=0; install_f14=0; fix_english=0; configure_mouse=0
    configure_widescreen=0; resolution=''; install_gamescope_launcher=0; use_fullscreen=0
    gamescope_backend=''; use_gamescope_mouse_sensitivity=0
    video_mode=''; video_aspect=''; video_language=''; resolved_video_aspect=''; resolved_video_language=''
    sync_dependencies
    has_selected_tasks && return 1
    [[ "$selected_item" == german ]] || return 1
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
    install_german=1; convert_audio=1; install_f14=1; fix_english=1
    sync_dependencies
    (( ! convert_audio && ! fix_english )) || return 1
    item_enabled english && return 1
    install_german=0; install_f14=1; fix_english=1; configure_widescreen=1
    sync_dependencies
    item_enabled english && item_enabled 720p || return 1
    install_f14=0; sync_dependencies
    (( ! fix_english )) || return 1
    install_gamescope_launcher=1; sync_dependencies
    item_enabled backend_auto && item_checked backend_auto && ! item_checked gamescope_mouse_sensitivity || return 1
    gamescope_backend=sdl; use_gamescope_mouse_sensitivity=1
    item_checked backend_sdl && ! item_checked backend_auto && item_checked gamescope_mouse_sensitivity || return 1
    display_configuration_requested || return 1
    install_german=0; convert_audio=0; install_f14=0; fix_english=0; install_nocd=0; configure_mouse=0
    configure_widescreen=0; resolution=''; install_gamescope_launcher=0; use_fullscreen=0
    gamescope_backend=''; use_gamescope_mouse_sensitivity=0
    video_mode=''; video_aspect=''; video_language=''
    install_german=1; sync_dependencies; build_tasks || return 1
    [[ "${TASK_IDS[*]}" == 'german-data-downloads german-video-downloads german' ]] || return 1
    video_mode=manual; video_aspect=standard; video_language=german
    sync_dependencies; build_tasks || return 1
    [[ "${TASK_IDS[*]}" == 'german-data-downloads video-downloads german videos' ]] || return 1
    install_german=0; video_language=english
    sync_dependencies; build_tasks || return 1
    [[ "${TASK_IDS[*]}" == 'video-downloads videos' ]] || return 1
    printf 'Ultimate Patcher dependency self-test passed.\n'
}

main() {
    if [[ "${1:-}" == --self-test ]]; then self_test; return; fi
    if [[ "${1:-}" == --help || $# -gt 1 ]]; then
        printf 'Usage: %s [IW2 installation directory]\n' "$(basename -- "$0")"
        return 0
    fi
    [[ $# -eq 0 ]] || TARGET_DIR="$1"
    TARGET_DIR="$(cd -- "$TARGET_DIR" 2>/dev/null && pwd -P)" || {
        printf 'Game directory does not exist: %s\n' "${1:-$TARGET_DIR}" >&2
        return 66
    }
    [[ -t 0 && -t 1 ]] || { printf 'This interactive patcher needs a terminal.\n' >&2; return 69; }
    [[ -x "$PATCH_DIR/apply-german-patch.sh" ]] || { printf 'German patch module is missing.\n' >&2; return 66; }
    hide_cursor
    while :; do
        menu_screen
        case "$(read_key)" in
            up) move_selection -1 ;;
            down) move_selection 1 ;;
            left|right|activate) toggle_selected ;;
            escape) break ;;
        esac
    done
}

main "$@"
