import AppKit
import SwiftUI

struct StatusMenuView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var isReady: Bool {
        model.serviceEnabled
            && model.remoteConnected
            && model.inputMonitoringStatus == .granted
            && model.accessibilityTrusted
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.vertical, 14)
            currentApplication

            if model.inputMonitoringStatus != .granted || !model.accessibilityTrusted {
                permissionNotice.padding(.top, 12)
            }

            Divider().padding(.vertical, 14)
            controls

            HStack(spacing: 8) {
                Button("打开控制台") { openDashboard() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                Button {
                    model.reloadProfiles()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("重新加载适配方案")

                Spacer()

                Menu {
                    Button("退出 mmTV Remote") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("更多")
            }
            .padding(.top, 14)
        }
        .padding(16)
        .frame(width: 330)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "appletvremote.gen4.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 3) {
                Text("mmTV Remote")
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle()
                        .fill(isReady ? .green : .orange)
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { model.serviceEnabled },
                set: model.setServiceEnabled
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private var currentApplication: some View {
        HStack(spacing: 12) {
            ApplicationIconView(
                bundleIdentifier: model.frontmostApp.bundleIdentifier,
                fallbackSymbol: "macwindow",
                size: 42
            )
            VStack(alignment: .leading, spacing: 3) {
                Text("正在控制")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.frontmostApp.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(model.activeProfile.name)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 13))
        .contentShape(Rectangle())
        .onTapGesture(perform: openDashboard)
    }

    private var permissionNotice: some View {
        Button(action: openDashboard) {
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("完成系统授权以使用全部按键")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .padding(10)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack {
                Label("遥控器", systemImage: "dot.radiowaves.left.and.right")
                Spacer()
                Text(remoteDetail)
                    .foregroundStyle(model.remoteConnected ? .green : .secondary)
            }
            HStack {
                Label("按键接管", systemImage: "switch.2")
                Spacer()
                Text(model.inputRoutingMode.title)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("语音输入", systemImage: "waveform.and.mic")
                Spacer()
                Text(model.voiceInputProvider.title)
                    .foregroundStyle(.secondary)
            }
            if let firmware = model.remoteFirmwareVersion {
                HStack {
                    Label("遥控器固件", systemImage: "cpu")
                    Spacer()
                    Text(firmware)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Label("登录后自动运行", systemImage: "power")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: model.setLaunchAtLogin
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
        .font(.subheadline)
    }

    private var statusText: String {
        if !model.serviceEnabled { return "服务已暂停" }
        if !model.remoteConnected { return "等待遥控器连接" }
        if !isReady { return "需要完成授权" }
        return "已连接，可以使用"
    }

    private var remoteDetail: String {
        guard model.remoteConnected else { return "未连接" }
        if let battery = model.remoteBatteryLevel { return "已连接 · \(battery)%" }
        return "已连接"
    }

    private func openDashboard() {
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }
}
