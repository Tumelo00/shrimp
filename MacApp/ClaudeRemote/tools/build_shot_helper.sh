#!/bin/bash
# CRShot yakalama yardımcısını BİR KEZ derler + imzalar. Sonra dokunma ki
# imzası (dolayısıyla Ekran Kaydı izni) sabit kalsın.
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/CRShot.app"
swiftc crshot.swift -o /tmp/crshot_bin
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp /tmp/crshot_bin "$APP/Contents/MacOS/CRShot"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>CRShot</string>
  <key>CFBundleIdentifier</key><string>com.crshot.helper</string>
  <key>CFBundleName</key><string>CRShot</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "CRShot kuruldu: $APP"
echo "Bir kez Ekran Kaydi izni ver; sonra bir daha sormaz."
