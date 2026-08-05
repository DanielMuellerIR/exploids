#!/usr/bin/env bash
# wrappers/sign-and-release.sh — baut Exploids, signiert mit Developer ID
# (Hardened Runtime + Timestamp), packt ein DMG mit Installations-Layout
# (Applications-Shortcut, Hintergrundbild, feste Icon-Positionen), notarisiert
# bei Apple und heftet das Ticket an. Ergebnis: ein DMG, das auf jedem Mac per
# Doppelklick ohne Gatekeeper-Warnung öffnet.
#
# Voraussetzungen (einmalig je Mac):
#   1. Developer-ID-Application-Zertifikat in der Login-Keychain.
#      Prüfen: security find-identity -v -p codesigning
#   2. notarytool-Keychain-Profil. Der Name kommt aus NOTARY_PROFILE oder aus
#      `git config exploids.notaryProfile` — er steht bewusst nirgends im Repo,
#      weil Keychain-Profile pro Mac lokal sind. Falls fehlend, einmalig anlegen:
#        xcrun notarytool store-credentials <profil> \
#          --apple-id <deine-apple-id> --team-id <team-id>
#      (App-spezifisches Passwort INTERAKTIV eingeben, NIE als CLI-Argument.)
#
# Aufruf:  ./release.sh              (dieser Wrapper ist der Unterbau davon)
#          ./release.sh --publish    # setzt git-Tag + lädt DMG zu GitHub hoch
#
# Exploids ist ein reines SwiftPM-Executable ohne eingebettete Frameworks —
# darum genügt es, das Bundle selbst zu signieren (kein Framework-Vorsignieren
# wie z. B. bei VLCKit).

set -euo pipefail

# ---------- Konstanten (überschreibbar für CI/anderen Account) ----------
# Team-ID und Developer-ID-Identity sind public-safe (stehen ohnehin in LICENSE,
# Info.plist und jeder signierten Binary). Das eigentliche Notar-Geheimnis liegt
# pro-Mac im Schlüsselbund-Profil (NOTARY_PROFILE), nie hier.
TEAM_ID="${APPLE_TEAM_ID:-9QSWKSR4NQ}"
IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Daniel Mueller ($TEAM_ID)}"

APP_NAME="Exploids"               # Bundle-/Anzeigename
VOLNAME="Exploids"                # DMG-Volume-Name (= /Volumes/<name>)
REPO="DanielMuellerIR/exploids"   # GitHub-Repo für --publish

# ---------- Optionen ----------
# Früh auswerten und unbekannte Flags sofort ablehnen: Ein Tippfehler soll nicht
# erst nach dem minutenlangen Notarisieren auffallen.
PUBLISH=0
FINDER_LAYOUT=1
for arg in "$@"; do
  case "$arg" in
    --publish)          PUBLISH=1 ;;
    --no-finder-layout) FINDER_LAYOUT=0 ;;
    *) echo "Unbekannte Option: $arg" >&2
       echo "Aufruf: ./release.sh [--publish] [--no-finder-layout]" >&2
       exit 1 ;;
  esac
done

# ---------- Pfade ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
APP_BUNDLE="$PROJECT_ROOT/$APP_NAME.app"    # build-app.sh legt das Bundle im Repo-Root ab
BACKGROUND_SRC="$PROJECT_ROOT/assets/dmg-background.png"

# Version = einzige Quelle in der Datei VERSION.
APP_VERSION="$(tr -d ' \n' < "$PROJECT_ROOT/VERSION")"
DMG_PATH="$BUILD_DIR/Exploids-${APP_VERSION}.dmg"
RW_DMG_PATH="$BUILD_DIR/Exploids-${APP_VERSION}-rw.dmg"

echo "==> Exploids Sign-and-Release v${APP_VERSION}"
mkdir -p "$BUILD_DIR"

