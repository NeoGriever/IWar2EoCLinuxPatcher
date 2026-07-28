#!/usr/bin/env bash
# Installs one checksum-verified language/aspect video set and keeps a ZIP backup.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=video-library.sh
source "$PATCH_DIR/modules/video-library.sh"
PROGRESS_FILE="${GERPATCH_PROGRESS_FILE:-}"

progress() {
    [[ -n "$PROGRESS_FILE" ]] || return 0
    local temporary="${PROGRESS_FILE}.tmp.$$"
    printf 'videos|%s|%s\n' "$1" "$2" > "$temporary"
    mv -f -- "$temporary" "$PROGRESS_FILE"
}

[[ $# -eq 3 ]] || {
    printf 'Usage: %s <IW2 installation directory> <english|german> <standard|widescreen>\n' "$(basename -- "$0")" >&2
    exit 64
}

TARGET_DIR="$(cd -- "$1" && pwd -P)"
language="$2"
aspect="$3"
case "$language" in english|german) ;; *) printf 'Unknown video language: %s\n' "$language" >&2; exit 64 ;; esac
case "$aspect" in standard|widescreen) ;; *) printf 'Unknown video aspect: %s\n' "$aspect" >&2; exit 64 ;; esac

[[ -d "$TARGET_DIR/movies" ]] || {
    printf 'The game movie directory is missing: %s/movies\n' "$TARGET_DIR" >&2
    exit 66
}
command -v 7z >/dev/null || { printf '7z is required to back up videos.\n' >&2; exit 69; }

declare -a relative_paths=()
declare -a expected_hashes=()
for name in "${VIDEO_CINEMATICS[@]}"; do
    relative="movies/$name"
    relative_paths+=("$relative")
    expected_hashes+=("$(video_expected_hash "$language" "$aspect" "$name")")
done

for index in "${!relative_paths[@]}"; do
    source_file="$(video_cache_file "$language" "$aspect" "${relative_paths[$index]}")"
    video_matches_hash "$source_file" "${expected_hashes[$index]}" || {
        printf 'Prepared video cache is missing or damaged: %s\n' "$source_file" >&2
        printf 'Run the download preparation before installing videos.\n' >&2
        exit 65
    }
    [[ -f "$TARGET_DIR/${relative_paths[$index]}" ]] || {
        printf 'Game video is missing and cannot be backed up: %s\n' "${relative_paths[$index]}" >&2
        exit 66
    }
done

backup_dir="${GERPATCH_BACKUP_DIR:-$PATCH_DIR/backups}"
mkdir -p -- "$backup_dir"
backup="$backup_dir/IW2EOC-before-videos-${language}-${aspect}-$(date +%Y%m%d-%H%M%S).zip"
list_file="$(mktemp)"
printf '%s\n' "${relative_paths[@]}" > "$list_file"
(
    cd -- "$TARGET_DIR"
    7z a -tzip -mx=1 -bd "$backup" @"$list_file"
)
rm -f -- "$list_file"
7z t -bd "$backup" >/dev/null
[[ -s "$backup" ]] || { printf 'Video backup was not created.\n' >&2; exit 65; }

installed=0
rollback_needed=1
rollback() {
    local status=$?
    if (( rollback_needed )); then
        printf 'Restoring the video backup after a failed install.\n' >&2
        7z x -y -bd "-o$TARGET_DIR" "$backup" >/dev/null || true
    fi
    return "$status"
}
trap rollback EXIT

total=$(( ${#relative_paths[@]} * 2 ))
progress 0 "$total"
for index in "${!relative_paths[@]}"; do
    relative="${relative_paths[$index]}"
    target_file="$TARGET_DIR/$relative"
    mkdir -p -- "$(dirname -- "$target_file")"
    cp -af -- "$(video_cache_file "$language" "$aspect" "$relative")" "$target_file"
    installed=$((installed + 1))
    progress "$installed" "$total"
done

for index in "${!relative_paths[@]}"; do
    target_file="$TARGET_DIR/${relative_paths[$index]}"
    [[ "$(video_sha256 "$target_file")" == "${expected_hashes[$index]}" ]] || {
        printf 'Video verification failed: %s\n' "${relative_paths[$index]}" >&2
        exit 65
    }
    installed=$((installed + 1))
    progress "$installed" "$total"
done

rollback_needed=0
trap - EXIT
printf 'Installed cached %s %s video set. Backup: %s\n' "$language" "$aspect" "$backup"
