#!/usr/bin/env bash
# Converts recognized original English WAV files to a canonical PCM form.
# Canonical PCM, legacy PCM and German WAV files are never converted again.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
MANIFEST="$PATCH_DIR/patch-manifest.txt"
AUDIO_HASH_MANIFEST="$PATCH_DIR/audio-conversion-hashes.txt"
# shellcheck source=audio-hash-library.sh
source "$PATCH_DIR/modules/audio-hash-library.sh"
PROGRESS_FILE="${GERPATCH_PROGRESS_FILE:-}"

sha256() { sha256sum -- "$1" | awk '{print $1}'; }
progress() {
    [[ -n "$PROGRESS_FILE" ]] || return 0
    local temporary="${PROGRESS_FILE}.tmp.$$"
    printf '%s|%s|%s\n' "$1" "$2" "$3" > "$temporary"
    mv -f -- "$temporary" "$PROGRESS_FILE"
}

[[ $# -eq 1 ]] || { printf 'Usage: %s <IW2 installation directory>\n' "$(basename -- "$0")" >&2; exit 64; }
TARGET_DIR="$(cd -- "$1" && pwd -P)"
STREAMS="$TARGET_DIR/streams"
[[ -d "$STREAMS" ]] || { printf 'Missing streams directory.\n' >&2; exit 66; }
[[ -f "$MANIFEST" ]] || { printf 'Missing patch manifest.\n' >&2; exit 66; }
[[ -f "$AUDIO_HASH_MANIFEST" ]] || { printf 'Missing audio conversion hash manifest.\n' >&2; exit 66; }
command -v ffmpeg >/dev/null || { printf 'ffmpeg is required to convert non-PCM WAV files.\n' >&2; exit 69; }
command -v ffprobe >/dev/null || { printf 'ffprobe is required to inspect WAV codecs.\n' >&2; exit 69; }

audio_hashes_load "$AUDIO_HASH_MANIFEST"

audio_codec() {
    ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 -- "$1" | head -n 1
}

is_pcm_s16le() {
    [[ "$(audio_codec "$1")" == 'pcm_s16le' ]]
}

declare -A GERMAN_HASH=()
while IFS='|' read -r relative _ german_hash; do
    [[ -n "$relative" && "$relative" != \#* ]] || continue
    [[ "${relative,,}" == streams/*.wav ]] || continue
    GERMAN_HASH["$relative"]="$german_hash"
done < "$MANIFEST"

mapfile -d '' wavs < <(find "$STREAMS" -type f -iname '*.wav' -print0 | sort -z)
declare -a convert=()
unknown_pcm=0
unknown_non_pcm=0
recognized_pcm=0
recognized_german=0
recognized_original_pcm=0

for wav in "${wavs[@]}"; do
    relative="$(realpath --relative-to="$TARGET_DIR" "$wav")"
    current_hash="$(sha256 "$wav")"
    german_hash="${GERMAN_HASH[$relative]:-}"
    original_hash="$(audio_original_hash "$relative")"

    if [[ -n "$german_hash" && "$current_hash" == "$german_hash" ]]; then
        ((recognized_german += 1))
        continue
    fi

    if audio_pcm_hash_matches "$relative" "$current_hash"; then
        ((recognized_pcm += 1))
        continue
    fi

    if [[ -n "$original_hash" && "$current_hash" == "$original_hash" ]]; then
        if is_pcm_s16le "$wav"; then
            ((recognized_original_pcm += 1))
        else
            convert+=("$wav")
        fi
        continue
    fi

    if is_pcm_s16le "$wav"; then
        printf 'Warning: unrecognized pcm_s16le WAV left untouched: %s\n' "$relative" >&2
        ((unknown_pcm += 1))
    else
        printf 'Unrecognized non-PCM WAV; refusing to convert: %s\n' "$relative" >&2
        ((unknown_non_pcm += 1))
    fi
done

if (( unknown_non_pcm > 0 )); then
    printf 'Found %s unrecognized non-PCM WAV file(s); nothing was converted.\n' "$unknown_non_pcm" >&2
    exit 2
fi

if (( ${#convert[@]} == 0 )); then
    progress audio 1 1
    printf 'No audio conversion needed. Recognized PCM: %s, original PCM: %s, German: %s, unknown PCM skipped: %s\n' \
        "$recognized_pcm" "$recognized_original_pcm" "$recognized_german" "$unknown_pcm"
    exit 0
fi

total="${#convert[@]}"
current=0
progress audio "$current" "$total"
for wav in "${convert[@]}"; do
    relative="$(realpath --relative-to="$TARGET_DIR" "$wav")"
    expected_pcm="$(audio_pcm_canonical_hash "$relative")"
    [[ -n "$expected_pcm" ]] || { printf 'No canonical PCM hash registered for: %s\n' "$relative" >&2; exit 65; }

    temporary="${wav}.pcm.tmp.$$"
    rm -f -- "$temporary"
    if ! ffmpeg -v error -nostdin -y -i "$wav" -map_metadata -1 -fflags +bitexact -flags:a +bitexact -c:a pcm_s16le -f wav "$temporary"; then
        rm -f -- "$temporary"
        printf 'ffmpeg failed for: %s\n' "$relative" >&2
        exit 65
    fi

    actual_pcm="$(sha256 "$temporary")"
    if [[ "$actual_pcm" != "$expected_pcm" ]]; then
        rm -f -- "$temporary"
        printf 'Canonical PCM verification failed: %s\nExpected: %s\nActual:   %s\n' "$relative" "$expected_pcm" "$actual_pcm" >&2
        exit 65
    fi

    chmod --reference="$wav" "$temporary"
    mv -f -- "$temporary" "$wav"
    ((current += 1))
    progress audio "$current" "$total"
done

printf 'Converted and verified %s WAV file(s) to canonical PCM.\n' "$total"
