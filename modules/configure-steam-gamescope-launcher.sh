#!/usr/bin/env bash
# Sets the Gamescope diagnostic wrapper as the Steam launch option for IW2.
set -Eeuo pipefail

PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP_ID="${IW2_STEAM_APP_ID:-359630}"
STEAM_ROOT="${IW2_STEAM_ROOT:-$HOME/.local/share/Steam}"
RUNTIME_DIR=''
SOURCE_WRAPPER="$PATCH_DIR/tools/iwar2-gamescope-diagnostic.sh"
INSTALLED_WRAPPER=''
SOURCE_DISPLAY_CONFIG="$PATCH_DIR/runtime/display.conf"
DISPLAY_CONFIG=''
PROGRESS_FILE="${GERPATCH_PROGRESS_FILE:-}"
NOTICE_FILE="${GERPATCH_NOTICE_FILE:-}"

progress() {
    [[ -n "$PROGRESS_FILE" ]] || return 0
    local temporary="${PROGRESS_FILE}.tmp.$$"
    printf '%s|%s|%s\n' "$1" "$2" "$3" > "$temporary"
    mv -f -- "$temporary" "$PROGRESS_FILE"
}

request_user_notice() {
    [[ -n "$NOTICE_FILE" ]] || return 0
    printf '%s\n' 'steam-launch-options' > "$NOTICE_FILE"
}

vdf_value() {
    local file="$1" key="$2"
    sed -nE "s/^[[:space:]]*\\\"${key}\\\"[[:space:]]*\\\"([^\\\"]*)\\\".*$/\\1/p" "$file" | head -n 1
}

registered_steam_target() {
    local game_dir="$1" common_dir steamapps_dir library manifest install_dir candidate canonical

    common_dir="$(dirname -- "$game_dir")"
    steamapps_dir="$(dirname -- "$common_dir")"
    [[ "$(basename -- "$common_dir")" == common && "$(basename -- "$steamapps_dir")" == steamapps ]] || return 1

    library="$(dirname -- "$steamapps_dir")"
    manifest="$library/steamapps/appmanifest_${APP_ID}.acf"
    [[ -f "$manifest" ]] || return 1

    install_dir="$(vdf_value "$manifest" installdir)"
    [[ -n "$install_dir" ]] || return 1

    candidate="$library/steamapps/common/$install_dir"
    canonical="$(cd -- "$candidate" 2>/dev/null && pwd -P)" || return 1
    [[ "$canonical" == "$game_dir" ]]
}

[[ $# -eq 1 ]] || {
    printf 'Usage: %s <IW2 installation directory>\n' "$(basename -- "$0")" >&2
    exit 64
}
TARGET_DIR="$(cd -- "$1" 2>/dev/null && pwd -P)" || {
    printf 'The selected IW2 directory does not exist.\n' >&2
    exit 66
}
[[ -f "$TARGET_DIR/flux.ini" ]] || {
    printf 'The selected IW2 directory does not contain flux.ini: %s\n' "$TARGET_DIR" >&2
    exit 66
}
registered_steam_target "$TARGET_DIR" || {
    printf 'Refusing to change Steam launch options: the selected target is not the registered Steam App %s installation.\n' "$APP_ID" >&2
    exit 66
}

RUNTIME_DIR="$TARGET_DIR/.iwar2-linux-patcher"
INSTALLED_WRAPPER="$RUNTIME_DIR/tools/iwar2-gamescope-diagnostic.sh"
DISPLAY_CONFIG="$RUNTIME_DIR/runtime/display.conf"

[[ -x "$SOURCE_WRAPPER" ]] || { printf 'Gamescope wrapper is missing: %s\n' "$SOURCE_WRAPPER" >&2; exit 66; }
[[ -f "$SOURCE_DISPLAY_CONFIG" ]] || { printf 'Gamescope display template is missing: %s\n' "$SOURCE_DISPLAY_CONFIG" >&2; exit 66; }

install_runtime() {
    local temporary
    mkdir -p -- "$RUNTIME_DIR/tools" "$RUNTIME_DIR/runtime"
    [[ -f "$DISPLAY_CONFIG" ]] || cp -a -- "$SOURCE_DISPLAY_CONFIG" "$DISPLAY_CONFIG"
    temporary="${INSTALLED_WRAPPER}.tmp.$$"
    cp -a -- "$SOURCE_WRAPPER" "$temporary"
    chmod 0755 -- "$temporary"
    mv -f -- "$temporary" "$INSTALLED_WRAPPER"
    cmp -s -- "$SOURCE_WRAPPER" "$INSTALLED_WRAPPER" || {
        printf 'Failed to install Gamescope wrapper: %s\n' "$INSTALLED_WRAPPER" >&2
        exit 65
    }
}

steam_is_running() {
    local pid_file pid process_name process_state

    # The main client writes this PID file on native Linux installations.  A
    # live PID is the most direct check and avoids relying on one particular
    # launcher process name.
    for pid_file in "$HOME/.steam/steam.pid" "$STEAM_ROOT/steam.pid"; do
        [[ -r "$pid_file" ]] || continue
        read -r pid < "$pid_file" || continue
        [[ "$pid" =~ ^[1-9][0-9]*$ && -d "/proc/$pid" ]] || continue
        process_state="$(ps -p "$pid" -o stat= 2>/dev/null || true)"
        [[ -n "$process_state" && "$process_state" != Z* ]] && return 0
    done

    # Depending on the package and client version, Steam's long-lived client
    # is visible either as steam, steamwebhelper, or the runtime launcher.
    # Ignore zombies: they cannot keep localconfig.vdf in memory.
    while read -r process_name process_state; do
        case "$process_name" in
            steam|steamwebhelper|steam-runtime-launcher-service)
                [[ "$process_state" != Z* ]] && return 0
                ;;
        esac
    done < <(ps -u "$(id -u)" -o comm= -o stat=)

    return 1
}

