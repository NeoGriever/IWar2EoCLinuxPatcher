#!/usr/bin/env bash
# Launches I-War 2 in Gamescope and preserves an exhaustive diagnostic bundle
# for every run.  The bundle is intentionally broad: a random rendering
# failure may originate in Flux, Wine/Proton, Gamescope, the Vulkan driver, or
# the compositor/kernel rather than in the last visible game action.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEFAULT_LOG_DIR="${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/iwar2-gamescope-diagnostic"
LOG_DIR="${IW2_DIAGNOSTIC_LOG_DIR:-$DEFAULT_LOG_DIR}"

# `/tmp` was used by older releases.  Prefer persistent state so a log remains
# available after a long play session or a normal reboot, but keep a safe
# fallback for unusual Steam environments without a writable home directory.
if ! mkdir -p -- "$LOG_DIR/runs"; then
    LOG_DIR=/tmp/iwar2-gamescope-diagnostic
    mkdir -p -- "$LOG_DIR/runs"
    printf 'Could not create the persistent diagnostic directory; using %s\n' "$LOG_DIR" >&2
fi

DISPLAY_CONFIG="$PATCH_DIR/runtime/display.conf"

read_config() {
    local key="$1"
    local fallback="$2"
    [[ -f "$DISPLAY_CONFIG" ]] || { printf '%s\n' "$fallback"; return 0; }
    local value
    value="$(sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)$/\\1/p" "$DISPLAY_CONFIG" | head -n 1)"
    value="$(printf '%s' "$value" | sed -E 's/[[:space:]]+$//')"
    printf '%s\n' "${value:-$fallback}"
}

read_flux_value() {
    local key="$1"
    sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)$/\\1/p" "$FLUX_INI" | head -n 1 | sed -E 's/[[:space:]]+$//'
}

set_flux_value() {
    local key="$1"
    local value="$2"
    FLUX_KEY="$key" FLUX_VALUE="$value" perl -0pi -e '
        my $key = quotemeta $ENV{FLUX_KEY};
        my $value = $ENV{FLUX_VALUE};
        my $changed = s{(^[ \t]*$key[ \t]*=)[^\r\n]*}{$1 . q{ } . $value}emsx;
        die "Missing Flux setting: $ENV{FLUX_KEY}\\n" unless $changed;
    ' "$FLUX_INI"
}

GAME_DIR="$(read_config game_dir "${HOME:-/tmp}/.local/share/Steam/steamapps/common/Independence War 2 - Edge of Chaos")"
FLUX_INI="$GAME_DIR/flux.ini"
OUTPUT_WIDTH="$(read_config width 1280)"
OUTPUT_HEIGHT="$(read_config height 720)"
OUTER_FULLSCREEN="$(read_config outer_fullscreen 0)"
MOUSE_SENSITIVITY_SETTING="$(read_config mouse_sensitivity 0.045)"
GAMESCOPE_BACKEND_SETTING="$(read_config backend auto)"
[[ "$OUTPUT_WIDTH" =~ ^[1-9][0-9]*$ && "$OUTPUT_HEIGHT" =~ ^[1-9][0-9]*$ ]] || {
    printf 'Invalid Gamescope resolution in %s\n' "$DISPLAY_CONFIG" >&2
    exit 65
}
[[ "$OUTER_FULLSCREEN" == 0 || "$OUTER_FULLSCREEN" == 1 ]] || {
    printf 'outer_fullscreen must be 0 or 1 in %s\n' "$DISPLAY_CONFIG" >&2
    exit 65
}
case "$MOUSE_SENSITIVITY_SETTING" in
    disabled|off|none) MOUSE_SENSITIVITY=disabled; declare -a mouse_sensitivity_args=() ;;
    *)
        [[ "$MOUSE_SENSITIVITY_SETTING" =~ ^0\.[0-9]+$ || "$MOUSE_SENSITIVITY_SETTING" =~ ^[1-9][0-9]*(\.[0-9]+)?$ ]] || {
            printf 'Invalid mouse sensitivity in %s\n' "$DISPLAY_CONFIG" >&2
            exit 65
        }
        MOUSE_SENSITIVITY="$MOUSE_SENSITIVITY_SETTING"
        declare -a mouse_sensitivity_args=( -s "$MOUSE_SENSITIVITY" )
        ;;
