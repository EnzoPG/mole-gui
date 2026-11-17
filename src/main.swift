// Mole Friend — Ultra-Lightweight Native macOS Menu Bar Friend (WKWebView)
// Clean Architecture & SOLID Composition Root

import Cocoa

/// Single Responsibility: Coordinates periodic background telemetry refreshes and notifies UI subscribers.
public final class TelemetryPollingCoordinator {
    private let metricsProvider: SystemMetricsProviding
    private let onUpdate: (SystemMetrics) -> Void
    private var timer: Timer?

    public init(
        metricsProvider: SystemMetricsProviding,
        onUpdate: @escaping (SystemMetrics) -> Void
    ) {
        self.metricsProvider = metricsProvider
        self.onUpdate = onUpdate
    }

    public func start(interval: TimeInterval = 5.0) {
        refreshNow()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshNow()
        }
    }

    public func refreshNow() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let metrics = self.metricsProvider.collectMetrics()
            DispatchQueue.main.async {
                self.onUpdate(metrics)
            }
        }
    }
}

/// Application Composition Root: Wires dependencies together following Dependency Inversion (DIP).
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var telemetryCoordinator: TelemetryPollingCoordinator!
    private var commandExecutor: CommandExecuting!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 1. Instantiate Infrastructure Services
        let metricsProvider = SystemMetricsProvider()
        let configRepository = FileConfigRepository()
        let processExecutor = MoleProcessExecutor()
        let osLauncher = MacOSIntegrationLauncher(commandExecutor: processExecutor)
        self.commandExecutor = processExecutor

        // 2. Instantiate Presentation & Bridge Adapter
        let router = BridgeActionRouter()
        let bridgeAdapter = WebViewBridgeAdapter(router: router)
        let statusController = StatusBarController(bridgeAdapter: bridgeAdapter)
        self.statusBarController = statusController

        // 3. Instantiate Telemetry Coordinator
        let coordinator = TelemetryPollingCoordinator(metricsProvider: metricsProvider) { [weak statusController, weak bridgeAdapter] metrics in
            let payload = metrics.toDictionary()
            let shortRam = payload["memory_used_short_gb"] as? String ?? "--"
            statusController?.updateTitle(ramUsedGB: shortRam)
            bridgeAdapter?.emitEvent(name: "metricsUpdated", data: payload)
        }
        self.telemetryCoordinator = coordinator

        // 4. Register Open/Closed Bridge Action Strategies
        let handlers: [BridgeActionHandling] = [
            GetInitialStateHandler(
                metricsProvider: metricsProvider,
                configStore: configRepository,
                commandExecutor: processExecutor
            ),
            RunStreamCommandHandler(
                commandExecutor: processExecutor,
                onCommandCompleted: { [weak coordinator] in coordinator?.refreshNow() }
            ),
            StopRunningCommandHandler(commandExecutor: processExecutor),
            AnalyzeDirectoryHandler(commandExecutor: processExecutor),
            GetCleanPreviewListHandler(configStore: configRepository),
            SaveConfigFileHandler(configStore: configRepository),
            OpenInTerminalHandler(launcher: osLauncher),
            RevealInFinderHandler(launcher: osLauncher),
            QuitAppHandler(launcher: osLauncher)
        ]
        handlers.forEach { router.register($0) }

        // 5. Start Telemetry & Open Popover on Launch
        coordinator.start(interval: 5.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak statusController] in
            statusController?.openPopover()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        commandExecutor?.stopCurrentProcess()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