# Fail-closed-Vorbedingung für --publish: Wenn der Tag vX.Y.Z schon existiert,
# MUSS er exakt auf HEAD zeigen. Der frühere reine Existenztest ließ einen Tag aus
# einem älteren Commit unbemerkt stehen und übersprang die Tag-Erzeugung; das
# Release hätte dann ein aus HEAD gebautes DMG unter einem Tag veröffentlicht, der
# ganz anderen Quellcode bezeichnet — inklusive abweichender Bundle-Buildnummer,
# die aus `git rev-list --count HEAD` kommt. Belegt am 2026-08-03: VERSION stand
# auf 0.14.6, Tag v0.14.6 zeigte auf 5e7c7b0, HEAD auf 9c3a933.
# Lieber abbrechen als etwas Falsches veröffentlichen.
require_tag_matches_head() {
  local tag="$1"
  local existing head_sha
  # Die Funktion wird als linke Seite von `||` aufgerufen; darin gilt `set -e`
  # nicht. Jeder Fehlerfall muss deshalb ausdrücklich zu `return 1` führen, sonst
  # liefe die Prüfung im Fehlerfall stillschweigend als „bestanden“ durch.
  if ! head_sha="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null)" || [ -z "$head_sha" ]; then
    echo "FEHLER: HEAD in $PROJECT_ROOT nicht auflösbar — Tag-Prüfung unmöglich." >&2
    return 1
  fi
  if existing="$(git -C "$PROJECT_ROOT" rev-parse -q --verify "refs/tags/$tag^{commit}" 2>/dev/null)"; then
    if [ "$existing" != "$head_sha" ]; then
      echo "FEHLER: Tag $tag zeigt auf ${existing:0:12}, HEAD ist ${head_sha:0:12}." >&2
      echo "  Ein Release würde ein aus HEAD gebautes Artefakt unter einem Tag" >&2
      echo "  veröffentlichen, der anderen Quellstand bezeichnet." >&2
      echo "  Abhilfe: VERSION erhöhen (neuer Tag) oder das Artefakt aus einem" >&2
      echo "  Checkout von $tag bauen." >&2
      return 1
    fi
  fi
  return 0
}

# Gebaut wird immer der Zustand auf der Platte, veröffentlicht aber unter einem
# Tag, der einen Commit bezeichnet. Ist der Arbeitsbaum nicht sauber, enthält das
# DMG Änderungen, die in keinem Commit stehen — niemand könnte das Artefakt je
# wieder aus dem Tag nachbauen. `require_tag_matches_head` hilft dagegen nicht:
# Ohne vorhandenen Tag läuft es auf `return 0` und prüft den Arbeitsbaum ohnehin
# nie. `git status --porcelain` zählt auch unversionierte Dateien mit; Build- und
# Bundle-Artefakte stehen in .gitignore und stören deshalb nicht.
require_clean_worktree() {
  local dirty
  # Wie oben: Die Funktion wird als linke Seite von `||` aufgerufen, `set -e` gilt
  # darin nicht. Jeder Fehlerfall muss ausdrücklich `return 1` liefern.
  if ! dirty="$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null)"; then
    echo "FEHLER: git status in $PROJECT_ROOT nicht ausführbar — Release abgebrochen." >&2
    return 1
  fi
  if [ -n "$dirty" ]; then
    echo "FEHLER: Arbeitsbaum nicht sauber. Ein Release muss genau dem Commit entsprechen," >&2
    echo "  den der Tag bezeichnet. Offene Änderungen:" >&2
    printf '%s\n' "$dirty" | sed 's/^/    /' >&2
    return 1
  fi
  return 0
}

# Zwischen Startprüfung und Veröffentlichung liegen Bau und Notarisierung, also
# Minuten. Wandert HEAD in dieser Zeit, stammt das DMG aus dem alten Stand.
require_head_unchanged() {   # $1 = die vor dem Bau festgehaltene Commit-SHA
  local built="$1" now
  if ! now="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null)" || [ -z "$now" ]; then
    echo "FEHLER: HEAD in $PROJECT_ROOT nicht auflösbar — Release abgebrochen." >&2
    return 1
  fi
  if [ "$now" != "$built" ]; then
    echo "FEHLER: HEAD ist seit dem Bau von ${built:0:12} auf ${now:0:12} gewandert." >&2
    echo "  Das DMG stammt aus dem alten Stand. Release abgebrochen." >&2
    return 1
  fi
  return 0
}