esac
case "$GAMESCOPE_BACKEND_SETTING" in
    wayland|sdl|auto) ;;
    *)
        printf 'Unsupported Gamescope backend %q in %s\n' "$GAMESCOPE_BACKEND_SETTING" "$DISPLAY_CONFIG" >&2
        exit 65
        ;;
esac
if [[ "$GAMESCOPE_BACKEND_SETTING" == auto ]]; then
    if [[ "${XDG_SESSION_TYPE:-}" == wayland && -n "${WAYLAND_DISPLAY:-}" ]]; then
        GAMESCOPE_BACKEND=wayland
    elif [[ -n "${DISPLAY:-}" ]]; then
        GAMESCOPE_BACKEND=sdl
    else
        GAMESCOPE_BACKEND=auto
    fi
else
    GAMESCOPE_BACKEND="$GAMESCOPE_BACKEND_SETTING"
fi

[[ -f "$FLUX_INI" ]] || {
    printf 'Missing flux.ini: %s\n' "$FLUX_INI" >&2
    exit 66
}
[[ $# -gt 0 ]] || {
    printf 'No game command was supplied by Steam.\n' >&2
    exit 64
}

RUN_ID="$(date +%Y%m%d-%H%M%S-%N)-$$"
RUN_DIR="$LOG_DIR/runs/$RUN_ID"
RUN_LOG="$RUN_DIR/run.txt"
GAMESCOPE_LOG="$RUN_DIR/gamescope.log"
RUNTIME_LOG="$RUN_DIR/runtime/process-samples.log"
mkdir -p -- "$RUN_DIR/system" "$RUN_DIR/runtime" "$RUN_DIR/proton" "$RUN_DIR/dxvk" "$RUN_DIR/artifacts"

RUN_STARTED="$(date --iso-8601=seconds)"
SAMPLE_SECONDS="${IW2_DIAGNOSTIC_SAMPLE_SECONDS:-1}"
[[ "$SAMPLE_SECONDS" =~ ^[1-9][0-9]*$ ]] || SAMPLE_SECONDS=1
CAPTURE_SECONDS="${IW2_DIAGNOSTIC_CAPTURE_SECONDS:-30}"
[[ "$CAPTURE_SECONDS" =~ ^[1-9][0-9]*$ ]] || CAPTURE_SECONDS=30
FLUX_LOG_NAME="$(read_flux_value log_file)"
FLUX_LOG_NAME="${FLUX_LOG_NAME:-flux.log}"
if [[ "$FLUX_LOG_NAME" == /* ]]; then
    FLUX_LOG_PATH="$FLUX_LOG_NAME"
else
    FLUX_LOG_PATH="$GAME_DIR/$FLUX_LOG_NAME"
fi
RECOVERY_ID="${FLUX_INI//[^[:alnum:]]/_}"
FLUX_RECOVERY_FILE="$LOG_DIR/flux-diagnostics-${RECOVERY_ID}.tsv"

declare -A ORIGINAL_FLUX_VALUES=()
declare -A DIAGNOSTIC_FLUX_VALUES=()
GAMESCOPE_PID=''
RECORDING_PID=''
HOTKEY_MONITOR_PID=''
HOTKEY_REGISTERED=0
CAPTURE_REQUESTED=0
HOTKEY_COMPONENT='iwar2-gamescope-diagnostic'
HOTKEY_ACTION='capture-render-diagnostics'
HOTKEY_COMPONENT_PATH='/component/iwar2_gamescope_diagnostic'
HOTKEY_KEYCODE=150995003 # Qt::ALT | Qt::Key_F12

log_event() {
    printf 'event_at=%s event=%s\n' "$(date --iso-8601=seconds)" "$*" >> "$RUN_LOG"
}

record_error() {
    local line="$1"
    local command="$2"
    local status="$3"
    printf 'error_at=%s line=%s status=%s command=%q\n' \
        "$(date --iso-8601=seconds)" "$line" "$status" "$command" >> "$RUN_LOG"
    return "$status"
}

capture_command() {
    local label="$1"
    shift
    local output="$RUN_DIR/system/$label.txt"
    {
        printf 'captured_at=%s\ncommand=' "$(date --iso-8601=seconds)"
        printf ' %q' "$@"
        printf '\n\n'
        local status
        if "$@"; then
            status=0
        else
            status=$?
        fi
        printf '\n\ncommand_exit_status=%s\n' "$status"
    } > "$output" 2>&1
}

capture_optional_command() {
    local label="$1"
    local utility="$2"
    shift 2
    if command -v "$utility" >/dev/null 2>&1; then
        capture_command "$label" "$utility" "$@"
    else
        printf 'captured_at=%s\nmissing_utility=%s\n' "$(date --iso-8601=seconds)" "$utility" \
            > "$RUN_DIR/system/$label.txt"
    fi
}

capture_graphics_environment() {
    local entry name value
    printf '%-42s %s\n' 'VARIABLE' 'VALUE'
    while IFS= read -r entry; do
        name="${entry%%=*}"
        value="${entry#*=}"
        case "$name" in
            *TOKEN*|*Token*|*token*|*SECRET*|*Secret*|*secret*|*PASSWORD*|*Password*|*password*|*COOKIE*|*Cookie*|*cookie*|*AUTH*|*Auth*|*auth*) value='<redacted>' ;;
        esac
        printf '%-42s %s\n' "$name" "$value"
    done < <(env | LC_ALL=C sort)
}

capture_program_versions() {
    local utility
    for utility in gamescope steam proton wine wineserver vulkaninfo glxinfo nvidia-smi lspci lsmod journalctl coredumpctl; do
        printf '\n===== %s =====\n' "$utility"
        if command -v "$utility" >/dev/null 2>&1; then
            command -v "$utility"
            # Steam and Proton launchers do not have a stable, documented
            # version-only mode.  Recording their resolved executable avoids
            # accidentally starting a second client while a game is running.
            case "$utility" in
                steam|proton) stat -Lc 'mode=%a size=%s modified=%y path=%n' "$(command -v "$utility")" 2>&1 || true ;;
                *) "$utility" --version 2>&1 || "$utility" -version 2>&1 || true ;;
            esac
        else
            printf 'not installed or not in PATH\n'
        fi
    done
}

capture_drm_status() {
    local path relative
    for path in /sys/class/drm/card*/device/{uevent,gpu_busy_percent,mem_info_vram_total,mem_info_vram_used,mem_info_gtt_total,mem_info_gtt_used}; do
        [[ -r "$path" ]] || continue
        relative="${path#/sys/class/drm/}"
        printf '\n===== %s =====\n' "$relative"
        cat -- "$path" || true
    done
}

capture_initial_system_state() {
    capture_command graphics-environment capture_graphics_environment
    capture_command program-versions capture_program_versions
    capture_command uname uname -a
    capture_command kernel-command-line cat /proc/cmdline
    capture_command ulimit bash -c 'ulimit -a'
    capture_command memory cat /proc/meminfo
    capture_optional_command disk-space df -hT
    capture_optional_command disk-inodes df -hi
    capture_optional_command pci-devices lspci -nnk
    capture_optional_command kernel-modules lsmod
    capture_optional_command vulkan-summary vulkaninfo --summary
    capture_optional_command opengl-summary glxinfo -B
    capture_optional_command xrandr-verbose xrandr --verbose
    capture_optional_command wayland-info wayland-info
    capture_command drm-status capture_drm_status
    capture_optional_command nvidia-initial nvidia-smi -q -x
}

tracked_processes() {
    local root="$1"
    local -a queue=("$root") children=()
    local pid child
    declare -A seen=()
    while :; do
        if [[ ${#queue[@]} -eq 0 ]]; then
            break
        fi
        pid="${queue[0]}"
        queue=("${queue[@]:1}")
        [[ "$pid" =~ ^[1-9][0-9]*$ && -d "/proc/$pid" && -z "${seen[$pid]:-}" ]] || continue
        seen["$pid"]=1
        printf '%s\n' "$pid"
        mapfile -t children < <(ps -o pid= --ppid "$pid" 2>/dev/null || true)
        for child in "${children[@]:-}"; do
            child="${child//[[:space:]]/}"
            [[ "$child" =~ ^[1-9][0-9]*$ ]] && queue+=("$child")
        done
    done
}

capture_process_snapshot() {
    local reason="$1"
    local -a pids=()
    local pid pid_list
    [[ -n "$GAMESCOPE_PID" ]] || return 0
    mapfile -t pids < <(tracked_processes "$GAMESCOPE_PID")
    {
        printf '\n===== snapshot_at=%s reason=%s =====\n' "$(date --iso-8601=seconds)" "$reason"
        if (( ${#pids[@]} == 0 )); then
            printf 'No live Gamescope process tree was found.\n'
            return 0
        fi
        pid_list="$(IFS=,; printf '%s' "${pids[*]}")"
        ps -ww -o pid=,ppid=,pgid=,sid=,stat=,lstart=,etime=,pcpu=,pmem=,rss=,vsz=,nlwp=,ni=,pri=,psr=,comm=,args= -p "$pid_list" || true
        for pid in "${pids[@]}"; do
            [[ -d "/proc/$pid" ]] || continue
            printf '\n--- /proc/%s/status ---\n' "$pid"
            sed -n '1,220p' "/proc/$pid/status" 2>&1 || true
            printf '\n--- /proc/%s/io ---\n' "$pid"
            cat -- "/proc/$pid/io" 2>&1 || true
            printf '\n--- /proc/%s/wchan ---\n' "$pid"
            cat -- "/proc/$pid/wchan" 2>&1 || true
            printf '\n--- /proc/%s/open-file-descriptors ---\n' "$pid"
            find "/proc/$pid/fd" -mindepth 1 -maxdepth 1 -printf '%f -> %l\n' 2>&1 || true
        done
    } >> "$RUNTIME_LOG" 2>&1
}

capture_gpu_sample() {
    local path relative
    {
        printf '\n===== gpu_sample_at=%s =====\n' "$(date --iso-8601=seconds)"
        if command -v nvidia-smi >/dev/null 2>&1; then
            nvidia-smi --query-gpu=timestamp,index,name,pstate,temperature.gpu,utilization.gpu,utilization.memory,memory.total,memory.used,power.draw,clocks.gr,clocks.mem \
                --format=csv,noheader,nounits 2>&1 || true
            nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory --format=csv,noheader 2>&1 || true
        else
            printf 'nvidia-smi is not available.\n'
        fi
        for path in /sys/class/drm/card*/device/{gpu_busy_percent,mem_info_vram_used,mem_info_gtt_used}; do
            [[ -r "$path" ]] || continue
            relative="${path#/sys/class/drm/}"
            printf '%s=' "$relative"
            cat -- "$path" 2>&1 || true
        done
    } >> "$RUNTIME_LOG" 2>&1
}

copy_capture_artifacts() {
    local label="$1"
    local capture_dir="$RUN_DIR/captures/$label"
    local source relative destination
    mkdir -p -- "$capture_dir"
    for source in "$FLUX_LOG_PATH" "$GAME_DIR/saves/autosave.sav"; do
        [[ -f "$source" ]] || continue
        cp -a -- "$source" "$capture_dir/$(basename -- "$source")" 2>/dev/null || true
    done
    while IFS= read -r -d '' source; do
        relative="${source#"$GAME_DIR"/}"
        destination="$capture_dir/${relative//\//__}"
        cp -a -- "$source" "$destination" 2>/dev/null || true
    done < <(find "$GAME_DIR" -maxdepth 4 -type f \( -iname access.log -o -iname '*.dmp' -o -iname '*.mdmp' -o -iname '*.crash' \) -print0 2>/dev/null)
}

record_diagnostics() {
    local source="$1"
    local sample=0
    local deadline=$((SECONDS + CAPTURE_SECONDS))
    while kill -0 "$GAMESCOPE_PID" 2>/dev/null && (( SECONDS < deadline )); do
        sample=$((sample + 1))
        capture_process_snapshot "${source}-sample-$sample"
        capture_gpu_sample
        sleep "$SAMPLE_SECONDS" || break
    done
    capture_process_snapshot "${source}-complete"
    capture_gpu_sample
    copy_capture_artifacts "${source}-complete"
    capture_post_run_system_state
    log_event "capture-finished source=$source samples=$sample"
}

start_recording() {
    local source="$1"
    if [[ -n "$RECORDING_PID" ]] && kill -0 "$RECORDING_PID" 2>/dev/null; then
        log_event "capture-ignored source=$source reason=already-recording"
        return 0
    fi
    CAPTURE_REQUESTED=1
    log_event "capture-started source=$source duration_seconds=$CAPTURE_SECONDS"
    capture_initial_system_state
    capture_process_snapshot "${source}-start"
    capture_gpu_sample
    copy_capture_artifacts "${source}-start"
    record_diagnostics "$source" &
    RECORDING_PID=$!
    printf 'recording_pid=%s source=%s\n' "$RECORDING_PID" "$source" >> "$RUN_LOG"
}

hotkey_monitor() {
    gdbus monitor --session --dest org.kde.kglobalaccel --object-path "$HOTKEY_COMPONENT_PATH" 2>&1 |
        while IFS= read -r line; do
            printf 'hotkey_monitor_at=%s %s\n' "$(date --iso-8601=seconds)" "$line" >> "$RUN_DIR/runtime/hotkey-monitor.log"
            if [[ "$line" == *globalShortcutPressed* && "$line" == *"'$HOTKEY_ACTION'"* ]]; then
                kill -USR2 "$$" 2>/dev/null || true
            fi
        done
}

start_hotkey_listener() {
    local action_id availability
    command -v gdbus >/dev/null 2>&1 || {
        log_event hotkey-disabled reason=gdbus-missing
        return 0
    }
    if ! availability="$(gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
        --method org.kde.KGlobalAccel.isGlobalShortcutAvailable "$HOTKEY_KEYCODE" "$HOTKEY_COMPONENT" 2>&1)" ||
        [[ "$availability" != *true* ]]; then
        log_event "hotkey-disabled reason=alt-f12-unavailable detail=$availability"
        return 0
    fi
    action_id="['$HOTKEY_COMPONENT', '$HOTKEY_ACTION', 'I-War 2 Gamescope Diagnostics', 'Capture render diagnostics']"
    if ! gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
        --method org.kde.KGlobalAccel.doRegister "$action_id" >> "$RUN_DIR/runtime/hotkey-monitor.log" 2>&1; then
        log_event hotkey-disabled reason=registration-failed
        return 0
    fi
    if ! gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
        --method org.kde.KGlobalAccel.setForeignShortcut "$action_id" "[$HOTKEY_KEYCODE]" \
        >> "$RUN_DIR/runtime/hotkey-monitor.log" 2>&1; then
        gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
            --method org.kde.KGlobalAccel.unregister "$HOTKEY_COMPONENT" "$HOTKEY_ACTION" >/dev/null 2>&1 || true
        log_event hotkey-disabled reason=shortcut-binding-failed
        return 0
    fi
    HOTKEY_REGISTERED=1
    hotkey_monitor &
    HOTKEY_MONITOR_PID=$!
    printf 'hotkey=Alt+F12 hotkey_monitor_pid=%s\n' "$HOTKEY_MONITOR_PID" >> "$RUN_LOG"
    log_event hotkey-ready key=Alt+F12
}

stop_hotkey_listener() {
    if [[ -n "$HOTKEY_MONITOR_PID" ]] && kill -0 "$HOTKEY_MONITOR_PID" 2>/dev/null; then
        kill "$HOTKEY_MONITOR_PID" 2>/dev/null
        wait "$HOTKEY_MONITOR_PID" 2>/dev/null
    fi
    if (( HOTKEY_REGISTERED )); then
        gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
            --method org.kde.KGlobalAccel.unregister "$HOTKEY_COMPONENT" "$HOTKEY_ACTION" \
            >> "$RUN_DIR/runtime/hotkey-monitor.log" 2>&1 || true
    fi
}

enable_flux_diagnostics() {
    local key original expected temporary
    # Flux reads these settings while starting.  Toggling its developer and
    # resource ledgers for an entire session changes game behaviour and can
    # make the old engine stutter, so all heavy capture is now opt-in.
    (( ${#DIAGNOSTIC_FLUX_VALUES[@]} > 0 )) || return 0
    cp -a -- "$FLUX_INI" "$RUN_DIR/artifacts/flux.ini.before-diagnostics"
    for key in "${!DIAGNOSTIC_FLUX_VALUES[@]}"; do
        original="$(read_flux_value "$key")"
        if [[ -z "$original" ]]; then
            printf 'flux_diagnostic_setting=%s status=missing\n' "$key" >> "$RUN_LOG"
            continue
        fi
        ORIGINAL_FLUX_VALUES["$key"]="$original"
    done
    # A hard reset cannot run the EXIT trap.  Persist every original value
    # before changing Flux so the next wrapper start can recover the game
    # configuration before it begins another diagnostic run.
    temporary="${FLUX_RECOVERY_FILE}.tmp.$$"
    {
        printf 'version\t1\n'
        for key in "${!ORIGINAL_FLUX_VALUES[@]}"; do
            printf '%s\t%s\n' "$key" "${ORIGINAL_FLUX_VALUES[$key]}"
        done
    } > "$temporary"
    mv -f -- "$temporary" "$FLUX_RECOVERY_FILE"
    for key in "${!ORIGINAL_FLUX_VALUES[@]}"; do
        expected="${DIAGNOSTIC_FLUX_VALUES[$key]}"
        set_flux_value "$key" "$expected"
        [[ "$(read_flux_value "$key")" == "$expected" ]] || {
            printf 'Could not enable Flux diagnostic setting %s\n' "$key" >&2
            exit 70
        }
        printf 'flux_diagnostic_setting=%s original=%q diagnostic=%q\n' \
            "$key" "${ORIGINAL_FLUX_VALUES[$key]}" "$expected" >> "$RUN_LOG"
    done
    cp -a -- "$FLUX_INI" "$RUN_DIR/artifacts/flux.ini.with-diagnostics"
}

restore_flux_diagnostics() {
    local key original restore_failed=0
    (( ${#ORIGINAL_FLUX_VALUES[@]} > 0 )) || return 0
    for key in "${!ORIGINAL_FLUX_VALUES[@]}"; do
        original="${ORIGINAL_FLUX_VALUES[$key]}"
        if set_flux_value "$key" "$original" && [[ "$(read_flux_value "$key")" == "$original" ]]; then
            printf 'flux_restore_setting=%s value=%q status=ok\n' "$key" "$original" >> "$RUN_LOG"
        else
            printf 'flux_restore_setting=%s value=%q status=FAILED\n' "$key" "$original" >> "$RUN_LOG"
            restore_failed=1
        fi
    done
    cp -a -- "$FLUX_INI" "$RUN_DIR/artifacts/flux.ini.after-restore" 2>/dev/null || true
    if (( restore_failed == 0 )); then
        rm -f -- "$FLUX_RECOVERY_FILE"
    fi
}

recover_stale_flux_diagnostics() {
    local key original recovery_failed=0
    [[ -f "$FLUX_RECOVERY_FILE" ]] || return 0
    cp -a -- "$FLUX_RECOVERY_FILE" "$RUN_DIR/artifacts/flux-diagnostics-stale-recovery.tsv" 2>/dev/null || true
    while IFS=$'\t' read -r key original; do
        [[ "$key" == version ]] && continue
        case "$key" in
            generate_access_log|dev_call_tracing|dev_memory|dev_package_assert|dev_package_trace|dev_string_statistics|developer_mode|trace_level|trace_to_console|trace_to_debugger|trace_to_log) ;;
            *)
            recovery_failed=1
            continue
                ;;
        esac
        if set_flux_value "$key" "$original" && [[ "$(read_flux_value "$key")" == "$original" ]]; then
            printf 'stale_flux_recovery_setting=%s value=%q status=ok\n' "$key" "$original" >> "$RUN_LOG"
        else
            printf 'stale_flux_recovery_setting=%s value=%q status=FAILED\n' "$key" "$original" >> "$RUN_LOG"
            recovery_failed=1
        fi
    done < "$FLUX_RECOVERY_FILE"
    if (( recovery_failed == 0 )); then
        rm -f -- "$FLUX_RECOVERY_FILE"
        log_event stale-flux-diagnostics-recovered
    else
        log_event stale-flux-diagnostics-recovery-failed
        return 70
    fi
}

copy_artifacts() {
    local source relative destination
    for source in "$FLUX_LOG_PATH" "$GAME_DIR/saves/autosave.sav"; do
        [[ -f "$source" ]] || continue
        cp -a -- "$source" "$RUN_DIR/artifacts/$(basename -- "$source").$RUN_ID" 2>/dev/null || true
    done
    while IFS= read -r -d '' source; do
        relative="${source#"$GAME_DIR"/}"
        destination="$RUN_DIR/artifacts/game/${relative//\//__}"
        mkdir -p -- "$(dirname -- "$destination")"
        cp -a -- "$source" "$destination" 2>/dev/null || true
    done < <(find "$GAME_DIR" -maxdepth 4 -type f \( -iname access.log -o -iname '*.dmp' -o -iname '*.mdmp' -o -iname '*.crash' \) -print0 2>/dev/null)
}

capture_post_run_system_state() {
    capture_process_snapshot final
    capture_gpu_sample
    capture_optional_command journal-kernel-after-run journalctl --no-pager -o short-precise -k --since "$RUN_STARTED"
    capture_optional_command journal-user-after-run journalctl --no-pager -o short-precise --user --since "$RUN_STARTED"
    capture_optional_command journal-all-after-run journalctl --no-pager -o short-precise --since "$RUN_STARTED"
    capture_optional_command dmesg-after-run dmesg --color=never --since "$RUN_STARTED"
    capture_optional_command coredumps-after-run coredumpctl --no-pager list --since "$RUN_STARTED"
    capture_optional_command nvidia-final nvidia-smi -q -x
}

create_manual_snapshot_helper() {
    local helper="$RUN_DIR/capture-now.sh"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'set -euo pipefail'
        printf 'kill -USR1 %q\n' "$$"
    } > "$helper"
    chmod 0700 -- "$helper"
    printf '%s\n' "$helper" > "$LOG_DIR/latest-capture-command"
}

finish() {
    local status=$?
    trap - EXIT ERR HUP INT TERM USR1 USR2
    set +e
    log_event "wrapper-finishing status=$status"
    stop_hotkey_listener
    if [[ -n "$RECORDING_PID" ]] && kill -0 "$RECORDING_PID" 2>/dev/null; then
        log_event "capture-interrupted reason=game-exit recording_pid=$RECORDING_PID"
        kill "$RECORDING_PID" 2>/dev/null
        wait "$RECORDING_PID" 2>/dev/null
    fi
    if (( CAPTURE_REQUESTED )); then
        capture_post_run_system_state
    fi
    copy_artifacts
    cp -a -- "$FLUX_INI" "$RUN_DIR/artifacts/flux.ini.before-restore" 2>/dev/null || true
    restore_flux_diagnostics
    printf 'finished_at=%s\nexit_status=%s\nrun_dir=%s\n' \
        "$(date --iso-8601=seconds)" "$status" "$RUN_DIR" >> "$RUN_LOG"
    find "$RUN_DIR" -type f -printf '%s %p\n' 2>/dev/null | LC_ALL=C sort -n > "$RUN_DIR/artifact-index.txt"
    exit "$status"
}

handle_signal() {
    local signal="$1"
    local status="$2"
    log_event "received-signal=$signal"
    exit "$status"
}

{
    printf 'run_id=%s\n' "$RUN_ID"
    printf 'started_at=%s\n' "$RUN_STARTED"
    printf 'wrapper_pid=%s\n' "$$"
    printf 'runtime_dir=%s\n' "$PATCH_DIR"
    printf 'game_dir=%s\n' "$GAME_DIR"
    printf 'launcher_mode=gamescope-%s-%s-fixed-%sx%s\n' "$GAMESCOPE_BACKEND_SETTING" "$GAMESCOPE_BACKEND" "$OUTPUT_WIDTH" "$OUTPUT_HEIGHT"
    printf 'gamescope_backend_setting=%s\n' "$GAMESCOPE_BACKEND_SETTING"
    printf 'gamescope_backend=%s\n' "$GAMESCOPE_BACKEND"
    printf 'outer_fullscreen=%s\n' "$OUTER_FULLSCREEN"
    printf 'mouse_sensitivity=%s\n' "$MOUSE_SENSITIVITY"
    printf 'diagnostic_log_root=%s\n' "$LOG_DIR"
    printf 'run_dir=%s\n' "$RUN_DIR"
    printf 'gamescope_log=%s\n' "$GAMESCOPE_LOG"
    printf 'proton_log_dir=%s\n' "$RUN_DIR/proton"
    printf 'dxvk_log_dir=%s\n' "$RUN_DIR/dxvk"
    printf 'process_sample_interval_seconds=%s\n' "$SAMPLE_SECONDS"
    printf 'capture_duration_seconds=%s\n' "$CAPTURE_SECONDS"
    printf 'capture_hotkey=Alt+F12\n'
    printf 'flux_log_path=%s\n' "$FLUX_LOG_PATH"
    printf 'command='
    printf ' %q' "$@"
    printf '\n'
} > "$RUN_LOG"

printf '%s\n' "$RUN_LOG" > "$LOG_DIR/latest-run-log"
printf '%s\n' "$GAMESCOPE_LOG" > "$LOG_DIR/latest-gamescope-log"
printf '%s\n' "$RUN_DIR" > "$LOG_DIR/latest-run-directory"
# Do not leave a prior run's helper usable while this process is still
# initializing its traps; it will be replaced immediately below.
printf '%s\n' "$RUN_DIR/capture-now.sh.pending" > "$LOG_DIR/latest-capture-command"

trap 'record_error "$LINENO" "$BASH_COMMAND" "$?"' ERR
trap finish EXIT
trap 'handle_signal HUP 129' HUP
trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM
trap 'start_recording manual-signal' USR1
trap 'start_recording alt-f12' USR2

# The helper is published only after its signal handler exists.  It is a
# fallback for desktops where KDE's global shortcut service is unavailable.
create_manual_snapshot_helper

recover_stale_flux_diagnostics
enable_flux_diagnostics

# Keep the game path quiet.  The intensive system inventory and one-second
# process/GPU sampling start only after Alt+F12 (or the fallback helper).
export PROTON_LOG=1
export PROTON_LOG_DIR="$RUN_DIR/proton"
export WINEDEBUG='-all,+err,+warn'
export DXVK_LOG_LEVEL=warn
export DXVK_LOG_PATH="$RUN_DIR/dxvk"
export VKD3D_DEBUG=warn
export VK_LOADER_DEBUG=error,warn

gamescope_args=(
    --backend "$GAMESCOPE_BACKEND" \
    -W "$OUTPUT_WIDTH" -H "$OUTPUT_HEIGHT" \
    -w "$OUTPUT_WIDTH" -h "$OUTPUT_HEIGHT" \
    "${mouse_sensitivity_args[@]}" \
    --force-windows-fullscreen \
)
if [[ "$OUTER_FULLSCREEN" == 1 ]]; then
    gamescope_args+=( -f )
fi

log_event gamescope-launching
set +e
gamescope "${gamescope_args[@]}" -- "$@" > "$GAMESCOPE_LOG" 2>&1 &
GAMESCOPE_PID=$!
set -e
printf 'gamescope_pid=%s\n' "$GAMESCOPE_PID" >> "$RUN_LOG"
start_hotkey_listener

set +e
wait "$GAMESCOPE_PID"
GAME_STATUS=$?
set -e
log_event "gamescope-exited status=$GAME_STATUS"
exit "$GAME_STATUS"
