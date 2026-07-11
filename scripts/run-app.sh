#!/bin/bash
# 与已验证可用路径一致：编成 .app 再 open（不要用 raw swift run 测菜单栏）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-Debug}"
DERIVED="$ROOT/.build/DerivedData"
APP="$DERIVED/Build/Products/$CONFIG/SwiftInsight.app"

echo "==> 结束旧进程"
pkill -9 -f 'SwiftInsight.app/Contents/MacOS/SwiftInsight' 2>/dev/null || true
pkill -9 -f '/\.build/.*/SwiftInsight$' 2>/dev/null || true
sleep 0.3

if [[ ! -f "$ROOT/SwiftInsight.xcodeproj/project.pbxproj" ]]; then
  if command -v xcodegen >/dev/null 2>&1; then
    echo "==> xcodegen generate"
    xcodegen generate
  else
    echo "error: 需要 SwiftInsight.xcodeproj 或安装 xcodegen" >&2
    exit 1
  fi
fi

echo "==> xcodebuild ($CONFIG)"
xcodebuild \
  -project "$ROOT/SwiftInsight.xcodeproj" \
  -scheme SwiftInsight \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  build \
  | tail -20

if [[ ! -x "$APP/Contents/MacOS/SwiftInsight" ]]; then
  echo "error: app not found: $APP" >&2
  exit 1
fi

echo "==> open $APP"
open "$APP"
echo "done"
