#!/usr/bin/env bash
# Shared cache and verification helpers for externally hosted German game data.

# shellcheck source=video-library.sh
source "$PATCH_DIR/modules/video-library.sh"

GERMAN_DATA_HASH_DIR="${IW2_GERMAN_DATA_HASH_DIR:-$PATCH_DIR/payload-hashes}"
GERMAN_DATA_CACHE_DIR="${IW2_GERMAN_DATA_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/independence-war-2-ultimate-patcher/german-game-data}"

german_data_sha256() {
    sha256sum -- "$1" | awk '{print $1}'
}

german_data_archive_hash() {
    local archive_name="$1" hash_file expected
    hash_file="$GERMAN_DATA_HASH_DIR/$archive_name.hash"
    [[ -f "$hash_file" ]] || {
        printf 'German data archive hash is missing: %s\n' "$hash_file" >&2
        return 66
    }
    expected="$(tr -d '[:space:]' < "$hash_file")"
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || {
        printf 'Invalid German data archive hash: %s\n' "$hash_file" >&2
        return 65
    }
    printf '%s\n' "$expected"
}

german_data_matches_hash() {
    local file="$1" expected="$2"
    [[ -f "$file" && "$(german_data_sha256 "$file")" == "$expected" ]]
}

german_data_source_file() {
    local relative="$1"
    case "$relative" in
        resource.zip|resource/*|streams/*) printf '%s/payload/%s\n' "$GERMAN_DATA_CACHE_DIR" "$relative" ;;
        *) printf 'Unsupported German game-data path: %s\n' "$relative" >&2; return 64 ;;
    esac
}

german_data_cache_is_complete() {
    local manifest="$1" relative _ german_hash source_file
    while IFS='|' read -r relative _ german_hash; do
        [[ -n "$relative" && "$relative" != \#* && -n "$german_hash" ]] || continue
        case "$relative" in resource.zip|resource/*|streams/*) ;; *) continue ;; esac
        source_file="$(german_data_source_file "$relative")"
        german_data_matches_hash "$source_file" "$german_hash" || return 1
    done < "$manifest"
}
