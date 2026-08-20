#!/usr/bin/env bash
# Applies this package to a verified English Steam installation.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=modules/german-data-library.sh
source "$PATCH_DIR/modules/german-data-library.sh"
# shellcheck source=modules/audio-hash-library.sh
source "$PATCH_DIR/modules/audio-hash-library.sh"
MANIFEST="$PATCH_DIR/patch-manifest.txt"
AUDIO_HASH_MANIFEST="$PATCH_DIR/audio-conversion-hashes.txt"
MODE=apply
PROGRESS_FILE="${GERPATCH_PROGRESS_FILE:-}"
SKIP_GERMAN_STORY_VIDEOS="${GERPATCH_SKIP_GERMAN_STORY_VIDEOS:-0}"
GERMAN_STORY_VIDEOS_PREPARED="${GERPATCH_GERMAN_STORY_VIDEOS_PREPARED:-0}"
GERMAN_GAME_DATA_PREPARED="${GERPATCH_GERMAN_GAME_DATA_PREPARED:-0}"

usage() {
    printf 'Usage: %s [--status] <IW2 installation directory>\n' "$(basename -- "$0")" >&2
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

if [[ "${1:-}" == "--status" ]]; then
    MODE=status
    shift
fi
[[ $# -eq 1 ]] || usage

TARGET_DIR="$(cd -- "$1" && pwd -P)"
[[ -f "$TARGET_DIR/EdgeOfChaos.exe" && -f "$TARGET_DIR/resource.zip" ]] || {
    printf 'Not an Independence War 2 installation: %s\n' "$TARGET_DIR" >&2
    exit 66
}
[[ -f "$MANIFEST" ]] || { printf 'Missing patch manifest.\n' >&2; exit 66; }
[[ -f "$AUDIO_HASH_MANIFEST" ]] || { printf 'Missing audio conversion hash manifest.\n' >&2; exit 66; }
audio_hashes_load "$AUDIO_HASH_MANIFEST"
command -v 7z >/dev/null || { printf '7z is required for backups.\n' >&2; exit 69; }
case "$SKIP_GERMAN_STORY_VIDEOS" in 0|1) ;; *) printf 'Invalid German story-video mode.\n' >&2; exit 64 ;; esac
case "$GERMAN_STORY_VIDEOS_PREPARED" in 0|1) ;; *) printf 'Invalid German story-video preparation state.\n' >&2; exit 64 ;; esac
case "$GERMAN_GAME_DATA_PREPARED" in 0|1) ;; *) printf 'Invalid German game-data preparation state.\n' >&2; exit 64 ;; esac

if [[ "$MODE" == apply ]]; then
    if [[ "$GERMAN_GAME_DATA_PREPARED" == 0 ]]; then
        "$PATCH_DIR/modules/prepare-german-game-data.sh"
    fi
    if [[ "$SKIP_GERMAN_STORY_VIDEOS" == 0 && "$GERMAN_STORY_VIDEOS_PREPARED" == 0 ]]; then
        "$PATCH_DIR/modules/prepare-video-downloads.sh" german standard "${GERMAN_STORY_VIDEOS[@]}"
    fi
fi

declare -a PATHS=()
declare -a BACKUP_PATHS=()
english_count=0
german_count=0
shared_count=0
unknown_count=0

