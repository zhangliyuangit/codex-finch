import Foundation

struct NotificationPreferences: Codable, Equatable {
    var enabled = false
    var completed = true
    var attention = true
    var lowQuota = true
    var lowQuotaThreshold = 20
    var sound = false
}
enum NoticeKind: String { case completed, attention, quota }
struct NoticePlan {
    let id: String
    let kind: NoticeKind
    let title: String
    let body: String
    let sessionID: String?
}
final class NoticePolicy {
    private(set) var seenKeys: [String]
    private var seen: Set<String>
    private var baselineAt: Date?
    private var quotaTimestamp: Date?
    init(seenKeys: [String] = []) {
        self.seenKeys = Array(seenKeys.suffix(200)); self.seen = Set(self.seenKeys)
    }
    func evaluate(_ snapshot: UsageSnapshot, preferences: NotificationPreferences, now: Date) -> [NoticePlan] {
        let initial = baselineAt == nil
        if initial { baselineAt = now }
        var plans: [NoticePlan] = []
        for signal in snapshot.activityEvents {
            let activity = signal.activity
            guard activity.phase.terminal || activity.phase == .waiting else { continue }
            let round = activity.turnID ?? "time-\(activity.timestamp.timeIntervalSince1970)"
            let key = "session|\(signal.sessionID)|\(round)|\(activity.phase.rawValue)|\(activity.requestID ?? "")"
            guard !seen.contains(key) else { continue }
            remember(key)
            let age = now.timeIntervalSince(activity.timestamp)
            guard !initial, preferences.enabled, age >= -60, age < 300,
                  activity.timestamp >= (baselineAt ?? now) else { continue }
            let attention = activity.phase == .waiting
            if attention {
                guard let current = snapshot.sessions.first(where: { $0.id == signal.sessionID })?.activity,
                      current.phase == .waiting, current.turnID == activity.turnID,
                      current.requestID == activity.requestID else { continue }
            }
            guard attention ? preferences.attention : preferences.completed else { continue }
            let title = attention ? "Codex · 需要确认" : (activity.phase == .failed ? "Codex · 任务失败" : activity.phase == .interrupted ? "Codex · 任务已中断" : "Codex · 会话已结束")
            let name = String(signal.title.prefix(80))
            let body = signal.projectName.map { "\($0) · \(name)" } ?? name
            plans.append(NoticePlan(id: key, kind: attention ? .attention : .completed, title: title, body: body, sessionID: signal.sessionID))
        }
        if let quota = snapshot.quota, let window = quota.displayWindow,
           quota.timestamp > (quotaTimestamp ?? .distantPast) {
            quotaTimestamp = quota.timestamp
            let key = "quota|\(window.minutes)|\(window.resetsAt?.timeIntervalSince1970 ?? 0)|\(preferences.lowQuotaThreshold)"
            if window.remaining <= Double(preferences.lowQuotaThreshold), !seen.contains(key) {
                remember(key)
                let age = now.timeIntervalSince(quota.timestamp)
                if !initial, preferences.enabled, preferences.lowQuota, age >= -60, age < 900,
                   window.resetsAt.map({ $0 > now }) ?? true {
                    plans.append(NoticePlan(id: key, kind: .quota, title: "Codex · 额度偏低",
                        body: "\(window.title)剩余 \(UsageFormat.percent(window.remaining)) · \(UsageFormat.reset(window.resetsAt))", sessionID: nil))
                }
            }
        }
        // Every event is consumed even when disabled; enabling cannot replay old alerts.
        return Array(plans.prefix(4))
    }

    private func remember(_ key: String) {
        seen.insert(key); seenKeys.append(key)
        if seenKeys.count > 200 {
            seenKeys.removeFirst(seenKeys.count - 200); seen = Set(seenKeys)
        }
    }
}
