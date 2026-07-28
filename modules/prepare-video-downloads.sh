#!/usr/bin/env bash
# Download only the selected twelve cinematic videos into a persistent cache.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=video-library.sh
source "$PATCH_DIR/modules/video-library.sh"

PROGRESS_FILE="${GERPATCH_PROGRESS_FILE:-}"
download_temporary=''

progress() {
    [[ -n "$PROGRESS_FILE" ]] || return 0
    local temporary="${PROGRESS_FILE}.tmp.$$"
    printf 'video-downloads|%s|%s\n' "$1" "$2" > "$temporary"
    mv -f -- "$temporary" "$PROGRESS_FILE"
}

cleanup() {
    if [[ -n "$download_temporary" ]]; then
        rm -f -- "$download_temporary"
    fi
}
trap cleanup EXIT INT TERM

[[ $# -ge 2 ]] || {
    printf 'Usage: %s <english|german> <standard|widescreen> [video.bik ...]\n' "$(basename -- "$0")" >&2
    exit 64
}

language="$1"
aspect="$2"
case "$language" in english|german) ;; *) printf 'Unknown video language: %s\n' "$language" >&2; exit 64 ;; esac
case "$aspect" in standard|widescreen) ;; *) printf 'Unknown video aspect: %s\n' "$aspect" >&2; exit 64 ;; esac
command -v curl >/dev/null || { printf 'curl is required to download videos.\n' >&2; exit 69; }

if (( $# > 2 )); then
    requested_videos=("${@:3}")
else
    requested_videos=("${VIDEO_CINEMATICS[@]}")
fi
declare -A allowed_videos=()
declare -A seen_videos=()
for name in "${VIDEO_CINEMATICS[@]}"; do allowed_videos["$name"]=1; done
for name in "${requested_videos[@]}"; do
    [[ -n "${allowed_videos[$name]:-}" ]] || {
        printf 'Unknown cinematic video: %s\n' "$name" >&2
        exit 64
    }
    [[ -z "${seen_videos[$name]:-}" ]] || {
        printf 'Duplicate cinematic video: %s\n' "$name" >&2
        exit 64
    }
    seen_videos["$name"]=1
done

mkdir -p -- "$VIDEO_CACHE_DIR/$language/$aspect/movies"
progress 0 "${#requested_videos[@]}"
completed=0

for relative in "${requested_videos[@]}"; do
    expected="$(video_expected_hash "$language" "$aspect" "$relative")"
    cached_file="$(video_cache_file "$language" "$aspect" "$relative")"
    if video_matches_hash "$cached_file" "$expected"; then
        printf 'Cached and verified: %s\n' "$relative"
    else
        # This directory belongs exclusively to this patcher, so a stale or corrupt
        # cache item can safely be replaced before the verified atomic move below.
        rm -f -- "$cached_file"
        url="$(video_source_url "$language" "$aspect" "$relative")"
        [[ -n "$url" ]] || {
            printf 'No URL configured for %s in %s (key: %s).\n' \
                "$relative" "$SOURCES_FILE" "$(video_source_key "$language" "$aspect" "$relative")" >&2
            exit 66
        }
        download_temporary="$(mktemp "${cached_file}.download.XXXXXX")"
        printf 'Downloading: %s\n' "$relative"
        curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --silent --show-error \
            --output "$download_temporary" "$url"
        video_matches_hash "$download_temporary" "$expected" || {
            printf 'Downloaded video failed SHA-256 validation: %s\n' "$relative" >&2
            exit 65
        }
        mv -f -- "$download_temporary" "$cached_file"
        download_temporary=''
        printf 'Downloaded and verified: %s\n' "$relative"
    fi
    completed=$((completed + 1))
    progress "$completed" "${#requested_videos[@]}"
done

printf 'Video cache is ready: %s\n' "$VIDEO_CACHE_DIR/$language/$aspect/movies"
