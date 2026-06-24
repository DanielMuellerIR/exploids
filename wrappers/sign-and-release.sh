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
#   2. notarytool-Keychain-Profil (Name via NOTARY_PROFILE). Falls fehlend,
#      einmalig anlegen:
#        xcrun notarytool store-credentials "$NOTARY_PROFILE" \
#          --apple-id <deine-apple-id> --team-id "$APPLE_TEAM_ID"
#      (App-spezifisches Passwort INTERAKTIV eingeben, NIE als CLI-Argument.)
#   3. Signing-Konfiguration bereitstellen (maschinen-/account-spezifisch, NICHT
#      im öffentlichen Repo): Environment-Variablen oder die gitignorete lokale
#      Datei wrappers/release.local.sh (Vorlage: wrappers/release.local.sh.example).
#
# Aufruf:  bash wrappers/sign-and-release.sh
#          bash wrappers/sign-and-release.sh --publish   # setzt git-Tag + lädt DMG zu GitHub hoch
#
# Exploids ist ein reines SwiftPM-Executable ohne eingebettete Frameworks —
# darum genügt es, das Bundle selbst zu signieren (kein Framework-Vorsignieren
# wie z. B. bei VLCKit).

set -euo pipefail

# ---------- Signing-/Notary-Konfiguration ----------
# Maschinen-/account-spezifisch und damit NICHT im öffentlichen Repo hinterlegt.
# Quelle (Priorität): Environment-Variablen, sonst die gitignorete lokale Datei
# wrappers/release.local.sh (Vorlage: release.local.sh.example). Werte sind zentral
# in der projektprivaten theplan-Wissensbasis dokumentiert.
__CONF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/release.local.sh"
# shellcheck source=/dev/null
[ -f "$__CONF" ] && source "$__CONF"

TEAM_ID="${APPLE_TEAM_ID:-}"
IDENTITY="${CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [ -z "$TEAM_ID" ] || [ -z "$IDENTITY" ] || [ -z "$NOTARY_PROFILE" ]; then
  echo "FEHLER: Signing-Konfiguration fehlt." >&2
  echo "  Benötigt: APPLE_TEAM_ID, CODESIGN_IDENTITY, NOTARY_PROFILE." >&2
  echo "  Setze sie als Environment-Variablen ODER lege wrappers/release.local.sh an" >&2
  echo "  (kopiere wrappers/release.local.sh.example und trage deine Werte ein)." >&2
  exit 1
fi

APP_NAME="Exploids"               # Bundle-/Anzeigename
VOLNAME="Exploids"                # DMG-Volume-Name (= /Volumes/<name>)
REPO="${RELEASE_REPO:-DanielMuellerIR/exploids}"   # öffentliches GitHub-Repo für --publish

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

# ---------- Sanity-Checks ----------
if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "FEHLER: Signing-Identität nicht gefunden: $IDENTITY" >&2
  security find-identity -v -p codesigning >&2
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "FEHLER: notarytool-Profil '$NOTARY_PROFILE' fehlt. Einmalig anlegen:" >&2
  echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <deine-apple-id> --team-id $TEAM_ID" >&2
  exit 1
fi
if [ ! -f "$BACKGROUND_SRC" ]; then
  echo "FEHLER: DMG-Hintergrund fehlt: $BACKGROUND_SRC" >&2
  echo "  swift assets/generate-dmg-background.swift assets/dmg-background.png" >&2
  exit 1
fi

# ---------- 1. Bauen ----------
echo "==> Baue App-Bundle"
bash "$PROJECT_ROOT/build-app.sh"

# ---------- 2. Signieren ----------
# --options runtime: Hardened Runtime (Pflicht für Notarisierung).
# --timestamp:       Apple-Zeitstempel → Signatur bleibt nach Zert-Ablauf gültig.
echo "==> Signiere App-Bundle"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP_BUNDLE"

echo "==> Verifiziere Signatur"
codesign --verify --strict --verbose=2 "$APP_BUNDLE"
codesign -dvv "$APP_BUNDLE" 2>&1 | grep -E "Authority|TeamIdentifier|flags" || true

# ---------- 3. DMG mit Installations-Layout ----------
echo "==> Erzeuge DMG-Layout"
rm -f "$DMG_PATH" "$RW_DMG_PATH"
[ -d "/Volumes/$VOLNAME" ] && hdiutil detach "/Volumes/$VOLNAME" -force >/dev/null 2>&1 || true

SIZE=$(( $(du -sm "$APP_BUNDLE" | cut -f1) + 40 ))
hdiutil create -srcfolder "$APP_BUNDLE" -volname "$VOLNAME" -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" -format UDRW -size "${SIZE}m" "$RW_DMG_PATH"

MOUNT_DIR="/Volumes/$VOLNAME"
hdiutil attach "$RW_DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -noverify -noautoopen

ln -s /Applications "$MOUNT_DIR/Applications"
mkdir -p "$MOUNT_DIR/.background"
cp "$BACKGROUND_SRC" "$MOUNT_DIR/.background/background.png"
chflags hidden "$MOUNT_DIR/.background"

# Finder-Ansicht setzen. Fenster-Innenmaß 600×400 = Hintergrundbild-Größe.
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

sync; sleep 2                       # Race: DS_Store-Schreibpuffer vs. detach
hdiutil detach "$MOUNT_DIR" -force

echo "==> Konvertiere zu komprimiertem read-only DMG"
hdiutil convert "$RW_DMG_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
rm -f "$RW_DMG_PATH"

echo "==> Signiere DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"

# ---------- 4. Notarisieren + stapeln ----------
echo "==> Notarisieren (1-10 Min)"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapele Ticket"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature -v "$DMG_PATH" || true

# ---------- 5. (optional) GitHub-Release veröffentlichen ----------
# Nur mit --publish. Setzt Tag vX.Y.Z, erstellt das Release, lädt das DMG hoch
# und entnimmt die Release-Notes aus dem passenden CHANGELOG.md-Abschnitt.
# Öffentliches Pushen ist rückfragepflichtig → daher opt-in, nicht Default.
PUBLISH=0
for arg in "$@"; do [ "$arg" = "--publish" ] && PUBLISH=1; done

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

  # git-Tag setzen (idempotent) und zum github-Remote pushen.
  if ! git -C "$PROJECT_ROOT" rev-parse "$TAG" >/dev/null 2>&1; then
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
