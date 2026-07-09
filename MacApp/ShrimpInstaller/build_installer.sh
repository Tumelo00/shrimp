#!/bin/bash
# Shrimp Kurulum.app + Shrimp-Kurulum.dmg üretir (Mac'te çalıştır).
set -e
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="Shrimp Kurulum"
APP="$HOME/Applications/$APP_NAME.app"
DMG="$HOME/Applications/Shrimp-Kurulum.dmg"
LOGO="../ClaudeRemote/assets/shrimp-logo.png"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"
BIN=".build/$CONFIG/ShrimpInstaller"

echo "==> ikon (shrimp logo)"
if [ -f "$LOGO" ]; then
  sips -c 920 920 "$LOGO" --out /tmp/si_crop.png >/dev/null 2>&1
  sips -z 1024 1024 /tmp/si_crop.png --out /tmp/si_shrimp.png >/dev/null 2>&1
  ICONSET=/tmp/ShrimpInst.iconset
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for sz in 16 32 128 256 512; do
    sips -z $sz $sz /tmp/si_shrimp.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null 2>&1
    sips -z $((sz*2)) $((sz*2)) /tmp/si_shrimp.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null 2>&1
  done
fi

echo "==> paketleniyor: $APP"
pkill -f "Shrimp Kurulum.app/Contents/MacOS" 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ShrimpInstaller"
[ -d "$ICONSET" ] && iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null && echo "    ikon gömüldü" || true

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>ShrimpInstaller</string>
  <key>CFBundleIdentifier</key><string>com.tumer.shrimpinstaller</string>
  <key>CFBundleName</key><string>Shrimp Kurulum</string>
  <key>CFBundleDisplayName</key><string>Shrimp Kurulum</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc imza"
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "==> DMG oluşturuluyor: $DMG"
STAGE=/tmp/shrimp_dmg_stage
rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
hdiutil create -volname "Shrimp Kurulum" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "==> tamam:"
echo "    app: $APP"
echo "    dmg: $DMG"
