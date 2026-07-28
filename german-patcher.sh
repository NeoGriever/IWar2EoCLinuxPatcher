#!/usr/bin/env bash
# The original entry point now opens the selectable Ultimate Patcher.  Set
# IW2_LEGACY_GERMAN_PATCHER=1 only to access the retained one-action UI below.
if [[ "${IW2_LEGACY_GERMAN_PATCHER:-0}" != 1 ]]; then
    PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
    exec "$PATCH_DIR/ultimate-patcher.sh" "$@"
fi

# Interactive front end for the checksum-verified apply/restore scripts.
set -uo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
APPLY_SCRIPT="$PATCH_DIR/apply-german-patch.sh"
RESTORE_SCRIPT="$PATCH_DIR/restore-english.sh"
DEFAULT_TARGET="$HOME/.local/share/Steam/steamapps/common/Independence War 2 - Edge of Chaos"
TARGET_DIR="${IW2_GAME_DIR:-$DEFAULT_TARGET}"

DARK_GREEN=$'\e[38;5;22m'
LIGHT_GREEN=$'\e[38;5;82m'
YELLOW=$'\e[38;5;220m'
ORANGE=$'\e[38;5;208m'
GRAY=$'\e[38;5;245m'
RESET=$'\e[0m'

status_log=''
progress_file=''
operation_log=''
DETECTED_STATE=unknown

usage() {
    printf 'Usage: %s [IW2 installation directory]\n' "$(basename -- "$0")"
    printf 'Default: %s\n' "$DEFAULT_TARGET"
}

cleanup() {
    [[ -n "$status_log" ]] && rm -f -- "$status_log"
    [[ -n "$progress_file" ]] && rm -f -- "$progress_file"
    [[ -n "$operation_log" ]] && rm -f -- "$operation_log"
    printf '%b\e[?25h' "$RESET"
}

trap cleanup EXIT
trap 'exit 130' INT TERM

clear_screen() {
    printf '\e[2J\e[H'
}

header() {
    printf '%b╔══════════════════════════════╗%b\n' "$DARK_GREEN" "$RESET"
    printf '%b║%b                              %b║%b\n' "$DARK_GREEN" "$LIGHT_GREEN" "$DARK_GREEN" "$RESET"
    printf '%b║%b      Independence War 2      %b║%b\n' "$DARK_GREEN" "$LIGHT_GREEN" "$DARK_GREEN" "$RESET"
    printf '%b║%b      The Edge  of Chaos      %b║%b\n' "$DARK_GREEN" "$LIGHT_GREEN" "$DARK_GREEN" "$RESET"
    printf '%b║%b   German / English Patcher   %b║%b\n' "$DARK_GREEN" "$LIGHT_GREEN" "$DARK_GREEN" "$RESET"
    printf '%b║%b                              %b║%b\n' "$DARK_GREEN" "$LIGHT_GREEN" "$DARK_GREEN" "$RESET"
    printf '%b╚══════════════════════════════╝%b\n' "$DARK_GREEN" "$RESET"
}

action_top() {
    printf '%b╭──────────────────────────────╮%b\n' "$YELLOW" "$RESET"
}

action_line() {
    local line="$1"
    local padded
    printf -v padded '%-29.29s' "$line"
    printf '%b│ %b%s%b│%b\n' "$YELLOW" "$ORANGE" "$padded" "$YELLOW" "$RESET"
}

action_bottom() {
    printf '%b╰──────────────────────────────╯%b\n' "$YELLOW" "$RESET"
}

menu_screen() {
    clear_screen
    header
    action_top
    local line
    for line in "$@"; do
        action_line "$line"
    done
    action_bottom
}

millis() {
    local value
    value="$(date +%s%3N 2>/dev/null || true)"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$((SECONDS * 1000))"
    fi
}

repeat_char() {
    local count="$1"
    local character="$2"
    local output=''
    while (( count > 0 )); do
        output+="$character"
        ((count -= 1))
    done
    printf '%s' "$output"
}

progress_screen() {
    local percent="$1"
    local message="$2"
    local complete="$3"
    local width=21
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    local hashes dashes bracket_color percent_color hash_color phase
    hashes="$(repeat_char "$filled" '#')"
    dashes="$(repeat_char "$empty" '-')"
    phase=$(( $(millis) / 800 % 2 ))
    bracket_color="$DARK_GREEN"
    (( phase == 1 )) && bracket_color="$LIGHT_GREEN"
    hash_color="$YELLOW"
    percent_color="$YELLOW"
    if (( complete == 1 )); then
        hash_color="$LIGHT_GREEN"
        percent_color="$LIGHT_GREEN"
    fi

    clear_screen
    header
    action_top
    printf '%b│ %b[%b%s%b%s%b] %b%3d%%%b │%b\n' \
        "$YELLOW" "$bracket_color" "$hash_color" "$hashes" "$GRAY" "$dashes" \
        "$bracket_color" "$percent_color" "$percent" "$YELLOW" "$RESET"
    action_line "$message"
    action_bottom
}