progress steam-launcher 0 1
install_runtime

# Steam retains localconfig.vdf in memory and otherwise overwrites a direct
# edit on shutdown. Give the user the exact safe manual alternative instead.
if steam_is_running; then
    progress steam-launcher 1 1
    request_user_notice
    printf 'Steam is running, so its local configuration was left unchanged.\n\n'
    printf 'In Steam: Library → Independence War 2 → Properties → General → Launch Options\n'
    printf 'Copy this exact line into the Launch Options field:\n\n'
    printf '%s %%command%%\n\n' "$INSTALLED_WRAPPER"
    printf 'Then start the game normally from Steam.\n'
    exit 0
fi

shopt -s nullglob
configs=("$STEAM_ROOT"/userdata/*/config/localconfig.vdf)
(( ${#configs[@]} > 0 )) || { printf 'No Steam localconfig.vdf was found.\n' >&2; exit 66; }

backup_dir="$PATCH_DIR/backups/steam-launch-options-$(date +%Y%m%d-%H%M%S)"
mkdir -p -- "$backup_dir"
progress steam-launcher 0 "${#configs[@]}"
updated=0
for config in "${configs[@]}"; do
    grep -Fq "\"$APP_ID\"" "$config" || continue
    cp -a -- "$config" "$backup_dir/$(basename "$(dirname "$(dirname "$config")")")-localconfig.vdf"
    IW2_APP_ID="$APP_ID" IW2_LAUNCH_OPTION="$INSTALLED_WRAPPER %command%" perl -0pi -e '
        my $app_id = $ENV{IW2_APP_ID};
        my $value = $ENV{IW2_LAUNCH_OPTION};
        my $escaped_value = $value;
        $escaped_value =~ s/([\\"])/\\$1/g;
        my $anchor = index($_, qq{"$app_id"});
        die "Steam app block not found for $app_id\\n" if $anchor < 0;
        my $open = index($_, "{", $anchor);
        die "Steam app block is malformed for $app_id\\n" if $open < 0;
        my $depth = 0;
        my $close = -1;
        for my $index ($open .. length($_) - 1) {
            my $char = substr($_, $index, 1);
            ++$depth if $char eq "{";
            --$depth if $char eq "}";
            if ($depth == 0) { $close = $index; last; }
        }
        die "Steam app block is unclosed for $app_id\\n" if $close < 0;
        my $block = substr($_, $anchor, $close - $anchor + 1);
        if ($block =~ /"LaunchOptions"/) {
            $block =~ s{("LaunchOptions"[ \t]*)"(?:\\.|[^"\\])*"}{$1"$escaped_value"};
        } else {
            my $insert_at = rindex($block, "}");
            die "Steam app block has no closing brace for $app_id\\n" if $insert_at < 0;
            substr($block, $insert_at, 0) = "\n\t\t\t\t\t\t\"LaunchOptions\"\t\t\"$escaped_value\"\n";
        }
        substr($_, $anchor, $close - $anchor + 1, $block);
    ' "$config"
    actual="$(IW2_APP_ID="$APP_ID" perl -0ne '
        my $app_id = $ENV{IW2_APP_ID};
        my $anchor = index($_, qq{"$app_id"});
        exit if $anchor < 0;
        my $open = index($_, "{", $anchor);
        my $depth = 0;
        my $close = -1;
        for my $index ($open .. length($_) - 1) {
            my $char = substr($_, $index, 1);
            ++$depth if $char eq "{"; --$depth if $char eq "}";
            if ($depth == 0) { $close = $index; last; }
        }
        my $block = substr($_, $anchor, $close - $anchor + 1);
        print $1 if $block =~ /"LaunchOptions"[ \t]*"((?:\\.|[^"\\])*)"/;
    ' "$config")"
    [[ "$actual" == "$INSTALLED_WRAPPER %command%" ]] || { printf 'Failed to verify Steam launch option in %s\n' "$config" >&2; exit 65; }
    updated=$((updated + 1))
    progress steam-launcher "$updated" "${#configs[@]}"
done

(( updated > 0 )) || { printf 'No local Steam account contains App %s yet. Start Steam once after installing the game, then rerun this selected task.\n' "$APP_ID" >&2; exit 66; }
progress steam-launcher "$updated" "$updated"
printf 'Gamescope runtime installed at %s and set as the Steam launch option for %s account configuration(s). Backup: %s\n' \
    "$RUNTIME_DIR" "$updated" "$backup_dir"
