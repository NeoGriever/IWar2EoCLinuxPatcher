# Independence War 2: Edge of Chaos – Ultimate Patcher

Dieses Paket ergänzt die geprüfte englische Steam-Fassung wahlweise um die deutsche Original-CD-Lokalisierung, F14.6, eine gezielte F14.6-Englischkorrektur, No-CD, Maussteuerung, auswählbare 4:3-/16:9-Videovarianten und die getestete Gamescope-Fensterkonfiguration. Es enthält keine Saves.

`resource.zip` wurde aus der aktuellen Steam-Datei erzeugt: Alle 33 Steam-spezifischen Inhalte bleiben erhalten, während 564 lokalisierte und 15 CD-exklusive Dateien durch die deutsche CD-Fassung ergänzt werden. Die sieben Steam-Overrides unter `resource/` und 2.557 deutsche PCM-Dialoge sind direkt enthalten. Die drei sprachabhängigen deutschen Intro-, Mittel- und Abschlussvideos kommen aus dem externen, geprüft heruntergeladenen Video-Stack.

## Interaktive Anwendung

Aus diesem Ordner starten:

```bash
./ultimate-patcher.sh
```

`german-patcher.sh` öffnet dieselbe neue Oberfläche, damit bestehende Starter weiter funktionieren. Die alte Ein-Aktions-Oberfläche bleibt nur mit `IW2_LEGACY_GERMAN_PATCHER=1 ./german-patcher.sh` erreichbar.

Pfeiltasten oder `W`/`S` bewegen die Auswahl; `A`/`D`, `Enter` oder Leertaste schalten die Auswahl. `Esc` schließt den Patcher. Die Symbole und Farben haben feste Bedeutungen:

- `□` gelb: auswählbar, nicht gewählt
- `▣` grün: auswählbar, gewählt
- `▤` grau: wegen einer Abhängigkeit nicht auswählbar
- `▩` hellgrau: gewählt, aber derzeit nicht änderbar

Während der Ausführung zeigt der Patcher ausschließlich für gewählte Aufgaben `▹` (wartend), `⠇ ⠦ ⠴ ⠸ ⠙ ⠋` (läuft) und `✓` (fertig). Der Balken verwendet Achtelzeichen für feineren Fortschritt.

Die Abhängigkeiten sind absichtlich fest:

- **Install german Game-data** schaltet **Convert Audio-Files to work under Linux** und **Fix english messages after 14.6-Patch** aus. Die deutsche Nutzlast enthält bereits PCM-Dialoge.
- **Fix english messages after 14.6-Patch** ist nur ohne deutsche Spieldaten und nur bei gewähltem F14.6 verfügbar.
- Werden **Install german Game-data** und F14.6 gemeinsam gewählt, installiert der Patcher erst F14.6 und legt anschließend die geprüften deutschen CD-Daten erneut darüber. Damit bleiben keine französischen oder englischen F14.6-Sprachreste in der deutschen Auswahl zurück.
- Bei **16:9** ist genau eine der vier Auflösungen wählbar.
- **Use fullscreen** ist unabhängig von 16:9. Ohne diese Auswahl bleibt das äußere Gamescope-Fenster ein normales Fenster.

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

## Vorhandene Komplettsicherung

`backups/IW2EOC-Steam-before-GERPATCH-20260727.zip` ist eine vollständige ZIP-Sicherung der lokalen Installation vor dem Paketbau (5.581 Dateien, einschließlich der bestehenden Proton-Audioanpassung). Eine Steam-Dateiprüfung stellt die englischen Steam-Dateien ebenfalls wieder her, kann aber eigene Anpassungen entfernen.

## Grenzen

Das Paket stellt Menüs, Missionsziele, E-Mails, Enzyklopädie, die 2.557 Dialogdateien der deutschen Originalfassung und die drei abweichenden Zwischensequenzen auf Deutsch um. 110 zusätzliche Steam-Sprachdateinamen besitzen kein Gegenstück auf der deutschen CD und bleiben für Steam-Kompatibilität unverändert im Spielordner; sie werden von diesem Paket nicht überschrieben.

## F14.6 und Sprachgrundlagen

`payloads/f14.6/` enthält die 394 nichtsprachlichen F14.6-Dateien aus `eoc_patch_2.exe`. Alle 162 CSV-/HTML-/INI-Sprachdateien wurden daraus entfernt: Sie liegen getrennt als vollständige, editierbare Deutsch- und Englisch-Bäume unter [`language-payloads/`](language-payloads/) vor. Beide Bäume enthalten dieselben 333 Zielpfade einschließlich der historischen `TEXT`/`text`-Varianten. Die ZIPs werden extern zusammen mit ihren SHA-256-Sidecars bereitgestellt, aber erst ein späterer expliziter Sprach-Auswahlschritt wird sie als letzten Patch-Schritt installieren. Die Installer-Datei wurde mit SHA-256 `d888f573b7f3589dedca157df6f8d0a0be0f480ce59de9d456f432db33a6fe71` geprüft. Das Modul überprüft jede verbliebene Nutzdatei, erstellt eine ZIP-Sicherung und registriert F14.6 im Proton-Prefix über `protontricks`.

