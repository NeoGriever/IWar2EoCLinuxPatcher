#!/usr/bin/env bash
# Installs the complete I-War 2 No-CD fix.
# Supports both official F14.6 and the Steam DUCK variant.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROGRESS_FILE="${GERPATCH_PROGRESS_FILE:-}"

# Official F14.6 igame.dll.
F14_HASH="f02b4d199471524db0b6cd6ffc82a76555c33fee5bb24b7a8fd61e4984f542bb"

# Clean Steam installation: historical DUCK No-CD change is already present.
STEAM_DUCK_HASH="182c3ce478ddb8747fd4beb7bede8d7a58bc7f2f4867153a97cd4ae6cd8074ec"

# Zero-based file offsets.
STONE_OFFSET=9301
DUCK_OFFSET=9347

STONE_ORIGINAL="45"
STONE_PATCHED="3c"
DUCK_ORIGINAL="75"
DUCK_PATCHED="eb"

progress() {
    [[ -n "$PROGRESS_FILE" ]] || return 0
    local temporary="${PROGRESS_FILE}.tmp.$$"
    printf "%s|%s|%s\n" "$1" "$2" "$3" > "$temporary"
    mv -f -- "$temporary" "$PROGRESS_FILE"
}

sha256() {
    sha256sum -- "$1" | cut -d " " -f 1
}

byte_at() {
    local file="$1"
    local offset="$2"
    od -An -v -t x1 -j "$offset" -N 1 -- "$file" | tr -d "[:space:]"
}

write_byte() {
    local file="$1"
    local offset="$2"
    local value="$3"
    printf "\x${value}" | dd of="$file" bs=1 seek="$offset" conv=notrunc status=none
}

[[ $# -eq 1 ]] || {
    printf "Usage: %s <IW2 installation directory>\n" "$(basename -- "$0")" >&2
    exit 64
}

TARGET_DIR="$(cd -- "$1" && pwd -P)"
DLL="$TARGET_DIR/bin/release/igame.dll"

[[ -f "$DLL" ]] || {
    printf "Missing igame.dll: %s\n" "$DLL" >&2
    exit 66
}

current_hash="$(sha256 "$DLL")"
stone_byte="$(byte_at "$DLL" "$STONE_OFFSET")"
duck_byte="$(byte_at "$DLL" "$DUCK_OFFSET")"

# Recognize an already completed patch without needing a hard-coded result hash.
if [[ "$stone_byte" == "$STONE_PATCHED" && "$duck_byte" == "$DUCK_PATCHED" ]]; then
    verify_tmp="$(mktemp)"
    cp -a -- "$DLL" "$verify_tmp"

    # Test whether this is Steam DUCK + Stone-D.
    write_byte "$verify_tmp" "$STONE_OFFSET" "$STONE_ORIGINAL"

    if [[ "$(sha256 "$verify_tmp")" == "$STEAM_DUCK_HASH" ]]; then
        rm -f -- "$verify_tmp"
        printf "The complete No-CD fix is already active (Steam DUCK + Stone-D).\n"
        progress nocd 1 1
        exit 0
    fi

    # Test whether this is official F14.6 + both No-CD modifications.
    write_byte "$verify_tmp" "$DUCK_OFFSET" "$DUCK_ORIGINAL"

    if [[ "$(sha256 "$verify_tmp")" == "$F14_HASH" ]]; then
        rm -f -- "$verify_tmp"
        printf "The complete No-CD fix is already active (F14.6 + DUCK + Stone-D).\n"
        progress nocd 1 1
        exit 0
    fi

    rm -f -- "$verify_tmp"
fi

mode=""
expected_source_hash=""

if [[ "$current_hash" == "$STEAM_DUCK_HASH" ]]; then
    [[ "$stone_byte" == "$STONE_ORIGINAL" && "$duck_byte" == "$DUCK_PATCHED" ]] || {
        printf "Known Steam DUCK DLL has unexpected patch bytes.\n" >&2
        exit 2
    }

    mode="steam-duck"
    expected_source_hash="$STEAM_DUCK_HASH"

elif [[ "$current_hash" == "$F14_HASH" ]]; then
    [[ "$stone_byte" == "$STONE_ORIGINAL" && "$duck_byte" == "$DUCK_ORIGINAL" ]] || {
        printf "Known F14.6 DLL has unexpected patch bytes.\n" >&2
        exit 2
    }

    mode="f14"
    expected_source_hash="$F14_HASH"

else
    printf "igame.dll is not a recognized F14.6 or Steam DUCK variant.\n" >&2
    printf "SHA-256: %s\n" "$current_hash" >&2
    printf "Stone-D byte at %s: %s\n" "$STONE_OFFSET" "$stone_byte" >&2
    printf "DUCK byte at %s: %s\n" "$DUCK_OFFSET" "$duck_byte" >&2
    printf "Refusing to patch an unknown binary.\n" >&2
    exit 2
fi

backup_dir="${GERPATCH_BACKUP_DIR:-$PATCH_DIR/backups}"
mkdir -p -- "$backup_dir"
backup="$backup_dir/igame.dll-before-nocd-$(date +%Y%m%d-%H%M%S)"
cp -a -- "$DLL" "$backup"

progress nocd 0 2

if [[ "$mode" == "steam-duck" ]]; then
    # Steam already contains the DUCK modification.
    # Only the Stone-D modification is required.
    write_byte "$DLL" "$STONE_OFFSET" "$STONE_PATCHED"
else
    # Official F14.6 needs both modifications.
    write_byte "$DLL" "$DUCK_OFFSET" "$DUCK_PATCHED"
    write_byte "$DLL" "$STONE_OFFSET" "$STONE_PATCHED"
fi

progress nocd 1 2

if [[ "$(byte_at "$DLL" "$STONE_OFFSET")" != "$STONE_PATCHED" ]]; then
    cp -af -- "$backup" "$DLL"
    printf "Stone-D byte verification failed; original DLL restored.\n" >&2
    exit 65
fi

if [[ "$(byte_at "$DLL" "$DUCK_OFFSET")" != "$DUCK_PATCHED" ]]; then
    cp -af -- "$backup" "$DLL"
    printf "DUCK byte verification failed; original DLL restored.\n" >&2
    exit 65
fi

# Reconstruct the exact known source in a temporary file.
# This proves that no unrelated byte was modified.
verify_tmp="$(mktemp)"
cp -a -- "$DLL" "$verify_tmp"

write_byte "$verify_tmp" "$STONE_OFFSET" "$STONE_ORIGINAL"

if [[ "$mode" == "f14" ]]; then
    write_byte "$verify_tmp" "$DUCK_OFFSET" "$DUCK_ORIGINAL"
fi

if [[ "$(sha256 "$verify_tmp")" != "$expected_source_hash" ]]; then
    rm -f -- "$verify_tmp"
    cp -af -- "$backup" "$DLL"
    printf "No-CD verification failed; original DLL restored.\n" >&2
    exit 65
fi

rm -f -- "$verify_tmp"
progress nocd 2 2

if [[ "$mode" == "steam-duck" ]]; then
    printf "Stone-D No-CD fix installed on the Steam DUCK igame.dll.\n"
else
    printf "DUCK + Stone-D No-CD fixes installed on the official F14.6 igame.dll.\n"
fi

printf "Backup: %s\n" "$backup"
