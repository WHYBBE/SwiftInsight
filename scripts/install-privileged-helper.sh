#!/bin/bash
# 自用：安装 root 特权采样助手，用于读取系统保护进程的 CPU/内存
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Building SwiftInsightHelper (release)"
swift build -c release --product SwiftInsightHelper

HELPER_SRC="$(swift build -c release --show-bin-path)/SwiftInsightHelper"
INSTALL_DIR="/usr/local/libexec"
INSTALL_PATH="$INSTALL_DIR/SwiftInsightHelper"

if [[ ! -x "$HELPER_SRC" ]]; then
  echo "error: built helper not found at $HELPER_SRC" >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "==> Re-running with sudo"
  exec sudo "$0" "$@"
fi

mkdir -p "$INSTALL_DIR"
cp "$HELPER_SRC" "$INSTALL_PATH"
chown root:wheel "$INSTALL_PATH"
# setuid root：主应用以普通用户调用即可获得 root 可读的 taskinfo
chmod 4755 "$INSTALL_PATH"

echo "==> Installed: $INSTALL_PATH"
ls -la "$INSTALL_PATH"
echo "==> status:"
"$INSTALL_PATH" status
echo
echo "Done. Relaunch SwiftInsight; privileged metrics should fill former N/A rows."
echo "Uninstall: sudo rm -f $INSTALL_PATH"
