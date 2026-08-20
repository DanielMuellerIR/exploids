#!/bin/bash
# Regressionstest fuer den Austauschschritt aus install.sh (Schritt 4/4).
#
# Geprueft wird die Reihenfolge "erst pruefen, dann ersetzen" und das
# Zuruecksetzen: Eine App, die die Abschlusspruefung am Ziel nicht besteht, darf
# die vorherige, funktionierende Installation nicht verdraengen.
#
# Der Test fuehrt install.sh NICHT aus (das wuerde bauen, signieren, notarisieren
# und nach /Applications schreiben). Stattdessen wird nur der letzte Abschnitt aus
# install.sh herausgeschnitten und in einem Wegwerf-Verzeichnis ausgefuehrt:
#   - EXPLOIDS_APPS_DIR zeigt auf ein Temp-Verzeichnis statt /Applications
#   - xcrun/spctl/pkill sind Attrappen, die je nach Fall Erfolg oder Fehler melden
# So laeuft der echte Code aus install.sh, ohne Signatur oder Systemzugriff.
set -uo pipefail

cd "$(dirname "$0")/.."
source Tests/shell-test-lib.sh
INSTALL_SH="${EXPLOIDS_INSTALL_SCRIPT:-$PWD/install.sh}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Die Zielpfad-Zuweisungen und den Abschnitt ab "=== 4/4 Installieren ==="
# getrennt herausschneiden. Der Runner prueft den Zielpfad, bevor der Abschnitt
# irgendetwas schreibt; ein Tippfehler bei EXPLOIDS_APPS_DIR kann deshalb nie
# versehentlich /Applications erreichen.
PATHS_SECTION="$WORK/install-paths.sh"
SECTION="$WORK/install-step.sh"
extract_block "$INSTALL_SH" '^APPS_DIR=' '^DESTINATION=' > "$PATHS_SECTION"
extract_from "$INSTALL_SH" '^echo "=== 4/4 Installieren ==="' > "$SECTION"
if [ ! -s "$PATHS_SECTION" ] || ! grep -q 'swap_app' "$SECTION"; then
    echo "FEHLER: Austauschabschnitt in install.sh nicht gefunden — Test veraltet." >&2
    exit 1
fi

fail=0
check() { # $1=Beschreibung $2=erwartet $3=tatsaechlich
    if [ "$2" = "$3" ]; then
        echo "  OK   $1"
    else
        echo "  FAIL $1: erwartet '$2', war '$3'" >&2
        fail=1
    fi
}

# Baut einen Testfall auf: frisches Ziel-Verzeichnis, frische Quell-App.
# $1 = Name des Falls, $2 = Inhalt der alten Installation ("" = keine vorhanden)
setup_case() {
    local name="$1" old="$2"
    CASE_DIR="$WORK/$name"
    rm -rf "$CASE_DIR"
    mkdir -p "$CASE_DIR/apps" "$CASE_DIR/src/Exploids.app/Contents/MacOS"
    echo "neu" > "$CASE_DIR/src/Exploids.app/Contents/MacOS/marker"
    if [ -n "$old" ]; then
        mkdir -p "$CASE_DIR/apps/Exploids.app/Contents/MacOS"
        echo "$old" > "$CASE_DIR/apps/Exploids.app/Contents/MacOS/marker"
    fi
}

# Fuehrt den herausgeschnittenen Abschnitt mit Attrappen aus.
# $1 = Fall-Verzeichnis, $2 = Pfadmuster, bei dem die Pruefung fehlschlagen soll
#      ("" = alles gruen; "install-" = Vorabpruefung rot; "apps/Exploids.app" = Ziel rot)
# $3 = optional das einzige Werkzeug, das rot werden soll: "xcrun" oder "spctl".
#      Leer = beide Attrappen reagieren auf das Muster.
run_step() {
    local case_dir="$1" fail_pattern="$2" fail_tool="${3:-}"
    cat > "$case_dir/runner.sh" <<RUNNER
set -euo pipefail
cd "$case_dir/src"
APP="Exploids.app"
EXPLOIDS_APPS_DIR="$case_dir/apps"
source "$PATHS_SECTION"
if [ "\$APPS_DIR" != "\$EXPLOIDS_APPS_DIR" ] || [ "\$DESTINATION" != "\$EXPLOIDS_APPS_DIR/\$APP" ]; then
    echo "FEHLER: install.sh hat EXPLOIDS_APPS_DIR nicht als Ziel uebernommen." >&2
    exit 90
fi
VERSION="0.0.0-test"
FAIL_PATTERN="$fail_pattern"
FAIL_TOOL="$fail_tool"

# Attrappen: echte Signatur-/Gatekeeper-Werkzeuge sind hier weder noetig noch
# moeglich. Shell-Funktionen gewinnen gegen den PATH, der Abschnitt ruft sie
# unveraendert auf.
xcrun() {   # erwartet: xcrun stapler validate <pfad>  -> Pfad ist Argument 3
    local target="\${3:-}"
    if [ "\$FAIL_TOOL" != "spctl" ] && [ -n "\$FAIL_PATTERN" ] && [[ "\$target" == *"\$FAIL_PATTERN"* ]]; then
        echo "stapler: Ticket fehlt (Attrappe)" >&2
        return 1
    fi
    echo "stapler: gueltig (Attrappe)"
}
# Der echte Aufruf lautet: spctl -a -t exec -vv <pfad>. Der Pfad ist damit
# Argument 5, nicht 4 — Argument 4 ist immer "-vv". Solange die Attrappe \$4 las,
# passte das Fehlermuster nie und alle roten Faelle kamen allein von der
# xcrun-Attrappe; ein kaputter spctl-Pfad waere unbemerkt geblieben.
spctl() {
    local target="\${5:-}"
    if [ "\$FAIL_TOOL" != "xcrun" ] && [ -n "\$FAIL_PATTERN" ] && [[ "\$target" == *"\$FAIL_PATTERN"* ]]; then
        echo "spctl: rejected (Attrappe)" >&2
        return 1
    fi
    echo "accepted (Attrappe)"
}
pkill() { return 0; }

source "$SECTION"
RUNNER
    bash "$case_dir/runner.sh" >"$case_dir/out.log" 2>&1
}

