#!/bin/bash
# Integrationstest fuer den dokumentierten nackten SwiftPM-CLI-Pfad: Die
# Ausgabe muss exakt an der einzigen Produktversionsquelle VERSION haengen.
set -euo pipefail

cd "$(dirname "$0")/.."

expected="$(tr -d '[:space:]' < VERSION)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" swift build --product exploids
bin_dir="$(DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" swift build --show-bin-path)"
actual="$("$bin_dir/exploids" --version)"

if [[ "$actual" != "Exploids version $expected" ]]; then
    echo "FEHLER: CLI meldet '$actual', VERSION erwartet '$expected'." >&2
    exit 1
fi

echo "cli-version: OK ($expected)"
