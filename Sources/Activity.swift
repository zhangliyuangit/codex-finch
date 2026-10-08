import Foundation

enum ActivityPhase: String, Codable {
    case unknown, running, waiting, completed, interrupted, failed
    var label: String {
        switch self {
        case .unknown: return "状态未知"
        case .running: return "处理中"
        case .waiting: return "待确认"
        case .completed: return "已结束"
        case .interrupted: return "已中断"
        case .failed: return "失败"
        }
    }
    var terminal: Bool { self == .completed || self == .interrupted || self == .failed }
}
struct SessionActivity: Codable, Equatable {
    var phase: ActivityPhase
    var turnID: String?
    var timestamp: Date
    var requestID: String?
    static let staleInterval: TimeInterval = 600
    func effectivePhase(at date: Date) -> ActivityPhase {
        if phase == .running && date.timeIntervalSince(timestamp) >= Self.staleInterval { return .unknown }
        return phase
    }
    func label(at date: Date) -> String {
        if phase == .running && effectivePhase(at: date) == .unknown { return "状态待更新" }
        return phase.label
    }
}

final class ActivityTracker {
    private(set) var latest: SessionActivity?
    private var events: [SessionActivity] = []
    private var terminalTurns: [String] = []

    func consume(payload: [String: Any], date: Date, responseItem: Bool) {
        guard date >= (latest?.timestamp ?? .distantPast), let type = payload["type"] as? String else { return }
        let turn = (payload["turn_id"] as? String) ?? latest?.turnID
        if responseItem {
            if type == "function_call",
               let name = (payload["name"] as? String)?.split(separator: ".").last.map(String.init),
               name == "request_user_input" {
                if let text = payload["arguments"] as? String,
                   let data = text.data(using: .utf8),
                   let args = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                   args["isBlocking"] as? Bool == false { return }
                set(.waiting, turn: turn, date: date, request: payload["call_id"] as? String, signal: true)
            } else if type == "function_call_output", latest?.phase == .waiting,
                      let request = latest?.requestID, payload["call_id"] as? String == request {
                set(.running, turn: turn, date: date)
            }
            return
        }
        switch type {
        case "task_started", "turn_started":
            let incoming = payload["turn_id"] as? String
            if let incoming, terminalTurns.contains(incoming) { return }
            set(.running, turn: incoming, date: date)
        case "task_complete", "turn_completed", "turn_aborted", "task_failed", "turn_failed":
            if let active = latest?.turnID, let incoming = payload["turn_id"] as? String,
               active != incoming, latest?.phase.terminal != true { return }
            let phase: ActivityPhase = type == "turn_aborted" ? .interrupted : (type.contains("failed") ? .failed : .completed)
            set(phase, turn: turn, date: date, signal: true)
            if let turn {
                terminalTurns.append(turn)
                terminalTurns = Array(terminalTurns.suffix(16))
            }
        case "request_user_input", "exec_approval_request", "apply_patch_approval_request":
            if payload["isBlocking"] as? Bool == false { return }
            let request = payload["call_id"] as? String ?? payload["id"] as? String
            set(.waiting, turn: turn, date: date, request: request, signal: true)
        case "user_input_response", "exec_approval_response", "apply_patch_approval_response":
            guard latest?.phase == .waiting else { return }
            let request = payload["call_id"] as? String ?? payload["id"] as? String
            if let pending = latest?.requestID, request != pending { return }
            set(.running, turn: turn, date: date)
        case "item_completed":
            guard let incoming = payload["turn_id"] as? String, !terminalTurns.contains(incoming) else { return }
            if let item = payload["item"] as? [String: Any], item["type"] as? String == "UserMessage" { return }
            if let active = latest?.turnID, active != incoming, latest?.phase.terminal != true { return }
            if latest?.phase == .waiting { return }
            set(.running, turn: incoming, date: date)
        default: break
        }
    }

    private func set(_ phase: ActivityPhase, turn: String?, date: Date, request: String? = nil, signal: Bool = false) {
        let value = SessionActivity(phase: phase, turnID: turn, timestamp: date, requestID: request)
        latest = value
        if signal { events.append(value); events = Array(events.suffix(128)) }
    }

    func drainEvents() -> [SessionActivity] {
        let output = events; events.removeAll(keepingCapacity: true); return output
    }
}
struct SessionSignal: Codable {
    var sessionID: String
    var title: String
    var projectName: String?
    var activity: SessionActivity
}
