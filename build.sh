#!/bin/zsh
# Builds ClaudeStatus.app without Xcode (Command Line Tools are enough).
#
#   ./build.sh          build into build/ClaudeStatus.app
#   ./build.sh run      build, then launch it
#   ./build.sh install  build, copy to /Applications, launch
set -euo pipefail
cd "$(dirname "$0")"

APP=ClaudeStatus
BUNDLE_ID=local.claudestatus
OUT=build/$APP.app
SDK=$(xcrun --show-sdk-path --sdk macosx)
ARCH=$(uname -m)

rm -rf build
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

echo "Compiling…"
swiftc -O \
  -sdk "$SDK" \
  -target "$ARCH-apple-macos13.0" \
  -module-name "$APP" \
  -o "$OUT/Contents/MacOS/$APP" \
  App.swift Service.swift Views.swift

cp assets/claude.png "$OUT/Contents/Resources/claude.png"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>      <string>en</string>
	<key>CFBundleExecutable</key>             <string>$APP</string>
	<key>CFBundleIdentifier</key>             <string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>  <string>6.0</string>
	<key>CFBundleName</key>                   <string>$APP</string>
	<key>CFBundlePackageType</key>            <string>APPL</string>
	<key>CFBundleShortVersionString</key>     <string>1.0</string>
	<key>CFBundleVersion</key>                <string>1</string>
	<key>LSMinimumSystemVersion</key>         <string>13.0</string>
	<key>LSUIElement</key>                    <true/>
	<key>NSHighResolutionCapable</key>        <true/>
	<key>NSPrincipalClass</key>               <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "Signing (ad-hoc)…"
codesign --force --sign - "$OUT"

echo "Built $OUT"

case "${1:-}" in
  run)
    open "$OUT" ;;
  install)
    rm -rf "/Applications/$APP.app"
    cp -R "$OUT" /Applications/
    open "/Applications/$APP.app"
    echo "Installed /Applications/$APP.app" ;;
esac
