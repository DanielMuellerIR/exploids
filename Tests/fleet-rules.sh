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
source Tests/shell-test-lib.sh

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
    first_line_of() {   # $1 = Datei, $2 = fester Text
        grep -nF -- "$2" "$1" | head -1 | cut -d: -f1
    }

    notarize_line="$(first_line_of "$INSTALL" 'notarize_app "$APP"')"
    # Erster Schreibzugriff im Installationsverzeichnis: das Anlegen/Leeren des
    # Staging-Pfads. Alles davor darf $APPS_DIR nicht beruehren.
    stage_line="$(first_line_of "$INSTALL" 'rm -rf "$STAGED" "$BACKUP"')"
    validate_line="$(first_line_of "$INSTALL" 'xcrun stapler validate "$STAGED"')"
    swap_line="$(first_line_of "$INSTALL" 'swap_app "$STAGED" "$DESTINATION"')"

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
    grep -rnE --include='*.swift' "$1" Sources ios 2>/dev/null \
        | grep -vE '^[^:]+:[0-9]+: *//'
}

hits="$(code_matches 'Bundle\.module')"
if [ -n "$hits" ]; then
    printf '%s\n' "$hits" >&2
    bad "Bundle.module im Swift-Quellcode — nutzt stattdessen GameCoreResources.bundle"
else
    ok "kein Bundle.module in Sources oder ios"
fi

# `#filePath`/`#file` setzen den absoluten Quellpfad des Build-Rechners als
# Zeichenkette ins Binary (2026-08-03 im signierten Bundle nachgewiesen).
file_macro_pattern='#file(Path)?([^A-Za-z0-9_]|$)'
macro_probe="$(printf '#file\n#filePath\n#fileID\n' | grep -E "$file_macro_pattern")"
if [ "$macro_probe" != $'#file\n#filePath' ]; then
    bad "interne #file-Regel erkennt Zeilenende/#filePath nicht eindeutig"
fi
hits="$(code_matches "$file_macro_pattern")"
if [ -n "$hits" ]; then
    printf '%s\n' "$hits" >&2
    bad "#filePath/#file im Swift-Quellcode — der Quellpfad des Build-Macs landet im Binary"
else
    ok "kein #filePath/#file in Sources oder ios"
fi

# Die Debug-Map ist der zweite Weg, auf dem Build-Mac-Pfade ins Bundle kommen:
# `swift build` legt fuer jede uebersetzte Quelldatei einen Eintrag mit dem Pfad
# ihrer .o-Datei ab (14 Stueck, am 2026-08-04 in der ausgelieferten App gefunden).
# build-app.sh nimmt sie mit `strip -S` heraus. Danach signiert es das gesamte
# Bundle, damit CodeResources und der Bundle-Identifier abgesichert sind. Faellt
# das Strippen weg, waeren die Pfade sofort wieder im Bundle.
# Nur echte Befehlszeilen zaehlen, keine Kommentare: build-app.sh erklaert `strip -S`
# direkt darueber im Fliesstext, und dieser Satz allein entfernt kein einziges
# Symbol. Deshalb muss das Muster am Zeilenanfang stehen.
strip_lines="$(grep -nE '^strip -S ' build-app.sh 2>/dev/null)"
sign_lines="$(grep -nE '^codesign --force --sign -' build-app.sh 2>/dev/null)"
strip_count="$(printf '%s\n' "$strip_lines" | grep -c .)"
sign_count="$(printf '%s\n' "$sign_lines" | grep -c .)"
strip_line="$(printf '%s\n' "$strip_lines" | head -1 | cut -d: -f1)"
sign_line="$(printf '%s\n' "$sign_lines" | head -1 | cut -d: -f1)"
if [ "$strip_count" != "1" ]; then
    bad "build-app.sh braucht genau einen echten 'strip -S'-Befehl, gefunden: $strip_count"
elif [ "$sign_count" != "1" ]; then
    bad "build-app.sh braucht genau eine ad-hoc-Bundle-Signatur, gefunden: $sign_count"
elif [ "$strip_line" -lt "$sign_line" ]; then
    ok "build-app.sh entfernt die Debug-Symbole vor dem Signieren"
else
    bad "'strip -S' steht in build-app.sh NACH dem Signieren"
fi

# Und die direkte Probe: ein bereits gebautes Bundle darf keinen Pfad aus dem
# Heimatverzeichnis tragen. Fehlt das Bundle, wird nichts gebaut — der Test
# meldet das und bleibt gruen (Bauen ist Sache von build-app.sh).

# `binary_hits` aus shell-test-lib.sh liest jedes Byte und damit auch __LINKEDIT.

BIN="Exploids.app/Contents/MacOS/exploids"
if [ -f "$BIN" ]; then
    # Erst die Gegenprobe: __mh_execute_header bleibt auch bei Chained Fixups und
    # nach `strip -S` erhalten. Ohne Kontrollfund ist jede gruene Meldung wertlos.
    if ! binary_probe_is_visible "$BIN"; then
        bad "Binaerprobe findet nicht einmal $MACHO_PROBE_SYMBOL in $BIN — sie ist blind"
    else
        ok "Binaerprobe liest alle Bytes (Kontrollfund $MACHO_PROBE_SYMBOL)"
        home_paths="$(binary_hits "$BIN" "$HOME/")"
        if [ -n "$home_paths" ]; then
            printf '%s\n' "$home_paths" | sed 's/^/    /' >&2
            bad "gebautes Binary enthaelt Pfade aus dem Heimatverzeichnis"
        else
            ok "gebautes Binary enthaelt keine Pfade aus dem Heimatverzeichnis"
        fi
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
