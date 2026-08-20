#!/bin/bash
# Integrationstest fuer den dokumentierten nackten SwiftPM-CLI-Pfad: Die
# Ausgabe muss exakt an der einzigen Produktversionsquelle VERSION haengen.
# Zusaetzlich abgesichert: der Quellpfad des Build-Rechners darf nicht im Binary
# landen, und eine woanders hin kopierte Binary darf nicht abstuerzen.
set -euo pipefail

cd "$(dirname "$0")/.."
source Tests/shell-test-lib.sh

# Xcode-Toolchain nur setzen, wenn es sie an dieser Stelle gibt; auf einem
# CI-Runner ohne /Applications/Xcode.app gilt die Toolchain aus dem PATH.
default_dev_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [ -d "$default_dev_dir" ]; then
    export DEVELOPER_DIR="$default_dev_dir"
fi

expected="$(tr -d '[:space:]' < VERSION)"
swift build --product exploids
bin_dir="$(swift build --show-bin-path)"
actual="$("$bin_dir/exploids" --version)"

if [[ "$actual" != "Exploids version $expected" ]]; then
    echo "FEHLER: CLI meldet '$actual', VERSION erwartet '$expected'." >&2
    exit 1
fi

# Die Versionssuche startet beim Ort der Binary, nicht beim Quellpfad. Waere sie
# wieder an #filePath geknuepft, stuende der absolute Quellpfad des Build-Rechners
# als Zeichenkette im verteilten Binary (2026-08-03 im Release-Bundle belegt).
#
# `binary_hits` aus shell-test-lib.sh nutzt `strings -`, damit die Probe auch
# __LINKEDIT und damit die frueher ausgelieferten Build-Mac-Pfade sieht.

# Geprueft wird eine gestrippte Kopie, nicht die frisch gebaute Datei selbst.
# Grund: `swift build` legt in jede Binary eine Debug-Map — je uebersetzter
# Quelldatei einen Eintrag mit deren Verzeichnis und dem Pfad ihrer .o-Datei auf
# DIESEM Mac. Die gehoert zum Bauen, nicht zum Ausliefern; build-app.sh nimmt sie
# vor dem Signieren mit `strip -S` heraus. Ohne denselben Schritt pruefte der Test
# einen Zustand, den niemand je bekommt, und waere dauerhaft rot.
# Ein per #filePath eingebauter Pfad ist dagegen eine gewoehnliche
# Zeichenkettenkonstante und ueberlebt `strip -S` — am 2026-08-05 an einem eigens
# dafuer gebauten Testbinary nachgemessen. Die Probe faengt ihn also weiterhin.
probe="$(mktemp -d)"
trap 'rm -rf "$probe"' EXIT
cp "$bin_dir/exploids" "$probe/exploids"
# Die Kopie wird nie ausgefuehrt. Diagnostik auf stderr wird unterdrueckt, ein
# echter `strip`-Fehler schlaegt weiter ueber den Exit-Code durch.
strip -S "$probe/exploids" 2>/dev/null

# Gegenprobe zuerst: __mh_execute_header bleibt auch bei Chained Fixups und nach
# `strip -S` erhalten. Sieht die Probe es nicht, waere jeder Freispruch wertlos.
if ! binary_probe_is_visible "$probe/exploids"; then
    echo "FEHLER: Die Binaerprobe findet nicht einmal $MACHO_PROBE_SYMBOL — sie ist blind." >&2
    exit 1
fi
if [ -n "$(binary_hits "$probe/exploids" "$PWD/Sources")" ]; then
    echo "FEHLER: Der Quellpfad $PWD/Sources steht als Zeichenkette im Binary." >&2
    binary_hits "$probe/exploids" "$PWD/Sources" | sed 's/^/    /' >&2
    exit 1
fi
rm -rf "$probe"
trap - EXIT

# Nackte Binary ohne Checkout daneben: Sie darf keine Version erfinden und nicht
# abstuerzen, sondern meldet ehrlich "unknown".
relocated="$(mktemp -d)"
# Aufraeumen sofort absichern: Scheitert `cp` oder der Aufruf der kopierten
# Binary, beendet `set -e` den Test an Ort und Stelle. Ohne diesen Trap bliebe das
# Verzeichnis samt Kopie im Temp-Bereich liegen.
trap 'rm -rf "$relocated"' EXIT
cp "$bin_dir/exploids" "$relocated/exploids"
moved="$("$relocated/exploids" --version)"
rm -rf "$relocated"
trap - EXIT
if [[ "$moved" != "Exploids version unknown" ]]; then
    echo "FEHLER: verschobene Binary meldet '$moved', erwartet 'Exploids version unknown'." >&2
    exit 1
fi

echo "cli-version: OK ($expected)"
