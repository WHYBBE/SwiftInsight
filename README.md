# SwiftInsight

[中文](README.zh-CN.md) · English

<p align="center">
  <img src="docs/app-icon.png" alt="SwiftInsight" width="128" />
</p>

> Built with Grok 4.5 / OpenCode vibe coding.

A lightweight **Activity Monitor alternative** for macOS (Swift / SwiftUI).  
Focus: **Apple vs third-party** resource breakdown, a **stable menu-bar panel**, dual/triple refresh tracks for low overhead, and an optional **root Helper** for protected metrics.

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
| **Menu bar** | Mini icon + frosted panel; independent top-list mode/count; resident without main window |
| **Refresh** | Three tracks: **icon** / **panel** / **main** — separate intervals, lower idle cost |
| **Launch** | Restores last main-window vs menu-bar-only state; no create-then-hide flash |
| **Prefs** | Tabbed Settings: General · Refresh · Menu Bar · Helper · About |

---

## Features

### Process monitoring
- Search, category filters, sort, quit / force quit, Reveal in Finder  
- Hold **⌃ Control** to pause **main-window** auto-refresh only (menu bar keeps sampling)  

### System overview
- **CPU** — user/system, per-core rings (efficiency / performance colors), adaptive multi-row or bar layout for high core counts  
- **Memory** — app / wired / compressed / available  
- **Memory pressure** — aligned with Activity Monitor jetsam (`kern.memorystatus_vm_pressure_level`)  
- Swap, network throughput, page in/out, load average  
- Optional **CPU frequency / temperature** when the privileged Helper is installed  

### Three-track refresh (low overhead)
| Track | Active when | Samples | Default | Options |
|-------|-------------|---------|---------|---------|
| **Icon** | Main closed **and** panel closed | System CPU + memory only (no process enum) | **3 s** | 2 / 3 / 5 / 10 s |
| **Panel** | Panel open, main closed | Compact metrics + rankings (no root Helper pass) | **2 s** | 1 / 2 / 3 / 5 s |
| **Main** | Main window open | Full list, charts, details; Helper fill when installed | **2 s** | 1 / 2 / 5 / 10 s |

- With main open, the panel reuses full data (no extra panel timer)  
- Closing main / panel drops heavy process data and falls back to the lighter track  
- Long-session memory growth is reduced via autorelease pools, cache prune, lazy panel, and publish gating  

### Menu bar
- Icon modes: **CPU only** · **MEM only** · **CPU + MEM** dual bars (default: CPU + MEM)  
- Panel: pressure + memory rings, E/P core strip, category composition, Top CPU / Top memory  
- **Top list mode** independent of the main window: **List** · **Grouped** · **Parent** (default: List)  
- **Top count**: 3–15 per column (default **8**)  
- Section cards use higher-contrast fill + hairline border (light/dark adaptive on frosted material)  
- Footer: open main window, quit, **Activity Monitor** / **System Information** (real app icons)  
- Context menu: open main window, launch at login, version, GitHub, quit  
- Positioning uses `NSPanel` — run a real **`.app`**, not raw `swift run`  

### Window / Dock / launch
- Main window is created **on demand** (AppKit); no SwiftUI `WindowGroup` at launch → **no flash** when starting menu-bar-only  
- Closing the main window **hides** it (app stays in the menu bar); does not quit  
- Remembers whether the main window was visible last quit (`launchMainWindowVisible`); next launch restores that state  
- Dock icon hides when no main / settings / about window is visible  
- Reopen: menu bar **Full Window** / context menu / Dock click / **⌘0**  

### Settings (tabbed)
| Tab | Contents |
|-----|----------|
| **General** | Language (System / 中文 / English) · Theme · **Launch at Login** (`SMAppService`) |
| **Refresh** | Main-window interval · notes for Control-pause |
| **Menu Bar** | Icon mode · icon interval · panel interval · top-list mode · top count |
| **Helper** | Status · install / uninstall (admin password) · recheck |
| **About** | Category rules · purpose · version · bundle ID · MIT |

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
Full-track sampling uses the Helper when installed; the light icon track does not.

### From the app (preferred, no source on the target machine)

1. Run a packaged **`.app`** (Xcode or `package-app.sh`) — Helper is **bundled** inside.  
2. **Settings → Helper → Install Helper…**  
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
Sources/SwiftInsight/         # Main app (SwiftUI + AppKit menu bar / main window)
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

### Architecture notes
- **AppSession** — process-level monitor / menu bar / prefs bootstrap  
- **MainWindowCoordinator** — on-demand `NSWindow`, launch preference, Dock policy  
- **ProcessMonitor** — icon / panel / full sampling tracks  
- Settings-only SwiftUI `Scene`; main UI hosted via AppKit when needed  

---

## License

[MIT](LICENSE) © 2026 [0x574859](https://github.com/WHYBBE) / [WHYBBE/SwiftInsight](https://github.com/WHYBBE/SwiftInsight)
