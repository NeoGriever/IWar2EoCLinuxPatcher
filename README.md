# Independence War 2: Edge of Chaos — Linux Ultimate Patcher

Console patcher for the Steam release of *Independence War 2: The Edge of
Chaos* on Linux/Proton. It offers selectable F14.6, the English language
repair, No-CD, mouse/display/Gamescope configuration and optional language/
aspect-ratio movie installation.

This repository intentionally contains patch code, audits, checksums and small
patch payloads only. It does **not** contain German CD game data or Bink movie
files. Before distributing the patcher, configure public direct URLs in
[`sources.json`](sources.json):

- `artifact_sources`: German `resource.zip`, `resource/` overlay and
  `streams/` archive;
- `video_sources`: the selected English/German × 4:3/16:9 cinematic files.

Every download is SHA-256 checked before the game directory is changed, then
kept in `~/.cache/independence-war-2-ultimate-patcher/` for reuse. The Patcher
will safely stop at its preflight stage when a required URL is missing or a
download does not match the shipped hash.

Run from this directory:

```bash
./ultimate-patcher.sh
```

See [PATCH-INFO.md](PATCH-INFO.md) for option details and host-layout notes.
