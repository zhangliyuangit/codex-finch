import Foundation

struct SessionConfiguration: Codable, Equatable {
    var model: String?
    var effort: String?
    var serviceTier: String?
    var timestamp: Date?
    var tierTimestamp: Date?

    var isFast: Bool { serviceTier == "priority" || serviceTier == "fast" }
    var modeLabel: String {
        switch serviceTier {
        case "priority", "fast": return "Fast"
        case "default": return "标准"
        case "ultrafast": return "Ultrafast"
        case "flex": return "Flex"
        case "auto": return "自动"
        case nil: return "模式未知"
        default: return serviceTier ?? "模式未知"
        }
    }
    var effortLabel: String {
        switch effort {
        case "none": return "无"
        case "minimal": return "最低"
        case "low": return "低"
        case "medium": return "中"
        case "high": return "高"
        case "xhigh": return "超高"
        case "max": return "Max"
        case "ultra": return "Ultra"
        default: return "未知"
        }
    }
    var summary: String { "\(model ?? "模型未知") · 思考 \(effortLabel) · \(modeLabel)" }
    var help: String {
        let observed = tierTimestamp.map { "\(UsageFormat.time($0)) 记录" } ?? "尚未记录模式"
        return "\(summary)\n\(observed)；模型/思考可来自当前本地会话元数据。模式仅表示日志明确记录的配置，不保证当前界面开关状态或请求实际服务等级；缺失不代表关闭。"
    }

    func resolving(metadataModel: String, metadataEffort: String?) -> SessionConfiguration {
        var result = self
        let model = Self.value(metadataModel)
        let effort = Self.value(metadataEffort)
        if (model != nil && self.model != nil && model != self.model) ||
           (effort != nil && self.effort != nil && effort != self.effort) {
            result.serviceTier = nil; result.tierTimestamp = nil
        }
        result.model = model ?? self.model
        result.effort = effort ?? self.effort
        return result
    }

    static func value(_ object: Any?) -> String? {
        guard let value = object as? String else { return nil }
        let trimmed = value.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 128,
              trimmed.rangeOfCharacter(from:.controlCharacters) == nil else { return nil }
        return trimmed
    }
}

final class SessionConfigurationTracker {
    private(set) var latest: SessionConfiguration?
    private let sessionID: String?
    init(sessionID: String? = nil) { self.sessionID = sessionID }

    func skipUnreadGap() { latest = nil }

    func consume(recordType: String, payload: [String:Any], date: Date) {
        guard date >= (latest?.timestamp ?? .distantPast) else { return }
        if recordType == "event_msg", payload["type"] as? String == "thread_settings_applied" {
            if let sessionID {
                guard payload["thread_id"] as? String == sessionID else { return }
            }
            guard let settings = payload["thread_settings"] as? [String:Any] else { return }
            let tier = SessionConfiguration.value(settings["service_tier"])
            // This is a complete applied-settings snapshot: absent/null fields are unknown.
            latest = SessionConfiguration(model:SessionConfiguration.value(settings["model"]),
                effort:SessionConfiguration.value(settings["reasoning_effort"]), serviceTier:tier,
                timestamp:date, tierTimestamp:tier == nil ? nil : date)
        } else if recordType == "turn_context" {
            if let owner = payload["thread_id"] as? String, let sessionID, owner != sessionID { return }
            let mode = payload["collaboration_mode"] as? [String:Any]
            let settings = mode?["settings"] as? [String:Any]
            let model = SessionConfiguration.value(payload["model"])
            let effort = SessionConfiguration.value(payload["effort"] ?? payload["reasoning_effort"] ?? settings?["reasoning_effort"])
            var next = latest ?? SessionConfiguration()
            let hasModel = payload.keys.contains("model")
            let hasEffort = payload.keys.contains("effort") || payload.keys.contains("reasoning_effort") || settings?.keys.contains("reasoning_effort") == true
            if (hasModel && model != next.model) || (hasEffort && effort != next.effort) {
                next.serviceTier = nil; next.tierTimestamp = nil
            }
            if hasModel { next.model = model }
            if hasEffort {
                next.effort = effort
            }
            if payload.keys.contains("service_tier") {
                next.serviceTier = SessionConfiguration.value(payload["service_tier"])
                next.tierTimestamp = next.serviceTier == nil ? nil : date
            }
            next.timestamp = date
            latest = next
        }
    }
}
