# SwiftInsight

[中文](README.zh-CN.md) · English

<p align="center">
  <img src="docs/app-icon.png" alt="SwiftInsight" width="128" />
</p>

> Built with Grok 4.5 / OpenCode vibe coding.

A lightweight **Activity Monitor alternative** for macOS (Swift / SwiftUI).  
Focus: **Apple vs third-party** resource breakdown, a **stable menu-bar panel**, and an optional **root Helper** for protected metrics.

<p align="center">
  <img src="docs/preview-main-en.png" alt="SwiftInsight main window" width="900" />
</p>

<p align="center">
  <img src="docs/preview-menu-en.png" alt="SwiftInsight menu bar panel" width="320" />
</p>

---

## Highlights

| Area | What you get |
|------|----------------|
| **Processes** | Live list with CPU / memory / threads / user / PID / path / Bundle ID |
| **Classification** | Apple System · Apple Apps · Third-Party |
| **Views** | Flat list · app aggregation tree · parent/child tree |
| **System strip** | CPU (cores, E/P), memory (app/wired/compressed), pressure, swap, net, disk, load |
| **History** | CPU / memory / category CPU charts |
| **Menu bar** | Mini icon + compact panel; reopen main window after close (Dock hides when window is closed) |
| **Prefs** | Language, theme, refresh, launch at login, top-process count, Helper install |

---

## Features

### Process monitoring
- Search, category filters, sort, quit / force quit, Reveal in Finder  
- Hold **⌃ Control** to pause auto-refresh while inspecting  

### System overview
- **CPU** — user/system, per-core rings (efficiency / performance colors), adaptive multi-row or bar layout for high core counts  
- **Memory** — app / wired / compressed / available  
- **Memory pressure** — aligned with Activity Monitor jetsam (`kern.memorystatus_vm_pressure_level`)  
- Swap, network throughput, page in/out, load average  
- Optional **CPU frequency / temperature** when the privileged Helper is installed  

### Menu bar
- Icon modes: **CPU only** (label + horizontal bar) · **MEM only** · **CPU + MEM** dual bars  
- Panel: pressure + memory rings, core strip, category composition (vs 100% / physical RAM), configurable top processes (3–15, default 8)  
- Footer: open main window, quit, shortcuts to **Activity Monitor** and **System Information** (real app icons)  
- Context menu: open main window, launch at login, version, GitHub, quit  
- Positioning uses `NSPanel` — run a real **`.app`**, not raw `swift run`  

### Window / Dock
- Closing the main window **hides** it (app stays in the menu bar)  
- Dock icon hides when no main/settings/about window is visible  
- Reopen from menu bar (**Full Window** / **Open Main Window**) or Dock reopen  

### Settings
- Language: System / 中文 / English  
- Theme: System / Light / Dark  
- Refresh interval · menu bar icon mode · top-process count · **Launch at Login** (`SMAppService`)  
- Privileged Helper: one-click install / uninstall (admin password; no source needed on the target Mac)  

---

## Requirements

- macOS **14+**  
- Xcode **15+** (or Swift 5.9+ with macOS SDK)  
- Optional: [XcodeGen](https://github.com/yonaskolb/XcodeGen) after editing `project.yml`  

---

## Build & run

### Recommended (menu bar + login item behave correctly)

```bash
./scripts/run-app.sh          # Debug .app, then open
./scripts/run-app.sh Release
```

Avoid for menu-bar checks:
- `swift run` — no proper app bundle (icon / panel / login item may fail)  
- Opening `Package.swift` as if it were a macOS Application  

### Xcode

```bash
xcodegen generate             # only if project.yml changed
open SwiftInsight.xcodeproj
```

Scheme **SwiftInsight** → Clean Build Folder → **⌘R**.  
Helper is built and copied into `SwiftInsight.app/Contents/MacOS/` automatically.

### SwiftPM (compile / logic only)

```bash
swift build
swift run --product SwiftInsight
```

### Package a local `.app`

```bash
./scripts/package-app.sh
open dist/SwiftInsight.app
```

Also embeds `SwiftInsightHelper` (unsigned, not setuid).

---

## Privileged Helper (optional)

Some system-protected processes show **N/A** for normal users. The Helper samples with elevated rights and can provide **frequency / temperature**.

### From the app (preferred, no source on the target machine)

1. Run a packaged **`.app`** (Xcode or `package-app.sh`) — Helper is **bundled** inside.  
2. **Settings → Privileged sampling → Install Helper…**  
3. Enter the admin password.  

Installs to:

```text
/usr/local/libexec/SwiftInsightHelper   # root:wheel, mode 4755 (setuid)
```

Uninstall from the same Settings section, or:

```bash
sudo rm -f /usr/local/libexec/SwiftInsightHelper
```

### From Terminal (still no source required if you have a built `.app`)

```bash
./scripts/install-privileged-helper.sh \
  /path/to/SwiftInsight.app/Contents/MacOS/SwiftInsightHelper
```

> For personal / local use only. Not notarized for App Store distribution.

---

## Project layout

```text
Package.swift                 # SwiftPM
project.yml                   # XcodeGen → SwiftInsight.xcodeproj
SwiftInsight.xcodeproj/       # Xcode project (shared sources)
Sources/SwiftInsight/         # Main app (SwiftUI + AppKit menu bar)
Sources/SwiftInsightHelper/   # Privileged sampling helper
Resources/Assets.xcassets/    # App icon
scripts/                      # run / package / install helper
docs/                         # Screenshots & logo
```

| | SwiftPM | Xcode / packaged `.app` |
|--|---------|-------------------------|
| Config | `Package.swift` | `project.yml` → `.xcodeproj` |
| Sources | `Sources/` | same |
| Output | executable | `.app` (+ embedded Helper) |
| Menu bar / login item | limited | **recommended** |

---

## License

[MIT](LICENSE) © 2026 [0x574859](https://github.com/WHYBBE) / [WHYBBE/SwiftInsight](https://github.com/WHYBBE/SwiftInsight)