# Löst den Tag auf dem GitHub-Remote zum COMMIT auf.
#
# `gh release create/upload` kennt nur den Tag-NAMEN und hängt das DMG an das, was
# unter diesem Namen bei GitHub steht. Ein lokal vorhandener Tag sagt darüber
# nichts: Er kann nie gepusht worden sein, oder der Remote-Tag kann von einem
# anderen Rechner stammen und auf fremden Quellcode zeigen.
#
# Bei einem annotierten Tag (`git tag -a`) enthält die Zeile "refs/tags/<tag>" nur
# das Tag-OBJEKT; der Commit steht in der zusätzlichen Zeile "refs/tags/<tag>^{}".
# Ein leichtgewichtiger Tag hat nur die erste Zeile und zeigt direkt auf den
# Commit. Deshalb beide Muster abfragen und die aufgelöste Zeile bevorzugen.
#
# Ausgabe: die Commit-SHA, oder leer, wenn es den Tag am Remote nicht gibt.
# Rückgabe 1 nur, wenn der Remote gar nicht abfragbar war.
remote_tag_commit() {   # $1 = Tagname
  local tag="$1" lines peeled plain
  if ! lines="$(git -C "$PROJECT_ROOT" ls-remote --tags github \
                    "refs/tags/$tag" "refs/tags/$tag^{}" 2>/dev/null)"; then
    return 1
  fi
  peeled="$(printf '%s\n' "$lines" | awk -v t="refs/tags/$tag^{}" '$2 == t { print $1; exit }')"
  plain="$( printf '%s\n' "$lines" | awk -v t="refs/tags/$tag"     '$2 == t { print $1; exit }')"
  if [ -n "$peeled" ]; then
    printf '%s\n' "$peeled"
  else
    printf '%s\n' "$plain"
  fi
  return 0
}

# ---------- Sanity-Checks ----------
# Profilermittlung und die eigentliche App-Notarisierung liegen in
# notarize-lib.sh, damit install.sh denselben Weg geht.
source "$PROJECT_ROOT/notarize-lib.sh"
require_notary_profile
if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "FEHLER: Signing-Identität nicht gefunden: $IDENTITY" >&2
  security find-identity -v -p codesigning >&2
  exit 1
fi
# Schon hier prüfen, nicht erst nach dem minutenlangen Notarisieren.
BUILD_SHA=""
if [ "$PUBLISH" = "1" ]; then
  require_clean_worktree || exit 1
  require_tag_matches_head "v${APP_VERSION}" || exit 1
  # Den Commit festhalten, aus dem gleich gebaut wird. Vor dem Veröffentlichen
  # wird gegen genau diesen Wert geprüft.
  BUILD_SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
  echo "    Release-Basis: ${BUILD_SHA:0:12} (sauberer Arbeitsbaum)"
fi
# Der Hintergrund wird ausschließlich vom AppleScript-Layout verwendet; ohne
# --no-finder-layout ist er Pflicht, mit --no-finder-layout wird er weder
# gebraucht noch ins Image gepackt.
if [ "$FINDER_LAYOUT" = "1" ] && [ ! -f "$BACKGROUND_SRC" ]; then
  echo "FEHLER: DMG-Hintergrund fehlt: $BACKGROUND_SRC" >&2
  echo "  swift assets/generate-dmg-background.swift assets/dmg-background.png" >&2
  exit 1
fi

# ---------- 1. Bauen ----------
echo "==> Baue App-Bundle"
bash "$PROJECT_ROOT/build-app.sh"

# ---------- 2. Signieren ----------
echo "==> Signiere App-Bundle"
sign_app "$APP_BUNDLE"
codesign -dvv "$APP_BUNDLE" 2>&1 | grep -E "Authority|TeamIdentifier|flags" || true

# ---------- 3. App notarisieren ----------
# Vor dem DMG, nicht danach: Wer die App aus dem Image herauszieht, hat sonst ein
# Bundle ohne eigenes Ticket — das DMG-Ticket reist nicht mit. Das angeheftete
# Ticket landet als Datei im Bundle und wird vom folgenden hdiutil mitkopiert.
echo "==> Notarisiere App-Bundle"
notarize_app "$APP_BUNDLE"

# ---------- 4. DMG mit Installations-Layout ----------
echo "==> Erzeuge DMG-Layout"
rm -f "$DMG_PATH" "$RW_DMG_PATH"
[ -d "/Volumes/$VOLNAME" ] && hdiutil detach "/Volumes/$VOLNAME" -force >/dev/null 2>&1 || true

SIZE=$(( $(du -sm "$APP_BUNDLE" | cut -f1) + 40 ))
hdiutil create -srcfolder "$APP_BUNDLE" -volname "$VOLNAME" -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" -format UDRW -size "${SIZE}m" "$RW_DMG_PATH"

