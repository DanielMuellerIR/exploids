#!/bin/bash
# Prueft die beiden fleetweiten Regeln vom 2026-08-03 an der QUELLE:
#
#   Regel 1  In /Applications gehoeren nur notarisierte Bundles. install.sh muss
#            das angeheftete Ticket pruefen, BEVOR es das erste Mal in das
#            Installationsverzeichnis schreibt.
#   Regel 2  Kein absoluter Pfad des Build-Rechners im ausgelieferten Bundle.
#            Deshalb kein `Bundle.module` in den Quellen — SwiftPM baut in dessen
#            erzeugten Zugriff den absoluten .build-Pfad des Build-Macs ein.
#
# Der Test liest nur Dateien. Er baut nichts, signiert nichts, notarisiert nichts
# und fasst /Applications nicht an — genau darum geht es: Ein Test, der zum Beleg
# den echten Installationsweg starten muesste, waere selbst die Gefahr.
#
# Aufruf:  bash Tests/fleet-rules.sh
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
ok()   { echo "  OK   $1"; }
bad()  { echo "  FAIL $1" >&2; fail=1; }

echo "1. Regel 1: install.sh verlangt das Ticket vor dem ersten Schreibzugriff"

INSTALL="install.sh"
if [ ! -f "$INSTALL" ]; then
    bad "install.sh fehlt"
else
    # Zeilennummern der entscheidenden Stellen. `grep -n` liefert "zeile:inhalt";
    # der Schnitt an ":" holt die Zeilennummer.
    first_line_of() { grep -n -- "$1" "$INSTALL" | head -1 | cut -d: -f1; }

    notarize_line="$(first_line_of 'notarize_app "$APP"')"
    # Erster Schreibzugriff im Installationsverzeichnis: das Anlegen/Leeren des
    # Staging-Pfads. Alles davor darf $APPS_DIR nicht beruehren.
    stage_line="$(first_line_of 'rm -rf "$STAGED" "$BACKUP"')"
    validate_line="$(first_line_of 'xcrun stapler validate "$STAGED"')"
    swap_line="$(first_line_of 'swap_app "$STAGED" "$DESTINATION"')"

    if [ -z "$notarize_line" ] || [ -z "$stage_line" ] || [ -z "$validate_line" ] || [ -z "$swap_line" ]; then
        bad "install.sh hat sich strukturell geaendert — Test veraltet, bitte anpassen"
    else
        [ "$notarize_line" -lt "$stage_line" ] \
            && ok "notarize_app laeuft vor dem ersten Schreiben in \$APPS_DIR" \
            || bad "notarize_app steht NACH dem ersten Schreiben in \$APPS_DIR"
        [ "$validate_line" -lt "$swap_line" ] \
            && ok "stapler validate am Staging-Pfad laeuft vor dem Austausch" \
            || bad "stapler validate steht NACH dem Austausch"
    fi

    # notarize_app selbst muss ad-hoc-Signaturen ablehnen und das Ticket anheften.
    grep -q "Signature=adhoc" notarize-lib.sh \
        && ok "notarize-lib.sh lehnt ad-hoc signierte Bundles ab" \
        || bad "notarize-lib.sh prueft nicht mehr auf ad-hoc-Signatur"
    grep -q "stapler staple" notarize-lib.sh \
        && ok "notarize-lib.sh heftet das Ticket an" \
        || bad "notarize-lib.sh heftet kein Ticket mehr an"
fi

echo
echo "2. Regel 2: keine absoluten Build-Mac-Pfade in den Quellen"

# Nur echter Code zaehlt. Reine Kommentarzeilen fliegen vorher raus — sonst
# schlaegt der Test an der Begruendung an, warum das Muster verboten ist.
# `grep -v` ohne Pipe-Verkettung mit `-q`: ein `grep -q` am Ende einer Pipeline
# schliesst die Leitung nach dem ersten Treffer, der Erzeuger stirbt an SIGPIPE
# und `pipefail` machte daraus faelschlich einen Fehlschlag. Deshalb wird das
# Ergebnis eingesammelt und danach geprueft.
code_matches() {   # $1 = erweiterter regulaerer Ausdruck
    grep -rnE --include='*.swift' "$1" Sources 2>/dev/null \
        | grep -vE '^[^:]+:[0-9]+: *//'
}

hits="$(code_matches 'Bundle\.module')"
if [ -n "$hits" ]; then
    printf '%s\n' "$hits" >&2
    bad "Bundle.module in Sources — nutzt stattdessen GameCoreResources.bundle"
else
    ok "kein Bundle.module in Sources"
fi

# `#filePath`/`#file` setzen den absoluten Quellpfad des Build-Rechners als
# Zeichenkette ins Binary (2026-08-03 im signierten Bundle nachgewiesen).
hits="$(code_matches '#filePath|#file[^P]')"
if [ -n "$hits" ]; then
    printf '%s\n' "$hits" >&2
    bad "#filePath/#file in Sources — der Quellpfad des Build-Macs landet im Binary"
else
    ok "kein #filePath/#file in Sources"
fi

# Und die direkte Probe: ein bereits gebautes Bundle darf keinen Pfad aus dem
# Heimatverzeichnis tragen. Fehlt das Bundle, wird nichts gebaut — der Test
# meldet das und bleibt gruen (Bauen ist Sache von build-app.sh).
BIN="Exploids.app/Contents/MacOS/exploids"
if [ -f "$BIN" ]; then
    home_paths="$(strings -a "$BIN" | grep -F "$HOME/")"
    if [ -n "$home_paths" ]; then
        printf '%s\n' "$home_paths" | sed 's/^/    /' >&2
        bad "gebautes Binary enthaelt Pfade aus dem Heimatverzeichnis"
    else
        ok "gebautes Binary enthaelt keine Pfade aus dem Heimatverzeichnis"
    fi
else
    echo "  --   $BIN nicht vorhanden; Binaerprobe uebersprungen (erst 'bash build-app.sh')"
fi

echo
if [ "$fail" = "0" ]; then
    echo "fleet-rules: OK"
else
    echo "fleet-rules: FEHLGESCHLAGEN" >&2
    exit 1
fi
