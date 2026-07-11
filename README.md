# SwiftInsight

macOS 活动监视器替代应用，使用 **Swift / SwiftUI** 构建。支持 **SwiftPM** 与 **Xcode 工程** 双路径。

## 核心能力

- 实时列出系统进程（CPU、内存、线程、用户、PID、路径）
- **区分 Apple 第一方与第三方进程占用**
  - **Apple 系统**：`kernel_task`、`launchd`、系统守护进程、`/System`、`/usr` 等
  - **Apple 应用**：`com.apple.*` Bundle ID、系统自带 App
  - **第三方**：其余进程
- 侧边栏汇总 CPU / 内存按类别占比
- 搜索、分类筛选、排序、退出 / 强制退出进程
- 菜单栏轻量面板（`NSStatusItem` + `NSPopover`）

## 要求

- macOS 14+
- Xcode 15+（或带 macOS SDK 的 Swift 5.9+ 工具链）
- 可选：`xcodegen`（重新生成 `.xcodeproj` 时）

## 构建与运行

### 推荐：一键 .app（与已验证可用路径相同）

```bash
./scripts/run-app.sh          # Debug .app 并 open
./scripts/run-app.sh Release  # Release
```

**不要用** `swift run` 测菜单栏位置（raw 二进制无正式 bundle，坐标不稳）。  
**不要用** `open Package.swift`（那是 SPM 包，不是 macOS Application）。

### Xcode

```bash
xcodegen generate          # 改过 project.yml 时
open SwiftInsight.xcodeproj
```

选 scheme **SwiftInsight** → Product → **Clean Build Folder** → ⌘R。  
若仍异常：删掉 `~/Library/Developer/Xcode/DerivedData/SwiftInsight-*` 后再编。

### SwiftPM（仅编译/逻辑，不测菜单栏定位）

```bash
swift build
swift run --product SwiftInsight   # 数据可用，菜单栏位置可能歪
```

### 打本地 .app 包（SPM 产物）

```bash
./scripts/package-app.sh
open dist/SwiftInsight.app
```

## 权限说明

- 本用户与多数进程：可通过 `libproc`（`PROC_PIDTASKINFO`）正常读取 CPU / 内存。
- **部分 root / 系统保护进程**：普通用户会被内核拒绝，界面显示 **N/A**。
- **自用提权**：

```bash
./scripts/install-privileged-helper.sh
sudo rm -f /usr/local/libexec/SwiftInsightHelper
```

## 项目结构

```
Package.swift                 # SPM
project.yml                   # XcodeGen → SwiftInsight.xcodeproj
SwiftInsight.xcodeproj/       # 生成的 Xcode 工程（与 SPM 共享源码）
Sources/SwiftInsight/         # 主 GUI
Sources/SwiftInsightHelper/   # setuid root 采样助手
scripts/
```

## 双路径说明

| | SwiftPM | Xcode 工程 |
|--|---------|------------|
| 配置 | `Package.swift` | `project.yml` → `.xcodeproj` |
| 源码 | `Sources/` 共用 | 同左 |
| 产物 | 可执行文件 | `.app` bundle |
| 菜单栏 | 可能异常 | 推荐验证路径 |
