# Editable language foundations

`german/` and `english/` deliberately contain the same 333 paths below
`resource/`.  They include CSV, HTML and INI language assets, as well as the
historical `TEXT`/`text` case variants required on Linux.  A future language
selection task can extract exactly one tree into the game directory after all
other patches have finished, so later patch steps cannot leave mixed-language
files behind.

The German tree uses the German CD archive wherever available.  The six paths
that are absent there use the corresponding English F14 base file.  The
English tree uses the seventeen unambiguously English F14 base-file paths and
uses the German counterpart for every other path.  No French F14 text is used.
`PROVENANCE.tsv` records the source and fallback decision for every file;
`COUNTS.txt` summarizes the current build.

The current downloadable archives are `german-text.zip` and `english-text.zip`
in the configured external artifact host.  Their SHA-256 sidecars are tracked
under `../language-hashes/`.  After manually editing either tree, rebuild its
ZIP and its sidecar before publishing it; the Patcher does not install these
foundations yet.
