# Independence War 2: Edge of Chaos – Ultimate Patcher

Dieses Paket ergänzt die geprüfte englische Steam-Fassung wahlweise um die deutsche Original-CD-Lokalisierung, Linux-Audiokonvertierung, No-CD, den CPU-Speed-Fix, Maussteuerung, auswählbare 4:3-/16:9-Videovarianten und die getestete Gamescope-Fensterkonfiguration. Es enthält keine Saves. Die Steam-Fassung liefert F14.6 bereits mit; der inkompatible historische Standalone-Patch wird deshalb weder angeboten noch mitgeliefert.

`resource.zip` wurde aus der aktuellen Steam-Datei erzeugt: Alle 33 Steam-spezifischen Inhalte bleiben erhalten, während 564 lokalisierte und 15 CD-exklusive Dateien durch die deutsche CD-Fassung ergänzt werden. Die sieben Steam-Overrides unter `resource/` und 2.557 deutsche PCM-Dialoge sind direkt enthalten. Die drei sprachabhängigen deutschen Intro-, Mittel- und Abschlussvideos kommen aus dem externen, geprüft heruntergeladenen Video-Stack.

## Interaktive Anwendung

Aus diesem Ordner starten:

```bash
./ultimate-patcher.sh
```

Pfeiltasten oder `W`/`S` bewegen die Auswahl; `A`/`D`, `Enter` oder Leertaste schalten die Auswahl. `Esc` schließt den Patcher. Die Symbole und Farben haben feste Bedeutungen:

- `□` gelb: auswählbar, nicht gewählt
- `▣` grün: auswählbar, gewählt
- `▤` grau: wegen einer Abhängigkeit nicht auswählbar
- `▩` hellgrau: gewählt, aber derzeit nicht änderbar

Während der Ausführung zeigt der Patcher ausschließlich für gewählte Aufgaben `▹` (wartend), einen animierten Braille-Spinner (läuft) und `✓` (fertig). Der Balken verwendet Achtelzeichen für feineren Fortschritt. Menü und Fortschrittsansicht werden jeweils vollständig gepuffert und als synchronisierter Terminal-Frame ausgegeben, damit beim Neuzeichnen keine einzelnen Zwischenstände sichtbar werden.

Die Abhängigkeiten sind absichtlich fest:

- **Install german Game-data** schaltet **Convert Audio-Files to work under Linux** aus. Die deutsche Nutzlast enthält bereits PCM-Dialoge.
- Bei **16:9** ist genau eine der vier Auflösungen wählbar.
- **Use fullscreen** ist unabhängig von 16:9. Ohne diese Auswahl bleibt das äußere Gamescope-Fenster ein normales Fenster.

### CPU Speed Fix

**Install CPU Speed Fix** prüft beim Start des Patchers mit `tools/iwar2-tsc-check.cpp` den tatsächlich laufenden x86-Time-Stamp-Counter (TSC). Das kleine native C++-Programm misst dessen Ticks über eine monotone Referenzzeit, statt die angezeigte Basis- oder Boost-Taktrate zu verwenden. Liegt der Messwert über `4.294.967.295` Ticks pro Sekunde, wird die Option automatisch ausgewählt; sie bleibt aber jederzeit manuell umschaltbar. Ist der Wert niedriger oder die Messung nicht verfügbar, bleibt die Option zunächst abgewählt.

Der Fix ist keine allgemeine Leistungsoptimierung. Er ändert ausschließlich die geprüfte Steam-`bin/release/flux.dll` mit SHA-256 `f5ceddfbebd4c23fe510d033918ccc1306eb02306157c3acf5d06151a5fcd39b`: Byte `0x18EF1` wird von `00` auf `01` gesetzt. Das ergänzt beim Überlauf einmal `2^32` Ticks. Das Modul akzeptiert nur diese Originaldatei oder seine selbst geprüfte Zielversion, sichert die DLL vor dem Schreiben und stellt sie bei jeder fehlgeschlagenen Nachprüfung wieder her. Für den ersten automatischen Test muss `g++` vorhanden sein; der gebaute Prüfer liegt anschließend im XDG-Cache.

