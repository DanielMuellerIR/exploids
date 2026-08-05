#!/bin/bash
# Regressionstest fuer die Vorbedingungen aus wrappers/sign-and-release.sh.
#
# Geprueft werden die Wachposten, die verhindern, dass ein Release etwas
# veroeffentlicht, das niemand mehr nachbauen kann:
#   - der Arbeitsbaum muss sauber sein,
#   - HEAD darf zwischen Bau und Veroeffentlichung nicht wandern,
#   - der Tag bei GitHub muss auf genau den gebauten Commit zeigen,
#   - ein eingehaengtes DMG darf nach einem Abbruch nicht stehenbleiben.
#
# Es wird nichts gebaut, signiert, notarisiert oder gepusht. Die Funktionen
# werden aus dem Skript herausgeschnitten und in Wegwerf-Git-Repos ausgefuehrt;
# der „GitHub"-Remote ist ein lokales bare-Repo, hdiutil eine Attrappe.
#
# Aufruf:  bash Tests/release-guards.sh
set -uo pipefail

cd "$(dirname "$0")/.."
SCRIPT="$PWD/wrappers/sign-and-release.sh"

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

# Schneidet eine Shell-Funktion samt Rumpf aus dem Skript. Der Test fuehrt damit
# den echten Code aus, nicht eine Nachbildung. Die Kopfzeile darf hinter der
# Klammer noch einen Kommentar tragen, die Schlusszeile ist die naechste
# schliessende Klammer ganz links.
cut_function() {   # $1 = Funktionsname
    sed -n "/^$1() {/,/^}\$/p" "$SCRIPT"
}

FUNCS="$WORK/guards.sh"
: > "$FUNCS"
for fn in require_clean_worktree require_head_unchanged remote_tag_commit; do
    body="$(cut_function "$fn")"
    if [ -z "$body" ]; then
        echo "FEHLER: Funktion $fn nicht in $SCRIPT gefunden — Test veraltet." >&2
        exit 1
    fi
    printf '%s\n' "$body" >> "$FUNCS"
done
# shellcheck disable=SC1090
source "$FUNCS"

# Legt ein Wegwerf-Repo mit einem Commit an und meldet dessen Pfad.
make_repo() {   # $1 = Name
    local dir="$WORK/$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email "test@example.invalid"
    git -C "$dir" config user.name "Test"
    echo "eins" > "$dir/datei.txt"
    git -C "$dir" add datei.txt
    git -C "$dir" commit -qm "erster Commit"
    printf '%s\n' "$dir"
}

echo "1. require_clean_worktree"
PROJECT_ROOT="$(make_repo sauber)"
require_clean_worktree >/dev/null 2>&1; rc=$?
check "sauberer Arbeitsbaum -> 0" 0 "$rc"

echo "geaendert" > "$PROJECT_ROOT/datei.txt"
require_clean_worktree >/dev/null 2>&1; rc=$?
check "geaenderte getrackte Datei -> 1" 1 "$rc"

git -C "$PROJECT_ROOT" checkout -q -- datei.txt
touch "$PROJECT_ROOT/uebrig.txt"
require_clean_worktree >/dev/null 2>&1; rc=$?
check "unversionierte Datei -> 1" 1 "$rc"
rm -f "$PROJECT_ROOT/uebrig.txt"

PROJECT_ROOT="$WORK/gar-kein-repo"
mkdir -p "$PROJECT_ROOT"
require_clean_worktree >/dev/null 2>&1; rc=$?
check "kein Git-Repo -> 1" 1 "$rc"

echo
echo "2. require_head_unchanged"
PROJECT_ROOT="$(make_repo head)"
head_sha="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
require_head_unchanged "$head_sha" >/dev/null 2>&1; rc=$?
check "HEAD unveraendert -> 0" 0 "$rc"

echo "zwei" > "$PROJECT_ROOT/datei.txt"
git -C "$PROJECT_ROOT" commit -qam "zweiter Commit"
require_head_unchanged "$head_sha" >/dev/null 2>&1; rc=$?
check "HEAD weitergewandert -> 1" 1 "$rc"

echo
echo "3. remote_tag_commit"
PROJECT_ROOT="$(make_repo remote)"
BARE="$WORK/remote-bare.git"
git init -q --bare "$BARE"
git -C "$PROJECT_ROOT" remote add github "$BARE"
git -C "$PROJECT_ROOT" push -q github main

out="$(remote_tag_commit v9.9.9)"; rc=$?
check "Tag fehlt am Remote -> Rueckgabe 0" 0 "$rc"
check "Tag fehlt am Remote -> leere Ausgabe" "" "$out"

# Annotierter Tag: Die Zeile "refs/tags/<tag>" traegt nur das Tag-OBJEKT. Wer die
# nimmt, vergleicht gegen eine SHA, die nie einem Commit entspricht.
git -C "$PROJECT_ROOT" tag -a v1.0.0 -m "v1.0.0"
git -C "$PROJECT_ROOT" push -q github v1.0.0
commit_sha="$(git -C "$PROJECT_ROOT" rev-parse 'v1.0.0^{commit}')"
tagobj_sha="$(git -C "$PROJECT_ROOT" rev-parse v1.0.0)"
out="$(remote_tag_commit v1.0.0)"
check "annotierter Tag -> Commit-SHA" "$commit_sha" "$out"
check "annotierter Tag -> nicht die Tag-Objekt-SHA" "verschieden" \
      "$([ "$out" != "$tagobj_sha" ] && echo verschieden || echo gleich)"

git -C "$PROJECT_ROOT" tag v1.0.1
git -C "$PROJECT_ROOT" push -q github v1.0.1
out="$(remote_tag_commit v1.0.1)"
check "leichtgewichtiger Tag -> Commit-SHA" \
      "$(git -C "$PROJECT_ROOT" rev-parse 'v1.0.1^{commit}')" "$out"

git -C "$PROJECT_ROOT" remote set-url github "$WORK/gibt-es-nicht.git"
remote_tag_commit v1.0.0 >/dev/null 2>&1; rc=$?
check "Remote nicht erreichbar -> Rueckgabe 1" 1 "$rc"

echo
echo "4. attach_dmg / detach_attached_dmg"
# Die beiden Funktionen brauchen einen eigenen Shell-Prozess: attach_dmg setzt
# einen EXIT-Trap, und genau dessen Wirkung wird hier gemessen.
DMG_FUNCS="$WORK/dmg.sh"
: > "$DMG_FUNCS"
for fn in detach_attached_dmg attach_dmg; do
    body="$(cut_function "$fn")"
    if [ -z "$body" ]; then
        echo "FEHLER: Funktion $fn nicht in $SCRIPT gefunden — Test veraltet." >&2
        exit 1
    fi
    printf '%s\n' "$body" >> "$DMG_FUNCS"
done

# $1 = Fallname, $2 = Attrappenmodus (normal|ohne-geraet), $3 = "abbruch" oder ""
run_attach() {
    local name="$1" mode="$2" abort="$3"
    local dir="$WORK/attach-$name"
    mkdir -p "$dir"
    cat > "$dir/runner.sh" <<RUNNER
set -uo pipefail
ATTACHED_DEV=""
MODE="$mode"
LOG="$dir/hdiutil.log"
: > "\$LOG"

# hdiutil-Attrappe. Die Ausgabe entspricht dem echten Format: je Partition eine
# Zeile mit Geraet, Typ und (bei der Datenpartition) Mountpoint.
hdiutil() {
    echo "\$*" >> "\$LOG"
    if [ "\$1" = "attach" ]; then
        if [ "\$MODE" = "ohne-geraet" ]; then
            echo "hdiutil: attach: keine Geraetezeile (Attrappe)"
            return 0
        fi
        printf '/dev/disk4\tApple_partition_scheme\t\n'
        printf '/dev/disk4s1\tApple_partition_map\t\n'
        printf '/dev/disk4s2\tApple_HFS\t/Volumes/Exploids\n'
    fi
    return 0
}

source "$DMG_FUNCS"

attach_dmg "$dir/egal.dmg" "/Volumes/Exploids" >/dev/null 2>&1
rc=\$?
echo "rc=\$rc"                  > "$dir/ergebnis.txt"
echo "dev=\${ATTACHED_DEV:-}"  >> "$dir/ergebnis.txt"
echo "trap=\$(trap -p EXIT | grep -c detach_attached_dmg)" >> "$dir/ergebnis.txt"

if [ "$abort" = "abbruch" ]; then
    # Stellvertretend fuer jeden Fehler zwischen Einhaengen und Auswerfen
    # (Symlink, Hintergrundbild, AppleScript-Layout).
    exit 3
fi
RUNNER
    bash "$dir/runner.sh" >/dev/null 2>&1
    CASE_RC=$?
    CASE_DIR="$dir"
}

run_attach erfolg normal ""
check "Exit-Code des Laufs 0" 0 "$CASE_RC"
check "attach_dmg meldet Erfolg" "rc=0" "$(grep '^rc=' "$CASE_DIR/ergebnis.txt")"
check "Geraetekennung aus der Ausgabe gelesen" "dev=/dev/disk4" \
      "$(grep '^dev=' "$CASE_DIR/ergebnis.txt")"
check "EXIT-Trap ist scharf" "trap=1" "$(grep '^trap=' "$CASE_DIR/ergebnis.txt")"

run_attach ohne_geraet ohne-geraet ""
check "unlesbare hdiutil-Ausgabe -> attach_dmg meldet Fehler" "rc=1" \
      "$(grep '^rc=' "$CASE_DIR/ergebnis.txt")"
check "keine Geraetekennung gesetzt" "dev=" "$(grep '^dev=' "$CASE_DIR/ergebnis.txt")"

run_attach abbruch normal abbruch
check "Abbruch nach dem Einhaengen -> Exit-Code 3" 3 "$CASE_RC"
check "Trap hat genau dieses Geraet getrennt" "1" \
      "$(grep -c '^detach /dev/disk4 -force$' "$CASE_DIR/hdiutil.log")"

echo
echo "5. Textpruefungen am Skript"
# Zwei Stellen lassen sich nur am Quelltext festhalten, weil ein echter Lauf
# Notarisierung und GitHub braucht.
if grep -q 'spctl --assess .*|| true' "$SCRIPT"; then
    check "Gatekeeper-Pruefung des DMG wird nicht mit '|| true' entwertet" "ja" "nein"
else
    check "Gatekeeper-Pruefung des DMG wird nicht mit '|| true' entwertet" "ja" "ja"
fi
if grep -q -- '--verify-tag' "$SCRIPT"; then
    check "gh release create verlangt den Tag am Remote (--verify-tag)" "ja" "ja"
else
    check "gh release create verlangt den Tag am Remote (--verify-tag)" "ja" "nein"
fi

echo
if [ "$fail" = "0" ]; then
    echo "release-guards: OK"
else
    echo "release-guards: FEHLGESCHLAGEN" >&2
    exit 1
fi
