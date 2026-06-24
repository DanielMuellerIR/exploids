#!/bin/bash
set -e

echo "=== Building Exploids in Release Mode ==="
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release

echo "=== Creating App Bundle Directory Structure ==="
rm -rf Exploids.app
mkdir -p Exploids.app/Contents/MacOS
mkdir -p Exploids.app/Contents/Resources

echo "=== Copying Executable Binary ==="
cp .build/release/exploids Exploids.app/Contents/MacOS/exploids

echo "=== Copying Resource Bundle (music) ==="
# Das SwiftPM-Resource-Bundle (Bundle.module) ins .app legen, damit die Musik auch in der
# doppelklickbaren App gefunden wird.
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
cat > Exploids.app/Contents/Info.plist << 'EOF'
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
    <string>0.9.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "=== App Bundle Created Successfully: Exploids.app ==="
echo "You can now double-click Exploids.app in Finder to run the game!"
