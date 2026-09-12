#!/bin/bash
# Prueft den Root-Wrapper mit einer harmlosen Build-Attrappe. Dadurch laufen
# weder Swift-Build noch Signierung, der echte build.sh wird aber ausgefuehrt.
set -euo pipefail

cd "$(dirname "$0")/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo" "$work/fremder-ordner"
cp build.sh "$work/repo/build.sh"

cat > "$work/repo/build-app.sh" <<'FAKE'
#!/bin/bash
printf '%s\n' "$PWD" > aufruf.cwd
printf '%s\n' "$@" > aufruf.args
if [ "${1:-}" = "--fail" ]; then exit 37; fi
printf 'Zwischenzeile\nBUILD OK: %s/Exploids.app\n' "$PWD"
FAKE

ausgabe="$(cd "$work/fremder-ordner" && bash ../repo/build.sh eins "zwei drei")"
test "$(cat "$work/repo/aufruf.cwd")" = "$work/repo"
test "$(sed -n '1p' "$work/repo/aufruf.args")" = "eins"
test "$(sed -n '2p' "$work/repo/aufruf.args")" = "zwei drei"
test "$(printf '%s\n' "$ausgabe" | tail -n 1)" = "BUILD OK: $work/repo/Exploids.app"

set +e
(cd "$work/fremder-ordner" && bash ../repo/build.sh --fail) >/dev/null 2>&1
status=$?
set -e
test "$status" -eq 37

echo "build-wrapper: OK (Arbeitsordner, Argumente, Schlusszeile, Exit-Code)"
