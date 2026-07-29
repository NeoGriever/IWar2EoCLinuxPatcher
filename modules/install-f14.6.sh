#!/usr/bin/env bash
# Installs the verified non-language F14.6 payload bundled with this package.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PAYLOAD_DIR="$PATCH_DIR/payloads/f14.6"
MANIFEST="$PATCH_DIR/payloads/f14.6-manifest.txt"
APP_ID="${IW2_STEAM_APP_ID:-359630}"
PROGRESS_FILE="${GERPATCH_PROGRESS_FILE:-}"
PROTON_PREFIX="${IW2_PROTON_PREFIX:-$HOME/.local/share/Steam/steamapps/compatdata/$APP_ID/pfx}"

progress() {
    [[ -n "$PROGRESS_FILE" ]] || return 0
    local temporary="${PROGRESS_FILE}.tmp.$$"
    printf '%s|%s|%s\n' "$1" "$2" "$3" > "$temporary"
    mv -f -- "$temporary" "$PROGRESS_FILE"
}

sha256() { sha256sum -- "$1" | awk '{print $1}'; }

f14_registry_present() {
    local registry="$PROTON_PREFIX/system.reg"
    [[ -f "$registry" ]] || return 1
    awk '
        /^\[Software\\\\Wow6432Node\\\\Particle Systems\\\\Edge of Chaos\\\\Settings\]/ { inside=1; next }
        /^\[/ { inside=0 }
        inside && /"InstallPath"=/ { install_path=1 }
        inside && /"Version"="14"/ { version=1 }
        END { exit !(install_path && version) }
    ' "$registry"
}

usage() {
    printf 'Usage: %s <IW2 installation directory>\n' "$(basename -- "$0")" >&2
    exit 64
}

[[ $# -eq 1 ]] || usage
TARGET_DIR="$(cd -- "$1" && pwd -P)"
[[ -f "$TARGET_DIR/EdgeOfChaos.exe" && -f "$TARGET_DIR/resource.zip" ]] || {
    printf 'Not an Independence War 2 installation: %s\n' "$TARGET_DIR" >&2
    exit 66
}
[[ -d "$PAYLOAD_DIR" && -f "$MANIFEST" ]] || {
    printf 'The bundled F14.6 payload is incomplete.\n' >&2
    exit 66
}
command -v 7z >/dev/null || { printf '7z is required for the reversible backup.\n' >&2; exit 69; }

declare -a paths=()
declare -a existing=()
payload_already_installed=1
while IFS='|' read -r relative expected_hash; do
    [[ -n "$relative" && -n "$expected_hash" ]] || continue
    source="$PAYLOAD_DIR/$relative"
    [[ -f "$source" && "$(sha256 "$source")" == "$expected_hash" ]] || {
        printf 'Damaged F14.6 payload: %s\n' "$relative" >&2
        exit 65
    }
    paths+=("$relative")
    [[ -f "$TARGET_DIR/$relative" ]] && existing+=("$relative")
    [[ -f "$TARGET_DIR/$relative" && "$(sha256 "$TARGET_DIR/$relative")" == "$expected_hash" ]] || payload_already_installed=0
done < "$MANIFEST"

(( ${#paths[@]} == 394 )) || { printf 'Unexpected F14.6 manifest size.\n' >&2; exit 65; }

if (( payload_already_installed )) && f14_registry_present; then
    progress install 1 1
    printf 'F14.6 files and the Proton registry entry are already verified.\n'
    exit 0
fi

backup_dir="${GERPATCH_BACKUP_DIR:-$PATCH_DIR/backups}"
mkdir -p -- "$backup_dir"
backup="$backup_dir/IW2EOC-before-F14.6-$(date +%Y%m%d-%H%M%S).zip"
list_file="$(mktemp)"
trap 'rm -f -- "$list_file"' EXIT
printf '%s\n' "${existing[@]}" > "$list_file"

progress backup 0 100
printf 'Creating reversible F14.6 backup: %s\n' "$backup"
( cd "$TARGET_DIR" && 7z a -tzip -mx=1 -bd "$backup" @"$list_file" )
7z t -bd "$backup" >/dev/null

total="${#paths[@]}"
current=0
progress install "$current" "$total"
for relative in "${paths[@]}"; do
    destination="$TARGET_DIR/$relative"
    mkdir -p -- "$(dirname -- "$destination")"
    cp -af -- "$PAYLOAD_DIR/$relative" "$destination"
    [[ "$(sha256 "$destination")" == "$(sha256 "$PAYLOAD_DIR/$relative")" ]] || {
        printf 'Verification failed while installing F14.6: %s\n' "$relative" >&2
        exit 65
    }
    ((current += 1))
    progress install "$current" "$total"
done

# The official installer creates this 32-bit Proton registry key.  The game
# files are already valid without it, but keep the installer state equivalent.
if f14_registry_present; then
    printf 'The existing F14.6 Proton registry entry is already valid.\n'
elif [[ "${IW2_SKIP_F14_REGISTRY:-0}" == 1 ]]; then
    printf 'Skipped Proton registry registration (test mode).\n'
elif command -v protontricks >/dev/null; then
    if install_path="$(protontricks "$APP_ID" winepath -w "$TARGET_DIR")" && \
       protontricks "$APP_ID" reg add 'HKLM\Software\Particle Systems\Edge of Chaos\Settings' /v InstallPath /t REG_SZ /d "$install_path" /f >/dev/null && \
       protontricks "$APP_ID" reg add 'HKLM\Software\Particle Systems\Edge of Chaos\Settings' /v Version /t REG_DWORD /d 14 /f >/dev/null; then
        printf 'F14.6 Proton registry entry created.\n'
    else
        printf 'Warning: F14.6 files were installed, but Protontricks could not create its optional registry entry.\n' >&2
    fi
else
    printf 'Warning: F14.6 files were installed, but Protontricks is unavailable for its optional registry entry.\n' >&2
fi

printf 'F14.6 installed. Backup: %s\n' "$backup"
