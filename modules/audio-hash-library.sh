#!/usr/bin/env bash
# Shared hash recognition for original and converted English WAV files.

declare -Ag AUDIO_ORIGINAL_HASH=()
declare -Ag AUDIO_PCM_CANONICAL=()
declare -Ag AUDIO_PCM_LEGACY=()

audio_hashes_load() {
    local manifest="${1:-}"
    AUDIO_ORIGINAL_HASH=()
    AUDIO_PCM_CANONICAL=()
    AUDIO_PCM_LEGACY=()
    [[ -n "$manifest" && -f "$manifest" ]] || return 0

    local relative original canonical legacy
    while IFS='|' read -r relative original canonical legacy; do
        [[ -n "$relative" && "$relative" != \#* && -n "$original" && -n "$canonical" ]] || continue
        AUDIO_ORIGINAL_HASH["$relative"]="$original"
        AUDIO_PCM_CANONICAL["$relative"]="$canonical"
        AUDIO_PCM_LEGACY["$relative"]="${legacy:--}"
    done < "$manifest"
}

audio_original_hash() {
    printf '%s\n' "${AUDIO_ORIGINAL_HASH[$1]:-}"
}

audio_pcm_canonical_hash() {
    printf '%s\n' "${AUDIO_PCM_CANONICAL[$1]:-}"
}

audio_pcm_hash_matches() {
    local relative="$1" actual="$2" canonical legacy item
    [[ -n "$actual" ]] || return 1

    canonical="${AUDIO_PCM_CANONICAL[$relative]:-}"
    [[ -n "$canonical" && "$actual" == "$canonical" ]] && return 0

    legacy="${AUDIO_PCM_LEGACY[$relative]:-}"
    [[ -n "$legacy" && "$legacy" != '-' ]] || return 1

    local -a legacy_items=()
    IFS=',' read -r -a legacy_items <<< "$legacy"
    for item in "${legacy_items[@]}"; do
        [[ -n "$item" && "$actual" == "$item" ]] && return 0
    done
    return 1
}
