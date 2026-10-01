# Aktiver Backlog

1. `stepSimulation`/Kollision nur als separaten Hochrisiko-Refactor aufteilen; nach
   jedem Schnitt Golden Replay bitgenau verifizieren.
2. iOS-Port: Touch-/GameController-Gefühl auf Gerät, App-Icon/Launch-Screen/
   Asset-Catalog und Lifecycle polieren.
3. Vor App-Store- oder kommerzieller Distribution die zwei Free-Plan-Musiktracks
   durch rechtlich saubere eigene/CC0/lizenzierte Musik ersetzen.
4. Balance und möglichen Fixed-Timestep-Mikroruckler erst reproduzierbar messen.
5. Kuratiertes Promo-GIF aus einem guten Replay auswählen/rendern.
6. Scroll-Modus später als eigenständigen dritten Modus planen.
7. `--version` der nackten SwiftPM-Binary meldet außerhalb eines Checkouts
   ehrlich `unknown`. Wer das ändern will, muss die Version beim Bauen einbetten
   (erzeugte Konstante oder SwiftPM-Plugin); das App-Bundle ist über die
   Info.plist bereits abgedeckt. Nur angehen, wenn die nackte Binary wirklich
   verteilt werden soll.

Veraltete Versions-/Push-Todos und bereits veröffentlichte Replay-/Demo-Arbeit nicht
als offen übernehmen; vor jedem Release den aktuellen Git-/Versionsstand neu prüfen.

## Abgleich 2026-10-01

- Separat geplant: Simulationsextraktion nur mit unabhängigem
  Golden Replay und einem konkreten Refactor-Auftrag. Für den Kollisionsfix war
  keine Extraktion notwendig.
- Geräteabhängig offen: Touch-hold/release, gleichzeitige Aktionen und Lifecycle
  auf einem iPhone abnehmen. Icon und Asset-Catalog sind vorhanden; der
  Launch-Screen wird generiert. GameController ist im iOS-Host noch nicht
  implementiert und braucht einen eigenen bestätigten Umfang.
- Entscheidung offen: konkrete rechtlich saubere Ersatzmusik, Auswahl des
  Promo-Replays und Beauftragung eines dritten Scroll-Modus.
- Beobachtung: Balance/120-Hz-Gefühl und Mikroruckler brauchen einen
  reproduzierbaren Bericht; ohne diesen bleibt der Fixed-Timestep unverändert.
- Optional: Versionseinbettung für die nackte Binary nur bei geplanter Verteilung
  dieses Artefakts; das App-Bundle trägt die Version bereits in der Info.plist.
