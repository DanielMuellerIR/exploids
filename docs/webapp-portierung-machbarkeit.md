# Machbarkeit: Exploids als Webapp für Mobilgeräte

Stand: 2026-08-06, gemessen an Commit `8bfcdfc`. **Status: reine Analyse, nichts beauftragt,
nichts umgesetzt.** Das Dokument hält den Befund fest, damit die Entscheidung später nicht
neu erarbeitet werden muss.

## Kurzfassung

Machbar, aber nicht als Portierung. `GameCore` ist zwar frei von AppKit, hängt jedoch
vollständig an SpriteKit — die Spielobjekte *sind* Szenengraph-Knoten und der Spielzustand
liegt in ihnen. Es gibt deshalb keinen Simulationskern, den man herauslösen und unter einem
anderen Renderer weiterbetreiben könnte. Eine Webversion liefe auf eine Neuimplementierung
der Spiellogik hinaus. Der günstigere Zeitpunkt läge nach der in `backlog.md` unter Punkt 2
geplanten Entzerrung von `stepSimulation`.

## Befund: Der Kern ist nicht plattformunabhängig

`CLAUDE.md` beschreibt `Sources/GameCore/` als „plattformunabhängige Simulation". Das trifft
auf AppKit zu, auf SpriteKit nicht.

