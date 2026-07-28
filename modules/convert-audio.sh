#!/usr/bin/env bash
# Converts only non-PCM WAV files.  The German game-data payload already has
# PCM dialogue, therefore this task is disabled whenever that payload is used.
set -Eeuo pipefail

PROGRESS_FILE="${GERPATCH_PROGRESS_FILE:-}"
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

mapfile -d '' wavs < <(find "$STREAMS" -type f -iname '*.wav' -print0 | sort -z)
declare -a convert=()
for wav in "${wavs[@]}"; do
    file -b -- "$wav" | grep -qi 'PCM' || convert+=("$wav")
done
if (( ${#convert[@]} == 0 )); then
    progress audio 1 1
    printf 'All existing WAV files are already PCM-compatible; no conversion was needed.\n'
    exit 0
fi
command -v ffmpeg >/dev/null || { printf 'ffmpeg is required to convert non-PCM WAV files.\n' >&2; exit 69; }

total="${#convert[@]}"
current=0
progress audio "$current" "$total"
for wav in "${convert[@]}"; do
    temporary="${wav}.pcm.tmp.$$"
    ffmpeg -v error -y -i "$wav" -acodec pcm_s16le "$temporary"
    mv -f -- "$temporary" "$wav"
    ((current += 1))
    progress audio "$current" "$total"
done
printf 'Converted %s incompatible WAV file(s) to PCM.\n' "$total"
