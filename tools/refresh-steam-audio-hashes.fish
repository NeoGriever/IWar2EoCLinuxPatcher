#!/usr/bin/env fish

set -l APP_ID 359630

function die
    printf 'ERROR: %s\n' "$argv" >&2
    exit 1
end

function detect_game --argument-names app_id
    set -l steam_roots \
        "$HOME/.local/share/Steam" \
        "$HOME/.steam/steam" \
        "$HOME/.steam/root" \
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"

    for steam_root in $steam_roots
        test -d "$steam_root"; or continue

        set -l libraries "$steam_root"
        set -l library_file "$steam_root/steamapps/libraryfolders.vdf"

        if test -f "$library_file"
            for library in (sed -nE \
                's/^[[:space:]]*"path"[[:space:]]*"([^"]*)".*$/\1/p' \
                "$library_file")
                set -a libraries "$library"
            end
        end

        for library in $libraries
            set -l steam_manifest \
                "$library/steamapps/appmanifest_$app_id.acf"

            test -f "$steam_manifest"; or continue

            set -l install_dir (sed -nE \
                's/^[[:space:]]*"installdir"[[:space:]]*"([^"]*)".*$/\1/p' \
                "$steam_manifest" | head -n 1)

            test -n "$install_dir"; or continue

            set -l candidate \
                "$library/steamapps/common/$install_dir"

            if test -f "$candidate/EdgeOfChaos.exe"; and \
               test -f "$candidate/resource.zip"

                realpath "$candidate"
                return 0
            end
        end
    end

    return 1
end


# ------------------------------------------------------------
# Locate repository
# ------------------------------------------------------------

set -l script_file (status --current-filename)
set -l script_dir (dirname (realpath "$script_file"))
set -l repo_dir (realpath "$script_dir/..")
set -l manifest "$repo_dir/patch-manifest.txt"

test -f "$manifest"; or \
    die "patch-manifest.txt not found in $repo_dir"


# ------------------------------------------------------------
# Locate game
# ------------------------------------------------------------

if test (count $argv) -gt 1
    die "Usage: "(basename "$script_file")" [IW2_GAME_DIR]"
end

set -l game_dir

if test (count $argv) -eq 1
    test -d "$argv[1]"; or \
        die "Game directory does not exist: $argv[1]"

    set game_dir (realpath "$argv[1]")
else
    printf 'Searching Steam installation...\n'

    set game_dir (detect_game "$APP_ID")

    test -n "$game_dir"; or \
        die "Could not find Steam App $APP_ID."
end

test -f "$game_dir/EdgeOfChaos.exe"; or \
    die "EdgeOfChaos.exe missing in $game_dir"

test -f "$game_dir/resource.zip"; or \
    die "resource.zip missing in $game_dir"


printf '\n'
printf 'Repository : %s\n' "$repo_dir"
printf 'Manifest   : %s\n' "$manifest"
printf 'Steam game : %s\n' "$game_dir"
printf '\n'

printf 'Scanning manifest WAV entries...\n\n'


# ------------------------------------------------------------
# Build corrected manifest
# ------------------------------------------------------------

set -l temporary (mktemp)
test -n "$temporary"; or die "Could not create temporary file."

set -l checked 0
set -l changed 0
set -l unchanged 0
set -l missing 0

while read -l line

    # Preserve comments and empty lines
    if test -z "$line"
        printf '\n' >> "$temporary"
        continue
    end

    if string match -q '#*' -- "$line"
        printf '%s\n' "$line" >> "$temporary"
        continue
    end

    set -l fields (string split '|' -- "$line")

    if test (count $fields) -ne 3
        printf 'Invalid manifest line:\n%s\n' "$line" >&2
        rm -f -- "$temporary"
        exit 2
    end

    set -l relative "$fields[1]"
    set -l english_hash "$fields[2]"
    set -l german_hash "$fields[3]"

    # Only original Steam WAV files are refreshed.
    if not string match -q -r -i '^streams/.*\.wav$' -- "$relative"
        printf '%s\n' "$line" >> "$temporary"
        continue
    end

    # "-" means this file does not exist in the English Steam version.
    if test "$english_hash" = '-'
        printf '%s\n' "$line" >> "$temporary"
        continue
    end

    set checked (math "$checked + 1")

    set -l source_file "$game_dir/$relative"

    if not test -f "$source_file"
        printf 'MISSING: %s\n' "$relative" >&2
        set missing (math "$missing + 1")

        printf '%s\n' "$line" >> "$temporary"
        continue
    end

    set -l new_hash (sha256sum -- "$source_file" | awk '{print $1}')

    if test "$new_hash" != "$english_hash"
        printf 'CHANGE: %s\n' "$relative"
        printf '  old: %s\n' "$english_hash"
        printf '  new: %s\n\n' "$new_hash"

        set changed (math "$changed + 1")
    else
        set unchanged (math "$unchanged + 1")
    end

    printf '%s|%s|%s\n' \
        "$relative" \
        "$new_hash" \
        "$german_hash" >> "$temporary"

end < "$manifest"


# ------------------------------------------------------------
# Result
# ------------------------------------------------------------

printf '\n'
printf 'Checked WAV entries : %d\n' "$checked"
printf 'Changed hashes      : %d\n' "$changed"
printf 'Already correct     : %d\n' "$unchanged"
printf 'Missing Steam files : %d\n' "$missing"
printf '\n'

if test "$missing" -gt 0
    rm -f -- "$temporary"

    printf 'Manifest was NOT changed because Steam files are missing.\n' >&2
    exit 2
end

if test "$changed" -eq 0
    rm -f -- "$temporary"

    printf 'Nothing to update. All Steam WAV hashes already match.\n'
    exit 0
end


# ------------------------------------------------------------
# Confirmation
# ------------------------------------------------------------

read -l -P "Update these $changed English SHA-256 hashes? [y/N] " answer

switch (string lower -- "$answer")
    case y yes j ja
        # continue
    case '*'
        rm -f -- "$temporary"
        printf 'Cancelled. Manifest was not changed.\n'
        exit 0
end


# ------------------------------------------------------------
# Backup + write
# ------------------------------------------------------------

set -l timestamp (date +%Y%m%d-%H%M%S)
set -l backup "$manifest.backup-$timestamp"

cp -a -- "$manifest" "$backup"; or begin
    rm -f -- "$temporary"
    die "Could not create manifest backup."
end

chmod --reference="$manifest" "$temporary"; or begin
    rm -f -- "$temporary"
    die "Could not preserve manifest permissions."
end

mv -f -- "$temporary" "$manifest"; or \
    die "Could not replace patch-manifest.txt."


printf '\n'
printf 'Manifest updated successfully.\n'
printf 'Backup: %s\n' "$backup"
printf '\n'


# ------------------------------------------------------------
# Verify the complete pristine Steam installation
# ------------------------------------------------------------

set -l verifier "$repo_dir/apply-german-patch.sh"

if test -x "$verifier"; and command -q 7z

    printf 'Running complete Steam checksum verification...\n\n'

    set -l status_log (mktemp)

    if "$verifier" --status "$game_dir" > "$status_log" 2>&1
        tail -n 1 "$status_log"
    else
        printf 'The installation still contains unrecognized files:\n\n'

        grep -E 'UNKNOWN|Result:' "$status_log" | head -n 40

        printf '\n'
        printf 'This means additional non-audio hashes may also need correction.\n'
    end

    rm -f -- "$status_log"
else
    printf 'Skipped complete verification because apply-german-patch.sh or 7z is unavailable.\n'
end
