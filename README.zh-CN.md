# SwiftInsight

[English](README.md) · 中文

> 使用 Grok 4.5 / OpenCode Vibe Coding 而成。

macOS **活动监视器替代应用**，使用 **Swift / SwiftUI** 构建。  
侧重：**Apple / 第三方资源对比**、稳定的**菜单栏轻量面板**，以及可选的 **root Helper** 补全受限指标。


<p align="center">
  <img src="docs/preview-main-zh.png" alt="SwiftInsight 主窗口" width="900" />
</p>

<p align="center">
  <img src="docs/preview-menu-zh.png" alt="SwiftInsight 菜单栏面板" width="320" />
</p>

## 功能

### 进程监控
- 实时列表：CPU、内存、线程、用户、PID、路径、Bundle ID
- **分类**
  - **Apple 系统** — 内核、launchd、守护进程、`/System`、`/usr` 等
  - **Apple 应用** — `com.apple.*` / 系统自带 App
  - **第三方** — 其余进程
- 视图：**扁平列表**、**应用聚合树**、**父子进程树**
- 搜索、分类筛选、排序、退出 / 强制退出、在 Finder 中显示

### 系统总览
- **CPU** — 总占用、用户/系统、每核小环（能效/性能着色），多核自动换行或竖条直方图  
  安装 Helper 后可显示**频率 / 温度**
- **内存** — 应用 / 联动 / 压缩 / 可用，构成条  
  **内存压力**对齐活动监视器 jetsam 档位（`kern.memorystatus_vm_pressure_level`）
- 交换、网络吞吐、页换入出、负载
- 历史曲线（CPU、内存、Apple vs 第三方 CPU）
- 分类高占用排行

### 菜单栏
- 状态栏迷你条（仅 CPU / 仅内存 / 叠加）
- 精简面板：压力环 + 内存环、核心条、构成（相对 100% / 物理内存）、高占用进程
- 使用 `NSPanel` 稳定定位（请用打包的 `.app`，不要用裸 `swift run` 测位置）

### 设置
- **语言**：跟随系统 / 中文 / English  
- **主题**：跟随系统 / 浅色 / 深色  
- 刷新间隔；按住 **⌃ Control** 暂停自动刷新  
- 可选 **setuid root Helper** 补全受保护进程与传感器数据

## 环境要求

- macOS 14+
- Xcode 15+（或带 macOS SDK 的 Swift 5.9+）
- 可选：[XcodeGen](https://github.com/yonaskolb/XcodeGen)（重新生成工程时）

## 构建与运行

### 推荐（菜单栏行为正确）

```bash
./scripts/run-app.sh          # Debug .app 并打开
./scripts/run-app.sh Release
```

**不要用** `swift run` 验证菜单栏位置（无正式 bundle，坐标不稳）。  
**不要用** `open Package.swift` 当 macOS Application。

### Xcode

```bash
xcodegen generate             # 修改 project.yml 后
open SwiftInsight.xcodeproj
```

选 scheme **SwiftInsight** → Clean Build Folder → ⌘R。

### SwiftPM（仅编译 / 逻辑）

```bash
swift build
swift run --product SwiftInsight
```

### 打本地 .app 包

```bash
./scripts/package-app.sh
open dist/SwiftInsight.app
```

## 特权 Helper（可选）

部分 root / 系统保护进程对普通用户返回 **N/A**。自用可安装：

```bash
./scripts/install-privileged-helper.sh   # 安装 setuid root 助手
# 卸载：
sudo rm -f /usr/local/libexec/SwiftInsightHelper
```

安装后 Helper 还可采样 **CPU 频率 / 温度**（`powermetrics` + SMC）。  
需管理员密码，仅建议本机自用。

## 项目结构

```
Package.swift                 # SwiftPM
project.yml                   # XcodeGen → SwiftInsight.xcodeproj
SwiftInsight.xcodeproj/       # Xcode 工程（与 SPM 共享源码）
Sources/SwiftInsight/         # 主程序（SwiftUI + AppKit 菜单栏）
Sources/SwiftInsightHelper/   # setuid 采样助手
scripts/                      # 运行 / 打包 / 安装 Helper
docs/                         # 预览截图
```

| | SwiftPM | Xcode / 打包 `.app` |
|--|---------|---------------------|
| 配置 | `Package.swift` | `project.yml` → `.xcodeproj` |
| 源码 | `Sources/` | 同左 |
| 产物 | 可执行文件 | `.app` |
| 菜单栏 | 可能错位 | 推荐 |

## 许可证

[MIT](LICENSE) © 2026 0x574859
