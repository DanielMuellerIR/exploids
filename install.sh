#!/bin/bash
# install.sh — Exploids notarisiert nach /Applications installieren.
#
# Die drei Einstiegspunkte des Projekts trennen bewusst:
#   bash build-app.sh   baut die App im Projektverzeichnis, mehr nicht
#   ./install.sh        baut, signiert, notarisiert und installiert nach /Applications
#   ./release.sh        baut, signiert, notarisiert und packt das DMG — installiert nie
#
# Warum notarisiert: In /Applications gehören nur Bundles mit angeheftetem
# Notary-Ticket, die Gatekeeper akzeptiert. Ein unsignierter Testbuild bleibt im
# Projektverzeichnis.
#
# Voraussetzungen:
#   - "Developer ID Application"-Zertifikat im Schlüsselbund
#   - NOTARY_PROFILE oder `git config exploids.notaryProfile`
#
# Aufruf:  ./install.sh
# Letzte Zeile bei Erfolg: INSTALL OK: /Applications/Exploids.app (<version>)
set -euo pipefail
cd "$(dirname "$0")"
source ./notarize-lib.sh

require_notary_profile

APP="Exploids.app"
# Ziel ist /Applications. Die Variable existiert nur, damit sich der Austausch-
# und Rücksetzpfad in einem Wegwerf-Verzeichnis testen lässt (Tests/install-swap.sh);
# im normalen Betrieb wird sie nie gesetzt.
APPS_DIR="${EXPLOIDS_APPS_DIR:-/Applications}"
DESTINATION="$APPS_DIR/$APP"
VERSION="$(tr -d '[:space:]' < VERSION)"

echo "=== 1/4 App bauen ==="
bash build-app.sh

echo "=== 2/4 Signieren ==="
sign_app "$APP"

echo "=== 3/4 Notarisieren ==="
notarize_app "$APP"

echo "=== 4/4 Installieren ==="
# Erst neben das Ziel legen, DORT vollständig prüfen, dann atomar austauschen:
# ein Abbruch mittendrin darf keine halb ersetzte App in /Applications
# hinterlassen, und eine von Gatekeeper abgelehnte App darf die vorherige,
# funktionierende Installation nicht verdrängen. Die alte App bleibt bis nach der
# Abschlussprüfung am Ziel als Backup liegen und wird im Fehlerfall zurückgeholt.
STAGED="$APPS_DIR/.$APP.install-$$"
BACKUP_NAME=".$APP.backup-$$"
BACKUP="$APPS_DIR/$BACKUP_NAME"
rm -rf "$STAGED" "$BACKUP"
trap 'rm -rf "$STAGED" "$BACKUP"' EXIT
ditto "$APP" "$STAGED"

# Prüfen VOR dem Austausch. Scheitert hier etwas, bleibt das Ziel unangetastet.
echo "--- Vorabprüfung am Staging-Pfad ---"
xcrun stapler validate "$STAGED"
spctl -a -t exec -vv "$STAGED" 2>&1 | tail -2

pkill -x exploids 2>/dev/null || true

# Atomarer Austausch. $3 = Name des Backups (leer: keins) — das Backup landet als
# Geschwisterdatei neben dem Ziel und überlebt den Austausch nur mit
# .withoutDeletingBackupItem; ohne die Option löscht replaceItemAt es sofort.
swap_app() {   # $1 = Quelle, $2 = Ziel, $3 = Backup-Name oder ""
    /usr/bin/swift - "$1" "$2" "$3" <<'SWIFT'
import Foundation

let fileManager = FileManager.default
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
let backupName = CommandLine.arguments[3]
if fileManager.fileExists(atPath: destination.path) {
    var options: FileManager.ItemReplacementOptions = [.usingNewMetadataOnly]
    if !backupName.isEmpty { options.insert(.withoutDeletingBackupItem) }
    _ = try fileManager.replaceItemAt(
        destination,
        withItemAt: source,
        backupItemName: backupName.isEmpty ? nil : backupName,
        options: options
    )
} else {
    try fileManager.moveItem(at: source, to: destination)
}
SWIFT
}

swap_app "$STAGED" "$DESTINATION" "$BACKUP_NAME"

# Nach dem Austausch am echten Ziel erneut prüfen: erst dann ist die Installation
# belegt. Beide Prüfungen werden einzeln bewertet, damit ein Fehler nicht über
# set -e abbricht, bevor zurückgesetzt wurde.
install_ok=1
xcrun stapler validate "$DESTINATION" || install_ok=0
spctl -a -t exec -vv "$DESTINATION" 2>&1 | tail -2 || install_ok=0

if [ "$install_ok" != "1" ]; then
    echo "FEHLER: Die installierte App besteht die Abschlussprüfung nicht." >&2
    if [ -d "$BACKUP" ]; then
        swap_app "$BACKUP" "$DESTINATION" "" || {
            trap - EXIT
            rm -rf "$STAGED"
            echo "  ACHTUNG: Rücksetzen fehlgeschlagen. Die vorherige App liegt noch" >&2
            echo "  unter $BACKUP und muss von Hand nach $DESTINATION zurück." >&2
            exit 1
        }
        echo "  Zurückgesetzt: $DESTINATION ist wieder die vorherige Installation." >&2
    else
        rm -rf "$DESTINATION"
        echo "  Es gab keine vorherige Installation; $DESTINATION wurde entfernt." >&2
    fi
    exit 1
fi

rm -rf "$STAGED" "$BACKUP"
trap - EXIT

echo "INSTALL OK: $DESTINATION ($VERSION)"
