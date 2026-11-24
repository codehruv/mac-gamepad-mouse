#!/bin/sh
# Native build using the existing macOS Command Line Tools; Xcode is optional.
set -eu
cd "$(dirname "$0")/.."
app="$(pwd)/build/GamepadMouse.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun swiftc -swift-version 5 -parse-as-library -O \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -target "$(uname -m)-apple-macos12.0" \
    GamepadMouse/*.swift -o "$app/Contents/MacOS/GamepadMouse"
cp GamepadMouse/Info.plist "$app/Contents/Info.plist"
for pair in 'CFBundleDevelopmentRegion en' 'CFBundleExecutable GamepadMouse' \
    'CFBundleIdentifier com.gamepadmouse.GamepadMouse' 'CFBundleName GamepadMouse' \
    'LSMinimumSystemVersion 12.0'; do
    /usr/libexec/PlistBuddy -c "Set :$pair" "$app/Contents/Info.plist"
done
iconutil -c icns GamepadMouse.iconset -o "$app/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$app/Contents/Info.plist"
codesign --force --sign - --options runtime "$app"
codesign --verify --strict "$app"
printf '%s\n' "$app"
