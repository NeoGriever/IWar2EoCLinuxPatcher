#!/usr/bin/env bash
# Shared video catalogue, checksum and cache helpers.  Source this file.

declare -a VIDEO_CINEMATICS=(
    Infogrames.bik OldCalShutdown.bik OldCalStartup.bik PBDiscovery.bik
    PB_Beauty.bik Prelude.bik YoungCalShutdown.bik YoungCalStartup.bik
    intro.bik midtro.bik Outro.bik psys.bik
)

# Only these original 4:3 files differ between the English and German base
# games. They are needed when German game data is installed without a complete
# user-selected video variant.
declare -a GERMAN_STORY_VIDEOS=(intro.bik midtro.bik Outro.bik)

VIDEO_HASH_DIR="${IW2_VIDEO_HASH_DIR:-$PATCH_DIR/video-hashes}"
# IW2_VIDEO_SOURCES_FILE remains accepted for isolated older tests, while the
# single shared configuration is now sources.json.
SOURCES_FILE="${IW2_SOURCES_FILE:-${IW2_VIDEO_SOURCES_FILE:-$PATCH_DIR/sources.json}}"
VIDEO_CACHE_DIR="${IW2_VIDEO_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/independence-war-2-ultimate-patcher/videos}"

video_sha256() {
    sha256sum -- "$1" | awk '{print $1}'
}

video_hash_file() {
    local language="$1" aspect="$2" relative="$3"
    printf '%s/%s/%s/movies/%s.hash\n' "$VIDEO_HASH_DIR" "$language" "$aspect" "${relative##*/}"
}

video_cache_file() {
    local language="$1" aspect="$2" relative="$3"
    printf '%s/%s/%s/movies/%s\n' "$VIDEO_CACHE_DIR" "$language" "$aspect" "${relative##*/}"
}

video_source_key() {
    local language="$1" aspect="$2" relative="$3" stem
    stem="${relative##*/}"
    stem="${stem%.bik}"
    stem="${stem,,}"
    printf '%s_%s_%s\n' "$language" "$aspect" "$stem"
}

video_expected_hash() {
    local language="$1" aspect="$2" relative="$3" hash_file expected
    hash_file="$(video_hash_file "$language" "$aspect" "$relative")"
    [[ -f "$hash_file" ]] || {
        printf 'Video hash file is missing: %s\n' "$hash_file" >&2
        return 66
    }
    expected="$(tr -d '[:space:]' < "$hash_file")"
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || {
        printf 'Invalid video hash file: %s\n' "$hash_file" >&2
        return 65
    }
    printf '%s\n' "$expected"
}

video_matches_hash() {
    local file="$1" expected="$2"
    [[ -f "$file" && "$(video_sha256 "$file")" == "$expected" ]]
}

source_url_for_key() {
    local key="$1"
    [[ -f "$SOURCES_FILE" ]] || {
        printf 'Source URL configuration is missing: %s\n' "$SOURCES_FILE" >&2
        return 66
    }
    # The supplied JSON is deliberately flat and contains only simple keys and URLs.
    # This avoids making jq a mandatory dependency for the patcher.
    sed -n -E 's/^[[:space:]]*"'"$key"'"[[:space:]]*:[[:space:]]*"([^"]*)"[[:space:]]*,?[[:space:]]*$/\1/p' "$SOURCES_FILE" | head -n 1
}

video_source_url() {
    local language="$1" aspect="$2" relative="$3" key
    key="$(video_source_key "$language" "$aspect" "$relative")"
    source_url_for_key "$key"
}
