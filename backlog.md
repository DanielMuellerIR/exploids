# Aktiver Backlog

Aktuell gibt es keine beauftragte offene Umsetzung oder Geräteabnahme.
Die iOS-App mit Touch-Steuerung ist vorhanden; die erfolgreiche iPhone-Abnahme
vom 2026-10-01 ist in `CHANGELOG.md` unter 0.14.12 dokumentiert.

## Zurückgestellte Arbeiten

- `stepSimulation`/Kollision nur als separaten Hochrisiko-Refactor aufteilen,
  wenn konkret beauftragt; nach jedem Schnitt Golden Replay bitgenau prüfen.
- GameController im iOS-Host später separat beauftragen. Vorrang hat die
  vorhandene Touch-Steuerung.
- Balance und möglichen Fixed-Timestep-Mikroruckler erst bei einem
  reproduzierbaren Bericht messen; den Fixed-Timestep bis dahin beibehalten.
- Scroll-Modus bleibt eine spätere optionale Idee für einen eigenständigen
  dritten Modus.
- `--version` der nackten SwiftPM-Binary meldet außerhalb eines Checkouts
  `unknown`. Versionseinbettung nur bei geplanter separater Verteilung dieser
  Binary angehen; das App-Bundle trägt die Version bereits in der Info.plist.

## Aktuelle Entscheidungen

- Die vorhandenen Musiktracks bleiben. Eine App-Store-/kommerzielle
  Distribution ist derzeit nicht geplant. Vor einer solchen Distribution
  müssen die Free-Plan-Tracks durch rechtlich passende Musik ersetzt werden.
- Das vorhandene Promo-GIF wird weiterverwendet. Ein neuer Promo-Export ist
  derzeit nicht beauftragt.

Veraltete Versions-/Push-Todos und bereits veröffentlichte Replay-/Demo-Arbeit nicht
als offen übernehmen; vor jedem Release den aktuellen Git-/Versionsstand neu prüfen.