latest_backup() {
    find "$PATCH_DIR/backups" -maxdepth 1 -type f -name 'IW2EOC-before-GERPATCH-*.zip' \
        -printf '%T@|%p\n' 2>/dev/null | LC_ALL=C sort -nr | sed -n '1s/^[^|]*|//p'
}

detect_state() {
    status_log="$(mktemp)"
    menu_screen 'Checking game files ...'
    if "$APPLY_SCRIPT" --status "$TARGET_DIR" > "$status_log" 2>&1; then
        :
    fi
    local result
    result="$(tail -n 1 "$status_log")"
    case "$result" in
        'Result: verified English Steam version.') DETECTED_STATE=english ;;
        'Result: German patch is active.') DETECTED_STATE=german ;;
        'Result: recognized partial German patch.') DETECTED_STATE=partial ;;
        *) DETECTED_STATE=unknown ;;
    esac
}

operation_progress() {
    local operation="$1"
    local stage current total percent message
    stage='starting'
    current=0
    total=1
    while kill -0 "$worker_pid" 2>/dev/null; do
        if [[ -s "$progress_file" ]]; then
            IFS='|' read -r stage current total < "$progress_file" || true
        fi
        percent=0
        case "$stage" in
            backup)
                percent=15
                message='Creating backup ...'
                ;;
            apply)
                (( total > 0 )) && percent=$((15 + current * 85 / total))
                message='Patching german files ...'
                ;;
            restore-backup)
                percent=15
                message='Creating backup ...'
                ;;
            restore)
                (( total > 0 )) && percent=$((15 + current * 85 / total))
                message='Restoring english files ...'
                ;;
            *)
                message='Preparing patch ...'
                ;;
        esac
        (( percent > 100 )) && percent=100
        progress_screen "$percent" " $message" 0
        sleep 0.1
    done

    if wait "$worker_pid"; then
        if [[ "$operation" == apply ]]; then
            progress_screen 100 'Patching german files ...' 1
        else
            progress_screen 100 'Restoring english files ...' 1
        fi
        sleep 0.3
        return 0
    fi
    return $?
}

run_operation() {
    local operation="$1"
    local backup="${2:-}"
    progress_file="$(mktemp)"
    operation_log="$(mktemp)"
    printf 'starting|0|1\n' > "$progress_file"

    if [[ "$operation" == apply ]]; then
        GERPATCH_PROGRESS_FILE="$progress_file" "$APPLY_SCRIPT" "$TARGET_DIR" > "$operation_log" 2>&1 &
    else
        GERPATCH_PROGRESS_FILE="$progress_file" "$RESTORE_SCRIPT" "$TARGET_DIR" "$backup" > "$operation_log" 2>&1 &
    fi
    worker_pid=$!

    if operation_progress "$operation"; then
        if [[ "$operation" == apply ]]; then
            menu_screen 'Patch done. Backup created.' 'Start this tool again to re-' 'store the original files.'
        else
            menu_screen 'English files restored.' 'Start this tool again to' 'patch to German.'
        fi
        sleep 2
        return 0
    fi

    local error
    error="$(tail -n 1 "$operation_log")"
    menu_screen 'Operation failed.' "$error" 'Hit any key to close'
    IFS= read -r -s -n1 _ || true
    return 1
}

main() {
    if [[ "${1:-}" == '--help' ]]; then
        usage
        return 0
    fi
    if (( $# > 1 )); then
        usage >&2
        return 64
    fi
    if (( $# == 1 )); then
        TARGET_DIR="$1"
    fi
    if [[ ! -t 0 || ! -t 1 ]]; then
        printf 'This interactive patcher needs a terminal.\n' >&2
        return 69
    fi
    if [[ ! -x "$APPLY_SCRIPT" || ! -x "$RESTORE_SCRIPT" ]]; then
        printf 'Patch scripts are missing or not executable.\n' >&2
        return 66
    fi

    printf '\e[?25l'
    local state backup key
    detect_state
    state="$DETECTED_STATE"
    backup="$(latest_backup)"
    case "$state" in
        english)
            menu_screen 'Hit [ENTER] to start patch' 'Hit [ESC] to close'
            key=''
            IFS= read -r -s -n1 key || true
            [[ "$key" == $'\e' ]] && return 0
            [[ -z "$key" ]] && run_operation apply
            ;;
        german)
            if [[ -n "$backup" ]]; then
                menu_screen 'Hit [R] to restore english' 'Hit [ESC] to close'
                key=''
                IFS= read -r -s -n1 key || true
                [[ "$key" == $'\e' ]] && return 0
                [[ "$key" == 'r' || "$key" == 'R' ]] && run_operation restore "$backup"
            else
                menu_screen 'No patch backup found.' 'Hit [ESC] to close'
                IFS= read -r -s -n1 _ || true
            fi
            ;;
        partial)
            menu_screen 'Hit [ENTER] to complete patch' 'Hit [ESC] to close'
            key=''
            IFS= read -r -s -n1 key || true
            [[ "$key" == $'\e' ]] && return 0
            [[ -z "$key" ]] && run_operation apply
            ;;
        *)
            menu_screen 'Installation not recognized.' 'Hit [ESC] to close'
            IFS= read -r -s -n1 _ || true
            ;;
    esac
}

main "$@"
