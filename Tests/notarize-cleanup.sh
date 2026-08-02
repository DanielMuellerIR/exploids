#!/bin/bash
# Regressionstest fuer notarize_app aus notarize-lib.sh: Das Temp-Verzeichnis
# (es enthaelt ein komplettes App-ZIP) darf auf keinem Weg stehenbleiben, und die
# Vorpruefungen duerfen es gar nicht erst anlegen.
#
# Es wird nichts wirklich signiert oder notarisiert: codesign, ditto, xcrun und
# spctl sind Shell-Attrappen (Funktionen gewinnen gegen den PATH). Auch mktemp
# ist eine Attrappe: Sie legt das Verzeichnis in einem Wegwerf-Ordner an und
# notiert den Pfad, damit der Test hinterher pruefen kann, ob genau dieses
# Verzeichnis wieder weg ist. (Ueber TMPDIR geht das nicht — `mktemp -d` ohne
# Vorlage ignoriert TMPDIR auf macOS und legt immer unter /var/folders an.)
set -uo pipefail

cd "$(dirname "$0")/.."
LIB="$PWD/notarize-lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
check() { # $1=Beschreibung $2=erwartet $3=tatsaechlich
    if [ "$2" = "$3" ]; then
        echo "  OK   $1"
    else
        echo "  FAIL $1: erwartet '$2', war '$3'" >&2
        fail=1
    fi
}

# $1 = Fallname
# $2 = Attrappen-Verhalten: ok | codesign-invalid | adhoc | ditto | notarytool |
#      stapler | spctl
run_case() {
    local name="$1" mode="$2"
    local dir="$WORK/$name"
    mkdir -p "$dir/tmp"
    cat > "$dir/runner.sh" <<RUNNER
set -euo pipefail
MODE="$mode"
TMP_ROOT="$dir/tmp"
HANDED_OUT="$dir/handed-out.txt"

mktemp() {
    # nur die im Skript benutzte Form 'mktemp -d' nachbilden
    local d="\$TMP_ROOT/mktemp-\$RANDOM\$RANDOM"
    mkdir -p "\$d"
    echo "\$d" >> "\$HANDED_OUT"
    echo "\$d"
}

codesign() {
    if [ "\$1" = "--verify" ]; then
        [ "\$MODE" = "codesign-invalid" ] && return 1
        return 0
    fi
    # codesign -dvv: Signaturtyp melden
    [ "\$MODE" = "adhoc" ] && echo "Signature=adhoc" || echo "Authority=Developer ID Application: Attrappe"
    return 0
}
ditto() {
    [ "\$MODE" = "ditto" ] && return 1
    # letztes Argument ist das Ziel-ZIP
    local out="\${@: -1}"
    echo "zip-attrappe" > "\$out"
    return 0
}
xcrun() {
    case "\$1:\$2" in
        notarytool:submit) [ "\$MODE" = "notarytool" ] && return 1 ;;
        stapler:staple)    [ "\$MODE" = "stapler" ] && return 1 ;;
    esac
    echo "xcrun \$1 \$2 (Attrappe)"
    return 0
}
spctl() {
    [ "\$MODE" = "spctl" ] && return 1
    echo "accepted (Attrappe)"
    return 0
}

source "$LIB"
NOTARY_PROFILE="attrappe"
notarize_app "Exploids.app"
RUNNER
    bash "$dir/runner.sh" >"$dir/out.log" 2>&1
    CASE_RC=$?
    # Wie viele der ausgegebenen Verzeichnisse existieren noch?
    CASE_LEFT=0
    CASE_HANDED=0
    if [ -f "$dir/handed-out.txt" ]; then
        while read -r d; do
            CASE_HANDED=$((CASE_HANDED + 1))
            [ -d "$d" ] && CASE_LEFT=$((CASE_LEFT + 1))
        done < "$dir/handed-out.txt"
    fi
}

echo "1. Erfolgspfad"
run_case erfolg ok
check "Exit-Code 0" 0 "$CASE_RC"
check "genau ein Temp-Verzeichnis angelegt" 1 "$CASE_HANDED"
check "kein Temp-Verzeichnis uebrig" 0 "$CASE_LEFT"

echo "2. Vorpruefung: Signatur ungueltig"
run_case unsigniert codesign-invalid
check "Exit-Code 1" 1 "$CASE_RC"
check "gar kein Temp-Verzeichnis angelegt" 0 "$CASE_HANDED"

echo "3. Vorpruefung: nur ad-hoc signiert"
run_case adhoc adhoc
check "Exit-Code 1" 1 "$CASE_RC"
check "gar kein Temp-Verzeichnis angelegt" 0 "$CASE_HANDED"

echo "4. ditto scheitert"
run_case ditto_rot ditto
check "Exit-Code ungleich 0" "ungleich0" "$([ "$CASE_RC" != "0" ] && echo ungleich0 || echo 0)"
check "genau ein Temp-Verzeichnis angelegt" 1 "$CASE_HANDED"
check "kein Temp-Verzeichnis uebrig" 0 "$CASE_LEFT"

echo "5. notarytool submit scheitert"
run_case notarytool_rot notarytool
check "Exit-Code ungleich 0" "ungleich0" "$([ "$CASE_RC" != "0" ] && echo ungleich0 || echo 0)"
check "genau ein Temp-Verzeichnis angelegt" 1 "$CASE_HANDED"
check "kein Temp-Verzeichnis uebrig" 0 "$CASE_LEFT"

echo "6. stapler staple scheitert"
run_case stapler_rot stapler
check "Exit-Code ungleich 0" "ungleich0" "$([ "$CASE_RC" != "0" ] && echo ungleich0 || echo 0)"
check "genau ein Temp-Verzeichnis angelegt" 1 "$CASE_HANDED"
check "kein Temp-Verzeichnis uebrig" 0 "$CASE_LEFT"

echo "7. spctl lehnt ab"
run_case spctl_rot spctl
check "Exit-Code ungleich 0" "ungleich0" "$([ "$CASE_RC" != "0" ] && echo ungleich0 || echo 0)"
check "genau ein Temp-Verzeichnis angelegt" 1 "$CASE_HANDED"
check "kein Temp-Verzeichnis uebrig" 0 "$CASE_LEFT"

echo
if [ "$fail" = "0" ]; then
    echo "notarize-cleanup: OK"
else
    echo "notarize-cleanup: FEHLGESCHLAGEN" >&2
    exit 1
fi
