import AppKit
import Foundation
import RemoteCore
import RemoteRuntime
import ServiceManagement

enum InputRoutingMode: Equatable {
    case inactive
    case deviceMapping
    case correlationFallback

    var title: String {
        switch self {
        case .inactive: "未接管"
        case .deviceMapping: "设备级接管"
        case .correlationFallback: "兼容模式"
        }
    }
}

struct RemoteLogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let button: RemoteButton
    let trigger: RemoteTrigger
    let profile: String
    let result: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var remoteConnected = false
    @Published private(set) var remoteBatteryLevel: Int?
    @Published private(set) var remoteFirmwareVersion: String?
    @Published private(set) var inputMonitoringStatus = InputMonitoringStatus.unknown
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var frontmostApp = AppIdentity(
        name: "正在识别…",
        bundleIdentifier: nil,
        processIdentifier: 0
    )
    @Published private(set) var activeProfile = BuiltInProfiles.defaultProfile
    @Published private(set) var inputRoutingMode = InputRoutingMode.inactive
    @Published private(set) var eventTapRunning = false
    @Published private(set) var logs: [RemoteLogEntry] = []
    @Published private(set) var launchAtLogin = false
    @Published private(set) var userProfiles: [AppProfile] = []
    @Published private(set) var gestureSettings = RemoteGestureSettings()
    @Published private(set) var voiceInputProvider = VoiceInputProvider.typeless
    @Published private(set) var typelessShortcutReady = false
    @Published private(set) var recoveredConfigurationCount = 0
    @Published private(set) var unknownUsages: Set<UInt32> = []
    @Published private(set) var voiceChannelDetected = false
    @Published var serviceEnabled: Bool {
        didSet { UserDefaults.standard.set(serviceEnabled, forKey: Self.enabledKey) }
    }

    private static let enabledKey = "RemoteServiceEnabled"

    private let hid = XiaomiRemoteHID()
    private let remapper = DeviceKeyRemapper()
    private let monitor = FrontmostApplicationMonitor()
    private let suppressor = EventTapSuppressor()
    private let executor = ActionExecutor()
    private let gestureEngine = RemoteGestureEngine()
    private let profileStore: ProfileStore
    private let configurationStore: ConfigurationStore
    private var resolver: ProfileResolver
    private var heldButton: RemoteButton?
    private var repeatTimer: Timer?
    private var heldSince: Date?
    private var permissionTimer: Timer?
    private var voiceStatusTimer: Timer?
    private var deviceInfoTimer: Timer?
    private var deviceInfoTask: Task<Void, Never>?
    private var routingTask: Task<Void, Never>?
    private var routingRevision: UInt = 0
    private var isShuttingDown = false

    init(
        profileStore: ProfileStore = ProfileStore(),
        configurationStore: ConfigurationStore = ConfigurationStore()
    ) {
        self.profileStore = profileStore
        self.configurationStore = configurationStore

        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil {
            serviceEnabled = true
        } else {
            serviceEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        }

        let profileResult = profileStore.load()
        userProfiles = profileResult.profiles
        resolver = ProfileResolver(userProfiles: profileResult.profiles)
        recoveredConfigurationCount = profileResult.recoveredFiles.count

        do {
            let configuration = try configurationStore.load()
            gestureSettings = configuration.gestureSettings
            voiceInputProvider = configuration.voiceInputProvider
        } catch {
            if (try? configurationStore.makeRecoveryCopy()) != nil {
                recoveredConfigurationCount += 1
            }
            gestureSettings = RemoteGestureSettings()
            voiceInputProvider = .typeless
        }

        configure()
        applyGestureSettings()
        start()
        if recoveredConfigurationCount > 0 {
            appendSystemLog("已保留 \(recoveredConfigurationCount) 个无法读取的配置文件")
        }
    }

    func setServiceEnabled(_ enabled: Bool) {
        serviceEnabled = enabled
        if !enabled {
            stopRepeat()
            gestureEngine.reset()
        }
        refreshInputRouting()
    }

    func requestInputMonitoring() {
        _ = InputAccess.requestInputMonitoring()
        refreshPermissions()
    }

    func requestAccessibility() {
        _ = InputAccess.requestAccessibility()
        refreshPermissions()
    }

    func continuePermissionSetup() {
        if inputMonitoringStatus != .granted {
            _ = InputAccess.requestInputMonitoring()
            openPrivacyPane("Privacy_ListenEvent")
        } else if !accessibilityTrusted {
            _ = InputAccess.requestAccessibility()
            openPrivacyPane("Privacy_Accessibility")
        } else {
            refreshPermissions()
        }
    }

    func openInputMonitoringSettings() {
        openPrivacyPane("Privacy_ListenEvent")
    }

    func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            appendSystemLog("登录启动设置失败：\(error.localizedDescription)")
        }
        refreshLaunchAtLogin()
    }

    func clearLogs() {
        logs.removeAll()
    }

    func reloadProfiles() {
        let result = profileStore.load()
        userProfiles = result.profiles
        resolver.userProfiles = result.profiles
        activeProfile = resolver.resolve(bundleIdentifier: frontmostApp.bundleIdentifier)
        recoveredConfigurationCount += result.recoveredFiles.count
        gestureEngine.reset()
        appendSystemLog("已重新加载适配方案")
    }

    func editableProfile(bundleIdentifier: String, name: String) -> AppProfile {
        if let userProfile = userProfiles.first(where: {
            $0.bundleIdentifiers.contains(bundleIdentifier)
        }) {
            return userProfile
        }
        let base = resolver.resolve(bundleIdentifier: bundleIdentifier)
        return AppProfile(
            id: "app-\(bundleIdentifier)",
            name: name,
            bundleIdentifiers: [bundleIdentifier],
            bindings: base.bindings,
            holdBindings: base.holdBindings,
            doubleTapBindings: base.doubleTapBindings
        )
    }

    func isCustomized(bundleIdentifier: String) -> Bool {
        userProfiles.contains { $0.bundleIdentifiers.contains(bundleIdentifier) }
    }

    @discardableResult
    func saveProfile(_ profile: AppProfile) -> Bool {
        do {
            try profileStore.save(profile)
            reloadProfiles()
            appendSystemLog("已保存 \(profile.name) 适配方案")
            return true
        } catch {
            appendSystemLog("保存适配方案失败：\(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func resetProfile(bundleIdentifier: String) -> Bool {
        let profiles = userProfiles.filter { $0.bundleIdentifiers.contains(bundleIdentifier) }
        do {
            for profile in profiles { try profileStore.remove(profileID: profile.id) }
            reloadProfiles()
            appendSystemLog("已恢复内置适配方案")
            return true
        } catch {
            appendSystemLog("恢复适配方案失败：\(error.localizedDescription)")
            return false
        }
    }

    func updateGestureSettings(_ settings: RemoteGestureSettings) {
        gestureSettings = settings
        applyGestureSettings()
        saveConfiguration(failureLabel: "保存手势设置失败")
    }

    func updateVoiceInputProvider(_ provider: VoiceInputProvider) {
        guard voiceInputProvider != provider else { return }
        voiceInputProvider = provider
        gestureEngine.reset()
        saveConfiguration(failureLabel: "保存语音输入设置失败")
        refreshVoiceInputStatus()
        let detail = switch provider {
        case .typeless: "语音键已交给 Typeless（硬件 F20）"
        case .systemDictation: "语音键已切换为 macOS 系统听写"
        case .disabled: "全局语音输入已关闭"
        }
        appendSystemLog(detail)
    }

    var typelessInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "now.typeless.desktop") != nil
    }

    func openTypeless() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "now.typeless.desktop"
        ) else {
            appendSystemLog("未找到 Typeless")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        refreshVoiceInputStatus()
    }

    func refreshDeviceInfo() {
        guard remoteConnected else { return }
        deviceInfoTask?.cancel()
        deviceInfoTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                RemoteDeviceInfoService.currentSnapshot()
            }.value
            guard !Task.isCancelled, let self, let snapshot else { return }
            self.remoteBatteryLevel = snapshot.batteryLevel
            self.remoteFirmwareVersion = snapshot.firmwareVersion
        }
    }

    func shutdown() {
        isShuttingDown = true
        routingRevision &+= 1
        routingTask?.cancel()
        routingTask = nil
        permissionTimer?.invalidate()
        voiceStatusTimer?.invalidate()
        deviceInfoTimer?.invalidate()
        deviceInfoTask?.cancel()
        stopRepeat()
        gestureEngine.reset()
        remapper.uninstall()
        suppressor.stop()
        hid.stop()
        monitor.stop()
    }

    private func configure() {
        hid.onConnectionChanged = { [weak self] connected in
            guard let self else { return }
            self.remoteConnected = connected
            if connected {
                self.refreshInputRouting()
                self.refreshDeviceInfo()
            } else {
                self.gestureEngine.reset()
                self.stopRepeat()
                self.remoteBatteryLevel = nil
                self.remoteFirmwareVersion = nil
                self.refreshInputRouting()
            }
        }
        hid.onButton = { [weak self] button, isPressed in
            guard let self,
                  !self.remapper.activeRemappedButtons.contains(button) else { return }
            self.handle(button, isPressed: isPressed)
        }
        hid.onUnknownUsage = { [weak self] usage, isDown in
            guard let self, isDown else { return }
            self.unknownUsages.insert(usage)
            self.appendSystemLog(String(format: "检测到未知按键 0x%02X", usage))
        }
        hid.onVoiceReport = { [weak self] _ in
            self?.voiceChannelDetected = true
        }
        remapper.onButton = { [weak self] button, isPressed in
            self?.handle(button, isPressed: isPressed)
        }
        remapper.shouldPassThrough = { [weak self] button in
            button == .voice && self?.voiceInputProvider == .typeless
        }
        remapper.onLog = { [weak self] message in
            self?.appendSystemLog(message)
        }
        gestureEngine.hasBinding = { [weak self] button, trigger in
            guard let self else { return false }
            if button == .voice, self.voiceInputProvider != .disabled {
                return trigger == .tap
            }
            return self.activeProfile.hasAction(for: button, trigger: trigger)
        }
        gestureEngine.onResolvedTrigger = { [weak self] button, trigger in
            self?.execute(button, trigger: trigger)
        }
        monitor.onChange = { [weak self] identity in
            guard let self else { return }
            self.stopRepeat()
            self.gestureEngine.reset()
            self.frontmostApp = identity
            self.activeProfile = self.resolver.resolve(bundleIdentifier: identity.bundleIdentifier)
            self.refreshInputRouting()
        }
    }

    private func start() {
        refreshPermissions()
        refreshLaunchAtLogin()
        refreshVoiceInputStatus()
        hid.start()
        monitor.start()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        voiceStatusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshVoiceInputStatus() }
        }
        deviceInfoTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDeviceInfo() }
        }
    }

    private func refreshPermissions() {
        let newInputStatus = InputAccess.inputMonitoringStatus
        let newAccessibilityStatus = InputAccess.accessibilityTrusted
        let changed = newInputStatus != inputMonitoringStatus
            || newAccessibilityStatus != accessibilityTrusted
        inputMonitoringStatus = newInputStatus
        accessibilityTrusted = newAccessibilityStatus
        if changed { refreshInputRouting() }
    }

    private func refreshInputRouting() {
        guard !isShuttingDown else { return }
        routingRevision &+= 1
        guard routingTask == nil else { return }
        routingTask = Task { @MainActor [weak self] in
            await self?.processInputRoutingChanges()
        }
    }

    private func processInputRoutingChanges() async {
        while !Task.isCancelled {
            let revision = routingRevision
            await performInputRoutingRefresh(revision: revision)
            guard !Task.isCancelled, revision != routingRevision else { break }
        }
        routingTask = nil
    }

    private func performInputRoutingRefresh(revision: UInt) async {
        func isCurrentRequest() -> Bool {
            !Task.isCancelled && !isShuttingDown && revision == routingRevision
        }

        guard serviceEnabled,
              remoteConnected,
              inputMonitoringStatus == .granted,
              accessibilityTrusted else {
            await remapper.uninstallAsync()
            guard isCurrentRequest() else { return }
            suppressor.stop()
            eventTapRunning = false
            inputRoutingMode = .inactive
            return
        }

        if activeProfile.requiresNativePassThrough {
            await remapper.uninstallAsync()
            guard isCurrentRequest() else { return }
            eventTapRunning = suppressor.start()
            inputRoutingMode = eventTapRunning ? .correlationFallback : .inactive
            return
        }

        let installed = remapper.isInstalled ? true : await remapper.installAsync()
        guard isCurrentRequest() else { return }
        if installed {
            suppressor.stop()
            eventTapRunning = true
            inputRoutingMode = .deviceMapping
        } else {
            eventTapRunning = suppressor.start()
            inputRoutingMode = eventTapRunning ? .correlationFallback : .inactive
        }
    }

    private func applyGestureSettings() {
        gestureEngine.holdMilliseconds = gestureSettings.holdMilliseconds
        gestureEngine.doubleTapMilliseconds = gestureSettings.doubleTapMilliseconds
        gestureEngine.debounceMilliseconds = gestureSettings.debounceMilliseconds
    }

    private func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func refreshVoiceInputStatus() {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Typeless/app-settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bindings = object["featureShortcutBindings"] as? [String: Any],
              let shortcut = bindings["dictationMode"] as? [String] else {
            typelessShortcutReady = false
            return
        }
        typelessShortcutReady = shortcut.contains { $0.caseInsensitiveCompare("F20") == .orderedSame }
    }

    private func saveConfiguration(failureLabel: String) {
        do {
            try configurationStore.save(RemoteConfiguration(
                gestureSettings: gestureSettings,
                voiceInputProvider: voiceInputProvider
            ))
        } catch {
            appendSystemLog("\(failureLabel)：\(error.localizedDescription)")
        }
    }

    private func handle(_ button: RemoteButton, isPressed: Bool) {
        if !isPressed, heldButton == button { stopRepeat() }
        guard serviceEnabled else { return }

        let tapAction = activeProfile.action(for: button, trigger: .tap)
        if inputRoutingMode == .correlationFallback,
           tapAction.shouldSuppressNativeEvent,
           let keyCode = XiaomiRemoteProfile.nativeKeyCode(for: button) {
            suppressor.expectNativeEvent(keyCode: keyCode, isPressed: isPressed)
        }

        let ownBundleID = Bundle.main.bundleIdentifier
        let actualFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if actualFrontmost == ownBundleID {
            if isPressed { appendLog(button, trigger: .tap, result: "控制台前台，仅记录") }
            return
        }

        gestureEngine.handle(button, isPressed: isPressed)
        guard isPressed,
              button.isRepeatable,
              !activeProfile.hasAction(for: button, trigger: .hold),
              !activeProfile.hasAction(for: button, trigger: .doubleTap),
              !isPassThrough(tapAction) else { return }
        beginRepeat(button, action: tapAction)
    }

    private func execute(_ button: RemoteButton, trigger: RemoteTrigger) {
        let action: RemoteAction
        if button == .voice, trigger == .tap {
            switch voiceInputProvider {
            case .typeless:
                appendLog(
                    button,
                    trigger: trigger,
                    result: typelessShortcutReady
                        ? "已交给 Typeless（硬件 F20）"
                        : "Typeless 需先将录音快捷键设为 F20"
                )
                return
            case .systemDictation:
                action = .systemDictation
            case .disabled:
                action = activeProfile.action(for: button, trigger: trigger)
            }
        } else {
            action = activeProfile.action(for: button, trigger: trigger)
        }
        let result = executor.execute(action)
        let message: String = switch result {
        case .completed(let detail): detail
        case .skipped(let detail): detail
        case .failed(let detail): "失败：\(detail)"
        }
        appendLog(button, trigger: trigger, result: message)
    }

    private func executeRepeated(_ button: RemoteButton, action: RemoteAction) {
        let result = executor.execute(action)
        if case .failed(let detail) = result {
            appendLog(button, trigger: .tap, result: "失败：\(detail)")
        }
    }

    private func beginRepeat(_ button: RemoteButton, action: RemoteAction) {
        stopRepeat()
        heldButton = button
        heldSince = .now
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self,
                      self.heldButton == button,
                      let heldSince = self.heldSince,
                      Date.now.timeIntervalSince(heldSince) > 0.32 else { return }
                self.executeRepeated(button, action: action)
            }
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        heldButton = nil
        heldSince = nil
    }

    private func isPassThrough(_ action: RemoteAction) -> Bool {
        if case .passThrough = action { return true }
        return false
    }

    private func appendLog(
        _ button: RemoteButton,
        trigger: RemoteTrigger,
        result: String
    ) {
        logs.insert(RemoteLogEntry(
            date: .now,
            button: button,
            trigger: trigger,
            profile: activeProfile.name,
            result: result
        ), at: 0)
        if logs.count > 80 { logs.removeLast(logs.count - 80) }
    }

    private func appendSystemLog(_ message: String) {
        logs.insert(RemoteLogEntry(
            date: .now,
            button: .menu,
            trigger: .tap,
            profile: "系统",
            result: message
        ), at: 0)
        if logs.count > 80 { logs.removeLast(logs.count - 80) }
    }

    private func openPrivacyPane(_ anchor: String) {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
