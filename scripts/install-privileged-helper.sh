#!/bin/bash
# 将 App 内嵌（或构建产物）的 Helper 安装为 setuid root
# 无需目标机源码 / Swift 工具链
set -euo pipefail

INSTALL_DIR="/usr/local/libexec"
INSTALL_PATH="$INSTALL_DIR/SwiftInsightHelper"
HELPER_NAME="SwiftInsightHelper"

resolve_source() {
  # 1) 命令行参数
  if [[ $# -ge 1 && -x "$1" ]]; then
    echo "$1"
    return
  fi
  # 2) 环境变量
  if [[ -n "${SWIFTINSIGHT_HELPER_SRC:-}" && -x "${SWIFTINSIGHT_HELPER_SRC}" ]]; then
    echo "$SWIFTINSIGHT_HELPER_SRC"
    return
  fi
  # 3) 同目录 / 常见 .app 位置
  local here
  here="$(cd "$(dirname "$0")" && pwd)"
  local candidates=(
    "$here/$HELPER_NAME"
    "$here/../MacOS/$HELPER_NAME"
    "$here/../../MacOS/$HELPER_NAME"
    "/Applications/SwiftInsight.app/Contents/MacOS/$HELPER_NAME"
  )
  # 4) 开发机：SPM 产物
  if command -v swift >/dev/null 2>&1; then
    local root
    root="$(cd "$(dirname "$0")/.." && pwd)"
    if [[ -d "$root" ]]; then
      local bin
      bin="$(cd "$root" && swift build -c release --show-bin-path 2>/dev/null || true)"
      if [[ -n "$bin" && -x "$bin/$HELPER_NAME" ]]; then
        candidates+=("$bin/$HELPER_NAME")
      fi
    fi
  fi
  local c
  for c in "${candidates[@]}"; do
    if [[ -x "$c" ]]; then
      echo "$c"
      return
    fi
  done
  return 1
}

SRC="$(resolve_source "$@" || true)"
if [[ -z "${SRC:-}" ]]; then
  echo "error: 找不到 SwiftInsightHelper" >&2
  echo "用法: $0 [/path/to/SwiftInsight.app/Contents/MacOS/SwiftInsightHelper]" >&2
  echo "或先构建/打包 App，使 Contents/MacOS 内含 Helper。" >&2
  exit 1
fi

echo "==> Source: $SRC"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "==> Re-running with sudo"
  exec sudo "$0" "$SRC"
fi

mkdir -p "$INSTALL_DIR"
cp -f "$SRC" "$INSTALL_PATH"
chown root:wheel "$INSTALL_PATH"
chmod 4755 "$INSTALL_PATH"

echo "==> Installed: $INSTALL_PATH"
ls -la "$INSTALL_PATH"
echo "==> status:"
"$INSTALL_PATH" status
echo
echo "Done. Relaunch SwiftInsight."
echo "Uninstall: sudo rm -f $INSTALL_PATH"
