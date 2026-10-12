import Foundation
import Combine
import ServiceManagement

final class LoginItemController: ObservableObject {
    @Published private(set) var state: LoginItemState = .disabled
    @Published private(set) var message = "登录 macOS 后自动启动 Finch。"
    private let service = SMAppService.mainApp
    private let legacyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/local.codexusage.menu.plist")
    private var legacyData: Data? {
        guard let executable = Bundle.main.executableURL?.path,
              let data = try? Data(contentsOf: legacyURL), LegacyLoginAgent.isOwned(data, executable: executable) else { return nil }
        return data
    }
    init() { refresh() }
    func refresh() {
        switch service.status {
        case .enabled: state = .enabled
        case .requiresApproval: state = legacyData == nil ? .approvalRequired : .legacy
        case .notRegistered: state = legacyData == nil ? .disabled : .legacy
        case .notFound: state = .unavailable
        @unknown default: state = .unavailable
        }
        switch state {
        case .enabled: message = "已开启，下次登录时由 macOS 启动。"
        case .legacy: message = "已开启，沿用现有启动项；可在这里关闭。"
        case .approvalRequired: message = "等待系统批准，请到登录项设置中允许 Finch。"
        case .disabled: message = "登录 macOS 后自动启动 Finch。"
        case .unavailable: message = "请先将 Finch 放入应用程序目录。"
        }
    }
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if service.status != .enabled && service.status != .requiresApproval { try service.register() }
                // Keep the known-working legacy item until system registration is enabled.
                if service.status == .enabled { try removeLegacy() }
            } else {
                if service.status != .notRegistered { try service.unregister() }
                try removeLegacy()
            }
            refresh()
        } catch {
            refresh()
            message = "未能更改开机启动：\(error.localizedDescription)"
        }
    }
    func migrateExistingIfNeeded() {
        guard legacyData != nil else { return }
        setEnabled(true)
    }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
    private func removeLegacy() throws {
        guard let data = legacyData else { return }
        let backup = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexUsage/legacy-startup.plist")
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: backup, options: .atomic)
        // Disabling prevents a future launch without killing the current menu-bar app.
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        command.arguments = ["disable", "gui/\(getuid())/local.codexusage.menu"]
        command.standardOutput = FileHandle.nullDevice
        command.standardError = FileHandle.nullDevice
        try command.run(); command.waitUntilExit()
        guard command.terminationStatus == 0 else {
            throw NSError(domain: "LoginItem", code: 1, userInfo: [NSLocalizedDescriptionKey:"旧启动项暂时不能关闭，已保留原配置。"])
        }
        try FileManager.default.removeItem(at: legacyURL)
    }
}
