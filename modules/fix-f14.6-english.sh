#!/usr/bin/env bash
# Restores English F14.6 resources without touching F14.6 binaries or data.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RESIDUE_MANIFEST="$PATCH_DIR/audits/f14.6-language-residue.txt"
ARCHIVE_MANIFEST="$PATCH_DIR/audits/f14.6-english-archive.txt"
EXTRAS_DIR="$PATCH_DIR/payloads/f14.6-english-extras"
EXTRAS_MANIFEST="$PATCH_DIR/audits/f14.6-english-extras.txt"
PROGRESS_FILE="${GERPATCH_PROGRESS_FILE:-}"

progress() {
    [[ -n "$PROGRESS_FILE" ]] || return 0
    local temporary="${PROGRESS_FILE}.tmp.$$"
    printf '%s|%s|%s\n' "$1" "$2" "$3" > "$temporary"
    mv -f -- "$temporary" "$PROGRESS_FILE"
}

sha256() { sha256sum -- "$1" | awk '{print $1}'; }
usage() { printf 'Usage: %s <IW2 installation directory>\n' "$(basename -- "$0")" >&2; exit 64; }

[[ $# -eq 1 ]] || usage
TARGET_DIR="$(cd -- "$1" && pwd -P)"
RESOURCE_ZIP="$TARGET_DIR/resource.zip"
[[ -f "$RESOURCE_ZIP" && -f "$TARGET_DIR/EdgeOfChaos.exe" ]] || {
    printf 'Not an Independence War 2 installation: %s\n' "$TARGET_DIR" >&2
    exit 66
}
[[ -f "$RESIDUE_MANIFEST" && -f "$ARCHIVE_MANIFEST" && -f "$EXTRAS_MANIFEST" && -d "$EXTRAS_DIR" ]] || {
    printf 'The F14.6 English-fix payload is incomplete.\n' >&2
    exit 66
}
command -v 7z >/dev/null || { printf '7z is required for the reversible backup.\n' >&2; exit 69; }
command -v unzip >/dev/null || { printf 'unzip is required for the English resource sources.\n' >&2; exit 69; }

declare -a residue_paths=()
declare -a archive_paths=()
declare -a extra_paths=()
while IFS='|' read -r relative expected_hash; do
    [[ -n "$relative" && -n "$expected_hash" ]] || continue
    target="$TARGET_DIR/$relative"
    [[ -f "$target" && "$(sha256 "$target")" == "$expected_hash" ]] || {
        printf 'Expected unmodified F14.6 language file is missing or changed: %s\n' "$relative" >&2
        exit 2
    }
    residue_paths+=("$relative")
done < "$RESIDUE_MANIFEST"

while IFS='|' read -r relative expected_hash; do
    [[ -n "$relative" && -n "$expected_hash" ]] || continue
    member="${relative#resource/}"
    actual_hash="$(unzip -p "$RESOURCE_ZIP" "$member" | sha256sum | awk '{print $1}')"
    [[ "$actual_hash" == "$expected_hash" ]] || {
        printf 'English Steam resource is not the expected source: %s\n' "$member" >&2
        exit 2
    }
    archive_paths+=("$relative|$expected_hash")
done < "$ARCHIVE_MANIFEST"

while IFS='|' read -r relative expected_hash; do
    [[ -n "$relative" && -n "$expected_hash" ]] || continue
    source="$EXTRAS_DIR/$relative"
    [[ -f "$source" && "$(sha256 "$source")" == "$expected_hash" ]] || {
        printf 'English F14.6 extra is missing or changed: %s\n' "$relative" >&2
        exit 65
    }
    extra_paths+=("$relative|$expected_hash")
done < "$EXTRAS_MANIFEST"

(( ${#residue_paths[@]} == 275 && ${#archive_paths[@]} == 243 && ${#extra_paths[@]} == 4 )) || {
    printf 'Unexpected F14.6 English-fix manifest size.\n' >&2
    exit 65
}

backup_dir="${GERPATCH_BACKUP_DIR:-$PATCH_DIR/backups}"
mkdir -p -- "$backup_dir"
backup="$backup_dir/IW2EOC-before-F14.6-english-fix-$(date +%Y%m%d-%H%M%S).zip"
list_file="$(mktemp)"
trap 'rm -f -- "$list_file"' EXIT
printf '%s\n' "${residue_paths[@]}" > "$list_file"
progress backup 0 100
( cd "$TARGET_DIR" && 7z a -tzip -mx=1 -bd "$backup" @"$list_file" )
7z t -bd "$backup" >/dev/null

total=$(( ${#residue_paths[@]} + ${#archive_paths[@]} + ${#extra_paths[@]} ))
current=0
progress english "$current" "$total"
for relative in "${residue_paths[@]}"; do
    rm -f -- "$TARGET_DIR/$relative"
    ((current += 1))
    progress english "$current" "$total"
done

for entry in "${archive_paths[@]}"; do
    relative="${entry%%|*}"
    expected_hash="${entry#*|}"
    member="${relative#resource/}"
    destination="$TARGET_DIR/$relative"
    mkdir -p -- "$(dirname -- "$destination")"
    temporary="${destination}.tmp.$$"
    unzip -p "$RESOURCE_ZIP" "$member" > "$temporary"
    [[ "$(sha256 "$temporary")" == "$expected_hash" ]] || {
        rm -f -- "$temporary"
        printf 'Failed to extract expected English resource: %s\n' "$member" >&2
        exit 65
    }
    mv -f -- "$temporary" "$destination"
    ((current += 1))
    progress english "$current" "$total"
done

for entry in "${extra_paths[@]}"; do
    relative="${entry%%|*}"
    expected_hash="${entry#*|}"
    source="$EXTRAS_DIR/$relative"
    destination="$TARGET_DIR/resource/$relative"
    mkdir -p -- "$(dirname -- "$destination")"
    cp -af -- "$source" "$destination"
    [[ "$(sha256 "$destination")" == "$expected_hash" ]] || {
        printf 'Failed to install verified English F14.6 extra: %s\n' "$relative" >&2
        exit 65
    }
    ((current += 1))
    progress english "$current" "$total"
done

printf 'F14.6 English resources restored and verified. Backup: %s\n' "$backup"
