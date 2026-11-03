#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/Quick Port.app"
CARGO_TARGET=$(cargo metadata --no-deps --format-version 1 | python3 -c 'import json,sys; print(json.load(sys.stdin)["target_directory"])')
RUST_TARGET=${RUST_TARGET:-$(rustc -vV | sed -n 's/^host: //p')}
case "$RUST_TARGET" in
    aarch64-apple-darwin) APP_ARCH=arm64 ;;
    x86_64-apple-darwin) APP_ARCH=x86_64 ;;
    *) echo "Quick Port requires macOS." >&2; exit 1 ;;
esac
cargo build --release --locked --target "$RUST_TARGET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$CARGO_TARGET/$RUST_TARGET/release/quick-port" "$APP/Contents/Helpers/quick-port"
xcrun swiftc -O -parse-as-library -target "$APP_ARCH-apple-macosx14.0" macos/*.swift -o "$APP/Contents/MacOS/QuickPort"
VERSION=$(cargo metadata --no-deps --format-version 1 | python3 -c 'import json,sys; print(next(p["version"] for p in json.load(sys.stdin)["packages"] if p["name"] == "quick-port"))')
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>QuickPort</string>
<key>CFBundleIdentifier</key><string>com.cesarferreira.quick-port</string>
<key>CFBundleName</key><string>Quick Port</string>
<key>CFBundleDisplayName</key><string>Quick Port</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
ICONSET="dist/AppIcon.iconset"
mkdir -p "$ICONSET"
xcrun swift scripts/generate-icon.swift dist/icon-1024.png
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" dist/icon-1024.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" dist/icon-1024.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP/Contents/Helpers/quick-port"
codesign --force --sign - "$APP"
echo "Built $APP"