### Videos

Der Bereich **Video variants** arbeitet mit Radiobuttons:

- **Don't change videos** schreibt keine Videodatei.
- **Install videos based on settings** leitet Sprache und Bildformat automatisch ab: mit deutscher Spieldaten-Auswahl werden deutsche Videos verwendet, sonst englische; mit aktivem 16:9-Display werden die 16:9-Videos verwendet, sonst die Standard-4:3-Fassung. Die beiden manuellen Gruppen bleiben in diesem Modus absichtlich deaktiviert.
- **Install manually selected videos** schaltet zwei unabhängige Radiogruppen frei: genau eine Wahl aus **Install 4:3 videos** / **Install 16:9 videos** und genau eine aus **Install English videos** / **Install German videos**. Die Voreinstellung dafür ist 4:3 und Englisch.

Alle vier Kombinationen enthalten ausschließlich die zwölf tatsächlich unterschiedlichen 640×480-Filmsequenzen. Für die 16:9-Fassung werden sie verlustfrei vorbereitet: je 60 Pixel oben und unten entfernt (640×360), anschließend auf 640×480 vorgestreckt und erst dann wieder als Bink 1 kodiert. Das Spiel streckt diese Fassung im eigenen 16:9-Rendering erneut korrekt. Die dreizehn identischen 400×400-Avatar-/HUD-Clips sind bewusst **nicht** Teil der Nutzlast: Sie bleiben unverändert in der Grundinstallation.

Die großen Bink-Dateien liegen absichtlich **nicht** mehr im Patcher. Sobald eine Video-Variante ausgewählt ist, läuft vor allen Änderungsaufgaben sichtbar **Download and verify selected videos**. Dieses Pre-Processing ermittelt exakt die zwölf Dateien der gewählten Kombination, prüft sie im persistenten Cache und lädt nur fehlende oder beschädigte Dateien herunter. Erst wenn alle SHA-256-Prüfungen erfolgreich sind, beginnt das Sichern oder Ändern des Spielordners. Der Cache liegt standardmäßig unter `~/.cache/independence-war-2-ultimate-patcher/videos/` und wird bei künftigen Durchläufen wiederverwendet. `IW2_VIDEO_CACHE_DIR` kann ihn für Tests oder einen anderen Speicherort umleiten.

Die öffentliche Download-Zuordnung steht zentral in [`sources.json`](sources.json). Jede Zeile ordnet eine Kombination aus Sprache, Format und BIK-Dateiname einer direkten HTTPS-URL zu; die zunächst leeren Werte müssen vor einer Veröffentlichung ausgefüllt werden. Die unabhängigen, kleinen Prüfsummen liegen als Klartext-Dateien `<video>.bik.hash` unter `video-hashes/`; derselbe Sidecar liegt für den Upload auch neben jeder BIK in `../VIDEO-DISTRIBUTION/videos/`. Eine fehlende URL oder eine falsche Prüfsumme lässt die Download-Aufgabe fehlschlagen, ohne irgendeine Spieldatei zu ändern. Nach erfolgreicher Vorbereitung erzeugt die Installationsaufgabe nur von den zwölf Zielvideos eine ZIP-Sicherung und prüft jede installierte Datei erneut.

Wird nur **Install german Game-data** gewählt, lädt die Vorprüfung exakt die drei abweichenden deutschen Originalfilme `intro.bik`, `midtro.bik` und `Outro.bik` aus dem deutschen 4:3-Stack und der Datenpatch verwendet sie aus dem Cache. Ist zusätzlich eine vollständige Video-Variante gewählt, lädt diese stattdessen die zwölf Dateien vorab; der deutsche Datenpatch lässt die drei Filme dann aus, damit nichts doppelt heruntergeladen oder kopiert wird.

