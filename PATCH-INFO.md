# Independence War 2: Edge of Chaos — Ultimate Patcher

This package can add the original German CD localization, Linux audio conversion, No-CD, the CPU Speed Fix, mouse controls, selectable 4:3/16:9 video variants, and the tested Gamescope window configuration to the verified English Steam release. It does not contain or modify save games. The Steam release already includes F14.6, so the incompatible historical standalone patch is neither offered nor installed.

The German `resource.zip` was created from the current Steam archive: all 33 Steam-specific files are retained, while 564 localized and 15 CD-exclusive files are supplied from the German CD release. The downloaded data set also includes the seven Steam overrides under `resource/` and 2,557 German PCM dialogue files. The three language-specific German intro, mid-game, and ending movies are downloaded from the verified external video set.

## Interactive use

Run the patcher from this directory:

```bash
./ultimate-patcher.sh
```

Use the arrow keys or `W`/`S` to move the selection. Use `A`/`D`, `Enter`, or `Space` to change an option. `Esc` closes the patcher. Symbols and colors have fixed meanings:

- yellow `□`: available, not selected
- green `▣`: available, selected
- gray `▤`: unavailable because of a dependency
- light-gray `▩`: selected, but currently locked by a dependency

During execution, selected tasks show `▹` while waiting, an animated Braille spinner while running, and `✓` when complete. The progress bar uses eighth-block characters for finer progress. The menu and progress view are fully buffered and emitted as synchronized terminal frames so intermediate redraw states are not visible.

The following dependencies are intentional:

- **Install german Game-data** disables **Convert Audio-Files to work under Linux**, because the German data already contains PCM dialogue.
- With **16:9** enabled, exactly one of the four resolutions can be selected.
- **Use fullscreen** is independent of 16:9. Without it, the outer Gamescope window remains a normal window.

### CPU Speed Fix

At startup, **Install CPU Speed Fix** uses `tools/iwar2-tsc-check.cpp` to measure the active x86 Time Stamp Counter (TSC). The small native C++ helper measures ticks against a monotonic reference clock instead of relying on an advertised base or boost frequency. If the measured rate exceeds `4,294,967,295` ticks per second, the option is selected automatically, but it can still be toggled manually. It remains unselected if the rate is lower or the measurement is unavailable.

This fix is not a general performance optimization. It modifies only the verified Steam `bin/release/flux.dll` with SHA-256 `f5ceddfbebd4c23fe510d033918ccc1306eb02306157c3acf5d06151a5fcd39b`: byte `0x18EF1` changes from `00` to `01`, adding `2^32` ticks once when the counter overflows. The module accepts only the original DLL or its own verified patched version, backs up the DLL before writing, and restores it after any failed verification. `g++` is required for the first automatic check; the compiled helper is then cached in the user's XDG cache.

### Videos

The **Video variants** section uses radio-button groups:

- **Don't change videos** does not write any video files.
- **Install videos based on settings** derives language and aspect ratio automatically. Selecting German game data uses German videos; otherwise it uses English. Enabling the 16:9 display option uses 16:9 videos; otherwise it uses the standard 4:3 set. The two manual groups remain disabled in this mode.
- **Install manually selected videos** enables two independent groups: exactly one choice between **Install 4:3 videos** and **Install 16:9 videos**, and exactly one choice between **Install English videos** and **Install German videos**. The defaults are 4:3 and English.

Each of the four combinations contains only the twelve 640×480 cinematic files that actually differ. The 16:9 variants are prepared without changing their content: 60 pixels are cropped from the top and bottom to produce 640×360, the image is pre-stretched back to 640×480, and the result is encoded as Bink 1. The game then displays that prepared image correctly through its own 16:9 rendering. The thirteen identical 400×400 avatar/HUD clips are deliberately left unchanged in the base installation.

When a video variant is selected, **Download and verify selected videos** runs visibly before any task that changes the game. This pre-processing step determines the exact twelve files for the selected combination, checks the persistent cache, and downloads only missing or damaged files. No backup or game-directory modification begins until all SHA-256 checks pass. The cache defaults to `~/.cache/independence-war-2-ultimate-patcher/videos/` and is reused on later runs. `IW2_VIDEO_CACHE_DIR` can redirect it for tests or another storage location.

The required download mappings are already configured. A missing download or hash mismatch fails the download task without changing any game files. After preparation, the installation task creates a ZIP backup containing only the twelve target videos and verifies every installed file again.

