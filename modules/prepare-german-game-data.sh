#!/usr/bin/env bash
# Fetch the non-redistributed German base-data archives before patching a game.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=german-data-library.sh
source "$PATCH_DIR/modules/german-data-library.sh"

MANIFEST="$PATCH_DIR/patch-manifest.txt"
PROGRESS_FILE="${GERPATCH_PROGRESS_FILE:-}"
temporary_download=''
temporary_extract=''

progress() {
    [[ -n "$PROGRESS_FILE" ]] || return 0
    local temporary="${PROGRESS_FILE}.tmp.$$"
    printf 'german-data-downloads|%s|%s\n' "$1" "$2" > "$temporary"
    mv -f -- "$temporary" "$PROGRESS_FILE"
}

cleanup() {
    if [[ -n "$temporary_download" ]]; then
        rm -f -- "$temporary_download"
    fi
    if [[ -n "$temporary_extract" ]]; then
        rm -rf -- "$temporary_extract"
    fi
}
trap cleanup EXIT INT TERM

[[ $# -eq 0 ]] || {
    printf 'Usage: %s\n' "$(basename -- "$0")" >&2
    exit 64
}
[[ -f "$MANIFEST" ]] || { printf 'German patch manifest is missing.\n' >&2; exit 66; }
command -v curl >/dev/null || { printf 'curl is required to download German game data.\n' >&2; exit 69; }
command -v 7z >/dev/null || { printf '7z is required to unpack German game data.\n' >&2; exit 69; }

mkdir -p -- "$GERMAN_DATA_CACHE_DIR/archives" "$GERMAN_DATA_CACHE_DIR/payload"

download_artifact() {
    local source_key="$1" archive_name="$2" expected cache_file url
    expected="$(german_data_archive_hash "$archive_name")"
    cache_file="$GERMAN_DATA_CACHE_DIR/archives/$archive_name"
    if german_data_matches_hash "$cache_file" "$expected"; then
        printf 'Cached and verified: %s\n' "$archive_name"
        return 0
    fi
    rm -f -- "$cache_file"
    url="$(source_url_for_key "$source_key")"
    [[ -n "$url" ]] || {
        printf 'No URL configured for %s in %s (key: %s).\n' "$archive_name" "$SOURCES_FILE" "$source_key" >&2
        return 66
    }
    temporary_download="$(mktemp "${cache_file}.download.XXXXXX")"
    printf 'Downloading: %s\n' "$archive_name"
    curl --fail --location --retry 3 --retry-delay 1 --connect-timeout 20 --silent --show-error \
        --output "$temporary_download" "$url"
    german_data_matches_hash "$temporary_download" "$expected" || {
        printf 'Downloaded German data archive failed SHA-256 validation: %s\n' "$archive_name" >&2
        return 65
    }
    mv -f -- "$temporary_download" "$cache_file"
    temporary_download=''
    printf 'Downloaded and verified: %s\n' "$archive_name"
}

extract_component() {
    local archive_name="$1" component="$2" archive_file destination
    archive_file="$GERMAN_DATA_CACHE_DIR/archives/$archive_name"
    destination="$GERMAN_DATA_CACHE_DIR/payload/$component"
    temporary_extract="$(mktemp -d "$GERMAN_DATA_CACHE_DIR/.extract.XXXXXX")"
    7z x -y -bd "-o$temporary_extract" "$archive_file" >/dev/null
    [[ -d "$temporary_extract/$component" ]] || {
        printf 'German data archive has no %s/ directory: %s\n' "$component" "$archive_name" >&2
        return 65
    }
    rm -rf -- "$destination"
    mv -- "$temporary_extract/$component" "$destination"
    rm -rf -- "$temporary_extract"
    temporary_extract=''
}

progress 0 3
download_artifact german_resource_zip resource.zip
cp -af -- "$GERMAN_DATA_CACHE_DIR/archives/resource.zip" "$GERMAN_DATA_CACHE_DIR/payload/resource.zip"
progress 1 3
download_artifact german_resource_overlay resource-overlay.zip
download_artifact german_streams streams.zip

if ! german_data_cache_is_complete "$MANIFEST"; then
    extract_component resource-overlay.zip resource
    extract_component streams.zip streams
fi
progress 3 3
german_data_cache_is_complete "$MANIFEST" || {
    printf 'Prepared German game data does not match the patch manifest.\n' >&2
    exit 65
}
printf 'German game-data cache is ready: %s/payload\n' "$GERMAN_DATA_CACHE_DIR"
