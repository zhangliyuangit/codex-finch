import AppKit
import SwiftUI
import Combine
import UserNotifications

@main
struct CodexFinchMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = UsageAppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class UsageAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let store: UsageStore
    private var subscriptions = Set<AnyCancellable>()
    private var window: NSWindow?
    private var isExporting = false
    private var resetDeadline: Date?
    private var resetWork: DispatchWorkItem?
    private var activityDeadline: Date?
    private var activityWork: DispatchWorkItem?
    private var notifications: LocalNotifications?
    private let login = LoginItemController()
    private var dayDeadline: Date?
    private var dayWork: DispatchWorkItem?
    private var dateObservers: [NSObjectProtocol] = []
    private let arguments = CommandLine.arguments

    override init() {
        let args = CommandLine.arguments
        func path(_ flag: String) -> URL? {
            guard let i = args.firstIndex(of:flag),args.count>i+1 else { return nil }
            return URL(fileURLWithPath:args[i+1])
        }
        let root = path("--data-root") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        store = UsageStore(root:root,dailyCacheURL:path("--daily-cache"))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = argument("--verify-native") {
            let center = UNUserNotificationCenter.current()
            var finished = false
            func finish(_ fields: [String:Any]) {
                guard !finished else { return };finished = true
                if let data=try? JSONSerialization.data(withJSONObject:fields,options:.sortedKeys) {
                    try? data.write(to:URL(fileURLWithPath:path),options:.atomic)
                }
                NSApp.terminate(nil)
            }
            notifications = LocalNotifications(store:store) { id in
                if let id,let url=CodexLink.url(for:id) { NSWorkspace.shared.open(url) }
            }
            var checked = false
            store.onUpdate = { [weak self] in
                guard let self,!checked else { return };checked=true
                let url = self.store.snapshot.sessions.first.flatMap { CodexLink.url(for:$0.id) }
                let handler = url.flatMap { NSWorkspace.shared.urlForApplication(toOpen:$0) } != nil
                self.notifications?.test { requestID in
                    DispatchQueue.main.asyncAfter(deadline:.now()+1) {
                        center.getDeliveredNotifications { notices in
                            DispatchQueue.main.async {
                                finish(["linkHandlerRegistered":handler,"notificationAccepted":requestID != nil,
                                        "testNotificationDelivered":notices.contains { $0.request.identifier == requestID },
                                        "visibleBannerVerified":false,"conversationClickVerified":false])
                            }
                        }
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline:.now()+20) { finish(["timedOut":true]) }
            store.start();return
        }
        if let path = argument("--login-status") {
            login.refresh()
            let object: [String:Any] = ["state":login.state.rawValue, "enabled":login.state.isEnabled, "message":login.message]
            if let data = try? JSONSerialization.data(withJSONObject:object) { try? data.write(to:URL(fileURLWithPath:path)) }
            NSApp.terminate(nil); return
        }
        if let path = argument("--diagnostics") { store.diagnosticsURL = URL(fileURLWithPath: path) }
        if let metric = argument("--metric").flatMap(MenuMetric.init(rawValue:)) { store.metric = metric }
        if let path = argument("--notification-status") {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let object: [String: Any] = ["authorizationStatus": settings.authorizationStatus.rawValue,
                                            "alertSetting": settings.alertSetting.rawValue,
                                            "soundSetting": settings.soundSetting.rawValue,
                                            "alertStyle": settings.alertStyle.rawValue,
                                            "notificationCenterSetting": settings.notificationCenterSetting.rawValue,
                                            "scheduledDeliverySetting": settings.scheduledDeliverySetting.rawValue,
                                            "timeSensitiveSetting": settings.timeSensitiveSetting.rawValue]
                if let data = try? JSONSerialization.data(withJSONObject: object) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            return
        }
        if let path = argument("--render") {
            isExporting = true
            store.onUpdate = { [weak self] in
                guard let self, self.window == nil else { return }
                self.renderPreview(path: path)
            }
            store.start()
            return
        }
        if let path = argument("--dump") {
            isExporting = true
            store.diagnosticsURL = URL(fileURLWithPath: path)
            store.onUpdate = { NSApp.terminate(nil) }
            store.start()
            return
        }
        if let seconds = argument("--benchmark").flatMap(Double.init), seconds > 0, seconds <= 60 {
            isExporting = true
            store.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
            return
        }
        // Avoid leaving duplicate status items after the user reopens the app bundle.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        login.migrateExistingIfNeeded()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        let mainMenu = NSMenu()
        let applicationMenu = NSMenu()
        let applicationItem = NSMenuItem()
        applicationItem.submenu = applicationMenu
        let quitItem = NSMenuItem(title: "退出 Codex Finch", action: #selector(terminate), keyEquivalent: "q")
        quitItem.target = self
        applicationMenu.addItem(quitItem)
        mainMenu.addItem(applicationItem)
        NSApp.mainMenu = mainMenu
        if let button = item.button {
            button.image = FinchBrand.menuImage
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Codex Finch 用量")
        }
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        notifications = LocalNotifications(store: store) { [weak self] id in
            if let id { _ = self?.openSession(id) }
            else { self?.showPopover() }
        }
        store.onTestNotification = { [weak self] in self?.notifications?.test() }
        store.onUpdate = { [weak self] in
            guard let self else { return }
            self.updateMenuTitle()
            self.notifications?.consume(self.store.snapshot)
        }
        store.$notifications.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] preferences in
            self?.notifications?.update(preferences: preferences)
        }.store(in: &subscriptions)
        store.$metric.receive(on: DispatchQueue.main).sink { [weak self] _ in
            // Published emits before the property changes.
            DispatchQueue.main.async { self?.updateMenuTitle() }
        }.store(in: &subscriptions)
        store.$paused.receive(on: DispatchQueue.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateMenuTitle() }
        }.store(in: &subscriptions)
        store.start()
        updateMenuTitle()
        for name in [NSNotification.Name.NSSystemTimeZoneDidChange,NSNotification.Name.NSCalendarDayChanged] {
            dateObservers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in self?.store.refresh() })
        }
        if arguments.contains("--window") {
            let controller = NSHostingController(rootView: UsagePanel(store:store,login:login,openSession:{ [weak self] id in self?.openSession(id) ?? false },quit:{ NSApp.terminate(nil) }))
            let win = NSWindow(contentViewController:controller)
            win.title = "Codex Finch"
            win.styleMask = [.titled,.closable]
            win.setContentSize(NSSize(width:380,height:780))
            win.center();win.makeKeyAndOrderFront(nil);NSApp.activate()
            window=win
        }
        if arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.showPopover() }
        }
    }

    private func argument(_ flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1 else { return nil }
        return arguments[index + 1]
    }

    private func updateMenuTitle() {
        guard let button = statusItem?.button else { return }
        let value = store.snapshot.menuValue(for:store.metric,at:Date())
        button.title = value.isEmpty ? "" : " " + value
        let updated = store.snapshot.quota.map { "额度快照 \(UsageFormat.time($0.timestamp))" } ?? "等待额度快照"
        let today = store.snapshot.daily.map { "今日 \($0.label) token · 本机日志 · \($0.timeZone)\($0.partial ? " · 统计不完整" : "")" } ?? "今日用量正在读取"
        button.toolTip = "Codex Finch · \(store.metric.label)\n\(today)\n\(store.snapshot.activeCount(at: Date())) 个处理中 · \(store.snapshot.waitingCount) 个待确认\n\(updated)\(store.paused ? "\n采集已暂停" : "")"
        let end = store.snapshot.daily?.end
        if end != dayDeadline {
            dayWork?.cancel();dayDeadline = end
            if let end,end>Date() {
                let work = DispatchWorkItem { [weak self] in self?.updateMenuTitle();self?.store.refresh() }
                dayWork = work
                DispatchQueue.main.asyncAfter(deadline:.now()+end.timeIntervalSinceNow+0.1,execute:work)
            }
        }
        let deadline = store.snapshot.quota?.displayWindow?.resetsAt
        if deadline != resetDeadline {
            resetWork?.cancel()
            resetDeadline = deadline
            if let deadline, deadline > Date() {
                // A single deadline invalidates an expired snapshot; this is not a poll.
                let work = DispatchWorkItem { [weak self] in
                    self?.updateMenuTitle()
                    self?.store.objectWillChange.send()
                }
                resetWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + deadline.timeIntervalSinceNow + 0.1, execute: work)
            }
        }
        let activityExpiry = store.snapshot.sessions.compactMap { session -> Date? in
            guard session.activity?.phase == .running, let date = session.activity?.timestamp else { return nil }
            let expiry = date.addingTimeInterval(SessionActivity.staleInterval)
            return expiry > Date() ? expiry : nil
        }.min()
        if activityExpiry != activityDeadline {
            activityWork?.cancel(); activityDeadline = activityExpiry
            if let activityExpiry {
                let work = DispatchWorkItem { [weak self] in
                    self?.updateMenuTitle(); self?.store.objectWillChange.send()
                }
                activityWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + activityExpiry.timeIntervalSinceNow + 0.1, execute: work)
            }
        }
    }

    private func setPanel(settings: Bool) {
        let view = UsagePanel(store: store, login: login, openSession: { [weak self] id in
            self?.openSession(id) ?? false
        }, quit: { NSApp.terminate(nil) }, settings: settings)
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 380, height: controller.view.fittingSize.height)
    }

    @objc private func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let settings = NSMenuItem(title: "偏好设置…", action: #selector(showSettings), keyEquivalent: ",")
            settings.target = self; menu.addItem(settings)
            let refresh = NSMenuItem(title: "刷新本地记录", action: #selector(refresh), keyEquivalent: "r")
            refresh.target = self; menu.addItem(refresh)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "退出 Codex Finch", action: #selector(terminate), keyEquivalent: "q")
            quit.target = self; menu.addItem(quit)
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }

    func applicationDidBecomeActive(_ notification: Notification) { login.refresh() }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        if popover.contentViewController == nil { setPanel(settings: false) }
        updateMenuTitle()
        store.refresh()
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func showSettings() { setPanel(settings: true); showPopover() }
    @objc private func refresh() { store.refresh() }
    @objc private func terminate() { NSApp.terminate(nil) }

    func popoverDidClose(_ notification: Notification) {
        // No SwiftUI view tree observes background snapshots while the popover is closed.
        popover.contentViewController = nil
    }

    private func openSession(_ id: String) -> Bool {
        guard let url = CodexLink.url(for: id) else { return false }
        let success = NSWorkspace.shared.open(url)
        if let diagnostics = store.diagnosticsURL,
           let data = try? JSONSerialization.data(withJSONObject: ["url": url.absoluteString, "accepted": success]) {
            try? data.write(to: diagnostics.appendingPathExtension("link.json"), options: .atomic)
        }
        if success { popover.performClose(nil) }
        return success
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        dateObservers.forEach { NotificationCenter.default.removeObserver($0) }
        store.stopMonitoring()
        return .terminateNow
    }

    private func renderPreview(path: String) {
        let dark = !arguments.contains("--light")
        let settings = arguments.contains("--settings")
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        NSApp.appearance = appearance
        let size = NSSize(width: 460, height: settings ? 780 : 860)
        let view = NSHostingView(rootView: PreviewScene(store: store, showSettings: settings, showStatistics: arguments.contains("--statistics"))
            .environment(\.colorScheme, dark ? .dark : .light))
        view.frame = NSRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = appearance
        win.backgroundColor = .windowBackgroundColor
        win.contentView = view
        win.orderFront(nil)
        window = win
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                fputs("Cannot create preview bitmap\n", stderr); exit(1)
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
            do { try png.write(to: URL(fileURLWithPath: path)) }
            catch { fputs("\(error)\n", stderr); exit(1) }
            print("Rendered native preview: \(path)")
            NSApp.terminate(nil)
        }
    }
}