Hinweis: Die F14.6-Hinweise des ursprünglichen Anbieters nennen `resource/images/planets` als versehentlich enthaltenes Grafik-Upgrade, das speziell mit der deutschen Fassung Probleme bereiten kann. Der Ultimate Patcher entfernt diesen Ordner **nicht** automatisch, weil die Auswahl „vollständiges F14.6“ exakt bleiben soll; bei einem reproduzierbaren Planeten-/Renderproblem ist das ein separat zu prüfender, rücksicherbarer Kandidat.

Auf einem Linux-Dateisystem können die im historischen Installer gleichzeitig enthaltenen englischen, deutschen und französischen Pfade wegen ihrer unterschiedlichen Groß-/Kleinschreibung nebeneinander liegen. In älteren, bereits gepatchten Installationen können solche Reste daher noch parallel existieren. Die neuen Sprachgrundlagen bereiten beide Varianten für einen späteren letzten, expliziten Auswahlschritt vor und werden bis dahin nicht automatisch installiert.

Die bestehende Option **Fix english messages after 14.6-Patch** bleibt ausschließlich für solche älteren Installationen erhalten und ist kein pauschales Überschreiben:

1. Sie akzeptiert nur die 275 exakt geprüften F14.6-Text-/HTML-Überlagerungen aus `audits/f14.6-language-residue.txt`.
2. Sie sichert diese Dateien in einer ZIP.
3. Sie entfernt nur diese Sprachreste und stellt 243 eindeutig geprüfte englische Quellen aus der originalen Steam-`resource.zip` wieder her (`audits/f14.6-english-archive.txt`).
4. Sie legt die drei englischen F14.6-Multiplayer-Zusatzdateien neu an und enthält für den vom historischen Patch nur auf Deutsch gelieferten Capture-the-Flag-Text eine englische Ergänzung. Alle vier Ergänzungen werden über `audits/f14.6-english-extras.txt` vor und nach dem Kopieren gehasht.

Keine F14.6-EXE, DLL, Modell-, Missions- oder sonstige Engine-Datei wird vom English Fix geändert. Die vollständige Prüfdokumentation steht in [F14.6-ENGLISH-FIX.md](audits/F14.6-ENGLISH-FIX.md). Für künftige Neuinstallationen soll ihn der noch zu implementierende ZIP-basierte Sprach-Auswahlschritt ersetzen.

## Fenster, 16:9 und Maus

`tools/iwar2-gamescope-diagnostic.sh` startet das Spiel in einem **äußeren, normalen Gamescope-Fenster**. Das Spiel selbst läuft darin mit festem innerem 16:9-Output; damit führt ein versehentliches Größenändern des alten DirectDraw-Fensters nicht direkt zum Einfrieren. Die Checkbox **Set Gamescope as Steam launch option** installiert eine aktuelle Wrapper-Kopie samt Laufzeitkonfiguration einheitlich nach `~/.local/share/independence-war-2-ultimate-patcher/` und trägt ausschließlich diesen stabilen Pfad als Steam-Startparameter ein. Damit kann der Ultimate Patcher aus jedem beliebigen Ordner ausgeführt oder später verschoben werden. Läuft Steam noch, installiert der Task die Laufzeitkopie trotzdem und gibt anschließend eine kurze Anleitung mit der exakt kopierbaren Zeile für Steam → Eigenschaften → Allgemein → Startoptionen aus; die Steam-Datei selbst bleibt dabei unverändert. Erst mit dieser Auswahl werden Gamescopes Backend (`Auto erkennen`, Wayland oder SDL), äußeres Vollbild und die verlangsamte Maus `-s 0.045` freigeschaltet. Bei `Auto erkennen` wird unter einer Wayland-Sitzung Wayland, unter X11/sonstiger Displaysitzung SDL gewählt; eine manuelle Auswahl hat Vorrang. `runtime/display.conf` zeichnet Einstellung und aufgelösten Backend-Wert im Startlog nach.

Die Mausoption installiert `configs/corrected.ini`, ergänzt Maus-Yaw/Pitch und setzt für Steam-App `359630` über `protontricks` `MouseWarpOverride=enabled`. Die Anzeigeoption schreibt nur `flux.ini` und `runtime/display.conf`; sie verändert keine F14.6- oder Sprachdateien.

## Video-Nutzlast erzeugen (Wartung)

`tools/build-video-variants.sh` ist das reproduzierbare Bauwerkzeug für die vier Video-Sets. Es erwartet den deutschen CD-Ordner `movies/` und eine ZIP-Sicherung mit den drei ursprünglichen englischen Zwischensequenzen. Standardmäßig schreibt es die großen Upload-Dateien nach `../VIDEO-DISTRIBUTION/videos/`, die Audit-Manifeste nach `audits/video-variants/` und die für den Patcher bestimmten Klartext-Prüfsummen nach `video-hashes/`. Es erzeugt erst in einem Staging-Verzeichnis, prüft Bildgröße, Bildrate und Stereo-Ton der zwölf Filmsequenzen und veröffentlicht alle drei Ergebnisse erst am Ende. Die unveränderten 400×400-HUD-/Avatarvideos werden nicht paketiert.

## Direkte Anwendung der deutschen Spieldaten

Die bewährten direkten Skripte bleiben erhalten. Sie sind sinnvoll, wenn ausschließlich die deutsche Original-CD-Lokalisierung installiert oder aus einer beim Apply erzeugten Sicherung zurückgestellt werden soll:
