# Externe Datenübersicht

Stand: 2026-08-20. Diese Übersicht beschreibt die Dateien, die absichtlich
nicht in Git liegen. Alle hier genannten URLs stehen in `sources.json`; ihre
Erreichbarkeit wurde mit einem HTTP-Range-Request geprüft (HTTP 206), ohne die
großen Nutzdaten herunterzuladen.

## Speicherort und Integrität

- Öffentlicher Speicher: Cloudflare R2 unter
  `https://pub-0ca299279443440ead5a96b2adff330c.r2.dev/`
- Lokale Integritätsdaten: 5 SHA-256-Sidecars für Archive unter
  `payload-hashes/` und `language-hashes/`, 48 Sidecars für Videos unter
  `video-hashes/`.
- Der Patcher prüft die passende SHA-256-Summe vor jeder Änderung am
  Spielordner. Die URLs können daher bei einem Umzug des Hosters in
  `sources.json` ersetzt werden, sofern die Dateien byte-identisch bleiben.

## Deutsche Spieldaten

Diese drei Archive werden nur für **Install german Game-data** benötigt.
Sie werden vollständig vorgeprüft und liefern zusammen rund 740 MiB.

| Schlüssel in `sources.json` | Datei | Größe |
| --- | --- | ---: |
| `german_resource_zip` | `german-game-data/resource.zip` | 219,074,199 B (208.9 MiB) |
| `german_resource_overlay` | `german-game-data/resource-overlay.zip` | 24,577 B |
| `german_streams` | `german-game-data/streams.zip` | 557,362,825 B (531.5 MiB) |

## Sprachgrundlagen (reserviert)

| Schlüssel | Datei | Größe |
| --- | --- | ---: |
| `german_language_text_zip` | `language-payloads/german-text.zip` | 600,604 B |
| `english_language_text_zip` | `language-payloads/english-text.zip` | 609,510 B |

Die ZIPs sind als externe Quellen hinterlegt, werden vom aktuellen
Patcher-Stand aber noch von keinem Modul verwendet. Sie sind daher kein
Erfordernis für die derzeit angebotenen Patch-Aufgaben.

## Videos

Eine ausdrücklich gewählte Video-Variante benötigt **genau eines** der vier
Sets mit jeweils 12 Bink-Dateien. Der Cache lädt keine anderen Varianten.

| Variante | Größe |
| --- | ---: |
| Englisch, Standard (4:3) | 575,730,708 B (549.1 MiB) |
| Englisch, 16:9 | 687,018,944 B (655.2 MiB) |
| Deutsch, Standard (4:3) | 579,823,568 B (553.0 MiB) |
| Deutsch, 16:9 | 691,302,380 B (659.3 MiB) |

Jedes Set enthält diese Dateien unter
`videos/<sprache>/<format>/movies/`:

`Infogrames.bik`, `OldCalShutdown.bik`, `OldCalStartup.bik`,
`PBDiscovery.bik`, `PB_Beauty.bik`, `Prelude.bik`,
`YoungCalShutdown.bik`, `YoungCalStartup.bik`, `intro.bik`, `midtro.bik`,
`Outro.bik`, `psys.bik`.

Ohne eine vollständige Videoauswahl, aber mit **Install german Game-data**,
werden lediglich drei deutsche Standard-4:3-Dateien benötigt:
`intro.bik`, `midtro.bik` und `Outro.bik` (zusammen 470,603,460 B / 448.8
MiB). Die übrigen neun deutschen Standardvideos bleiben dann in der
Steam-Grundinstallation unangetastet.

## Minimaler Bedarf je Vorhaben

| Vorhaben | Externe Daten |
| --- | --- |
| Nur F14.6, No-CD, Maus oder Anzeige | keine |
| Deutsche Spieldaten ohne Videoauswahl | 3 Archive + 3 deutsche 4:3-Filme |
| Beliebige Videoauswahl | nur das gewählte 12-Dateien-Set |
| Deutsche Spieldaten + Videoauswahl | 3 Archive + das gewählte 12-Dateien-Set |
