# Exploids

**🌐 Sprache / Language:** [English](README.md) · [Deutsch](README.de.md)

<p align="center"><img src="Icon/icon_1024.png" width="180" alt="Exploids App-Icon"></p>

Ein nativer macOS-Arcade-Shooter im Asteroids-Stil (Swift 6 · SpriteKit) mit einem an den Commodore 64 angelehnten Vektor-Look — in moderner hoher Auflösung und butterweicher Bildrate (Apple Silicon, ProMotion 120 Hz). Jede Grafik ist prozedurale Vektor-Geometrie, jeder Soundeffekt wird in Echtzeit synthetisiert — die einzigen mitgelieferten Medien sind zwei Chiptune-Musikstücke. Zwei Spielmodi, neun Power-Ups, Gravitationsfelder, gegnerische UFOs und ein Pixel-Font-HUD.

> Der Text im Spiel ist auf Englisch.

## Download

**[➜ Aktuelles signiertes & notarisiertes DMG herunterladen](https://github.com/DanielMuellerIR/exploids/releases/latest)** — öffnen, *Exploids* in den Programme-Ordner ziehen und doppelklicken. Mit Developer ID signiert und von Apple notarisiert, öffnet also ohne Gatekeeper-Warnung. Benötigt macOS 14 oder neuer (Apple Silicon).

Lieber selbst aus dem Quellcode bauen? Siehe [Bauen & starten](#bauen--starten-kommandozeile--headless-tauglich) weiter unten.

## Screenshots

<p align="center"><img src="screenshots/sc1.jpg" width="860" alt="Asteroidenfeld mit aufgesammelter Option-Drohne, Schiff mit Schild und geschrumpft"></p>

| Glossar im Spiel | Laserstrahl | Gravitationsfeld + Bombe |
|:--:|:--:|:--:|
| ![Glossar der Objekte und Power-Ups](screenshots/sc3.jpg) | ![Der gehaltene Laserstrahl fegt über das Feld](screenshots/sc2.jpg) | ![Ein Gravitationsfeld verzerrt den Raum, während eine Bombe zündet](screenshots/sc4.jpg) |

## Bauen & starten (Kommandozeile / headless-tauglich)

Kein Xcode-Projekt — ein Swift-Package-Manager-Executable, das zu einem `.app`-Bundle kompiliert wird. Die gesamte Toolchain ist skriptbar (praktisch für Automatisierung und KI-Agenten):

```bash
./build-app.sh                                   # baut -> Exploids.app (doppelklickbar)
open Exploids.app                                # starten
.build/release/exploids                          # nackte Binary starten (Logs im Terminal)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # die 54 Unit-Tests laufen lassen
```

### Signiertes + notarisiertes DMG

```bash
bash wrappers/sign-and-release.sh                # -> build/Exploids-<version>.dmg, Gatekeeper-sauber
bash wrappers/sign-and-release.sh --publish      # setzt zusätzlich Tag + lädt das DMG zu GitHub Releases
```

## Spielmodi

Auswahl im Startbildschirm (▲/▼ wechseln, ◀/▶ für den Startlevel, Leertaste startet):

- **Ancient Asteroids** — der klassische Modus. Festes Spielfeld; Objekte laufen über die Bildschirmränder hinaus und kommen gegenüber wieder herein.
- **Mad Meteoroids** — das gesamte Feld (Asteroiden, Gravitationsfelder, Power-Ups, Sternenhimmel) rotiert fortlaufend um die Bildschirmmitte, während das Schiff ausgenommen bleibt (Crazy-Comets-Stil). Die Rotationsgeschwindigkeit steigt mit dem Level, mit geplanten Richtungswechseln und gelegentlichen „Record-Scratch"-Rucklern in höheren Leveln.

## Power-Ups

Neun Aufsammler, jeder mit eigenem Vektor-Symbol:

| Symbol | Power-Up | Wirkung |
|:--:|--|--|
| `S` | Schild | Energieschild fängt einen Treffer ab |
| `W` | Streuschuss | Dreifacher Fächer-Schuss |
| `R` | Schnellfeuer | Stark erhöhte Feuerrate |
| `O` | Option | Eine Satelliten-Drohne feuert mit |
| `B` | Bombe | Bildschirmräumende Explosion |
| `L` | Laserstrahl | Halten für einen sweependen, randumlaufenden Strahl |
| `T` | Heck | Zusätzlicher Schuss nach hinten |
| `C` | Kompress | Schrumpft das Schiff auf ~30 % (kleineres Ziel) |
| `+` | Extra-Leben | Wiederbelebung mittig mit kurzer Unverwundbarkeit |

## Steuerung

- **Startbildschirm:** ▲/▼ Spielmodus wechseln · ◀/▶ (oder A/D) Startlevel wählen · Leertaste/Enter starten · I Glossar
- **Im Spiel:** Pfeiltasten / WASD zum Fliegen · Leertaste zum Schießen (halten zum Aufladen / Strahl sweepen) · M Musik an/aus · Esc Pause / Beenden
- Highscores werden lokal gespeichert; bei einer Platzierung den Namen auf der Liste eintragen.
- **Cheat:** Taste `#` gibt ein Extra‑Leben — praktisch zum Testen oder für einen entspannten Durchlauf ohne Herausforderung.

## Einordnung

Exploids ist ein Hobby-Klon, kein Produkt. Zur ehrlichen Einordnung, Schwachstellen ausdrücklich eingeschlossen:

**Gegenüber dem Original-Asteroids (1979)** — das Original ist monochrome Vektorgrafik mit splittenden Brocken, zwei Untertassen, Hyperspace und einem Extra-Leben bei 10.000 Punkten. Exploids behält diesen Kern und ergänzt einen zweiten, rotierenden Modus (Mad Meteoroids), neun Power-Ups, Gravitationsfelder, imploding- und wobbling-Spezialasteroiden, einen Ladeschuss und einen sweependen Laserstrahl, Farbe, Chiptune-Musik, ein In-Game-Glossar und lokale Highscore-Eingabe.

**Gegenüber Maelstrom** — [Maelstrom](https://github.com/libsdl-org/Maelstrom) (Ambrosia, 1992; seit 1995 GPL-SDL-Port, heute ein SDL2/SDL3-Build, der auf Apple Silicon läuft) ist der bekannteste noch gepflegte Open-Source-Asteroids-Klon für den Mac und der fairere Maßstab: Power-Ups, Bonus-Objekte und satten Sound hat er bereits. Worin sich Exploids tatsächlich unterscheidet:

- **Rendering:** Exploids ist prozedural gezeichnete Echtzeit-*Vektor*-Geometrie in hoher Auflösung und mit 120 Hz ProMotion; Maelstrom ist Bitmap-/Sprite-Rastergrafik.
- **Audio:** Exploids synthetisiert die Soundeffekte live auf dem Audio-Thread (nur die zwei Musikstücke sind Dateien); Maelstrom spielt Samples ab.
- **Mechaniken:** der rotierende Mad-Meteoroids-Modus, Gravitationsfelder und imploding-Asteroiden sind Exploids-spezifisch.
- **Stack:** nativ Swift 6 / SpriteKit / AppKit auf Apple Silicon statt eines C/SDL-Ports.

**Wo Maelstrom klar vorn liegt:** Ein- *und* Mehrspieler (kooperativ und kompetitiv), Gamepad- und Touch-Steuerung, läuft auf mehr Plattformen und trägt 30 Jahre Feinschliff und Community. Exploids ist Einzelspieler, nur Tastatur, nur macOS-Desktop und jung. Außerdem bringt es nicht-kommerzielle Musik mit (siehe unten) — eine Einschränkung, die Maelstroms CC-lizenzierte Assets nicht haben.

## Lizenzen

- **Code:** [MIT](LICENSE) — © 2026 Daniel Müller.
- **Überschriften-Font** `Sources/GameCore/Fonts/PressStart2P-Regular.ttf` (Press Start 2P): **SIL Open Font License 1.1** (`Sources/GameCore/Fonts/OFL.txt`) — frei für jede Nutzung, auch kommerziell.
- **⚠️ Musik** `Sources/GameCore/Music/*.mp3` (zwei Chiptune-Stücke): erzeugt mit **[musely.ai](https://musely.ai)** im Free Plan — **nur persönliche, nicht-kommerzielle Nutzung**. Diese Stücke fallen **nicht** unter die MIT-Code-Lizenz und behalten die separaten Bedingungen von musely.ai. Vor jeder kommerziellen Nutzung durch eigene / CC0 / kommerziell lizenzierte Musik ersetzen. Alle anderen Klänge werden zur Laufzeit synthetisiert (keine Drittrechte).

## Voraussetzungen

macOS **14+**, Apple Silicon. Zum Bauen: eine vollständige Xcode-Installation (die Skripte nutzen `DEVELOPER_DIR=/Applications/Xcode.app/...` für die SpriteKit-/XCTest-Toolchain).

---

*Status: privates Projekt — eine prozedurale Vektor-Hommage an den Asteroids-Arcade-Klassiker von 1979, ohne übernommenen Code oder Assets.*
