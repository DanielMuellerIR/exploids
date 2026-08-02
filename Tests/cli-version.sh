#!/bin/bash
# Integrationstest fuer den dokumentierten nackten SwiftPM-CLI-Pfad: Die
# Ausgabe muss exakt an der einzigen Produktversionsquelle VERSION haengen.
# Zusaetzlich abgesichert: der Quellpfad des Build-Rechners darf nicht im Binary
# landen, und eine woanders hin kopierte Binary darf nicht abstuerzen.
set -euo pipefail

cd "$(dirname "$0")/.."

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
if strings -a "$bin_dir/exploids" | grep -qF "$PWD/Sources"; then
    echo "FEHLER: Der Quellpfad $PWD/Sources steht als Zeichenkette im Binary." >&2
    exit 1
fi

# Nackte Binary ohne Checkout daneben: Sie darf keine Version erfinden und nicht
# abstuerzen, sondern meldet ehrlich "unknown".
relocated="$(mktemp -d)"
cp "$bin_dir/exploids" "$relocated/exploids"
moved="$("$relocated/exploids" --version)"
rm -rf "$relocated"
if [[ "$moved" != "Exploids version unknown" ]]; then
    echo "FEHLER: verschobene Binary meldet '$moved', erwartet 'Exploids version unknown'." >&2
    exit 1
fi

echo "cli-version: OK ($expected)"