# Trennt das von attach_dmg eingehängte Gerät, falls es noch hängt. Wird als
# EXIT-Trap aufgerufen und darf deshalb nie selbst fehlschlagen.
detach_attached_dmg() {
  [ -n "${ATTACHED_DEV:-}" ] || return 0
  hdiutil detach "$ATTACHED_DEV" -force >/dev/null 2>&1 || true
  ATTACHED_DEV=""
}

# Hängt das beschreibbare Image ein und rüstet sofort einen EXIT-Trap, der genau
# dieses Gerät wieder trennt. Ohne den Trap blieb das Image nach jedem Fehler
# zwischen Einhängen und Auswerfen (Symlink, Hintergrundbild, AppleScript-Layout)
# dauerhaft unter /Volumes stehen; der nächste Lauf trennt es zwar erzwungen, bis
# dahin liegt es aber offen herum.
#
# Der Mountpoint MUSS /Volumes/$VOLNAME bleiben: Das Finder-AppleScript spricht das
# Volume über `tell disk "$VOLNAME"` an. Ein eigener Mountpoint außerhalb /Volumes
# würde das Layout brechen.
#
# Setzt ATTACHED_DEV auf die Gerätekennung.
attach_dmg() {   # $1 = Image, $2 = Mountpoint
  local out
  out="$(hdiutil attach "$1" -mountpoint "$2" -nobrowse -noverify -noautoopen)"
  printf '%s\n' "$out"
  # hdiutil listet je Partition eine Zeile "/dev/diskNsM <Typ> <Mountpoint>".
  # Die erste /dev/-Zeile ist das Gerät als Ganzes — genau das wird getrennt.
  ATTACHED_DEV="$(printf '%s\n' "$out" | awk '/^\/dev\// { print $1; exit }')"
  if [ -z "$ATTACHED_DEV" ]; then
    echo "FEHLER: Gerätekennung aus der hdiutil-Ausgabe nicht lesbar." >&2
    return 1
  fi
  trap detach_attached_dmg EXIT
  return 0
}

MOUNT_DIR="/Volumes/$VOLNAME"
ATTACHED_DEV=""
attach_dmg "$RW_DMG_PATH" "$MOUNT_DIR"

ln -s /Applications "$MOUNT_DIR/Applications"

# Finder-Ansicht setzen. Fenster-Innenmaß 600×400 = Hintergrundbild-Größe.
# --no-finder-layout überspringt diesen Schritt: Er öffnet ein echtes
# Finder-Fenster und reißt den Fokus an sich, was headless-Läufe (und Läufe
# neben laufender Arbeit) stört. Das DMG ist dann funktional, nur ohne
# Icon-Positionen und Hintergrundbild.
# Das Hintergrundbild gehört zu diesem Schritt: Einziger Verbraucher ist
# `set background picture` unten. Ohne Layout wanderte es früher trotzdem als
# ungenutzte Datei ins Image.
if [ "$FINDER_LAYOUT" = "1" ]; then
mkdir -p "$MOUNT_DIR/.background"
cp "$BACKGROUND_SRC" "$MOUNT_DIR/.background/background.png"
chflags hidden "$MOUNT_DIR/.background"
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 520}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "$APP_NAME.app" of container window to {150, 180}
    set position of item "Applications" of container window to {450, 180}
    try
      set position of item ".background" of container window to {900, 900}
    end try
    update without registering applications
    close
  end tell
end tell
APPLESCRIPT
else
  echo "    (Finder-Layout übersprungen: --no-finder-layout)"
fi

sync; sleep 2                       # Race: DS_Store-Schreibpuffer vs. detach
hdiutil detach "$MOUNT_DIR" -force
# Erst nach dem erfolgreichen Trennen entwaffnen: Scheitert das Detach oben,
# beendet `set -e` das Skript und der Trap räumt noch auf.
trap - EXIT
ATTACHED_DEV=""

echo "==> Konvertiere zu komprimiertem read-only DMG"
hdiutil convert "$RW_DMG_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
rm -f "$RW_DMG_PATH"

echo "==> Signiere DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"

# ---------- 5. DMG notarisieren + stapeln ----------
echo "==> Notarisieren (1-10 Min)"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapele Ticket"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
# Ohne `|| true`: Das ist die letzte Prüfung vor dem optionalen Veröffentlichen.
# Verwirft man ihr Ergebnis, läuft der --publish-Block darunter auch dann weiter,
# wenn Gatekeeper das DMG ablehnt — und genau das soll er nicht.
spctl --assess --type open --context context:primary-signature -v "$DMG_PATH"

