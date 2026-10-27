import AppKit
import RemoteCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @State private var editingApplication: AdaptedApplication?

    private var isReady: Bool {
        model.serviceEnabled
            && model.remoteConnected
            && model.inputMonitoringStatus == .granted
            && model.accessibilityTrusted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                readinessCard
                supportedAppsSection
                currentAppSection
                voiceInputSection
                settingsSection
                gestureSection
                activitySection
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $editingApplication) { application in
            ProfileEditorView(application: application, model: model)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "appletvremote.gen4.fill")
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text("mmTV Remote")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("小米蓝牙遥控器2 Pro 适配 macOS")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("遥控服务", isOn: Binding(
                get: { model.serviceEnabled },
                set: model.setServiceEnabled
            ))
            .toggleStyle(.switch)
            .fontWeight(.medium)
        }
    }

    private var readinessCard: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.18))
                Image(systemName: readinessSymbol)
                    .font(.system(size: 27, weight: .semibold))
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 5) {
                Text(readinessTitle)
                    .font(.title2.bold())
                Text(readinessDetail)
                    .foregroundStyle(.white.opacity(0.82))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                ProductStatusPill(
                    title: model.remoteConnected ? "遥控器已连接" : "等待遥控器",
                    symbol: model.remoteConnected ? "checkmark" : "wave.3.right"
                )
                ProductStatusPill(
                    title: model.serviceEnabled ? "服务运行中" : "服务已暂停",
                    symbol: model.serviceEnabled ? "bolt.fill" : "pause.fill"
                )
                if model.inputRoutingMode != .inactive {
                    ProductStatusPill(title: model.inputRoutingMode.title, symbol: "switch.2")
                }
                if let battery = model.remoteBatteryLevel {
                    ProductStatusPill(title: "电量 \(battery)%", symbol: "battery.75percent")
                }
                if let firmware = model.remoteFirmwareVersion {
                    ProductStatusPill(title: "固件 \(firmware)", symbol: "cpu")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .background(
            LinearGradient(
                colors: isReady
                    ? [Color.blue, Color.indigo]
                    : [Color.orange, Color.pink.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .shadow(color: (isReady ? Color.blue : Color.orange).opacity(0.16), radius: 18, y: 8)
    }

    private var readinessTitle: String {
        if !model.serviceEnabled { return "遥控服务已暂停" }
        if !model.remoteConnected { return "正在等待遥控器" }
        if model.inputMonitoringStatus != .granted || !model.accessibilityTrusted {
            return "完成授权即可开始使用"
        }
        return "遥控器已就绪"
    }

    private var readinessDetail: String {
        if !model.serviceEnabled { return "重新开启后，会自动恢复当前应用的遥控适配。" }
        if !model.remoteConnected { return "请在系统蓝牙设置中连接小米蓝牙遥控器2 Pro。" }
        if model.inputMonitoringStatus != .granted || !model.accessibilityTrusted {
            return "只需完成一次系统授权，之后会在后台自动工作。"
        }
        return "现在可以直接使用方向、确认、返回、菜单和音量键。"
    }

    private var readinessSymbol: String {
        if !model.serviceEnabled { return "pause.fill" }
        if !model.remoteConnected { return "wave.3.right" }
        if !isReady { return "hand.raised.fill" }
        return "checkmark"
    }

    private var supportedAppsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: "已适配应用",
                subtitle: "切换到这些应用时，遥控器会自动使用合适的按键方案"
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AdaptedApplication.all) { app in
                        Button { editingApplication = app } label: {
                            AdaptedAppTile(
                                app: app,
                                customized: model.isCustomized(bundleIdentifier: app.bundleIdentifier)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var currentAppSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: "正在控制",
                subtitle: "适配方案会跟随前台应用自动切换"
            )

            HStack(spacing: 16) {
                ApplicationIconView(
                    bundleIdentifier: model.frontmostApp.bundleIdentifier,
                    fallbackSymbol: "macwindow",
                    size: 54
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.frontmostApp.name)
                        .font(.title3.bold())
                        .lineLimit(1)
                    Text("正在使用“\(model.activeProfile.name)”适配方案")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label("自动切换", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.blue.opacity(0.1), in: Capsule())
            }
            .padding(18)
            .productCard()
        }
    }

    private var gestureSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: "按键手势",
                subtitle: "只有配置了长按或双击动作的按键才会等待识别"
            )

            VStack(spacing: 0) {
                GestureSettingRow(
                    symbol: "hand.tap",
                    title: "长按触发",
                    value: model.gestureSettings.holdMilliseconds,
                    range: 250 ... 800,
                    step: 50
                ) { value in
                    model.updateGestureSettings(RemoteGestureSettings(
                        holdMilliseconds: value,
                        doubleTapMilliseconds: model.gestureSettings.doubleTapMilliseconds,
                        debounceMilliseconds: model.gestureSettings.debounceMilliseconds
                    ))
                }
                Divider().padding(.leading, 58)
                GestureSettingRow(
                    symbol: "hand.tap.fill",
                    title: "双击间隔",
                    value: model.gestureSettings.doubleTapMilliseconds,
                    range: 150 ... 500,
                    step: 50
                ) { value in
                    model.updateGestureSettings(RemoteGestureSettings(
                        holdMilliseconds: model.gestureSettings.holdMilliseconds,
                        doubleTapMilliseconds: value,
                        debounceMilliseconds: model.gestureSettings.debounceMilliseconds
                    ))
                }
                Divider().padding(.leading, 58)
                GestureSettingRow(
                    symbol: "waveform.path",
                    title: "按键防抖",
                    value: model.gestureSettings.debounceMilliseconds,
                    range: 10 ... 100,
                    step: 10
                ) { value in
                    model.updateGestureSettings(RemoteGestureSettings(
                        holdMilliseconds: model.gestureSettings.holdMilliseconds,
                        doubleTapMilliseconds: model.gestureSettings.doubleTapMilliseconds,
                        debounceMilliseconds: value
                    ))
                }
            }
            .productCard()
        }
    }

    private var voiceInputSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: "语音输入",
                subtitle: "语音键是全局能力，不随前台应用 Profile 变化"
            )

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    SettingsIcon(symbol: model.voiceInputProvider.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("按下语音键时")
                            .fontWeight(.medium)
                        Text(model.voiceInputProvider.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("语音输入", selection: Binding(
                        get: { model.voiceInputProvider },
                        set: model.updateVoiceInputProvider
                    )) {
                        ForEach(VoiceInputProvider.allCases, id: \.self) { provider in
                            Label(provider.title, systemImage: provider.symbol).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
                .padding(16)

                if model.voiceInputProvider == .typeless {
                    Divider().padding(.leading, 58)
                    HStack(spacing: 14) {
                        ApplicationIconView(
                            bundleIdentifier: "now.typeless.desktop",
                            fallbackSymbol: "waveform.and.mic",
                            size: 34
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Typeless 录音快捷键")
                                .fontWeight(.medium)
                            Text(typelessStatusDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.typelessShortcutReady {
                            Label("已设为 F20", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.green)
                        } else {
                            Button("打开 Typeless") { model.openTypeless() }
                                .buttonStyle(.borderedProminent)
                                .disabled(!model.typelessInstalled)
                        }
                    }
                    .padding(16)
                }
            }
            .productCard()
        }
    }

    private var typelessStatusDetail: String {
        if !model.typelessInstalled { return "这台 Mac 上尚未安装 Typeless。" }
        if model.typelessShortcutReady {
            return "遥控器会把真实的硬件 F20 交给 Typeless。"
        }
        return "请在 Typeless 中把 Dictation Mode 快捷键改为 F20。"
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: "使用设置",
                subtitle: "保持以下选项开启，遥控器就能随时工作"
            )

            VStack(spacing: 0) {
                if model.inputMonitoringStatus != .granted || !model.accessibilityTrusted {
                    permissionSetupBanner
                    Divider().padding(.leading, 58)
                }
                PermissionSettingRow(
                    symbol: "keyboard.badge.eye",
                    title: "读取遥控器按键",
                    detail: "输入监控",
                    granted: model.inputMonitoringStatus == .granted
                )
                Divider().padding(.leading, 58)
                PermissionSettingRow(
                    symbol: "cursorarrow.motionlines",
                    title: "控制当前应用",
                    detail: "辅助功能",
                    granted: model.accessibilityTrusted && model.eventTapRunning
                )
                Divider().padding(.leading, 58)
                HStack(spacing: 14) {
                    SettingsIcon(symbol: "power")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("登录后自动运行")
                            .fontWeight(.medium)
                        Text("无需先打开 mmTV")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: model.setLaunchAtLogin
                    ))
                    .labelsHidden()
                }
                .padding(16)
            }
            .productCard()
        }
    }

    private var permissionSetupBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.orange.gradient, in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(permissionSetupTitle)
                    .fontWeight(.semibold)
                Text("在系统设置中开启 mmTV Remote；应用会自动识别下一步。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(model.inputMonitoringStatus == .granted ? "继续授权" : "开始授权") {
                model.continuePermissionSetup()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    private var permissionSetupTitle: String {
        if model.inputMonitoringStatus != .granted { return "第一步：允许读取遥控器" }
        return "第二步：允许控制当前应用"
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeading(
                    title: "最近操作",
                    subtitle: "用来确认遥控器按键是否正常响应"
                )
                Spacer()
                if !model.logs.isEmpty {
                    Button("清除") { model.clearLogs() }
                        .buttonStyle(.borderless)
                }
            }

            Group {
                if model.logs.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "appletvremote.gen4")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("试着按一下遥控器")
                            .font(.headline)
                        Text("按键响应会显示在这里")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.logs.prefix(8))) { entry in
                            ActivityRow(entry: entry)
                            if entry.id != model.logs.prefix(8).last?.id {
                                Divider().padding(.leading, 54)
                            }
                        }
                    }
                }
            }
            .productCard()
        }
    }
}

