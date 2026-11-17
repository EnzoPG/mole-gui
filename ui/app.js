/**
 * Mole Friend — Frontend Architecture (SOLID Principles)
 *
 * - Single Responsibility (SRP): Dedicated classes for RPC transport, byte formatting,
 *   tab navigation, telemetry rendering, console streaming, disk exploration, and config editing.
 * - Open/Closed (OCP): Event bus (`MoleBridgeClient.on`) allows registering new native event
 *   listeners without modifying the core bridge client.
 * - Liskov Substitution (LSP): `MoleBridgeClient` accepts any transport implementing `postMessage`.
 * - Interface Segregation (ISP): View controllers receive only the narrow DOM elements and
 *   callbacks they require.
 * - Dependency Inversion (DIP): High-level UI controllers depend on the abstract bridge client
 *   interface rather than `window.webkit.messageHandlers` directly.
 */
(function () {
  "use strict";

  // ===========================================================================
  // 1. Utilities (SRP: Pure formatting helpers)
  // ===========================================================================
  class ByteFormatter {
    static format(bytes) {
      if (!bytes || bytes <= 0) return "0 B";
      const units = ["B", "KB", "MB", "GB", "TB"];
      const i = Math.floor(Math.log(bytes) / Math.log(1024));
      return (bytes / Math.pow(1024, i)).toFixed(i > 1 ? 1 : 0) + " " + units[i];
    }

    static clampPercent(value, min = 4, max = 100) {
      const parsed = parseFloat(value);
      if (Number.isNaN(parsed)) return min;
      return Math.min(max, Math.max(min, parsed));
    }
  }

  // ===========================================================================
  // 2. Infrastructure / Transport Layer (DIP & OCP: Native WebKit Bridge Client)
  // ===========================================================================
  class MoleBridgeClient {
    constructor(nativeHandler) {
      this.nativeHandler = nativeHandler;
      this.pendingCallbacks = new Map();
      this.eventListeners = new Map();
      this.reqCounter = 0;

      this._installGlobalHooks();
    }

    _installGlobalHooks() {
      window.__resolveMoleBridge = (reqId, data) => {
        const resolver = this.pendingCallbacks.get(reqId);
        if (resolver) {
          resolver(data);
          this.pendingCallbacks.delete(reqId);
        }
      };

      window.__onMoleEvent = (event, data) => {
        const listeners = this.eventListeners.get(event) || [];
        listeners.forEach((handler) => handler(data));
      };
    }

    on(eventName, handler) {
      if (!this.eventListeners.has(eventName)) {
        this.eventListeners.set(eventName, []);
      }
      this.eventListeners.get(eventName).push(handler);
    }

    invoke(action, payload = {}) {
      return new Promise((resolve) => {
        const reqId = `req_${++this.reqCounter}_${Date.now()}`;
        this.pendingCallbacks.set(reqId, resolve);

        if (this.nativeHandler && typeof this.nativeHandler.postMessage === "function") {
          this.nativeHandler.postMessage({ reqId, action, payload });
        } else {
          this.pendingCallbacks.delete(reqId);
          resolve({ error: "Native bridge unavailable" });
        }
      });
    }
  }

  // ===========================================================================
  // 3. Presentation Controllers (SRP: Focused View & Feature Controllers)
  // ===========================================================================

  /** Manages header subtitle status and running state indicators. */
  class StatusBannerController {
    constructor() {
      this.statusTextEl = document.getElementById("pop-status-text");
      this.runPillEl = document.getElementById("pop-run-pill");
      this.stopBtnEl = document.getElementById("btn-stop");
      this.consoleDotEl = document.getElementById("console-dot");
    }

    setStatusText(message) {
      if (this.statusTextEl) {
        this.statusTextEl.textContent = message;
      }
    }

    setRunState(state, statusMessage) {
      if (this.runPillEl) {
        this.runPillEl.className = `status-pill ${state}`;
        const labels = { running: "Running", done: "Done", idle: "Idle" };
        this.runPillEl.textContent = labels[state] || "Idle";
      }
      if (this.stopBtnEl) {
        this.stopBtnEl.disabled = state !== "running";
      }
      if (this.consoleDotEl) {
        this.consoleDotEl.classList.toggle("hidden", state !== "running");
      }
      document.body.classList.toggle("is-running", state === "running");

      if (statusMessage) {
        this.setStatusText(statusMessage);
      }
    }
  }

  /** Manages pill tab switching and view visibility. */
  class TabNavigationController {
    constructor() {
      this.tabButtons = document.querySelectorAll(".pill-tab");
      this.tabViews = document.querySelectorAll(".tab-view");
      this.consoleDotEl = document.getElementById("console-dot");
      this._bindEvents();
    }

    _bindEvents() {
      this.tabButtons.forEach((btn) => {
        btn.addEventListener("click", () => this.switchTo(btn.dataset.tab));
      });
    }

    switchTo(tabId) {
      this.tabButtons.forEach((btn) => {
        btn.classList.toggle("active", btn.dataset.tab === tabId);
      });
      this.tabViews.forEach((view) => {
        view.classList.toggle("active", view.id === `tab-${tabId}`);
      });
      if (tabId === "console" && this.consoleDotEl) {
        this.consoleDotEl.classList.add("hidden");
      }
    }
  }

  /** Renders live RAM, Disk, Uptime, and Touch ID metrics. */
  class TelemetryViewController {
    constructor() {
      this.diskFreeEl = document.getElementById("pop-disk-free");
      this.diskBarEl = document.getElementById("pop-disk-bar");
      this.diskSubEl = document.getElementById("pop-disk-sub");
      this.memUsedEl = document.getElementById("pop-mem-used");
      this.memBarEl = document.getElementById("pop-mem-bar");
      this.memSubEl = document.getElementById("pop-mem-sub");
      this.uptimeEl = document.getElementById("footer-uptime");
      this.touchIdSubEl = document.getElementById("touchid-sub-status");
    }

    render(metrics) {
      if (!metrics) return;

      const freeGB = metrics.disk_free_exact_gb || metrics.disk_free_gb || "--";
      const usedGB = metrics.disk_used_gb || "--";
      const totalGB = metrics.disk_total_gb || "--";
      const usedPct = ByteFormatter.clampPercent(metrics.disk_used_percent || "10");

      const memUsed = metrics.memory_used_gb || "--";
      const memTotal = metrics.memory_total_gb || "--";
      const memPct = ByteFormatter.clampPercent(metrics.memory_used_percent || "35");

      if (this.diskFreeEl) this.diskFreeEl.textContent = `${freeGB} GB`;
      if (this.diskBarEl) this.diskBarEl.style.width = `${usedPct}%`;
      if (this.diskSubEl) this.diskSubEl.textContent = `${usedGB} / ${totalGB} GB used`;

      if (this.memUsedEl) this.memUsedEl.textContent = `${memUsed} GB`;
      if (this.memBarEl) this.memBarEl.style.width = `${memPct}%`;
      if (this.memSubEl) this.memSubEl.textContent = `${memPct.toFixed(0)}% of ${memTotal} GB`;

      if (this.uptimeEl && metrics.uptime_days) {
        const tidBadge = metrics.touchid_enabled ? " · Touch ID ✓" : "";
        this.uptimeEl.textContent = `Uptime: ${metrics.uptime_days}d${tidBadge}`;
      }

      if (this.touchIdSubEl && typeof metrics.touchid_enabled === "boolean") {
        this.touchIdSubEl.textContent = metrics.touchid_enabled
          ? "Touch ID sudo is enabled ✓"
          : "Enable fingerprint for sudo tasks";
      }
    }
  }

  /** Manages streaming CLI console output. */
  class ConsoleViewController {
    constructor() {
      this.titleEl = document.getElementById("pop-console-title");
      this.logEl = document.getElementById("pop-console-log");
      this.clearBtnEl = document.getElementById("btn-clear-log");

      this.clearBtnEl?.addEventListener("click", () => {
        this.append("Console cleared.\n", true);
      });
    }

    setTitle(title) {
      if (this.titleEl) {
        this.titleEl.textContent = title;
      }
    }

    append(text, reset = false) {
      if (!this.logEl) return;
      if (reset) this.logEl.textContent = "";
      this.logEl.textContent += text;
      this.logEl.scrollTop = this.logEl.scrollHeight;
    }
  }

  /** Manages interactive folder size scanning and drill-down navigation. */
  class DiskExplorerController {
    constructor(bridgeClient, statusBanner) {
      this.bridge = bridgeClient;
      this.statusBanner = statusBanner;
      this.pathInputEl = document.getElementById("analyze-path-input");
      this.resultsEl = document.getElementById("analyze-results");
      this._bindEvents();
    }

    _bindEvents() {
      document.getElementById("btn-run-analyze")?.addEventListener("click", () => {
        this.analyze();
      });

      document.getElementById("btn-analyze-up")?.addEventListener("click", () => {
        if (!this.pathInputEl) return;
        const current = this.pathInputEl.value.trim().replace(/\/+$/, "");
        if (current.length > 1 && current.includes("/")) {
          const parent = current.substring(0, current.lastIndexOf("/")) || "/";
          this.analyze(parent);
        }
      });

      document.querySelectorAll(".quick-chips .chip").forEach((chip) => {
        chip.addEventListener("click", () => {
          this.analyze(chip.getAttribute("data-path"));
        });
      });
    }

    async analyze(targetPath) {
      if (!this.resultsEl) return;

      const path = targetPath || (this.pathInputEl ? this.pathInputEl.value.trim() : "~") || "~";
      if (this.pathInputEl) this.pathInputEl.value = path;

      this.resultsEl.innerHTML = `<div class="empty-msg">Scanning <code>${path}</code>...</div>`;
      this.statusBanner.setStatusText(`Scanning ${path}...`);

      const res = await this.bridge.invoke("analyzeDirectory", { path });
      this.statusBanner.setStatusText("Burrow is cozy & clean");

      if (!res || !res.json) {
        this.resultsEl.innerHTML = `<div class="empty-msg">Could not scan ${path}.</div>`;
        return;
      }

      this._renderEntries(res.json);
    }

    _renderEntries(rawJson) {
      try {
        const parsed = JSON.parse(rawJson);
        const entries = (parsed.entries || []).sort((a, b) => (b.size || 0) - (a.size || 0));
        const totalSize =
          parsed.total_size ||
          entries.reduce((acc, e) => acc + (e.size || 0), 0) ||
          1;

        if (entries.length === 0) {
          this.resultsEl.innerHTML = `<div class="empty-msg">Empty folder or needs Full Disk Access.</div>`;
          return;
        }

        this.resultsEl.innerHTML = "";
        entries.slice(0, 30).forEach((entry) => {
          const pct = ByteFormatter.clampPercent(((entry.size || 0) / totalSize) * 100, 3, 100);
          const row = document.createElement("div");
          row.className = "analyze-row";
          const icon = entry.is_dir ? "📁" : "📄";

          row.innerHTML = `
            <div class="analyze-name" title="${entry.path}">${icon} ${entry.name}</div>
            <div class="progress-bar"><div class="progress-fill ${pct > 40 ? "amber" : ""}" style="width:${pct.toFixed(0)}%"></div></div>
            <div class="analyze-size">${ByteFormatter.format(entry.size)}</div>
            <button class="btn ghost xs">Show</button>
          `;

          if (entry.is_dir) {
            row.querySelector(".analyze-name").addEventListener("click", () => {
              this.analyze(entry.path);
            });
          }

          row.querySelector("button").addEventListener("click", () => {
            this.bridge.invoke("revealInFinder", { path: entry.path });
          });

          this.resultsEl.appendChild(row);
        });
      } catch (_) {
        this.resultsEl.innerHTML = `<div class="empty-msg">${rawJson}</div>`;
      }
    }
  }

  /** Manages reading and saving Mole configuration files and dry-run previews. */
  class ConfigEditorController {
    constructor(bridgeClient, tabNav, consoleView) {
      this.bridge = bridgeClient;
      this.tabNav = tabNav;
      this.consoleView = consoleView;
      this.selectEl = document.getElementById("cfg-select");
      this.editorEl = document.getElementById("cfg-editor");
      this.saveBtnEl = document.getElementById("btn-save-cfg");
      this.previewBtnEl = document.getElementById("btn-load-clean-preview");

      this.store = {
        whitelist_clean: "",
        whitelist_optimize: "",
        purge_paths: "",
      };

      this._bindEvents();
    }

    _bindEvents() {
      if (this.selectEl && this.editorEl) {
        this.selectEl.addEventListener("change", () => {
          this.editorEl.value = this.store[this.selectEl.value] || "";
        });
      }

      this.saveBtnEl?.addEventListener("click", async (e) => {
        if (!this.selectEl || !this.editorEl) return;
        const key = this.selectEl.value;
        this.store[key] = this.editorEl.value;
        await this.bridge.invoke("saveConfigFile", {
          type: key,
          content: this.editorEl.value,
        });

        const btn = e.currentTarget;
        const oldText = btn.textContent;
        btn.textContent = "Saved ✓";
        setTimeout(() => {
          btn.textContent = oldText;
        }, 1300);
      });

      this.previewBtnEl?.addEventListener("click", async () => {
        const res = await this.bridge.invoke("getCleanPreviewList");
        this.tabNav.switchTo("console");
        this.consoleView.setTitle("~/.config/mole/clean-list.txt");
        this.consoleView.append(
          res && res.content
            ? res.content
            : "No preview file found yet. Click 'Preview' on Deep Clean first.",
          true
        );
      });
    }

    hydrate(initialState) {
      if (!initialState) return;
      this.store.whitelist_clean = initialState.whitelist_clean || "";
      this.store.whitelist_optimize = initialState.whitelist_optimize || "";
      this.store.purge_paths = initialState.purge_paths || "";

      if (this.selectEl && this.editorEl) {
        this.editorEl.value = this.store[this.selectEl.value] || "";
      }
    }
  }

  // ===========================================================================
  // 4. Application Coordinator / Composition Root
  // ===========================================================================
  class MolePopoverApp {
    constructor() {
      const nativeHandler =
        window.webkit &&
        window.webkit.messageHandlers &&
        window.webkit.messageHandlers.moleBridge;

      this.bridge = new MoleBridgeClient(nativeHandler);
      this.statusBanner = new StatusBannerController();
      this.tabNav = new TabNavigationController();
      this.telemetryView = new TelemetryViewController();
      this.consoleView = new ConsoleViewController();
      this.diskExplorer = new DiskExplorerController(this.bridge, this.statusBanner);
      this.configEditor = new ConfigEditorController(
        this.bridge,
        this.tabNav,
        this.consoleView
      );
    }

    init() {
      this._bindActionButtons();
      this._subscribeToNativeEvents();
      this.refreshState();
    }

    async refreshState() {
      const state = await this.bridge.invoke("getInitialState");
      if (!state) return;
      this.telemetryView.render(state);
      this.configEditor.hydrate(state);
    }

    _bindActionButtons() {
      document.querySelectorAll("[data-run]").forEach((btn) => {
        btn.addEventListener("click", () => {
          this.bridge.invoke("runStreamCommand", {
            command: btn.getAttribute("data-run"),
            dryRun: btn.getAttribute("data-dry") === "true",
          });
        });
      });

      document.querySelectorAll("[data-term]").forEach((btn) => {
        btn.addEventListener("click", () => {
          this.bridge.invoke("openInTerminal", {
            command: btn.getAttribute("data-term"),
          });
        });
      });

      document.getElementById("btn-refresh")?.addEventListener("click", () => {
        this.refreshState();
      });

      document.getElementById("btn-stop")?.addEventListener("click", () => {
        this.bridge.invoke("stopRunningCommand");
        this.statusBanner.setRunState("idle", "Stopped task.");
      });

      document.getElementById("pop-open-tui")?.addEventListener("click", () => {
        this.bridge.invoke("openInTerminal", { command: "" });
      });

      document.getElementById("pop-quit")?.addEventListener("click", () => {
        this.bridge.invoke("quitApp");
      });
    }

    _subscribeToNativeEvents() {
      this.bridge.on("metricsUpdated", (data) => {
        this.telemetryView.render(data);
      });

      this.bridge.on("commandStarted", (data) => {
        this.consoleView.setTitle(`$ ${data.fullCommand}`);
        this.tabNav.switchTo("console");
        this.statusBanner.setRunState(
          "running",
          `Digging: mo ${data.command}${data.dryRun ? " (preview)" : ""}...`
        );
        this.consoleView.append(`$ ${data.fullCommand}\n`, true);
      });

      this.bridge.on("commandOutput", (data) => {
        this.consoleView.append(data.chunk || "", false);
      });

      this.bridge.on("commandFinished", (data) => {
        this.consoleView.append(
          `\n[Finished: mo ${data.command} (exit ${data.exitCode})]\n`,
          false
        );
        this.statusBanner.setRunState("done", `Completed mo ${data.command}!`);
      });
    }
  }

  // Bootstrap application
  const app = new MolePopoverApp();
  app.init();
})();
