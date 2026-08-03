#!/bin/bash
# Sammelstelle fuer die Shell-Integrationstests des Projekts.
#
# `swift test` fuehrt nur den in Package.swift registrierten Test-Target
# Tests/GameCoreTests aus. Die Skripte hier pruefen, was daneben liegt: den
# CLI-Versionspfad und die Austausch- bzw. Aufraeumlogik der Build-Skripte.
# Ohne diesen Sammel-Aufruf hatte Tests/cli-version.sh gar keinen Aufrufer und
# lief bei keinem normalen Testlauf mit.
#
# Aufruf:  bash Tests/run-shell-tests.sh
# Exit 0 = alle gruen. Es wird nichts signiert, notarisiert oder nach
# /Applications geschrieben; die Tests arbeiten in Temp-Verzeichnissen.
set -uo pipefail
cd "$(dirname "$0")/.."

tests="Tests/cli-version.sh Tests/install-swap.sh Tests/notarize-cleanup.sh Tests/fleet-rules.sh"

failed=""
count=0
for t in $tests; do
    count=$((count + 1))
    echo "=== $t ==="
    bash "$t" || failed="$failed $t"
    echo
done

if [ -z "$failed" ]; then
    echo "Shell-Tests: alle gruen ($count)"
else
    echo "Shell-Tests: FEHLGESCHLAGEN ->$failed" >&2
    exit 1
fi
