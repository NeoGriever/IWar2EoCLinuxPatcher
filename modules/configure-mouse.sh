#!/usr/bin/env bash
# Enables the tested mouse yaw/pitch bindings and Proton mouse warp mode.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE_CONFIG="$PATCH_DIR/payloads/configs/corrected.ini"
APP_ID="${IW2_STEAM_APP_ID:-359630}"
PROGRESS_FILE="${GERPATCH_PROGRESS_FILE:-}"
PROTON_PREFIX="${IW2_PROTON_PREFIX:-}"
TARGET_IS_STEAM="${IW2_TARGET_IS_STEAM:-0}"

progress() {
    [[ -n "$PROGRESS_FILE" ]] || return 0
    local temporary="${PROGRESS_FILE}.tmp.$$"
    printf '%s|%s|%s\n' "$1" "$2" "$3" > "$temporary"
    mv -f -- "$temporary" "$PROGRESS_FILE"
}

mouse_warp_enabled() {
    local registry="$PROTON_PREFIX/user.reg"
    [[ -f "$registry" ]] || return 1
    awk '
        /^\[Software\\\\Wine\\\\DirectInput\]/ { inside=1; next }
        /^\[/ { inside=0 }
        inside && /"MouseWarpOverride"="enabled"/ { enabled=1 }
        END { exit !enabled }
    ' "$registry"
}

wait_for_mouse_warp() {
    local attempt

    for ((attempt = 0; attempt < 50; attempt++)); do
        mouse_warp_enabled && return 0
        sleep 0.1
    done

    return 1
}

[[ $# -eq 1 ]] || { printf 'Usage: %s <IW2 installation directory>\n' "$(basename -- "$0")" >&2; exit 64; }
TARGET_DIR="$(cd -- "$1" && pwd -P)"

FLUX_INI="$TARGET_DIR/flux.ini"
TARGET_CONFIG="$TARGET_DIR/configs/corrected.ini"
[[ -f "$FLUX_INI" && -f "$SOURCE_CONFIG" ]] || { printf 'Game configuration or mouse payload is missing.\n' >&2; exit 66; }

backup_dir="$PATCH_DIR/backups/config-$(date +%Y%m%d-%H%M%S)"
mkdir -p -- "$backup_dir"
cp -a -- "$FLUX_INI" "$backup_dir/flux.ini"
[[ -f "$TARGET_CONFIG" ]] && cp -a -- "$TARGET_CONFIG" "$backup_dir/corrected.ini"
progress mouse 0 3
mkdir -p -- "$(dirname -- "$TARGET_CONFIG")"
cp -af -- "$SOURCE_CONFIG" "$TARGET_CONFIG"
progress mouse 1 3
perl -0pi -e 's/^\s*input_scheme_ini\s*=.*$/input_scheme_ini = configs\/corrected.ini/m' "$FLUX_INI"
grep -q '^input_scheme_ini = configs/corrected.ini$' "$FLUX_INI" || {
    printf '\n[FcInputMapper]\ninput_scheme_ini = configs/corrected.ini\n' >> "$FLUX_INI"
}
progress mouse 2 3

# MouseWarpOverride lives in a Proton prefix, not in the selected game folder.
# For a standalone/test copy there is deliberately no associated Steam prefix,
# so stop after applying the game-local mouse files.
if [[ "$TARGET_IS_STEAM" != 1 || -z "$PROTON_PREFIX" ]]; then
    progress mouse 3 3
    printf 'Mouse ship controls configured for the selected game directory. Proton MouseWarpOverride was skipped because this target is not the registered Steam installation.\n'
    printf 'Mouse ship controls configured. Backup: %s\n' "$backup_dir"
    exit 0
fi

if mouse_warp_enabled; then
    printf 'MouseWarpOverride is already enabled in the Proton prefix.\n'

elif command -v protontricks >/dev/null; then
    protontricks "$APP_ID" mwo=enabled >/dev/null

    if ! wait_for_mouse_warp; then
        printf 'Protontricks completed, but MouseWarpOverride could not be verified.\n' >&2
        printf 'Registry checked: %s/user.reg\n' "$PROTON_PREFIX" >&2
        exit 65
    fi

    printf 'MouseWarpOverride enabled and verified.\n'

else
    printf 'protontricks is required to configure MouseWarpOverride.\n' >&2
    exit 69
fi
progress mouse 3 3
printf 'Mouse ship controls configured. Backup: %s\n' "$backup_dir"
