import RemoteCore
import SwiftUI

struct ProfileEditorView: View {
    let application: AdaptedApplication
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var profile: AppProfile
    @State private var trigger: RemoteTrigger = .tap
    @State private var showingResetConfirmation = false

    init(application: AdaptedApplication, model: AppModel) {
        self.application = application
        self.model = model
        _profile = State(initialValue: model.editableProfile(
            bundleIdentifier: application.bundleIdentifier,
            name: application.name
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    triggerPicker
                    bindings
                    explanation
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(minWidth: 660, idealWidth: 700, minHeight: 650, idealHeight: 720)
        .confirmationDialog(
            "恢复 (application.name) 的默认按键？",
            isPresented: $showingResetConfirmation
        ) {
            Button("恢复默认", role: .destructive) {
                if model.resetProfile(bundleIdentifier: application.bundleIdentifier) {
                    profile = model.editableProfile(
                        bundleIdentifier: application.bundleIdentifier,
                        name: application.name
                    )
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会移除这个应用的自定义配置，内置适配会继续生效。")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ApplicationIconView(
                bundleIdentifier: application.bundleIdentifier,
                fallbackSymbol: application.fallbackSymbol,
                size: 48
            )
            VStack(alignment: .leading, spacing: 3) {
                Text("配置 \(application.name)")
                    .font(.title2.bold())
                Text("为遥控器的每种操作选择应用行为")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isCustomized(bundleIdentifier: application.bundleIdentifier) {
                Label("已自定义", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.blue)
            }
        }
        .padding(24)
    }

    private var triggerPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("操作方式")
                .font(.headline)
            Picker("操作方式", selection: $trigger) {
                ForEach(RemoteTrigger.allCases, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            Text(triggerHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var bindings: some View {
        VStack(spacing: 0) {
            ForEach(Array(RemoteButton.allCases.enumerated()), id: \.element) { index, button in
                bindingRow(button)
                if index != RemoteButton.allCases.count - 1 {
                    Divider().padding(.leading, 54)
                }
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.separator.opacity(0.55), lineWidth: 0.5)
        }
    }

    private func bindingRow(_ button: RemoteButton) -> some View {
        HStack(spacing: 14) {
            Image(systemName: button.editorSymbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))

            Text(button.title)
                .fontWeight(.medium)
            Spacer()

            Menu {
                ForEach(ActionPreset.all) { preset in
                    Button {
                        profile.setAction(preset.action, for: button, trigger: trigger)
                    } label: {
                        if preset.action == profile.action(for: button, trigger: trigger) {
                            Label(preset.title, systemImage: "checkmark")
                        } else {
                            Text(preset.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Text(ActionPreset.title(for: profile.action(for: button, trigger: trigger)))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 150, alignment: .trailing)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var explanation: some View {
        Label(
            "“原样交给应用”适合已经原生支持遥控器的 App；“不执行”会屏蔽该操作。",
            systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack {
            if model.isCustomized(bundleIdentifier: application.bundleIdentifier) {
                Button("恢复默认") { showingResetConfirmation = true }
                    .buttonStyle(.borderless)
            }
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("保存") {
                if model.saveProfile(profile) { dismiss() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(18)
    }

    private var triggerHelp: String {
        switch trigger {
        case .tap: "轻按并松开时执行；未配置长按或双击时会立即响应。"
        case .hold: "持续按住达到设定时间后执行一次。"
        case .doubleTap: "在设定间隔内连续按两次时执行。"
        }
    }
}

private struct ActionPreset: Identifiable {
    let id: String
    let title: String
    let action: RemoteAction

    static let all: [ActionPreset] = [
        .init(id: "pass", title: "原样交给应用", action: .passThrough),
        .init(id: "none", title: "不执行", action: .none),
        .init(id: "up", title: "键盘：上", action: .keyStroke(KeyStroke(MacKeyCode.up))),
        .init(id: "down", title: "键盘：下", action: .keyStroke(KeyStroke(MacKeyCode.down))),
        .init(id: "left", title: "键盘：左", action: .keyStroke(KeyStroke(MacKeyCode.left))),
        .init(id: "right", title: "键盘：右", action: .keyStroke(KeyStroke(MacKeyCode.right))),
        .init(id: "return", title: "键盘：回车", action: .keyStroke(KeyStroke(MacKeyCode.returnKey))),
        .init(id: "escape", title: "键盘：Esc", action: .keyStroke(KeyStroke(MacKeyCode.escape))),
        .init(id: "space", title: "键盘：空格", action: .keyStroke(KeyStroke(MacKeyCode.space))),
        .init(id: "dictation", title: "macOS 系统听写", action: .systemDictation),
        .init(id: "home", title: "键盘：Home", action: .keyStroke(KeyStroke(MacKeyCode.home))),
        .init(id: "menu", title: "键盘：F2（mmTV 菜单）", action: .keyStroke(KeyStroke(MacKeyCode.f2))),
        .init(id: "back", title: "浏览器返回", action: .keyStroke(KeyStroke(MacKeyCode.leftBracket, modifiers: .command))),
        .init(id: "volume-up", title: "系统音量加", action: .systemVolume(delta: 0.0625)),
        .init(id: "volume-down", title: "系统音量减", action: .systemVolume(delta: -0.0625)),
        .init(id: "mute", title: "静音", action: .mute),
        .init(id: "play", title: "播放／暂停", action: .media(.playPause)),
        .init(id: "next", title: "下一首", action: .media(.next)),
        .init(id: "previous", title: "上一首", action: .media(.previous)),
        .init(id: "mmtv", title: "打开 mmTV", action: .launch(bundleIdentifier: "com.mmtv.mac")),
    ]

    static func title(for action: RemoteAction) -> String {
        all.first(where: { $0.action == action })?.title ?? action.title
    }
}

private extension RemoteButton {
    var editorSymbol: String {
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
