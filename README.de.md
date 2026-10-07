# Exploids

**🌐 Sprache / Language:** [English](README.md) · [Deutsch](README.de.md)

<p align="center"><img src="Icon/icon_1024.png" width="180" alt="Exploids App-Icon"></p>

Ein nativer Arcade-Shooter für macOS und iOS im Asteroids-Stil (Swift 6 · SpriteKit) mit einem an den Commodore 64 angelehnten Vektor-Look — in moderner hoher Auflösung und butterweicher Bildrate (Apple Silicon, ProMotion 120 Hz). Fast jede Grafik ist prozedurale Vektor-Geometrie — nur die beiden Bosse nutzen getracte Vektor-Konturen als Texturen — und die Soundeffekte stammen aus Echtzeitsynthese oder optionalen gebündelten Aufnahmen; mitgeliefert sind zwei Chiptune-Musikstücke, die Boss-Texturen und ein optionales Paket aufgenommener Soundeffekte. Drei Spielmodi auf macOS (zwei auf iOS), neun Power-Ups, Gravitationsfelder, gegnerische UFOs, zwei Bosse, ein Pixel-Font-HUD und ein deterministisches Replay-System, das Promo-GIFs headless rendern kann.

> Der Text im Spiel ist auf Englisch.

## Download

**[➜ Aktuelles signiertes & notarisiertes DMG herunterladen](https://github.com/DanielMuellerIR/exploids/releases/latest)** — öffnen, *Exploids* in den Programme-Ordner ziehen und doppelklicken. Mit Developer ID signiert und von Apple notarisiert, öffnet also ohne Gatekeeper-Warnung. Benötigt macOS 11 oder neuer (Apple Silicon).

Lieber selbst aus dem Quellcode bauen? Siehe [Bauen & starten](#bauen--starten-kommandozeile--headless-tauglich) weiter unten.

## Screenshots

<p align="center"><img src="screenshots/sc0.jpg" width="860" alt="Survival-Modus in vollem Fluss — das Schiff feuert einen regenbogenfarbenen Schuss-Strom an einem violetten Gravitationsfeld vorbei, während Asteroiden und ein gegnerisches UFO heranrücken"></p>

| Option-Drohne + Schild | Glossar im Spiel |
|:--:|:--:|
| ![Asteroidenfeld mit aufgesammelter Option-Drohne, Schiff mit Schild und geschrumpft](screenshots/sc1.jpg) | ![Glossar der Objekte und Power-Ups](screenshots/sc3.jpg) |
| **Laserstrahl** | **Gravitationsfeld + Bombe** |
| ![Das Laserstrahl-Power-up fegt bei gehaltener Feuertaste über das Feld](screenshots/sc2.jpg) | ![Ein Gravitationsfeld verzerrt den Raum, während eine Bombe zündet](screenshots/sc4.jpg) |

## Bauen & starten (Kommandozeile / headless-tauglich)

Der macOS-Build verwendet Swift Package Manager und wird zu einem `.app`-Bundle kompiliert; der iOS-Port hat ein eigenes Xcode-Projekt unter `ios/`. Die gesamte Toolchain ist skriptbar (praktisch für Automatisierung und KI-Agenten):

```bash
./build-app.sh                                   # baut -> Exploids.app (doppelklickbar)
open Exploids.app                                # starten
.build/release/exploids                          # nackte Binary starten (Logs im Terminal)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # die Unit-Tests laufen lassen
```

### Installieren und Release bauen

Drei Einstiegspunkte, bewusst getrennt:

```bash
./build.sh                        # baut nur, bleibt im Projektverzeichnis (Wrapper auf build-app.sh)
./install.sh                      # baut, notarisiert, installiert nach /Applications
./release.sh                      # baut, notarisiert, packt das DMG — installiert nie
./release.sh --publish            # setzt zusätzlich Tag + lädt das DMG zu GitHub Releases
./release.sh --no-finder-layout   # ohne Finder-Fensterlayout (für headless Läufe)
```

`install.sh` und `release.sh` notarisieren zuerst die **App selbst** und heften
ihr das Ticket an. Das ist der Punkt: Eine App, die nur im notarisierten
Disk-Image steckt, verliert ihre Garantie in dem Moment, in dem jemand sie
herauszieht. `release.sh` notarisiert danach zusätzlich das Image.

Für die Notarisierung wird ein notarytool-Keychain-Profil gebraucht. Solche
Profile sind pro Mac lokal und werden nie synchronisiert, deshalb kommt der Name
aus `NOTARY_PROFILE` oder aus der Konfiguration dieses Clones:

```bash
git config --local exploids.notaryProfile <profil>
xcrun notarytool store-credentials <profil> --apple-id <apple-id> --team-id <team-id>
```

## Spielmodi

Auswahl im Startbildschirm (▲/▼ wechseln, ◀/▶ für den Startlevel, Leertaste startet):

- **Ancient Asteroids** — der klassische Modus. Festes Spielfeld; Objekte laufen über die Bildschirmränder hinaus und kommen gegenüber wieder herein.
- **Mad Meteoroids** — das gesamte Feld (Asteroiden, Gravitationsfelder, Power-Ups, Sternenhimmel) rotiert fortlaufend um die Bildschirmmitte, während das Schiff ausgenommen bleibt (Crazy-Comets-Stil). Die Rotationsgeschwindigkeit steigt mit dem Level, mit geplanten Richtungswechseln und gelegentlichen „Record-Scratch"-Rucklern in höheren Leveln.
- **Event Horizon** — vorerst nur auf macOS. Bewegliche Spielobjekte verschwinden endgültig, sobald sie vollständig außerhalb des Bildes sind. Das Schiff prallt spiegelnd an den Rändern ab. Ein dauerhaftes schwarzes Loch liegt in der Mitte; weitere schwarze Löcher entstehen in diesem Modus nicht.

## Power-Ups

Neun Aufsammler, jeder mit eigenem Vektor-Symbol:

| Symbol | Power-Up | Wirkung |
|:--:|--|--|
| `S` | Schild | Energieschild fängt einen Treffer ab |
| `W` | Streuschuss | Dreifacher Fächer-Schuss |
| `R` | Schnellfeuer | Stark erhöhte Feuerrate |
| `O` | Option | Eine Satelliten-Drohne feuert mit |
| `B` | Bombe | Bildschirmräumende Explosion |
| `L` | Laserstrahl | Halten für einen sweependen Strahl; endet in Event Horizon am Rand, läuft in den anderen Modi um |
| `T` | Heck | Zusätzlicher Schuss nach hinten |
| `C` | Kompress | Schrumpft das Schiff auf ~30 % (kleineres Ziel) |
| `+` | Extra-Leben | Wiederbelebung am Startpunkt mit kurzer Unverwundbarkeit |

## Gegner & Bosse

Über die splittenden Brocken hinaus füllt sich das Feld, je höher der Level:

- **Gegnerische UFOs** — ein großes grünes UFO, das in zufällige Richtungen feuert, und ein kleines pinkes, das gezielt auf das Schiff schießt. Beide gleiten mit leichtem Sog in Richtung Spieler herein.
- **Gravitationsfelder** — Schwarze Löcher, die den Raum verzerren, alles nach innen ziehen und das Schiff bei Berührung zermalmen.
- **Implodierende Asteroiden** — magenta umrandete Brocken, die beim Abschuss zu einem frischen Gravitationsfeld kollabieren; in Event Horizon entstehen keine zusätzlichen Löcher.
- **Wobble-Bomben** — rote Brocken, die pulsieren, in Stufen wachsen und dann in einen Fächer schneller Splitter detonieren.
- **Weltraumkatze** — ein pirschender Boss, der hinter Asteroiden in Deckung geht, deine Bewegung vorhält und mit Zwillings-Augenstrahlen feuert; drei Treffer vertreiben sie.
- **Das Idol** — ein großer schwebender Steinkopf, der hereingleitet, deinen Schüssen ausweicht und eine Armada UFOs aus dem Mund speit; zehn Treffer zerstören ihn.

## Steuerung

- **Startbildschirm:** ▲/▼ Spielmodus wechseln · ◀/▶ Startlevel wählen · Leertaste/Enter starten · D (oder 30 s Leerlauf) eine Autopilot-Demo ansehen · I Glossar · 1–5 ein Highscore-Replay ansehen
- **Im Spiel:** Pfeiltasten / WASD zum Fliegen · Leertaste zum Schießen (halten für Dauerfeuer; mit aktivem Laserstrahl-Power-up halten, um den Strahl zu schwenken) · F Auto-Feuer umschalten · M Musik an/aus · N Synth-/Aufnahme-Effekte umschalten · Esc Pause / Beenden
- **Replay-Ansicht:** Esc verlässt das Replay zurück zum Startbildschirm.
- Highscores werden lokal gespeichert; bei einer Platzierung den Namen auf der Liste eintragen.
- **Cheat:** Taste `#` gibt ein Extra‑Leben — praktisch zum Testen oder für einen entspannten Durchlauf ohne Herausforderung.

## Replay & GIF-Export

Die Simulation ist **deterministisch**: Jeder Durchlauf wird allein als Seed plus deine Tastendrücke aufgezeichnet und lässt sich dadurch bit-genau reproduzieren. Daraus folgen zwei Dinge:

- Während Aufnahme und Wiedergabe skaliert eine Größenänderung nur die Ansicht; die Simulation behält ihre Startgröße. Der Startbildschirm passt sich anschließend wieder ans Fenster an.
- Die Wiedergabe benötigt die passende Simulations-Logikversion. Version 0.15.2 verwendet Logikversion 7 und lehnt ältere Aufnahmen ab; deren gespeicherte Bytes und Highscores bleiben erhalten.
- **Highscore-Läufe erneut ansehen** — im Startbildschirm `1`–`5` drücken, um den Eintrag exakt so abzuspielen, wie er gespielt wurde; `Esc` verlässt ihn.
- **Promo-GIFs headless rendern** — ein Replay direkt auf der Kommandozeile in ein sauberes, cursorfreies animiertes GIF verwandeln, ganz ohne Fenster:

```bash
exploids --render-demo --out demo.gif            # skriptgesteuerter Demo-Lauf -> GIF (Pipeline-Selbsttest)
exploids --export-replay 0 --out run.replay      # Replay von Highscore-Eintrag #0 in eine Datei exportieren
exploids --render-replay run.replay --out run.gif --scale 480 --fps 30
```

GIF-Export erhält die Dauer in ganzen Hundertstelsekunden und fasst Raten oberhalb von 50 FPS zusammen; Video behält die gewünschte Bildrate.

## Einordnung

Exploids ist ein Hobby-Klon, kein Produkt. Zur ehrlichen Einordnung, Schwachstellen ausdrücklich eingeschlossen:

**Gegenüber dem Original-Asteroids (1979)** — das Original ist monochrome Vektorgrafik mit splittenden Brocken, zwei Untertassen, Hyperspace und einem Extra-Leben bei 10.000 Punkten. Exploids behält diesen Kern und ergänzt Mad Meteoroids mit Rotation und Event Horizon mit reflektierenden Schiffsgrenzen, neun Power-Ups, Gravitationsfelder, imploding- und wobbling-Spezialasteroiden, zwei Bosse, einen sweependen Laserstrahl, Farbe, Chiptune-Musik, ein In-Game-Glossar, lokale Highscore-Eingabe und deterministische Replays, die sich erneut ansehen oder als GIF exportieren lassen.

**Gegenüber Maelstrom** — [Maelstrom](https://github.com/libsdl-org/Maelstrom) (Ambrosia, 1992; seit 1995 GPL-SDL-Port, heute ein SDL3-Build, der auf Apple Silicon läuft) ist der bekannteste noch gepflegte Open-Source-Asteroids-Klon für den Mac und der fairere Maßstab: Power-Ups, Bonus-Objekte und satten Sound hat er bereits. Worin sich Exploids tatsächlich unterscheidet:

- **Rendering:** Exploids ist prozedural gezeichnete Echtzeit-*Vektor*-Geometrie in hoher Auflösung und mit 120 Hz ProMotion; Maelstrom ist Bitmap-/Sprite-Rastergrafik.
- **Audio:** Exploids synthetisiert die Soundeffekte live auf dem Audio-Thread und bietet optionale gebündelte Effektaufnahmen; Maelstrom spielt Samples ab.
- **Mechaniken:** der rotierende Mad-Meteoroids-Modus, Gravitationsfelder und imploding-Asteroiden sind Exploids-spezifisch.
- **Stack:** nativ Swift 6 / SpriteKit / AppKit auf Apple Silicon statt eines C/SDL-Ports.

**Wo Maelstrom klar vorn liegt:** Ein- *und* Mehrspieler (kooperativ und kompetitiv), Gamepad- und Touch-Steuerung, läuft auf mehr Plattformen und trägt 30 Jahre Feinschliff und Community. Exploids bietet Einzelspieler mit Tastatur auf macOS und Touch-Steuerung auf iOS. Außerdem bringt es nicht-kommerzielle Musik mit (siehe unten) — eine Einschränkung, die Maelstroms CC-lizenzierte Assets nicht haben.

## Lizenzen

- **Code:** [MIT](LICENSE) — © 2026 Daniel Müller.
- **Überschriften-Font** `Sources/GameCore/Fonts/PressStart2P-Regular.ttf` (Press Start 2P): **SIL Open Font License 1.1** (`Sources/GameCore/Fonts/OFL.txt`) — frei für jede Nutzung, auch kommerziell.
- **⚠️ Musik** `Sources/GameCore/Music/*.mp3` (zwei Chiptune-Stücke): erzeugt mit **[musely.ai](https://musely.ai)** im Free Plan — **nur persönliche, nicht-kommerzielle Nutzung**. Diese Stücke fallen **nicht** unter die MIT-Code-Lizenz und behalten die separaten Bedingungen von musely.ai. Vor jeder kommerziellen Nutzung durch eigene / CC0 / kommerziell lizenzierte Musik ersetzen. Prozedurale Effekte entstehen im Code; die optionalen SFX-Aufnahmen haben eine eigene Herkunft. Siehe [gebündelte Assets](docs/assets.md).

## iOS-Port

Der iOS-Port unter `ios/` verwendet SpriteKit, Touch-Steuerung auf dem Bildschirm und dieselbe `GameCore`-Engine wie der macOS-Build. Er unterstützt iPhone und iPad ab iOS 17 im Querformat. Touch-Steuerung, gleichzeitige Eingaben, Loslassen, Hintergrund/Rückkehr, Audio und Darstellung wurden am 2026-10-01 auf einem iPhone erfolgreich abgenommen.

App-Icon und Asset-Catalog sind vorhanden; Xcode generiert den Launch-Screen. `bash ios/generate.sh` erzeugt das Xcode-Projekt und übernimmt die Version aus `VERSION`. GameController-Unterstützung ist noch nicht implementiert. Eine App-Store-Veröffentlichung ist derzeit nicht geplant.

## Voraussetzungen

macOS **11+**, Apple Silicon. Zum Bauen: eine vollständige Xcode-Installation (die Skripte nutzen `DEVELOPER_DIR=/Applications/Xcode.app/...` für die SpriteKit-/XCTest-Toolchain).

---

*Status: privates Projekt — eine prozedurale Vektor-Hommage an den Asteroids-Arcade-Klassiker von 1979, ohne übernommenen Code oder Assets.*
