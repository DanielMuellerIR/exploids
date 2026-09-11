#!/bin/bash
# build.sh — einheitlicher Einstieg zum Bauen (Daniels Regel vom 2026-09-11:
# jedes Projekt hat build.sh, install.sh und release.sh an der Repo-Wurzel).
#
# Baut nur: keine Signatur mit Developer ID, keine Notarisierung, keine
# Installation. Die eigentliche Arbeit macht build-app.sh, das seinen Namen
# wegen Tests und Doku behält; Argumente gehen unverändert durch, der
# Exit-Code ist der von build-app.sh (exec ersetzt diesen Prozess).
#
# Aufruf:  ./build.sh
# Letzte Zeile bei Erfolg: BUILD OK: <pfad>/Exploids.app
set -euo pipefail
cd "$(dirname "$0")"
exec bash build-app.sh "$@"
