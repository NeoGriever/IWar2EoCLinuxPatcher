# Independence War 2: Edge of Chaos — Linux Ultimate Patcher

Console patcher for the Steam release of *Independence War 2: The Edge of
Chaos* on Linux/Proton. The Steam release already includes F14.6, so this tool
does not install the incompatible historical standalone patch. It offers
German game data, Linux audio conversion, No-CD, CPU timing, mouse/display/
Gamescope configuration and optional language/aspect-ratio movie installation.

Required German game data and the selected English/German × 4:3/16:9 movies
are downloaded automatically from the configured sources. Every download is
SHA-256 checked before the game directory is changed, then kept in
`~/.cache/independence-war-2-ultimate-patcher/` for reuse. The Patcher safely
stops during preflight if a download is unavailable or does not match the
shipped hash.

The editable language source trees live in
[`language-payloads/`](language-payloads/). They are prepared for a later
explicit language-selection step and are not installed by the Patcher yet.

Run from this directory:

```bash
./ultimate-patcher.sh
```

At startup the patcher reads Steam's `libraryfolders.vdf` and the
`appmanifest_359630.acf` entries for every mounted Steam library, then accepts
only a directory containing both `EdgeOfChaos.exe` and `resource.zip`. This
also covers games installed on a second drive. The selected directory is shown
above the installation options. Choose **Change path ...** to select
`EdgeOfChaos.exe` manually; the containing folder is validated before it can
be used. KDE's KDialog is used when available, with Zenity as the fallback.

At startup, the CPU Speed Fix option builds and runs a small native C++ TSC
counter checker. It measures the actual time-stamp-counter rate instead of an
advertised or boost clock. When the measured rate exceeds the 32-bit limit of
4,294,967,295 ticks per second, the option is selected automatically; it is
always still possible to toggle it manually. The first check requires `g++`;
the compiled helper is cached under the user's XDG cache directory.

See [PATCH-INFO.md](PATCH-INFO.md) for option details and host-layout notes.
