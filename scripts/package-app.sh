#!/bin/bash
# 将 SPM 产物包装成 .app，菜单栏/状态项在正式 app bundle 下行为更正常
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="SwiftInsight"
BUILD_DIR="$(swift build -c release --show-bin-path)"
BIN="$BUILD_DIR/$APP_NAME"
OUT_DIR="${1:-$ROOT_DIR/dist}"
APP_DIR="$OUT_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
ICON_SRC="$ROOT_DIR/Resources/Assets.xcassets/AppIcon.appiconset"

echo "==> Building release"
swift build -c release --product "$APP_NAME"

if [[ ! -x "$BIN" ]]; then
  echo "error: binary not found: $BIN" >&2
  exit 1
fi

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "$BIN" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# 可选：一并放入 helper（未 setuid；特权仍需 install-privileged-helper）
if [[ -x "$BUILD_DIR/SwiftInsightHelper" ]]; then
  cp "$BUILD_DIR/SwiftInsightHelper" "$MACOS_DIR/SwiftInsightHelper"
fi

# App 图标 → AppIcon.icns
if [[ -d "$ICON_SRC" ]] && command -v iconutil >/dev/null 2>&1; then
  TMP_DIR="$(mktemp -d)"
  TMP_ICONSET="$TMP_DIR/AppIcon.iconset"
  mkdir -p "$TMP_ICONSET"
  cp "$ICON_SRC/appicon-mac-16@1x.png"  "$TMP_ICONSET/icon_16x16.png"
  cp "$ICON_SRC/appicon-mac-16@2x.png"  "$TMP_ICONSET/icon_16x16@2x.png"
  cp "$ICON_SRC/appicon-mac-32@1x.png"  "$TMP_ICONSET/icon_32x32.png"
  cp "$ICON_SRC/appicon-mac-32@2x.png"  "$TMP_ICONSET/icon_32x32@2x.png"
  cp "$ICON_SRC/appicon-mac-128@1x.png" "$TMP_ICONSET/icon_128x128.png"
  cp "$ICON_SRC/appicon-mac-128@2x.png" "$TMP_ICONSET/icon_128x128@2x.png"
  cp "$ICON_SRC/appicon-mac-256@1x.png" "$TMP_ICONSET/icon_256x256.png"
  cp "$ICON_SRC/appicon-mac-256@2x.png" "$TMP_ICONSET/icon_256x256@2x.png"
  cp "$ICON_SRC/appicon-mac-512@1x.png" "$TMP_ICONSET/icon_512x512.png"
  cp "$ICON_SRC/appicon-mac-512@2x.png" "$TMP_ICONSET/icon_512x512@2x.png"
  iconutil -c icns "$TMP_ICONSET" -o "$RES_DIR/AppIcon.icns"
  rm -rf "$TMP_DIR"
  echo "==> Embedded AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-Hans</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>me.whynbnb.SwiftInsight</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>

  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

# ad-hoc 签名，便于本机启动
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "==> Done"
echo "Open: open \"$APP_DIR\""
echo "Note: 菜单栏定位请用 .app 启动验证；swift run 不是完整 bundle。"
