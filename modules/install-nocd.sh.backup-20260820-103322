#!/usr/bin/env bash
# Applies the two-byte F14.6 No-CD change documented by i-war2.com.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROGRESS_FILE="${GERPATCH_PROGRESS_FILE:-}"
F14_HASH='f02b4d199471524db0b6cd6ffc82a76555c33fee5bb24b7a8fd61e4984f542bb'
NOCD_HASH='0641e2c804311af5d678191e48dea2f0473414fc86286dde5650dc51c8059356'

progress() {
    [[ -n "$PROGRESS_FILE" ]] || return 0
    local temporary="${PROGRESS_FILE}.tmp.$$"
    printf '%s|%s|%s\n' "$1" "$2" "$3" > "$temporary"
    mv -f -- "$temporary" "$PROGRESS_FILE"
}

sha256() { sha256sum -- "$1" | awk '{print $1}'; }
[[ $# -eq 1 ]] || { printf 'Usage: %s <IW2 installation directory>\n' "$(basename -- "$0")" >&2; exit 64; }
TARGET_DIR="$(cd -- "$1" && pwd -P)"
DLL="$TARGET_DIR/bin/release/igame.dll"
[[ -f "$DLL" ]] || { printf 'Missing F14.6 igame.dll.\n' >&2; exit 66; }

current_hash="$(sha256 "$DLL")"
if [[ "$current_hash" == "$NOCD_HASH" ]]; then
    printf 'The F14.6 No-CD fix is already active.\n'
    progress nocd 1 1
    exit 0
fi
[[ "$current_hash" == "$F14_HASH" ]] || {
    printf 'igame.dll is not the verified F14.6 version; refusing to patch it.\n' >&2
    exit 2
}

backup_dir="${GERPATCH_BACKUP_DIR:-$PATCH_DIR/backups}"
mkdir -p -- "$backup_dir"
backup="$backup_dir/igame.dll-before-F14.6-nocd-$(date +%Y%m%d-%H%M%S)"
cp -a -- "$DLL" "$backup"
progress nocd 0 2
printf '\x3c' | dd of="$DLL" bs=1 seek=9301 conv=notrunc status=none
progress nocd 1 2
printf '\xeb' | dd of="$DLL" bs=1 seek=9347 conv=notrunc status=none
[[ "$(sha256 "$DLL")" == "$NOCD_HASH" ]] || {
    cp -af -- "$backup" "$DLL"
    printf 'No-CD verification failed; the original DLL was restored.\n' >&2
    exit 65
}
progress nocd 2 2
printf 'F14.6 No-CD fix installed. Backup: %s\n' "$backup"
