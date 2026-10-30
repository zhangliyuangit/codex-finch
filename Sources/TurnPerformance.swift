import Foundation
import CoreFoundation

struct TurnPerformance: Codable, Equatable {
    let turnID: String
    let completedAt: Date
    var durationMilliseconds: Double?
    var firstTokenMilliseconds: Double?
    var outputTokens: Int64?

    var averageTokensPerSecond: Double? {
        guard let outputTokens, let durationMilliseconds, durationMilliseconds > 0 else { return nil }
        let rate = Double(outputTokens) / (durationMilliseconds / 1000)
        return rate.isFinite ? rate : nil
    }

    static func secondsLabel(_ milliseconds: Double?) -> String {
        guard let milliseconds else { return "—" }
        let seconds = milliseconds / 1000
        if seconds >= 3600 { return String(format: "%.1f h", seconds / 3600) }
        if seconds >= 60 { return String(format: "%.1f min", seconds / 60) }
        return String(format: "%.1f s", seconds)
    }

    var firstTokenLabel: String { Self.secondsLabel(firstTokenMilliseconds) }
    var durationLabel: String { Self.secondsLabel(durationMilliseconds) }
    var throughputLabel: String {
        guard let rate = averageTokensPerSecond else { return "—" }
        return "≈" + String(format: "%.1f", rate) + " tok/s"
    }
    var help: String {
        "最近完成一轮（\(UsageFormat.time(completedAt))）：首 token 延迟 \(firstTokenLabel)，整轮耗时 \(durationLabel)，整轮平均吞吐 \(throughputLabel)。输出含推理及工具调用 token；均速含工具执行与等待，并非纯生成速度。"
    }
}

/// Retains only numeric metadata for a bounded set of local turns.
final class TurnPerformanceTracker {
    private struct Round {
        var start: Date?
        var usageDate: Date?
        var output: Int64?
        var completion: TurnPerformance?
        var touched: Date
    }
    private var rounds: [String: Round] = [:]
    private(set) var latest: TurnPerformance?

    func skipUnreadGap() {
        // A per-turn cumulative snapshot after the gap can establish a fresh numerator.
        // Never join a pre-gap incomplete snapshot to a post-gap completion.
        rounds.removeAll(keepingCapacity: false)
    }

    func consume(recordType: String, payload: [String: Any], date: Date) {
        let kind = recordType == "event_msg" ? payload["type"] as? String : recordType
        guard ["token_usage_record", "task_started", "turn_started", "task_complete", "turn_completed"].contains(kind),
              let turn = payload["turn_id"] as? String, !turn.isEmpty,
              (payload["root_turn_id"] as? String).map({ $0 == turn }) ?? true else { return }
        var round = rounds[turn] ?? Round(touched: date)
        round.touched = max(round.touched, date)
        switch kind {
        case "task_started", "turn_started":
            round.start = round.start ?? (payload["started_at"] as? String).flatMap(UsageDate.parse) ?? date
        case "token_usage_record":
            guard let usage = payload["turn_token_usage"] as? [String: Any],
                  let output = Self.number(usage["output_tokens"]), output.rounded() == output,
                  output < Double(Int64.max),
                  date >= (round.usageDate ?? .distantPast),
                  date <= (round.completion?.completedAt ?? .distantFuture) else { return }
            // This is the cumulative snapshot for this local turn, never response/thread totals.
            round.output = Int64(output)
            round.usageDate = date
        case "task_complete", "turn_completed":
            let end = (payload["completed_at"] as? String).flatMap(UsageDate.parse) ?? date
            guard end >= (round.completion?.completedAt ?? .distantPast) else { return }
            let duration = Self.number(payload["duration_ms"]) ?? round.completion?.durationMilliseconds
            var first = Self.number(payload["time_to_first_token_ms"]) ?? round.completion?.firstTokenMilliseconds
            if let duration, let value = first, value > duration { first = nil }
            round.completion = TurnPerformance(turnID: turn, completedAt: end,
                durationMilliseconds: duration, firstTokenMilliseconds: first)
        default: break
        }
        if var completion = round.completion {
            completion.outputTokens = nil
            if let usageDate = round.usageDate, usageDate <= completion.completedAt,
               usageDate >= (round.start ?? .distantPast) { completion.outputTokens = round.output }
            round.completion = completion
            if completion.completedAt >= (latest?.completedAt ?? .distantPast) {
                // A late record for an older round must not replace a more recent round.
                if completion.completedAt > (latest?.completedAt ?? .distantPast) || latest?.turnID == turn {
                    latest = completion
                }
            }
        }
        rounds[turn] = round
        if rounds.count > 32, let oldest = rounds.min(by: { $0.value.touched < $1.value.touched })?.key {
            rounds.removeValue(forKey: oldest)
        }
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let result = value.doubleValue
        return result.isFinite && result >= 0 ? result : nil
    }
}
