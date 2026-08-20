# Video variants

The Ultimate Patcher does not carry the large movie files.  They are stored
separately for publication under `../VIDEO-DISTRIBUTION/videos/` and downloaded
only when the user selects a video variant.  The Patcher itself carries four
small, fully hashed catalogue entries:

- `video-hashes/english/standard`
- `video-hashes/english/widescreen`
- `video-hashes/german/standard`
- `video-hashes/german/widescreen`

Each contains one plain-text `<video>.bik.hash` SHA-256 file for each of the
12 game-relative cinematics. An identical sidecar is also kept beside each
publication BIK under `../VIDEO-DISTRIBUTION/videos/`. The matching public
direct URLs are configured in `sources.json` with keys of the form
`<language>_<aspect>_<lowercase BIK basename>`. The pre-processing downloader
verifies the persistent cache before it writes anything to the game, then the
installer creates a ZIP backup of the 12 files it will replace and verifies
every target hash after copying. The audit manifests in
`audits/video-variants/<language>-<aspect>.txt` remain a compact build audit.

The 12 640×480 cinematics in each `widescreen` set are made as follows:

1. Decode the original Bink 1 source to a lossless FFV1/PCM AVI.
2. Crop `640:360:0:60` — exactly 60 pixels from the top and bottom.
3. Scale the resulting image back to `640:480` with Lanczos.
4. Encode the result once as Bink 1 at 25 fps with 44.1 kHz stereo legacy
   `binkaudio_rdft` audio. This codec is required by the game's original Bink
   decoder; the modern `binkaudio_dct` output is not compatible.

The game subsequently applies its own 16:9 stretch, which cancels this
intentional pre-stretch. The 13 400×400 HUD/avatar videos, including all
`movies/multiplayer/` clips, are intentionally omitted from every payload:
they are identical in every language/aspect combination and remain untouched
in the base game installation.