private struct ProductStatusPill: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.15), in: Capsule())
    }
}

private struct SectionHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AdaptedAppTile: View {
    let app: AdaptedApplication
    let customized: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                ApplicationIconView(
                    bundleIdentifier: app.bundleIdentifier,
                    fallbackSymbol: app.fallbackSymbol,
                    size: 48
                )
                if customized {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 17, height: 17)
                        .background(.blue, in: Circle())
                        .offset(x: 5, y: -4)
                }
            }
            Text(app.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .padding(.vertical, 14)
        .frame(width: 104)
        .productCard()
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct GestureSettingRow: View {
    let symbol: String
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let step: Int
    let update: (Int) -> Void

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol: symbol)
            Text(title)
                .fontWeight(.medium)
                .frame(width: 82, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { update(Int($0.rounded())) }
                ),
                in: Double(range.lowerBound) ... Double(range.upperBound),
                step: Double(step)
            )
            Text("\(value) ms")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .trailing)
        }
        .padding(16)
    }
}

private struct PermissionSettingRow: View {
    let symbol: String
    let title: String
    let detail: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("已开启", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Text("未开启")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
    }
}

private struct SettingsIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.blue)
            .frame(width: 34, height: 34)
            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct ActivityRow: View {
    let entry: RemoteLogEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.button.productSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 30, height: 30)
                .background(.blue.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.button.title)
                    .fontWeight(.medium)
                Text("\(entry.trigger.title) · \(entry.result)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(entry.date, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private extension RemoteButton {
    var productSymbol: String {
        switch self {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .select: "circle.inset.filled"
        case .back: "arrow.uturn.backward"
        case .home: "house"
        case .tv: "tv"
        case .menu: "line.3.horizontal"
        case .volumeUp: "speaker.plus"
        case .volumeDown: "speaker.minus"
        case .power: "power"
        case .voice: "mic"
        }
    }
}

private extension VoiceInputProvider {
    var symbol: String {
        switch self {
        case .typeless: "waveform.and.mic"
        case .systemDictation: "mic.fill"
        case .disabled: "mic.slash"
        }
    }

    var detail: String {
        switch self {
        case .typeless: "通过硬件 F20 触发 Typeless，保留它的原生语音流程"
        case .systemDictation: "在当前应用中启动 macOS 听写"
        case .disabled: "不由全局语音服务处理，仍可交给应用 Profile"
        }
    }
}

private extension View {
    func productCard() -> some View {
        background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.separator.opacity(0.55), lineWidth: 0.5)
            }
    }
}
