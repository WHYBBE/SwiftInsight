# SwiftInsight

macOS 活动监视器替代应用，使用 **Swift / SwiftUI / SwiftPM** 构建。

## 核心能力

- 实时列出系统进程（CPU、内存、线程、用户、PID、路径）
- **区分 Apple 第一方与第三方进程占用**
  - **Apple 系统**：`kernel_task`、`launchd`、系统守护进程、`/System`、`/usr` 等
  - **Apple 应用**：`com.apple.*` Bundle ID、系统自带 App
  - **第三方**：其余进程
- 侧边栏汇总 CPU / 内存按类别占比
- 搜索、分类筛选、排序、退出 / 强制退出进程

## 要求

- macOS 14+
- Xcode 15+（或带 macOS SDK 的 Swift 5.9+ 工具链）

## 构建与运行

```bash
cd /Users/tom/Downloads/SwiftInsight
swift build -c release
swift run
```

或用 Xcode 打开：

```bash
open Package.swift
```

然后选择 `SwiftInsight` scheme 运行。

## 权限说明

- 本用户与多数进程：可通过 `libproc`（`PROC_PIDTASKINFO`）正常读取 CPU / 内存。
- **部分 root / 系统保护进程**（如 `amfid`、`trustd`、`sysmond`、XProtect 相关）：普通用户会被内核拒绝，界面显示 **N/A**。
- **活动监视器能读到**：它是系统组件，通过 `sysmond` + 私有 entitlement（如 `com.apple.sysmond.client`、`com.apple.system-task-ports.read`）。第三方 App 默认没有。
- **自用提权（推荐）**：安装 setuid root Helper，主程序合并其采样结果，即可覆盖原 N/A 行：

```bash
./scripts/install-privileged-helper.sh   # 会请求 sudo
# 卸载
sudo rm -f /usr/local/libexec/SwiftInsightHelper
```

Helper 只做一件事：以 root 调用 `PROC_PIDTASKINFO` 并输出 JSON。不涉及公证/上架。

## 项目结构

```
Sources/SwiftInsight/          # 主 GUI
Sources/SwiftInsightHelper/    # setuid root 采样助手
scripts/install-privileged-helper.sh
```