Auch die nicht im Repository enthaltenen deutschen Basisdaten werden vor jeder Spieländerung vorbereitet: `artifact_sources` in `sources.json` enthält drei direkte URLs für `resource.zip`, das kleine `resource/`-Overlay und `streams.zip`. Die Archive werden im Cache entpackt und anschließend gegen alle 2.565 deutschen Hashes aus `patch-manifest.txt` geprüft. Damit enthält das Git-Projekt keine CD-Spielinhalte; ohne vollständig konfigurierte URLs bleibt der deutsche Datenpatch sicher in der Vorprüfung stehen.

Der Patcher startet vollständig ohne ausgewählte Aufgaben; so wird nur das installiert, was bewusst markiert wurde. Für eine Steam-Bibliothek an einem anderen Ort kann der Spielpfad als Argument übergeben werden:

Beim Start sucht der Patcher jedoch normalerweise selbst: Er liest alle eingebundenen Steam-Bibliotheken aus `libraryfolders.vdf`, prüft zu App `359630` jeweils das Steam-Manifest `appmanifest_359630.acf` und akzeptiert den gemeldeten Ordner nur mit `EdgeOfChaos.exe` und `resource.zip`. Dadurch werden auch Installationen auf zweiten Laufwerken erkannt. Der gefundene beziehungsweise ausgewählte Pfad steht oberhalb der Installationsoptionen. **Change path ...** öffnet einen Dateidialog für `EdgeOfChaos.exe`; erst nach derselben Prüfung wird dessen Ordner übernommen. Unter KDE verwendet der Patcher KDialog, ansonsten Zenity, falls vorhanden.

Der Pfad kann bei Bedarf weiterhin als Argument übergeben werden:

```bash
./ultimate-patcher.sh "/anderer/Pfad/Independence War 2 - Edge of Chaos"
```

## Direkte Anwendung per Skript

Die Anwendung prüft vorher jede Prüfsumme und erzeugt dann eine reversible ZIP-Sicherung aller vorhandenen Zieldateien (derzeit 2.495 Dateien). Die 73 Dialoge, die nur auf der deutschen CD vorkommen, werden beim Restore gezielt wieder entfernt:

```bash
./apply-german-patch.sh "/home/mind/.local/share/Steam/steamapps/common/Independence War 2 - Edge of Chaos"
```

Den Zustand prüfen:

```bash
./apply-german-patch.sh --status "/home/mind/.local/share/Steam/steamapps/common/Independence War 2 - Edge of Chaos"
```

Eine als `SHARED` markierte Datei ist in beiden Fassungen bitidentisch und kein Fehler.

Die englische Fassung aus der beim Anwenden angelegten Sicherung wiederherstellen:

```bash
./restore-english.sh "/home/mind/.local/share/Steam/steamapps/common/Independence War 2 - Edge of Chaos"
```

## Direkt kopieren

Die deutschen Nutzdaten werden nicht mehr im Patcher mitgeliefert. Ein direktes Überkopieren ist daher nicht vorgesehen; das Script oben führt die nötige Vorprüfung, Downloads und Sicherungen aus.

`backups/` sowie die Scripts müssen dafür nicht in den Spielordner kopiert werden.

## Grenzen

Das Paket stellt Menüs, Missionsziele, E-Mails, Enzyklopädie, die 2.557 Dialogdateien der deutschen Originalfassung und die drei abweichenden Zwischensequenzen auf Deutsch um. 110 zusätzliche Steam-Sprachdateinamen besitzen kein Gegenstück auf der deutschen CD und bleiben für Steam-Kompatibilität unverändert im Spielordner; sie werden von diesem Paket nicht überschrieben.

## Steam-F14.6 und Sprachgrundlagen

