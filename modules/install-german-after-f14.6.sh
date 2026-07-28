#!/usr/bin/env bash
# Reapplies the checksum-verified German CD data after F14.6.  F14.6 contains
# mixed-case English/German/French language payloads on Linux, so this order is
# required when the user explicitly selected German game data.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=german-data-library.sh
source "$PATCH_DIR/modules/german-data-library.sh"
MANIFEST="$PATCH_DIR/patch-manifest.txt"
PROGRESS_FILE="${GERPATCH_PROGRESS_FILE:-}"
F14_IGAME_HASH='f02b4d199471524db0b6cd6ffc82a76555c33fee5bb24b7a8fd61e4984f542bb'
SKIP_GERMAN_STORY_VIDEOS="${GERPATCH_SKIP_GERMAN_STORY_VIDEOS:-0}"
GERMAN_STORY_VIDEOS_PREPARED="${GERPATCH_GERMAN_STORY_VIDEOS_PREPARED:-0}"
GERMAN_GAME_DATA_PREPARED="${GERPATCH_GERMAN_GAME_DATA_PREPARED:-0}"

progress() {
    [[ -n "$PROGRESS_FILE" ]] || return 0
    local temporary="${PROGRESS_FILE}.tmp.$$"
    printf '%s|%s|%s\n' "$1" "$2" "$3" > "$temporary"
    mv -f -- "$temporary" "$PROGRESS_FILE"
}
sha256() { sha256sum -- "$1" | awk '{print $1}'; }

[[ $# -eq 1 ]] || { printf 'Usage: %s <IW2 installation directory>\n' "$(basename -- "$0")" >&2; exit 64; }
TARGET_DIR="$(cd -- "$1" && pwd -P)"
[[ -f "$TARGET_DIR/EdgeOfChaos.exe" && -f "$TARGET_DIR/resource.zip" ]] || {
    printf 'Not an Independence War 2 installation: %s\n' "$TARGET_DIR" >&2
    exit 66
}
[[ "$(sha256 "$TARGET_DIR/bin/release/igame.dll")" == "$F14_IGAME_HASH" ]] || {
    printf 'Verified F14.6 must be installed before the German post-F14 step.\n' >&2
    exit 2
}
[[ -f "$MANIFEST" ]] || { printf 'Missing German patch manifest.\n' >&2; exit 66; }
command -v 7z >/dev/null || { printf '7z is required for the reversible backup.\n' >&2; exit 69; }
case "$SKIP_GERMAN_STORY_VIDEOS" in 0|1) ;; *) printf 'Invalid German story-video mode.\n' >&2; exit 64 ;; esac
case "$GERMAN_STORY_VIDEOS_PREPARED" in 0|1) ;; *) printf 'Invalid German story-video preparation state.\n' >&2; exit 64 ;; esac
case "$GERMAN_GAME_DATA_PREPARED" in 0|1) ;; *) printf 'Invalid German game-data preparation state.\n' >&2; exit 64 ;; esac

if [[ "$GERMAN_GAME_DATA_PREPARED" == 0 ]]; then
    "$PATCH_DIR/modules/prepare-german-game-data.sh"
fi
if [[ "$SKIP_GERMAN_STORY_VIDEOS" == 0 && "$GERMAN_STORY_VIDEOS_PREPARED" == 0 ]]; then
    "$PATCH_DIR/modules/prepare-video-downloads.sh" german standard "${GERMAN_STORY_VIDEOS[@]}"
fi

declare -a paths=()
declare -a existing=()
while IFS='|' read -r relative _ german_hash; do
    [[ -n "$relative" && "$relative" != \#* && -n "$german_hash" ]] || continue
    if [[ "$relative" == movies/* ]]; then
        [[ "$SKIP_GERMAN_STORY_VIDEOS" == 0 ]] || continue
        payload="$(video_cache_file german standard "${relative#movies/}")"
        [[ -f "$payload" && "$(sha256 "$payload")" == "$german_hash" ]] || {
            printf 'Damaged prepared German video: %s\n' "$relative" >&2
            exit 65
        }
    else
        payload="$(german_data_source_file "$relative")"
        [[ -f "$payload" && "$(sha256 "$payload")" == "$german_hash" ]] || {
            printf 'Damaged prepared German payload: %s\n' "$relative" >&2
            exit 65
        }
    fi
    paths+=("$relative")
    [[ -f "$TARGET_DIR/$relative" ]] && existing+=("$relative")
done < "$MANIFEST"

backup_dir="${GERPATCH_BACKUP_DIR:-$PATCH_DIR/backups}"
mkdir -p -- "$backup_dir"
backup="$backup_dir/IW2EOC-before-German-after-F14.6-$(date +%Y%m%d-%H%M%S).zip"
list_file="$(mktemp)"
trap 'rm -f -- "$list_file"' EXIT
printf '%s\n' "${existing[@]}" > "$list_file"
progress backup 0 100
( cd "$TARGET_DIR" && 7z a -tzip -mx=1 -bd "$backup" @"$list_file" )
7z t -bd "$backup" >/dev/null

current=0
total="${#paths[@]}"
progress german "$current" "$total"
for relative in "${paths[@]}"; do
    destination="$TARGET_DIR/$relative"
    mkdir -p -- "$(dirname -- "$destination")"
    if [[ "$relative" == movies/* ]]; then
        cp -af -- "$(video_cache_file german standard "${relative#movies/}")" "$destination"
    else
        cp -af -- "$(german_data_source_file "$relative")" "$destination"
    fi
    ((current += 1))
    progress german "$current" "$total"
done
printf 'German game data reapplied after F14.6. Backup: %s\n' "$backup"
