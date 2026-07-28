#!/usr/bin/env bash
# Restores the exact files saved by apply-german-patch.sh.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
MANIFEST="$PATCH_DIR/patch-manifest.txt"
PROGRESS_FILE="${GERPATCH_PROGRESS_FILE:-}"

usage() {
    printf 'Usage: %s <IW2 installation directory> [backup.zip]\n' "$(basename -- "$0")" >&2
    exit 64
}

sha256() {
    sha256sum -- "$1" | awk '{print $1}'
}

progress() {
    [[ -n "$PROGRESS_FILE" ]] || return 0
    local stage="$1"
    local current="$2"
    local total="$3"
    local temporary="${PROGRESS_FILE}.tmp.$$"
    printf '%s|%s|%s\n' "$stage" "$current" "$total" > "$temporary"
    mv -f -- "$temporary" "$PROGRESS_FILE"
}

[[ $# -ge 1 && $# -le 2 ]] || usage
TARGET_DIR="$(cd -- "$1" && pwd -P)"
[[ -f "$TARGET_DIR/EdgeOfChaos.exe" && -f "$TARGET_DIR/resource.zip" ]] || {
    printf 'Not an Independence War 2 installation: %s\n' "$TARGET_DIR" >&2
    exit 66
}
[[ -f "$MANIFEST" ]] || { printf 'Missing patch manifest.\n' >&2; exit 66; }
command -v 7z >/dev/null || { printf '7z is required for restoration.\n' >&2; exit 69; }

if [[ $# -eq 2 ]]; then
    BACKUP="$2"
else
    BACKUP="$(find "$PATCH_DIR/backups" -maxdepth 1 -type f -name 'IW2EOC-before-GERPATCH-*.zip' -printf '%T@|%p\n' 2>/dev/null | LC_ALL=C sort -nr | sed -n '1s/^[^|]*|//p')"
fi
[[ -n "${BACKUP:-}" && -f "$BACKUP" ]] || {
    printf 'No apply-time backup found; pass its path explicitly.\n' >&2
    exit 66
}

declare -a PATHS=()
declare -a BACKUP_PATHS=()
while IFS='|' read -r relative english_hash german_hash; do
    [[ -z "$relative" || "$relative" == \#* ]] && continue
    current="$TARGET_DIR/$relative"
    if [[ "$english_hash" == '-' ]]; then
        [[ -f "$current" && "$(sha256 "$current")" == "$german_hash" ]] || {
            printf 'Refusing to remove unrecognized file: %s\n' "$relative" >&2
            exit 2
        }
    else
        [[ -f "$current" && "$(sha256 "$current")" == "$german_hash" ]] || {
            printf 'Refusing to overwrite unrecognized file: %s\n' "$relative" >&2
            exit 2
        }
        BACKUP_PATHS+=("$relative")
    fi
    PATHS+=("$relative")
done < "$MANIFEST"

tmp_dir="$(mktemp -d)"
list_file="$(mktemp)"
trap 'rm -rf "$tmp_dir"; rm -f "$list_file"' EXIT
printf '%s\n' "${BACKUP_PATHS[@]}" > "$list_file"
progress restore-backup 15 100
7z x -y -bd "-o$tmp_dir" "$BACKUP" @"$list_file" >/dev/null

restore_count=0
progress restore "$restore_count" "${#PATHS[@]}"
while IFS='|' read -r relative english_hash german_hash; do
    [[ -z "$relative" || "$relative" == \#* ]] && continue
    if [[ "$english_hash" == '-' ]]; then
        rm -f -- "$TARGET_DIR/$relative"
        ((restore_count += 1))
        progress restore "$restore_count" "${#PATHS[@]}"
        continue
    fi
    saved="$tmp_dir/$relative"
    [[ -f "$saved" && "$(sha256 "$saved")" == "$english_hash" ]] || {
        printf 'Backup does not contain the expected English file: %s\n' "$relative" >&2
        exit 65
    }
    destination="$TARGET_DIR/$relative"
    mkdir -p -- "$(dirname -- "$destination")"
    cp -af -- "$saved" "$destination"
    ((restore_count += 1))
    progress restore "$restore_count" "${#PATHS[@]}"
done < "$MANIFEST"

printf 'English files restored from %s\n' "$BACKUP"