**Alle Spielobjekte erben von SpriteKit-Klassen.** `Ship`, `Asteroid`, `UFO`, `PowerUp`,
`Laser`, `GravityWell` und `OptionDrone` sind `SKShapeNode`-Unterklassen, `SpaceCat` und
`FloatingHead` erben von `SKNode`, `GameScene` von `SKScene`
([GameScene.swift:92](../Sources/GameCore/GameScene.swift#L92)).

**Der Spielzustand liegt im Szenengraph, nicht daneben.** In `GameCore` stehen 242 Zugriffe
auf `.position`, davon 123 allein in `GameScene.swift`. Die Simulation liest und schreibt
Knoteneigenschaften direkt: die Gravitationsrechnung greift auf `ship.position` und
`well.position` zu ([GameScene.swift:1201](../Sources/GameCore/GameScene.swift#L1201)),
Positionen werden per `option.position.x += …` fortgeschrieben. Die Kollisionsprüfung
arbeitet auf Weltkoordinaten, die aus Knotentransformationen entstehen.

**Zeitverhalten liegt teils außerhalb des Fixed Timestep.** 51 `SKAction`-Aufrufe steuern
Effekte über SpriteKits eigene Zeitachse statt über `stepSimulation`.

Tatsächlich portabel ist nur ein kleiner Teil: `Collision.swift`, `GameRandom.swift`,
`VectorMath.swift` und `Replay.swift` — zusammen rund 350 der etwa 9.100 Zeilen in
`GameCore`. Diese vier Dateien wären in jeder Zielsprache fast unverändert nachbaubar; der
Rest nicht.

## Bewertung der zwei Wege

### Swift nach WebAssembly (SwiftWasm)

Nicht empfohlen. SpriteKit existiert für WebAssembly nicht, der vollständige Umbau auf einen
SpriteKit-freien Kern wäre also trotzdem fällig — und danach bräuchte es zusätzlich einen
eigenen Renderer in JavaScript. Man zahlt den gesamten Umbau und spart keine Grafikarbeit.
Dazu kommt die WebAssembly-Laufzeit im Download, was dem Ziel Mobilgerät entgegensteht.

### Neuimplementierung in TypeScript

Der technisch passendere Weg. Drei Dinge sprechen dafür:

- Die C64-Vektorgrafik besteht aus `SKShapeNode`-Pfaden. Die lassen sich auf Canvas2D nahezu
  eins zu eins abbilden; es gibt keine aufwendigen Shader oder Texturebenen zu ersetzen.
- Das prozedurale Audio hat bereits die richtige Form. `SoundManager` berechnet die Samples
  in einem Callback von `AVAudioSourceNode`
  ([SoundManager.swift:242](../Sources/GameCore/SoundManager.swift#L242)) — das entspricht
  direkt einem `AudioWorkletProcessor` im Web-Audio-System.
- Der Fixed Timestep von 1/120 s bleibt erhalten, indem pro Bildschirmaktualisierung zwei
  Simulationsschritte laufen. Da der Timestep schon von der Bildrate entkoppelt ist, ist das
  kein Sonderfall, sondern der vorgesehene Mechanismus.

Dagegen steht der Umfang: rund 9.000 Zeilen Spiellogik plus die zugehörigen Tests wären neu
zu schreiben.

## Zwei Punkte, die unabhängig vom Weg gelten

### Replays wären nicht kompatibel

Die Simulation ist deterministisch, aber ihr Determinismus reicht nicht über Sprachgrenzen.
`sin`, `cos` und `pow` sind in IEEE 754 nicht bitgenau festgelegt und liefern zwischen der
libm-Implementierung unter Swift und einer JavaScript-Laufzeit geringfügig verschiedene
Werte. Über die Zehntausenden Schritte eines Laufs driftet das auseinander.

Bestehende Replaydateien liefen in einer Webversion also anders ab. Da Replay laut
`CLAUDE.md` ein Kernvertrag des Projekts ist und nicht bloß eine Zusatzfunktion, ist das eine
bewusste Entscheidung, keine Nebensache: Die Webversion bekäme faktisch einen eigenen
Replay-Raum. Ein plattformübergreifend bitgenaues Replay wäre nur mit eigener
Festkomma-Arithmetik oder eigenen Winkelfunktionen zu haben — beides ein Vorhaben für sich.

### Die Musiklizenz wird vom Zukunfts- zum Sofortproblem

`backlog.md` verschiebt unter Punkt 4 den Austausch der beiden Free-Plan-Musiktracks auf den
Zeitpunkt „vor App-Store- oder kommerzieller Distribution". Für eine Webapp greift diese
Reihenfolge nicht: Eine öffentlich erreichbare Seite liefert `neon-vectors.mp3` und
`asteroid-storm.mp3` als Datei an jeden Besucher aus. Das ist Weiterverbreitung der
Audiodateien selbst, und Free-Pläne solcher Anbieter decken üblicherweise die Verwendung
*innerhalb* eines Werks ab, nicht die Auslieferung der Datei. Der Lizenztext des konkreten
Anbieters ist daher **vor** dem ersten öffentlichen Deploy zu prüfen, nicht danach.

### Weitere Pflichten bei öffentlicher Auslieferung

- **Ladegewicht:** Die Assets wiegen zusammen etwa 6,6 MB, davon 6,0 MB Musik. Für
  Mobilfunkverbindungen ist das zu viel für einen Vorabdownload; Musik und Sprachsamples
  müssten nachgeladen werden, das Spiel ohne sie startklar sein.
- **Schrift:** Press Start 2P steht unter SIL OFL 1.1 und muss selbst gehostet werden, mit
  `Sources/GameCore/Fonts/OFL.txt` und Attribution. Kein Einbinden über ein fremdes
  Font-Netzwerk.
- **Impressum und Datenschutz** müssen im gerenderten Seiteninhalt erreichbar sein, nicht nur
  in einer ansonsten leeren `index.html`.
- **Audio-Start:** Mobile Browser starten Tonausgabe erst nach einer Nutzergeste. Der
  Audiokontext muss also an den Spielstart gekoppelt werden, nicht an das Laden der Seite.

## Empfohlenes Vorgehen, falls das Thema aufgegriffen wird

1. Zuerst `backlog.md` Punkt 2 abschließen. Ist die Simulation einmal sauber vom Szenengraph
   getrennt, schrumpft eine Webversion von „alles neu" auf „Renderer und Audio neu".
2. Danach ein kleiner Prototyp: Schiff, Asteroiden, Kollision und Touch-Steuerung auf
   Canvas2D, um Steuergefühl und Bildrate auf einem echten Mobilgerät zu messen, bevor
   Aufwand in die Breite geht.
3. Erst nach diesem Messergebnis über den vollen Umfang entscheiden.

Die vorhandene Touch-Steuerung des iOS-Ports (`ios/Exploids/TouchControlsView.swift`) ist als
Vorlage für Anordnung und Bediengefühl brauchbar, auch wenn der Code selbst nicht übernommen
werden kann.