If only **Install german Game-data** is selected, preflight downloads the three differing German movies—`intro.bik`, `midtro.bik`, and `Outro.bik`—from the German 4:3 set, and the game-data patch uses them from the cache. If a complete video variant is selected as well, that task prepares all twelve movies and the German data task skips its three copies, avoiding duplicate downloads and writes.

The German base data is also prepared automatically before the game is changed. The patcher downloads `resource.zip`, the small `resource/` overlay, and `streams.zip`, extracts them into the cache, and validates them against all 2,565 German hashes in `patch-manifest.txt`.

The patcher starts with no tasks selected, so it installs only explicitly chosen changes.

At startup, it normally discovers the game automatically. It reads every mounted Steam library from `libraryfolders.vdf`, checks the Steam manifest `appmanifest_359630.acf` for App 359630, and accepts a reported installation only when both `EdgeOfChaos.exe` and `resource.zip` are present. This also detects installations on secondary drives. The discovered or manually selected path is shown above the installation options. **Change path ...** opens a file chooser for `EdgeOfChaos.exe`; its directory is accepted only after the same validation. The patcher uses KDialog on KDE and falls back to Zenity when available.

The game path can also be passed explicitly:

```bash
./ultimate-patcher.sh "/other/path/Independence War 2 - Edge of Chaos"
```

## Direct script use

The direct German-data script verifies every checksum before writing and creates a reversible ZIP backup of all existing target files (currently 2,495 files). During restore, it also removes the 73 dialogue files that exist only on the German CD.

Apply the German game data:

```bash
./apply-german-patch.sh "/home/mind/.local/share/Steam/steamapps/common/Independence War 2 - Edge of Chaos"
```

Check the current state:

```bash
./apply-german-patch.sh --status "/home/mind/.local/share/Steam/steamapps/common/Independence War 2 - Edge of Chaos"
```

A file reported as `SHARED` is byte-identical in both language versions and is not an error.

Restore the English version from the backup created during installation:

```bash
./restore-english.sh "/home/mind/.local/share/Steam/steamapps/common/Independence War 2 - Edge of Chaos"
```

## Direct copying

Directly copying German data into the game is not supported. Use the script above so that downloads, validation, and backups are completed correctly. Neither `backups/` nor the scripts need to be copied into the game directory.

## Scope and limits

The German package localizes menus, mission objectives, email, encyclopedia content, the 2,557 dialogue files from the original German release, and the three differing cinematics. The Steam release has 110 additional language-file names with no German CD equivalent. They remain unchanged for Steam compatibility.

## Steam F14.6 and language foundations

The Steam version already includes F14.6. The former standalone installer from `eoc_patch_2.exe` is incompatible with this release and has been removed completely. If the historical patch was applied manually, restore the supported state with Steam's file verification or a clean installation before using this patcher.

The complete editable German and English trees under [`language-payloads/`](language-payloads/) remain available as foundations for a future explicit language-selection step. Both contain the same 333 target paths, including the historical `TEXT`/`text` variants. The current patcher does not install these foundations automatically.

## Window mode, 16:9, and mouse controls

`tools/iwar2-gamescope-diagnostic.sh` starts the game inside an **outer, normal Gamescope window**. The game itself uses a fixed internal 16:9 output, preventing accidental resizing of the old DirectDraw window from immediately freezing it. **Set Gamescope as Steam launch option** installs an up-to-date wrapper and runtime configuration under `~/.local/share/independence-war-2-ultimate-patcher/` and uses only that stable location in Steam's launch options. The Ultimate Patcher can therefore be run from any directory or moved later.

If Steam is still running, the task installs the runtime copy but leaves Steam's configuration unchanged and prints the exact line to copy into Steam → Properties → General → Launch Options. Selecting the Gamescope option enables the backend choice (**Auto-detect for the current desktop session**, Wayland, or SDL), outer fullscreen mode, and the slower mouse setting `-s 0.045`. Auto detection selects Wayland in a Wayland session and SDL under X11 or another display session; an explicit selection takes precedence. `runtime/display.conf` records both the configured and resolved backend in the startup log.

The mouse option installs `payloads/configs/corrected.ini`, adds mouse yaw/pitch, and uses `protontricks` to set `MouseWarpOverride=enabled` for Steam App 359630. The display option writes only `flux.ini` and `runtime/display.conf`; it does not modify language or mission files.
