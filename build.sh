#!/bin/zsh
# Builds Glaze.app (no Xcode project) and ad-hoc signs it. Needs Xcode command-line tools.
set -e
cd "$(dirname "$0")"
APP=Glaze.app
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp icon/AppIcon.icns $APP/Contents/Resources/   # regenerate with: python3 icon/make_icon.py
cat > $APP/Contents/Info.plist <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.longado.glaze</string>
<key>CFBundleName</key><string>Glaze</string>
<key>CFBundleExecutable</key><string>Glaze</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSCameraUsageDescription</key><string>Checks whether you are facing the screen, to frost it when you look away. Frames are never stored or sent anywhere.</string>
</dict></plist>
PL
swiftc -O -framework Cocoa -framework AVFoundation -framework Vision -framework Carbon Calib.swift main.swift -o $APP/Contents/MacOS/Glaze
codesign -s - --force --options runtime --entitlements entitlements.plist $APP
echo "built $APP"
