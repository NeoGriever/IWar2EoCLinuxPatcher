#!/usr/bin/env bash
# Builds and runs the small native TSC-rate checker used for the CPU speed fix.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE="$PATCH_DIR/tools/iwar2-tsc-check.cpp"
CACHE_ROOT="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/independence-war-2-ultimate-patcher/tools"
BINARY="$CACHE_ROOT/iwar2-tsc-check"

[[ -f "$SOURCE" ]] || { printf 'CPU timing-counter source is missing: %s\n' "$SOURCE" >&2; exit 66; }

if [[ ! -x "$BINARY" || "$SOURCE" -nt "$BINARY" ]]; then
    command -v g++ >/dev/null || { printf 'g++ is required to build the native CPU timing-counter check.\n' >&2; exit 69; }
    mkdir -p -- "$CACHE_ROOT"
    temporary="${BINARY}.tmp.$$"
    trap 'rm -f -- "$temporary"' EXIT
    g++ -O2 -std=c++17 -Wall -Wextra -Werror "$SOURCE" -o "$temporary"
    chmod 0755 -- "$temporary"
    mv -f -- "$temporary" "$BINARY"
    trap - EXIT
fi

exec "$BINARY" "$@"
