#!/usr/bin/env bash
# Configures a fixed 16:9 inner Flux display and optional outer fullscreen.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUNTIME_DIR="${IW2_RUNTIME_DIR:-$HOME/.local/share/independence-war-2-ultimate-patcher}"
DISPLAY_CONFIG="$RUNTIME_DIR/runtime/display.conf"
PROGRESS_FILE="${GERPATCH_PROGRESS_FILE:-}"

progress() {
    [[ -n "$PROGRESS_FILE" ]] || return 0
    local temporary="${PROGRESS_FILE}.tmp.$$"
    printf '%s|%s|%s\n' "$1" "$2" "$3" > "$temporary"
    mv -f -- "$temporary" "$PROGRESS_FILE"
}

# Flux keeps its active graphics settings in [FcGame].  Do not use a global
# replacement here: similarly named keys may be added to other sections by
# future game versions or tools.
read_fcg_value() {
    local key="$1"
    FCG_KEY="$key" perl -0ne '
        my $key = quotemeta $ENV{FCG_KEY};
        if (/\[FcGame\][^\[]*?^[ \t]*$key[ \t]*=[ \t]*([^\r\n]*)/ms) {
            my $value = $1;
            $value =~ s/[ \t]+$//;
            print $value;
        }
    ' "$FLUX_INI"
}

set_fcg_value() {
    local key="$1"
    local value="$2"
    FCG_KEY="$key" FCG_VALUE="$value" perl -0pi -e '
        my $key = quotemeta $ENV{FCG_KEY};
        my $value = $ENV{FCG_VALUE};
        my $changed = s{
            (\[FcGame\][^\[]*?^[ \t]*$key[ \t]*=)[^\r\n]*
        }{$1 . q{ } . $value}emsx;
        die "Missing [FcGame] setting: $ENV{FCG_KEY}\\n" unless $changed;
    ' "$FLUX_INI"
}

verify_fcg_value() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(read_fcg_value "$key")"
    [[ "$actual" == "$expected" ]] || {
        printf 'flux.ini verification failed: [FcGame] %s is %q, expected %q.\n' \
            "$key" "$actual" "$expected" >&2
        exit 70
    }
}

usage() {
    printf 'Usage: %s <IW2 installation directory> <keep|720p|1080p|1440p|4k> <0|1> [auto|wayland|sdl] [0|1]\n' "$(basename -- "$0")" >&2
    exit 64
}

[[ $# -ge 3 && $# -le 5 ]] || usage
TARGET_DIR="$(cd -- "$1" && pwd -P)"
RESOLUTION="$2"
OUTER_FULLSCREEN="$3"
GAMESCOPE_BACKEND="${4:-auto}"
USE_MOUSE_SENSITIVITY="${5:-1}"
FLUX_INI="$TARGET_DIR/flux.ini"
[[ -f "$FLUX_INI" ]] || { printf 'Missing flux.ini.\n' >&2; exit 66; }
case "$RESOLUTION" in
    keep)
        width="$(sed -nE 's/^\s*width\s*=\s*([1-9][0-9]*).*/\1/p' "$FLUX_INI" | head -n 1)"
        height="$(sed -nE 's/^\s*height\s*=\s*([1-9][0-9]*).*/\1/p' "$FLUX_INI" | head -n 1)"
        [[ "$width" =~ ^[1-9][0-9]*$ && "$height" =~ ^[1-9][0-9]*$ ]] || {
            printf 'Could not preserve the current Flux resolution.\n' >&2
            exit 65
        }
        ;;
    720p) width=1280; height=720 ;;
    1080p) width=1920; height=1080 ;;
    1440p) width=2560; height=1440 ;;
    4k) width=3840; height=2160 ;;
    *) usage ;;
esac
[[ "$OUTER_FULLSCREEN" == 0 || "$OUTER_FULLSCREEN" == 1 ]] || usage
case "$GAMESCOPE_BACKEND" in auto|wayland|sdl) ;; *) usage ;; esac
[[ "$USE_MOUSE_SENSITIVITY" == 0 || "$USE_MOUSE_SENSITIVITY" == 1 ]] || usage
mouse_sensitivity=disabled
(( USE_MOUSE_SENSITIVITY )) && mouse_sensitivity=0.045

backup_dir="$PATCH_DIR/backups/config-$(date +%Y%m%d-%H%M%S)"
mkdir -p -- "$backup_dir"
cp -a -- "$FLUX_INI" "$backup_dir/flux.ini"
[[ -f "$DISPLAY_CONFIG" ]] && cp -a -- "$DISPLAY_CONFIG" "$backup_dir/display.conf"
progress display 0 3
if [[ "$RESOLUTION" != keep ]]; then
    # The selected mode is explicit: Flux receives the exact inner dimensions
    # and stays fullscreen only inside the Gamescope window.
    set_fcg_value full_screen 1
    set_fcg_value width "$width"
    set_fcg_value height "$height"
fi
verify_fcg_value width "$width"
verify_fcg_value height "$height"
[[ "$RESOLUTION" == keep ]] || verify_fcg_value full_screen 1
progress display 1 3
temporary="${DISPLAY_CONFIG}.tmp.$$"
mkdir -p -- "$(dirname -- "$DISPLAY_CONFIG")"
{
    printf 'game_dir=%s\n' "$TARGET_DIR"
    printf 'width=%s\n' "$width"
    printf 'height=%s\n' "$height"
    printf 'outer_fullscreen=%s\n' "$OUTER_FULLSCREEN"
    printf 'mouse_sensitivity=%s\n' "$mouse_sensitivity"
    printf 'backend=%s\n' "$GAMESCOPE_BACKEND"
} > "$temporary"
mv -f -- "$temporary" "$DISPLAY_CONFIG"
progress display 2 3
bash -n "$PATCH_DIR/tools/iwar2-gamescope-diagnostic.sh"
progress display 3 3
if [[ "$RESOLUTION" == keep ]]; then
    printf 'Preserved the current inner resolution. Runtime: %s. Gamescope backend: %s. Slow mouse: %s. Outer fullscreen: %s. Backup: %s\n' \
        "$RUNTIME_DIR" "$GAMESCOPE_BACKEND" "$mouse_sensitivity" "$OUTER_FULLSCREEN" "$backup_dir"
else
    printf 'Configured %s explicitly as %sx%s in [FcGame]. Runtime: %s. Gamescope backend: %s. Slow mouse: %s. Outer fullscreen: %s. Backup: %s\n' \
        "$RESOLUTION" "$width" "$height" "$RUNTIME_DIR" "$GAMESCOPE_BACKEND" "$mouse_sensitivity" "$OUTER_FULLSCREEN" "$backup_dir"
fi