Die Steam-Version enthält F14.6 bereits. Der frühere Standalone-Installer aus `eoc_patch_2.exe` passt nicht auf diese Ausgabe und wurde vollständig aus dem Patcher entfernt. Installationen, auf die dieser historische Patch bereits manuell angewendet wurde, sollten vor Verwendung des Tools über Steams Dateiprüfung oder eine saubere Neuinstallation in den unterstützten Zustand zurückgebracht werden.

Die vollständigen, editierbaren Deutsch- und Englisch-Bäume unter [`language-payloads/`](language-payloads/) bleiben als Grundlagen für einen späteren expliziten Sprach-Auswahlschritt erhalten. Beide enthalten dieselben 333 Zielpfade einschließlich der historischen `TEXT`/`text`-Varianten. Der aktuelle Patcher installiert diese Grundlagen noch nicht automatisch.

## Fenster, 16:9 und Maus

`tools/iwar2-gamescope-diagnostic.sh` startet das Spiel in einem **äußeren, normalen Gamescope-Fenster**. Das Spiel selbst läuft darin mit festem innerem 16:9-Output; damit führt ein versehentliches Größenändern des alten DirectDraw-Fensters nicht direkt zum Einfrieren. Die Checkbox **Set Gamescope as Steam launch option** installiert eine aktuelle Wrapper-Kopie samt Laufzeitkonfiguration einheitlich nach `~/.local/share/independence-war-2-ultimate-patcher/` und trägt ausschließlich diesen stabilen Pfad als Steam-Startparameter ein. Damit kann der Ultimate Patcher aus jedem beliebigen Ordner ausgeführt oder später verschoben werden. Läuft Steam noch, installiert der Task die Laufzeitkopie trotzdem und gibt anschließend eine kurze Anleitung mit der exakt kopierbaren Zeile für Steam → Eigenschaften → Allgemein → Startoptionen aus; die Steam-Datei selbst bleibt dabei unverändert. Erst mit dieser Auswahl werden Gamescopes Backend (`Auto erkennen`, Wayland oder SDL), äußeres Vollbild und die verlangsamte Maus `-s 0.045` freigeschaltet. Bei `Auto erkennen` wird unter einer Wayland-Sitzung Wayland, unter X11/sonstiger Displaysitzung SDL gewählt; eine manuelle Auswahl hat Vorrang. `runtime/display.conf` zeichnet Einstellung und aufgelösten Backend-Wert im Startlog nach.

Die Mausoption installiert `configs/corrected.ini`, ergänzt Maus-Yaw/Pitch und setzt für Steam-App `359630` über `protontricks` `MouseWarpOverride=enabled`. Die Anzeigeoption schreibt nur `flux.ini` und `runtime/display.conf`; sie verändert keine Sprach- oder Missionsdateien.

## Video-Nutzlast erzeugen (Wartung)

`tools/build-video-variants.sh` ist das reproduzierbare Bauwerkzeug für die vier Video-Sets. Es erwartet den deutschen CD-Ordner `movies/` und eine ZIP-Sicherung mit den drei ursprünglichen englischen Zwischensequenzen. Standardmäßig schreibt es die großen Upload-Dateien nach `../VIDEO-DISTRIBUTION/videos/`, die Audit-Manifeste nach `audits/video-variants/` und die für den Patcher bestimmten Klartext-Prüfsummen nach `video-hashes/`. Es erzeugt erst in einem Staging-Verzeichnis, prüft Bildgröße, Bildrate und Stereo-Ton der zwölf Filmsequenzen und veröffentlicht alle drei Ergebnisse erst am Ende. Die unveränderten 400×400-HUD-/Avatarvideos werden nicht paketiert.

## Direkte Anwendung der deutschen Spieldaten

Die bewährten direkten Skripte bleiben erhalten. Sie sind sinnvoll, wenn ausschließlich die deutsche Original-CD-Lokalisierung installiert oder aus einer beim Apply erzeugten Sicherung zurückgestellt werden soll:
