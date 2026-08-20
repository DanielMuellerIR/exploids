#!/bin/bash
# Regressionstest fuer die Vorbedingungen aus wrappers/sign-and-release.sh.
#
# Es wird nichts gebaut, signiert, notarisiert oder gepusht. Die Funktionen
# werden aus dem Produktionsskript ausgeschnitten und in Wegwerf-Repos mit
# lokalen Remotes beziehungsweise Werkzeug-Attrappen ausgefuehrt.
set -uo pipefail

cd "$(dirname "$0")/.."
source Tests/shell-test-lib.sh
SCRIPT="${EXPLOIDS_RELEASE_SCRIPT:-$PWD/wrappers/sign-and-release.sh}"

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

FUNCS="$WORK/guards.sh"
: > "$FUNCS"
for fn in require_tag_matches_head require_clean_worktree require_head_unchanged \
          require_release_preconditions remote_tag_commit require_publish_environment; do
    append_function "$SCRIPT" "$fn" "$FUNCS" || exit 1
done
# shellcheck disable=SC1090
source "$FUNCS"

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
echo "3. require_tag_matches_head"
PROJECT_ROOT="$(make_repo tag)"
require_tag_matches_head v9.9.9 >/dev/null 2>&1; rc=$?
check "Tag fehlt -> 0" 0 "$rc"

git -C "$PROJECT_ROOT" tag v1.0.0
require_tag_matches_head v1.0.0 >/dev/null 2>&1; rc=$?
check "Tag zeigt auf HEAD -> 0" 0 "$rc"

echo "zwei" > "$PROJECT_ROOT/datei.txt"
git -C "$PROJECT_ROOT" commit -qam "zweiter Commit"
require_tag_matches_head v1.0.0 >/dev/null 2>&1; rc=$?
check "Tag zeigt nicht auf HEAD -> 1" 1 "$rc"

PROJECT_ROOT="$WORK/kein-head"
mkdir -p "$PROJECT_ROOT"
require_tag_matches_head v1.0.0 >/dev/null 2>&1; rc=$?
check "HEAD nicht aufloesbar -> 1" 1 "$rc"

echo
echo "4. remote_tag_commit"
PROJECT_ROOT="$(make_repo remote)"
BARE="$WORK/remote-bare.git"
git init -q --bare "$BARE"
git -C "$PROJECT_ROOT" push -q "$BARE" main
GITHUB_REMOTE_URL="$BARE"

out="$(remote_tag_commit v9.9.9)"; rc=$?
check "Tag fehlt am Remote -> Rueckgabe 0" 0 "$rc"
check "Tag fehlt am Remote -> leere Ausgabe" "" "$out"

git -C "$PROJECT_ROOT" tag -a v1.0.0 -m "v1.0.0"
git -C "$PROJECT_ROOT" push -q "$BARE" v1.0.0
commit_sha="$(git -C "$PROJECT_ROOT" rev-parse 'v1.0.0^{commit}')"
tagobj_sha="$(git -C "$PROJECT_ROOT" rev-parse v1.0.0)"
out="$(remote_tag_commit v1.0.0)"
check "annotierter Tag -> Commit-SHA" "$commit_sha" "$out"
check "annotierter Tag -> nicht die Tag-Objekt-SHA" "verschieden" \
      "$([ "$out" != "$tagobj_sha" ] && echo verschieden || echo gleich)"

git -C "$PROJECT_ROOT" tag v1.0.1
git -C "$PROJECT_ROOT" push -q "$BARE" v1.0.1
out="$(remote_tag_commit v1.0.1)"
check "leichtgewichtiger Tag -> Commit-SHA" \
      "$(git -C "$PROJECT_ROOT" rev-parse 'v1.0.1^{commit}')" "$out"

GITHUB_REMOTE_URL="$WORK/gibt-es-nicht.git"
remote_tag_commit v1.0.0 >/dev/null 2>&1; rc=$?
check "Remote nicht erreichbar -> Rueckgabe 1" 1 "$rc"

