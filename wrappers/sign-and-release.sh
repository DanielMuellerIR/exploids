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
if [ "$PUBLISH" = "1" ]; then
  require_tag_matches_head "v${APP_VERSION}" || exit 1
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

MOUNT_DIR="/Volumes/$VOLNAME"
hdiutil attach "$RW_DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -noverify -noautoopen

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
spctl --assess --type open --context context:primary-signature -v "$DMG_PATH" || true

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

  # git-Tag setzen (idempotent) und zum github-Remote pushen. Die Vorbedingung von
  # oben hier direkt vor dem Push erneut prüfen: Zwischen Start und diesem Punkt
  # liegen Bau und Notarisierung, HEAD kann sich in der Zeit bewegt haben.
  require_tag_matches_head "$TAG" || exit 1
  if ! git -C "$PROJECT_ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    git -C "$PROJECT_ROOT" tag -a "$TAG" -m "Exploids $TAG"
    git -C "$PROJECT_ROOT" push github "$TAG"
  fi

  # Release anlegen — oder, falls es schon existiert, nur das Asset aktualisieren.
  if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    gh release upload "$TAG" "$DMG_PATH" -R "$REPO" --clobber
  else
    gh release create "$TAG" "$DMG_PATH" -R "$REPO" \
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