marker_of() { cat "$1/Contents/MacOS/marker" 2>/dev/null || echo "<fehlt>"; }
leftovers()  { find "$1" -maxdepth 1 -name '.Exploids.app.*' | wc -l | tr -d ' '; }

echo "1. Erfolgsfall mit vorhandener Vorgaengerversion"
setup_case erfolg alt
run_step "$CASE_DIR" ""; rc=$?
check "Exit-Code 0" 0 "$rc"
check "Ziel traegt die neue App" "neu" "$(marker_of "$CASE_DIR/apps/Exploids.app")"
check "keine Staging-/Backup-Reste" "0" "$(leftovers "$CASE_DIR/apps")"

echo "2. Abschlusspruefung am Ziel schlaegt fehl -> Rueckkehr zur alten App"
setup_case rollback alt
run_step "$CASE_DIR" "apps/Exploids.app"; rc=$?
check "Exit-Code 1" 1 "$rc"
check "Ziel traegt wieder die alte App" "alt" "$(marker_of "$CASE_DIR/apps/Exploids.app")"
check "keine Staging-/Backup-Reste" "0" "$(leftovers "$CASE_DIR/apps")"

echo "3. Vorabpruefung am Staging-Pfad schlaegt fehl -> Ziel unberuehrt"
setup_case vorab alt
run_step "$CASE_DIR" "install-"; rc=$?
check "Exit-Code 1" 1 "$rc"
check "Ziel traegt unveraendert die alte App" "alt" "$(marker_of "$CASE_DIR/apps/Exploids.app")"
check "keine Staging-/Backup-Reste" "0" "$(leftovers "$CASE_DIR/apps")"

echo "4. Erstinstallation ohne Vorgaenger, Abschlusspruefung schlaegt fehl"
setup_case neuinstall_rot ""
run_step "$CASE_DIR" "apps/Exploids.app"; rc=$?
check "Exit-Code 1" 1 "$rc"
check "kein halbfertiges Ziel zurueckgelassen" "<fehlt>" "$(marker_of "$CASE_DIR/apps/Exploids.app")"
check "keine Staging-/Backup-Reste" "0" "$(leftovers "$CASE_DIR/apps")"

echo "5. Erstinstallation ohne Vorgaenger, alles gruen"
setup_case neuinstall_gruen ""
run_step "$CASE_DIR" ""; rc=$?
check "Exit-Code 0" 0 "$rc"
check "Ziel traegt die neue App" "neu" "$(marker_of "$CASE_DIR/apps/Exploids.app")"
check "keine Staging-/Backup-Reste" "0" "$(leftovers "$CASE_DIR/apps")"

# Die beiden folgenden Faelle isolieren spctl: das Ticket (xcrun stapler) ist in
# Ordnung, nur Gatekeeper lehnt ab. Genau diese Faelle liefen frueher gruen durch,
# weil die spctl-Attrappe das falsche Argument las.
echo "6. Nur spctl lehnt am Staging-Pfad ab -> Ziel unberuehrt"
setup_case spctl_vorab alt
run_step "$CASE_DIR" "install-" spctl; rc=$?
check "Exit-Code 1" 1 "$rc"
check "Ziel traegt unveraendert die alte App" "alt" "$(marker_of "$CASE_DIR/apps/Exploids.app")"
check "keine Staging-/Backup-Reste" "0" "$(leftovers "$CASE_DIR/apps")"

echo "7. Nur spctl lehnt am Ziel ab -> Rueckkehr zur alten App"
setup_case spctl_ziel alt
run_step "$CASE_DIR" "apps/Exploids.app" spctl; rc=$?
check "Exit-Code 1" 1 "$rc"
check "Ziel traegt wieder die alte App" "alt" "$(marker_of "$CASE_DIR/apps/Exploids.app")"
check "keine Staging-/Backup-Reste" "0" "$(leftovers "$CASE_DIR/apps")"

echo
if [ "$fail" = "0" ]; then
    echo "install-swap: OK"
else
    echo "install-swap: FEHLGESCHLAGEN" >&2
    exit 1
fi