echo
echo "5. require_publish_environment"
FAKE_BIN="$WORK/fake-bin"
mkdir -p "$FAKE_BIN" "$WORK/no-gh"
printf '#!/bin/sh\nexit 0\n' > "$FAKE_BIN/gh"
chmod +x "$FAKE_BIN/gh"
ORIGINAL_PATH="$PATH"
PATH="$FAKE_BIN:$ORIGINAL_PATH"
GITHUB_REMOTE_URL="$BARE"
require_publish_environment >/dev/null 2>&1; rc=$?
check "gh vorhanden und GitHub-Ziel erreichbar -> 0" 0 "$rc"

PATH="$WORK/no-gh"
require_publish_environment >/dev/null 2>&1; rc=$?
check "gh fehlt -> frueher Abbruch 1" 1 "$rc"

PATH="$FAKE_BIN:$ORIGINAL_PATH"
GITHUB_REMOTE_URL="$WORK/gibt-es-nicht.git"
require_publish_environment >/dev/null 2>&1; rc=$?
check "GitHub-Ziel nicht erreichbar -> frueher Abbruch 1" 1 "$rc"
PATH="$ORIGINAL_PATH"

preflight_line="$(grep -nF 'require_publish_environment || exit 1' "$SCRIPT" | head -1 | cut -d: -f1)"
build_line="$(grep -nF 'bash "$PROJECT_ROOT/build-app.sh"' "$SCRIPT" | head -1 | cut -d: -f1)"
if [ -n "$preflight_line" ] && [ -n "$build_line" ] && [ "$preflight_line" -lt "$build_line" ]; then
    check "Publish-Umgebung wird vor dem Bau geprueft" ja ja
else
    check "Publish-Umgebung wird vor dem Bau geprueft" ja nein
fi

echo
echo "6. require_release_preconditions"
ORDER_LOG="$WORK/order.log"
require_clean_worktree() { echo clean >> "$ORDER_LOG"; }
require_head_unchanged() { echo "head:$1" >> "$ORDER_LOG"; }
require_tag_matches_head() { echo "tag:$1" >> "$ORDER_LOG"; }

: > "$ORDER_LOG"
require_release_preconditions v1.2.3 ""
check "Kette vor dem Bau" $'clean\ntag:v1.2.3' "$(cat "$ORDER_LOG")"

: > "$ORDER_LOG"
require_release_preconditions v1.2.3 abc123
check "Kette vor dem Upload" $'clean\nhead:abc123\ntag:v1.2.3' "$(cat "$ORDER_LOG")"

echo
echo "7. attach_dmg / detach_attached_dmg"
DMG_FUNCS="$WORK/dmg.sh"
: > "$DMG_FUNCS"
append_function "$SCRIPT" detach_attached_dmg "$DMG_FUNCS" || exit 1
append_function "$SCRIPT" attach_dmg "$DMG_FUNCS" || exit 1

