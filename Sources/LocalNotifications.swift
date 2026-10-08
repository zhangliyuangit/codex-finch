import Foundation
import UserNotifications

final class LocalNotifications: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let policy: NoticePolicy
    private weak var store: UsageStore?
    private let open: (String?) -> Void
    private var preferences: NotificationPreferences
    private var authorized = false
    private var requesting = false

    init(store: UsageStore, open: @escaping (String?) -> Void) {
        self.store = store
        self.open = open
        self.preferences = store.notifications
        self.policy = NoticePolicy(seenKeys: UserDefaults.standard.stringArray(forKey: "noticeSeenKeys") ?? [])
        super.init()
        center.delegate = self
        updateAuthorization(requestIfNeeded: preferences.enabled)
    }

    func update(preferences: NotificationPreferences) {
        let justEnabled = preferences.enabled && !self.preferences.enabled
        self.preferences = preferences
        updateAuthorization(requestIfNeeded: justEnabled)
        if !preferences.enabled {
            center.removeAllPendingNotificationRequests()
        }
    }

    func consume(_ snapshot: UsageSnapshot) {
        let before = policy.seenKeys
        let plans = policy.evaluate(snapshot, preferences: preferences, now: Date())
        if before != policy.seenKeys { UserDefaults.standard.set(policy.seenKeys, forKey: "noticeSeenKeys") }
        guard preferences.enabled, authorized else { return }
        plans.forEach(deliver)
    }

    func test() {
        guard preferences.enabled else {
            store?.notificationMessage = "请先开启通知"; return
        }
        updateAuthorization(requestIfNeeded: true) { [weak self] allowed in
            guard let self, allowed else { return }
            let session = self.store?.snapshot.sessions.first
            self.deliver(NoticePlan(id: "test-" + UUID().uuidString, kind: .completed,
                                   title: "Codex Finch · 测试通知", body: "通知已连接；点击可打开最近会话。",
                                   sessionID: session?.id))
        }
    }

    private func deliver(_ plan: NoticePlan) {
        guard preferences.enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        if preferences.sound { content.sound = .default }
        if let id = plan.sessionID { content.userInfo = ["thread_id": id] }
        let request = UNNotificationRequest(identifier: plan.id, content: content, trigger: nil)
        center.add(request) { [weak self] error in
            DispatchQueue.main.async {
                if let error { self?.store?.notificationMessage = "发送失败：\(error.localizedDescription)" }
                else { self?.store?.notificationMessage = "通知已提交；横幅显示取决于系统通知与专注模式设置" }
            }
        }
    }

    private func updateAuthorization(requestIfNeeded: Bool, completion: ((Bool) -> Void)? = nil) {
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    self.authorized = true
                    self.store?.notificationMessage = "macOS 通知已授权"
                    completion?(true)
                case .notDetermined:
                    self.authorized = false
                    guard requestIfNeeded, !self.requesting else {
                        self.store?.notificationMessage = "开启后由 macOS 请求通知授权"
                        completion?(false); return
                    }
                    self.requesting = true
                    self.center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                        DispatchQueue.main.async {
                            self.requesting = false; self.authorized = granted
                            self.store?.notificationMessage = error.map { "授权失败：\($0.localizedDescription)" }
                                ?? (granted ? "macOS 通知已授权" : "未获授权，请在 macOS 系统设置中开启通知")
                            completion?(granted)
                        }
                    }
                case .denied:
                    self.authorized = false
                    self.store?.notificationMessage = "通知被禁用，请在 macOS 系统设置中开启"
                    completion?(false)
                @unknown default:
                    self.authorized = false
                    self.store?.notificationMessage = "无法读取系统通知权限"
                    completion?(false)
                }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        DispatchQueue.main.async {
            guard self.preferences.enabled else { completionHandler([]); return }
            completionHandler(self.preferences.sound ? [.banner, .list, .sound] : [.banner, .list])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let value = response.notification.request.content.userInfo["thread_id"] as? String
        DispatchQueue.main.async {
            if let value, CodexLink.url(for: value) != nil { self.open(value) }
            else { self.open(nil) }
            completionHandler()
        }
    }
}
