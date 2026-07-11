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

读取其他用户进程的详细信息时，部分字段可能为空；结束系统进程通常需要更高权限。应用本身不需要特殊沙盒权限即可在本地以普通用户运行并查看本用户及多数系统进程。

## 项目结构

```
Sources/SwiftInsight/
  App/SwiftInsightApp.swift      # 入口
  Models/ProcessModels.swift     # 数据模型
  Services/
    ProcessMonitor.swift         # 进程采集（libproc）
    ProcessClassifier.swift      # Apple / 第三方分类
  Views/
    ContentView.swift            # 主界面 + 侧边栏 + 汇总
    ProcessTableView.swift       # 进程表
    SettingsView.swift           # 设置
```
