#!/usr/bin/env bash
# Applies Schmatzler's verified one-byte high-clock TSC overflow repair.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROGRESS_FILE="${GERPATCH_PROGRESS_FILE:-}"
FLUX_SIZE=1392640
ORIGINAL_HASH='f5ceddfbebd4c23fe510d033918ccc1306eb02306157c3acf5d06151a5fcd39b'
PATCHED_HASH='60cf69c2cc7ff4e35e5479eca77b95acadf9bbedf57b673f26c5082f0b61e33b'
OFFSET=$((0x18EF1))
EXPECTED_CONTEXT='8975f0c745f400000000df6df0'
PATCHED_CONTEXT='8975f0c745f401000000df6df0'

progress() {
    [[ -n "$PROGRESS_FILE" ]] || return 0
    local temporary="${PROGRESS_FILE}.tmp.$$"
    printf '%s|%s|%s\n' "$1" "$2" "$3" > "$temporary"
    mv -f -- "$temporary" "$PROGRESS_FILE"
}

sha256() { sha256sum -- "$1" | awk '{print $1}'; }
context_at_offset() { od -An -tx1 -j "$(( OFFSET - 6 ))" -N 13 -- "$1" | tr -d '[:space:]'; }

[[ $# -eq 1 ]] || { printf 'Usage: %s <IW2 installation directory>\n' "$(basename -- "$0")" >&2; exit 64; }
TARGET_DIR="$(cd -- "$1" && pwd -P)"
FLUX_DLL="$TARGET_DIR/bin/release/flux.dll"
[[ -f "$FLUX_DLL" ]] || { printf 'Missing flux.dll: %s\n' "$FLUX_DLL" >&2; exit 66; }
[[ "$(stat -c '%s' -- "$FLUX_DLL")" == "$FLUX_SIZE" ]] || { printf 'flux.dll has an unsupported size; refusing the CPU speed fix.\n' >&2; exit 66; }

current_hash="$(sha256 "$FLUX_DLL")"
if [[ "$current_hash" == "$PATCHED_HASH" ]]; then
    [[ "$(context_at_offset "$FLUX_DLL")" == "$PATCHED_CONTEXT" ]] || { printf 'Patched flux.dll has an unexpected context.\n' >&2; exit 65; }
    progress cpu-speed 1 1
    printf 'CPU speed fix is already verified.\n'
    exit 0
fi
[[ "$current_hash" == "$ORIGINAL_HASH" ]] || {
    printf 'flux.dll is not the verified version for the CPU speed fix; refusing to patch it.\n' >&2
    exit 66
}
[[ "$(context_at_offset "$FLUX_DLL")" == "$EXPECTED_CONTEXT" ]] || {
    printf 'flux.dll has an unexpected byte sequence at the CPU speed fix offset.\n' >&2
    exit 65
}

backup_dir="${GERPATCH_BACKUP_DIR:-$PATCH_DIR/backups}"
mkdir -p -- "$backup_dir"
backup="$backup_dir/flux.dll-before-high-clock-cpu-fix-$(date +%Y%m%d-%H%M%S)"
cp -a -- "$FLUX_DLL" "$backup"
progress cpu-speed 0 2
printf '\001' | dd of="$FLUX_DLL" bs=1 seek="$OFFSET" conv=notrunc status=none
progress cpu-speed 1 2
if [[ "$(sha256 "$FLUX_DLL")" != "$PATCHED_HASH" || "$(context_at_offset "$FLUX_DLL")" != "$PATCHED_CONTEXT" ]]; then
    cp -af -- "$backup" "$FLUX_DLL"
    printf 'CPU speed fix verification failed; the original flux.dll was restored.\n' >&2
    exit 65
fi
progress cpu-speed 2 2
printf 'CPU speed fix installed. Backup: %s\n' "$backup"