printf 'Patch status for %s\n' "$TARGET_DIR"
while IFS='|' read -r relative english_hash german_hash; do
    [[ -z "$relative" || "$relative" == \#* ]] && continue
    if [[ "$relative" == movies/* ]]; then
        [[ "$SKIP_GERMAN_STORY_VIDEOS" == 0 ]] || continue
        payload="$(video_cache_file german standard "${relative#movies/}")"
        if [[ "$MODE" == apply ]]; then
            [[ -f "$payload" ]] || { printf 'Prepared German video is missing: %s\n' "$relative" >&2; exit 66; }
            [[ "$(sha256 "$payload")" == "$german_hash" ]] || {
                printf 'Damaged prepared German video: %s\n' "$relative" >&2
                exit 65
            }
        fi
    else
        payload="$(german_data_source_file "$relative")"
        if [[ "$MODE" == apply ]]; then
            [[ -f "$payload" ]] || { printf 'Prepared German payload is missing: %s\n' "$relative" >&2; exit 66; }
            [[ "$(sha256 "$payload")" == "$german_hash" ]] || {
                printf 'Damaged prepared German payload: %s\n' "$relative" >&2
                exit 65
            }
        fi
    fi
    target="$TARGET_DIR/$relative"
    PATHS+=("$relative")
    current_hash=''
    [[ -f "$target" ]] && current_hash="$(sha256 "$target")"
    if [[ ! -f "$target" ]]; then
        if [[ "$english_hash" == '-' ]]; then
            printf '  ENGLISH  %s (not present in Steam)\n' "$relative"
            ((english_count += 1))
        else
            printf '  UNKNOWN  %s (missing)\n' "$relative"
            ((unknown_count += 1))
        fi
    elif [[ "$english_hash" != '-' && "$english_hash" == "$german_hash" && "$current_hash" == "$german_hash" ]]; then
        printf '  SHARED   %s (identical in English and German)\n' "$relative"
        ((shared_count += 1))
    elif [[ "$current_hash" == "$english_hash" ]]; then
        printf '  ENGLISH  %s\n' "$relative"
        ((english_count += 1))
    elif [[ "$current_hash" == "$german_hash" ]]; then
        printf '  GERMAN   %s\n' "$relative"
        ((german_count += 1))
    elif audio_pcm_hash_matches "$relative" "$current_hash"; then
        printf '  ENGLISH-PCM  %s\n' "$relative"
        ((english_count += 1))
    else
        printf '  UNKNOWN  %s (unexpected checksum)\n' "$relative"
        ((unknown_count += 1))
    fi
    [[ -f "$target" ]] && BACKUP_PATHS+=("$relative")
done < "$MANIFEST"

if (( unknown_count > 0 )); then
    printf 'Result: unrecognized installation; nothing will be changed.\n' >&2
    exit 2
fi
if (( german_count + shared_count == ${#PATHS[@]} )); then
    printf 'Result: German patch is active.\n'
    exit 0
fi
if (( english_count + shared_count == ${#PATHS[@]} )); then
    printf 'Result: verified English Steam version.\n'
else
    printf 'Result: recognized partial German patch.\n'
fi
[[ "$MODE" == status ]] && exit 0

BACKUP_DIR="$PATCH_DIR/backups"
mkdir -p "$BACKUP_DIR"
timestamp="$(date +%Y%m%d-%H%M%S)"
backup="$BACKUP_DIR/IW2EOC-before-GERPATCH-$timestamp.zip"
list_file="$(mktemp)"
trap 'rm -f "$list_file"' EXIT
printf '%s\n' "${BACKUP_PATHS[@]}" > "$list_file"

printf 'Creating reversible backup: %s\n' "$backup"
progress backup 15 100
( cd "$TARGET_DIR" && 7z a -tzip -mx=1 -bd "$backup" @"$list_file" )
7z t -bd "$backup" >/dev/null

copy_count=0
progress apply "$copy_count" "${#PATHS[@]}"
for relative in "${PATHS[@]}"; do
    destination="$TARGET_DIR/$relative"
    mkdir -p -- "$(dirname -- "$destination")"
    if [[ "$relative" == movies/* ]]; then
        cp -af -- "$(video_cache_file german standard "${relative#movies/}")" "$destination"
    else
        cp -af -- "$(german_data_source_file "$relative")" "$destination"
    fi
    ((copy_count += 1))
    progress apply "$copy_count" "${#PATHS[@]}"
done

printf 'German patch applied. Restore with:\n  %s %q %q\n' \
    "$PATCH_DIR/restore-english.sh" "$TARGET_DIR" "$backup"
