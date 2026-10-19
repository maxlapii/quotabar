#!/bin/zsh
# Builds ClaudeStatus.app without Xcode (Command Line Tools are enough).
#
#   ./build.sh          build into build/ClaudeStatus.app
#   ./build.sh run      build, then launch it
#   ./build.sh install  build, copy to /Applications (or ~/Applications), launch
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
    # /Applications needs an admin account; everyone can use ~/Applications.
    DEST=/Applications
    if ! { mkdir "$DEST/.$APP-write-test" 2>/dev/null && rmdir "$DEST/.$APP-write-test"; }; then
      DEST="$HOME/Applications"
      mkdir -p "$DEST"
    fi
    pkill -f "$APP.app/Contents/MacOS/$APP" 2>/dev/null || true
    rm -rf "$DEST/$APP.app"
    cp -R "$OUT" "$DEST/"
    open "$DEST/$APP.app"
    echo "Installed $DEST/$APP.app" ;;
esac