# ---------- 6. (optional) GitHub-Release veröffentlichen ----------
# Nur mit --publish (oben ausgewertet). Setzt Tag vX.Y.Z, erstellt das Release,
# lädt das DMG hoch und entnimmt die Release-Notes aus dem passenden
# CHANGELOG.md-Abschnitt. Öffentliches Pushen ist rückfragepflichtig → daher
# opt-in, nicht Default.
if [ "$PUBLISH" = "1" ]; then
  TAG="v${APP_VERSION}"
  echo "==> Veröffentliche GitHub-Release $TAG"
  command -v gh >/dev/null || { echo "FEHLER: gh CLI fehlt (brew install gh)" >&2; exit 1; }

  # Release-Notes aus CHANGELOG.md ziehen: Zeilen ab "## [VERSION]" bis zum nächsten "## [".
  NOTES_FILE="$BUILD_DIR/release-notes-${APP_VERSION}.md"
  awk -v ver="$APP_VERSION" '
    $0 ~ "^## \\[" ver "\\]" { grab=1; next }
    grab && /^## \[/         { exit }
    grab                     { print }
  ' "$PROJECT_ROOT/CHANGELOG.md" > "$NOTES_FILE"
  [ -s "$NOTES_FILE" ] || echo "Exploids $TAG" > "$NOTES_FILE"

  # Die Vorbedingungen von oben hier direkt vor dem Push erneut prüfen: Zwischen
  # Start und diesem Punkt liegen Bau und Notarisierung, in der Zeit können sich
  # Arbeitsbaum und HEAD bewegt haben.
  require_clean_worktree || exit 1
  require_head_unchanged "$BUILD_SHA" || exit 1
  require_tag_matches_head "$TAG" || exit 1

  # Maßgeblich ist der Tag bei GitHub, nicht der lokale. Vorher wurde beides
  # übersprungen, sobald der Tag lokal existierte — ob er jemals gepusht wurde und
  # worauf er dort zeigt, prüfte niemand. `gh release` arbeitet danach nur noch mit
  # dem Tag-NAMEN und hängte das DMG im schlimmsten Fall an fremden Quellstand.
  if ! REMOTE_TAG_SHA="$(remote_tag_commit "$TAG")"; then
    echo "FEHLER: Tag $TAG am Remote 'github' nicht abfragbar." >&2
    exit 1
  fi
  if [ -z "$REMOTE_TAG_SHA" ]; then
    # Tag fehlt bei GitHub: lokal anlegen, falls nötig, und ohne --force pushen.
    # Ohne Force scheitert der Push, falls dort doch etwas anderes steht.
    git -C "$PROJECT_ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
      || git -C "$PROJECT_ROOT" tag -a "$TAG" -m "Exploids $TAG"
    git -C "$PROJECT_ROOT" push github "refs/tags/$TAG"
  elif [ "$REMOTE_TAG_SHA" != "$BUILD_SHA" ]; then
    echo "FEHLER: Tag $TAG zeigt bei GitHub auf ${REMOTE_TAG_SHA:0:12}," >&2
    echo "  gebaut wurde aber ${BUILD_SHA:0:12}. Ein Upload hängte das DMG an" >&2
    echo "  fremden Quellstand. Release abgebrochen." >&2
    exit 1
  fi

  # Release anlegen — oder, falls es schon existiert, nur das Asset aktualisieren.
  # `--verify-tag` lässt gh das Release nur für einen Tag anlegen, den es am Remote
  # wirklich gibt, statt ihn stillschweigend aus dem Default-Branch zu erzeugen.
  if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    gh release upload "$TAG" "$DMG_PATH" -R "$REPO" --clobber
  else
    gh release create "$TAG" "$DMG_PATH" -R "$REPO" \
      --verify-tag \
      --title "Exploids $TAG" \
      --notes-file "$NOTES_FILE"
  fi
  echo "==> Release online: https://github.com/$REPO/releases/tag/$TAG"
fi

echo
echo "==> Fertig"
echo "    DMG:   $DMG_PATH"
echo "    Größe: $(du -h "$DMG_PATH" | cut -f1)"
echo "    Test:  open \"$DMG_PATH\""
