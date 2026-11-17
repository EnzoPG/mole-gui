# 🐹 Mole Friend (`mole-gui`)

An ultra-lightweight, minimalist macOS companion interface (Menu Bar Friend) for **[tw93/Mole](https://github.com/tw93/Mole)** (`mo`).

## Footprint & Architecture
- **App Bundle Size:** ~196 KB total (`128 KB` native binary + `64 KB` HTML/CSS/JS UI)
- **RAM Usage:** ~25 MB (uses macOS's built-in `WKWebView` + native `NSStatusItem` & `NSPopover`, zero Chromium/Electron bloat)
- **Idle CPU:** ~0.0%
- **Zero External Build Dependencies:** Compiles directly with macOS's built-in `swiftc` compiler.

## Features
1. **Menu Bar Friend (`🐹 <Free>G`)**:
   - Lives in your top macOS menu bar showing live free disk space.
   - Click to open a 360×480 quick-action popover with live Disk & RAM gauges, 1-click **Preview Clean (`--dry-run`)**, **Deep Clean**, **Audit System (`optimize --dry-run`)**, **Scan Artifacts (`purge --dry-run`)**, and a live streaming output console.
2. **Main Desktop Window**:
   - **Burrow Dashboard:** Live disk space, memory pressure (active + wired + compressed), uptime, Touch ID sudo status, and quick command cards.
   - **Clean & Purge:** Run `--dry-run` previews, inspect `~/.config/mole/clean-list.txt`, or execute `mo clean` and `mo purge`.
   - **Optimize & Audit:** View all 19 macOS health & optimization checks from Mole's catalog and run `mo optimize` (`--dry-run` or live).
   - **Disk Explorer:** Graphical folder size analyzer powered by `mo analyze --json` with 1-click drill-down and **Reveal in Finder**.
   - **Apps & Installers:** Scan for leftover `.dmg`/`.pkg`/`.iso` installers, preview universal app slimming (`mo slim`), or launch Mole's interactive App Uninstaller and Touch ID configurator in Terminal.
   - **Whitelists & Paths:** Edit `~/.config/mole/whitelist`, `~/.config/mole/whitelist_optimize`, and `~/.config/mole/purge_paths` directly in the UI.

## Quick Start

### Launch the Built App
```bash
open "/Users/enzogerola/Projects/mole-gui/build/Mole Friend.app"
```
*(Or copy `build/Mole Friend.app` into `/Applications`!)*

### Rebuild After Editing HTML/CSS/JS or Swift
```bash
./build.sh
```

## Project Structure & SOLID Architecture

The project is structured following **Clean Architecture** and **SOLID** principles across both the Swift native host and the JavaScript frontend:

### Native Host (`src/`)
- **Domain Layer (`src/Domain/`)**
  - [`Models.swift`](file:///Users/enzogerola/Projects/mole-gui/src/Domain/Models.swift) — Value types (`SystemMetrics`, `ConfigFileType`, `BridgeRequest`, `CommandStreamEvent`).
  - [`Protocols.swift`](file:///Users/enzogerola/Projects/mole-gui/src/Domain/Protocols.swift) — Segregated interfaces (`SystemMetricsProviding`, `ConfigStoring`, `CommandExecuting`, `ExternalIntegrationLaunching`, `BridgeEventEmitting`, `BridgeActionHandling`).
- **Application Layer (`src/Application/`)**
  - [`BridgeActionHandlers.swift`](file:///Users/enzogerola/Projects/mole-gui/src/Application/BridgeActionHandlers.swift) — Open/Closed `BridgeActionRouter` and single-responsibility command handlers (`GetInitialStateHandler`, `RunStreamCommandHandler`, `AnalyzeDirectoryHandler`, etc.).
- **Infrastructure Layer (`src/Infrastructure/`)**
  - [`SystemMetricsProvider.swift`](file:///Users/enzogerola/Projects/mole-gui/src/Infrastructure/SystemMetricsProvider.swift) — Mach VM memory, disk space, uptime, and PAM Touch ID telemetry collector + `AnsiSanitizer`.
  - [`CommandAndConfigServices.swift`](file:///Users/enzogerola/Projects/mole-gui/src/Infrastructure/CommandAndConfigServices.swift) — `MoleProcessExecutor`, `FileConfigRepository`, and `MacOSIntegrationLauncher`.
- **Presentation & Composition Root (`src/Presentation/` & `src/main.swift`)**
  - [`StatusBarController.swift`](file:///Users/enzogerola/Projects/mole-gui/src/Presentation/StatusBarController.swift) — Manages `NSStatusItem`, `NSPopover`, and `WebViewBridgeAdapter`.
  - [`main.swift`](file:///Users/enzogerola/Projects/mole-gui/src/main.swift) — `TelemetryPollingCoordinator` and `AppDelegate` dependency injection composition root.

### Frontend (`ui/`)
- [`ui/index.html`](file:///Users/enzogerola/Projects/mole-gui/ui/index.html) — Menu Bar Popover interface with custom SVG Mole mascot.
- [`ui/styles.css`](file:///Users/enzogerola/Projects/mole-gui/ui/styles.css) — Minimalist warm-earthy dark theme (`#131110` / `#e59866`).
- [`ui/app.js`](file:///Users/enzogerola/Projects/mole-gui/ui/app.js) — Modular SOLID frontend classes (`MoleBridgeClient`, `TelemetryViewController`, `ConsoleViewController`, `DiskExplorerController`, `ConfigEditorController`, `MolePopoverApp`).
- [`build.sh`](file:///Users/enzogerola/Projects/mole-gui/build.sh) — Zero-dependency build script that compiles all Swift modules and packages `build/Mole Friend.app`.
