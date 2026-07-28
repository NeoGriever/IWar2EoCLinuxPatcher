#!/usr/bin/env bash
# Enables the tested mouse yaw/pitch bindings and Proton mouse warp mode.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE_CONFIG="$PATCH_DIR/payloads/configs/corrected.ini"
APP_ID="${IW2_STEAM_APP_ID:-359630}"
PROGRESS_FILE="${GERPATCH_PROGRESS_FILE:-}"
PROTON_PREFIX="${IW2_PROTON_PREFIX:-$HOME/.local/share/Steam/steamapps/compatdata/$APP_ID/pfx}"

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
if mouse_warp_enabled; then
    printf 'MouseWarpOverride is already enabled in the Proton prefix.\n'
elif command -v protontricks >/dev/null; then
    protontricks "$APP_ID" mwo=enabled >/dev/null
    mouse_warp_enabled || { printf 'Protontricks did not enable MouseWarpOverride.\n' >&2; exit 65; }
else
    printf 'protontricks is required to configure MouseWarpOverride.\n' >&2
    exit 69
fi
progress mouse 3 3
printf 'Mouse ship controls configured. Backup: %s\n' "$backup_dir"
