#!/bin/bash
# Shrimp.app'i derler, .app bundle olarak paketler ve ad-hoc imzalar.
# Mac'te calistir:  bash build_app.sh   (Xcode/Swift toolchain gerekir)
set -e
cd "$(dirname "$0")"

CONFIG="${1:-release}"     # release | debug
APP="$HOME/Applications/Shrimp.app"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"
BIN=".build/$CONFIG/ClaudeRemote"

echo "==> ikon (shrimp logo — assets/shrimp-logo.png karttan kirpilir)"
if [ -f assets/shrimp-logo.png ]; then
  sips -c 920 920 assets/shrimp-logo.png --out /tmp/cr_crop.png >/dev/null 2>&1
  sips -z 1024 1024 /tmp/cr_crop.png --out /tmp/cr_shrimp.png >/dev/null 2>&1
else
  # yedek: cizilen shrimp
  swiftc icon_gen.swift -o /tmp/cr_icongen 2>/dev/null && /tmp/cr_icongen /tmp/cr_shrimp.png
fi
ICONSET=/tmp/Shrimp.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for sz in 16 32 64 128 256 512 1024; do
  sips -z $sz $sz /tmp/cr_shrimp.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null 2>&1
done
cp "$ICONSET/icon_32x32.png"     "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/icon_64x64.png"     "$ICONSET/icon_32x32@2x.png"
cp "$ICONSET/icon_256x256.png"   "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/icon_512x512.png"   "$ICONSET/icon_256x256@2x.png"
cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
rm -f "$ICONSET/icon_64x64.png" "$ICONSET/icon_1024x1024.png"

echo "==> paketleniyor: $APP"
pkill -f "Shrimp.app/Contents/MacOS" 2>/dev/null || true
pkill -f "ClaudeRemote.app/Contents/MacOS" 2>/dev/null || true   # eski isim
rm -rf "$APP" "$HOME/Applications/ClaudeRemote.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Shrimp"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null && echo "    ikon gomuldu"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Shrimp</string>
  <key>CFBundleIdentifier</key><string>com.tumer.clauderemote</string>
  <key>CFBundleName</key><string>Shrimp</string>
  <key>CFBundleDisplayName</key><string>Shrimp</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSUserNotificationAlertStyle</key><string>alert</string>
  <!-- ONEMLI: sadece NSAllowsArbitraryLoads. NSAllowsLocalNetworking EKLEME
       (macOS 26'da NSAllowsArbitraryLoads'u yok saydirip Tailscale cleartext'i engeller). -->
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST

echo "==> ad-hoc imza"
codesign --force --deep --sign - "$APP"

echo "==> tamam: $APP"
echo "    Acmak icin:  open \"$APP\""
