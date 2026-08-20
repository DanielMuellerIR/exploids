#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "=== Building Exploids in Release Mode ==="
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release

echo "=== Creating App Bundle Directory Structure ==="
rm -rf Exploids.app
mkdir -p Exploids.app/Contents/MacOS
mkdir -p Exploids.app/Contents/Resources

echo "=== Copying Executable Binary ==="
cp .build/release/exploids Exploids.app/Contents/MacOS/exploids

echo "=== Copying Resource Bundle (music) ==="
# Das von SwiftPM erzeugte GameCore-Ressourcenbundle ins .app legen, damit
# GameCoreResources.bundle Musik, Grafik, Schrift und SFX dort findet.
if [ -d .build/release/exploids_GameCore.bundle ]; then
    cp -R .build/release/exploids_GameCore.bundle Exploids.app/Contents/Resources/
fi

echo "=== App Icon ==="
# Icon regenerieren, falls es fehlt (Quelle: tools/make-icon.swift -> Icon/icon_1024.png -> AppIcon.icns).
if [ ! -f AppIcon.icns ]; then
    echo "AppIcon.icns fehlt – wird neu erzeugt ..."
    mkdir -p Icon
    swift tools/make-icon.swift Icon/icon_1024.png
    rm -rf Exploids.iconset && mkdir -p Exploids.iconset
    for entry in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
                 "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" \
                 "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
        px="${entry%%:*}"; name="${entry##*:}"
        sips -z "$px" "$px" Icon/icon_1024.png --out "Exploids.iconset/${name}.png" >/dev/null
    done
    iconutil -c icns Exploids.iconset -o AppIcon.icns
    rm -rf Exploids.iconset
fi
cp AppIcon.icns Exploids.app/Contents/Resources/AppIcon.icns

echo "=== Writing Info.plist ==="
# Version aus der VERSION-Datei ziehen (Single Source of Truth) statt sie hier hart zu
# codieren — vorher driftete die Info.plist-Version bei jedem Release, wenn man das
# Skript vergaß. Die Build-Nummer (CFBundleVersion) muss nur monoton wachsen; die
# Commit-Anzahl des Repos leistet das automatisch (ersetzt das manuelle Hochzählen).
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
cat > Exploids.app/Contents/Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>exploids</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.danielmuellerir.exploids</string>
    <key>CFBundleName</key>
    <string>Exploids</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Debug-Symbole entfernen. `swift build -c release` legt eine Debug-Map in die
# Binärdatei: für jede übersetzte Quelldatei einen Eintrag mit dem vollen Pfad
# ihrer .o-Datei auf DIESEM Mac (14 Stück, gefunden am 2026-08-04 in der
# ausgelieferten App). Das Spiel braucht das nicht, es verrät nur Benutzernamen
# und Projektaufbau. `strip -S` nimmt genau diese Debug-Symbole und lässt die
# normale Symboltabelle stehen, damit Absturzberichte lesbar bleiben. Xcode tut
# das bei Release-Builds von sich aus (STRIP_STYLE=debugging), SwiftPM nicht.
#
# Danach wird das gesamte Bundle signiert. Die Linker-Signatur deckt nur die
# einzelne Binary ab; erst die Bundle-Signatur legt Contents/_CodeSignature/
# CodeResources an und verwendet den Bundle-Identifier aus der Info.plist.
echo "=== Debug-Symbole entfernen ==="
strip -S Exploids.app/Contents/MacOS/exploids
codesign --force --sign - Exploids.app

echo "=== App Bundle Created Successfully: Exploids.app ==="
echo "You can now double-click Exploids.app in Finder to run the game!"