# $1 = Fallname, $2 = normal|ohne-geraet|attach-fehler, $3 = normal|abbruch
run_attach() {
    local name="$1" mode="$2" action="$3"
    local dir="$WORK/attach-$name"
    mkdir -p "$dir"
    cat > "$dir/runner.sh" <<RUNNER
set -euo pipefail
ATTACHED_DEV=""
ATTACHED_MOUNT=""
MODE="$mode"
LOG="$dir/hdiutil.log"
: > "\$LOG"

hdiutil() {
    echo "\$*" >> "\$LOG"
    if [ "\$1" = "attach" ]; then
        if [ "\$MODE" = "attach-fehler" ]; then
            return 1
        elif [ "\$MODE" = "ohne-geraet" ]; then
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
echo "dev=\${ATTACHED_DEV:-}" > "$dir/ergebnis.txt"
echo "mount=\${ATTACHED_MOUNT:-}" >> "$dir/ergebnis.txt"
echo "trap=\$(trap -p EXIT | grep -c detach_attached_dmg)" >> "$dir/ergebnis.txt"

if [ "$action" = "abbruch" ]; then
    echo abort-marker >> "\$LOG"
    exit 3
fi
hdiutil detach "\$ATTACHED_MOUNT" -force
trap - EXIT
RUNNER
    bash "$dir/runner.sh" >/dev/null 2>&1
    CASE_RC=$?
    CASE_DIR="$dir"
}

run_attach erfolg normal normal
check "erfolgreicher Lauf -> Exit-Code 0" 0 "$CASE_RC"
check "Geraetekennung gelesen" "dev=/dev/disk4" "$(grep '^dev=' "$CASE_DIR/ergebnis.txt")"
check "Mountpoint als Rueckfall gespeichert" "mount=/Volumes/Exploids" \
      "$(grep '^mount=' "$CASE_DIR/ergebnis.txt")"
check "EXIT-Trap nach dem Einhaengen scharf" "trap=1" \
      "$(grep '^trap=' "$CASE_DIR/ergebnis.txt")"

run_attach ohne_geraet ohne-geraet normal
check "unlesbare Ausgabe -> Exit-Code 1" 1 "$CASE_RC"
check "unlesbare Ausgabe -> Mountpoint getrennt" 1 \
      "$(grep -c '^detach /Volumes/Exploids -force$' "$CASE_DIR/hdiutil.log")"

run_attach attach_fehler attach-fehler normal
check "fehlgeschlagenes attach -> Exit-Code 1" 1 "$CASE_RC"
check "fehlgeschlagenes attach -> kein unberechtigtes detach" 0 \
      "$(grep -c '^detach ' "$CASE_DIR/hdiutil.log")"

run_attach abbruch normal abbruch
check "Abbruch nach dem Einhaengen -> Exit-Code 3" 3 "$CASE_RC"
detach_after_marker="$(awk '
    /^abort-marker$/ { marker=NR }
    /^detach \/dev\/disk4 -force$/ { detached=NR }
    END { print (marker > 0 && detached > marker) ? 1 : 0 }
' "$CASE_DIR/hdiutil.log")"
check "EXIT-Trap trennt das Geraet nach dem Abbruch" 1 "$detach_after_marker"

echo
echo "8. Produktionsaufrufe"
precondition_calls="$(grep -c '^  require_release_preconditions ' "$SCRIPT")"
check "Vorbedingungskette laeuft vor Bau und Upload" 2 "$precondition_calls"

SPCTL_LINE="$(extract_block "$SCRIPT" '^spctl --assess' '^spctl --assess')"
check "Gatekeeper-Pruefung ist vorhanden und unentwertet" \
      'spctl --assess --type open --context context:primary-signature -v "$DMG_PATH"' \
      "$SPCTL_LINE"

GH_CREATE_BLOCK="$(extract_block "$SCRIPT" '^[[:space:]]+gh release create ' \
                                       '^[[:space:]]+--notes-file ')"
if [ -n "$GH_CREATE_BLOCK" ] && grep -q -- '--verify-tag' <<< "$GH_CREATE_BLOCK"; then
    check "gh release create verlangt den Tag am Remote (--verify-tag)" ja ja
else
    check "gh release create verlangt den Tag am Remote (--verify-tag)" ja nein
fi

PUSH_LINE="$(extract_block "$SCRIPT" '^[[:space:]]+git -C .* push "[$]GITHUB_REMOTE_URL"' \
                              '^[[:space:]]+git -C .* push "[$]GITHUB_REMOTE_URL"')"
check "Tag-Push nutzt dasselbe kanonische GitHub-Ziel" \
      '    git -C "$PROJECT_ROOT" push "$GITHUB_REMOTE_URL" "refs/tags/$TAG"' \
      "$PUSH_LINE"

echo
if [ "$fail" = "0" ]; then
    echo "release-guards: OK"
else
    echo "release-guards: FEHLGESCHLAGEN" >&2
    exit 1
fi
