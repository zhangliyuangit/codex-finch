import Foundation
import Darwin

struct TokenUsage: Codable, Equatable {
    var input: Int64
    var cached: Int64
    var output: Int64
    var reasoning: Int64
    var total: Int64
    var timestamp: Date
    var cacheRatio: Double { input > 0 ? Double(cached) / Double(input) : 0 }
}

struct QuotaWindow: Codable, Equatable {
    var used: Double
    var minutes: Int
    var resetsAt: Date?
    var remaining: Double { max(0, min(100, 100 - used)) }
    var title: String {
        if minutes == 10080 { return "每周额度" }
        if minutes == 300 { return "5 小时额度" }
        if minutes == 1440 { return "每日额度" }
        if minutes >= 60 && minutes % 60 == 0 { return "\(minutes / 60) 小时额度" }
        return minutes > 0 ? "\(minutes) 分钟额度" : "账号额度"
    }
}

struct QuotaSnapshot: Codable, Equatable {
    var primary: QuotaWindow?
    var secondary: QuotaWindow?
    var timestamp: Date
    var displayWindow: QuotaWindow? {
        // Prefer the weekly pool when present, otherwise the primary window.
        if primary?.minutes == 10080 { return primary }
        if secondary?.minutes == 10080 { return secondary }
        return primary ?? secondary
    }
}

enum CodexLink {
    static func url(for id: String) -> URL? {
        guard UUID(uuidString: id) != nil else { return nil }
        return URL(string: "codex://threads/\(id)")
    }
}

enum UsageDate {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let plain = ISO8601DateFormatter()
    static func parse(_ value: String) -> Date? {
        fractional.date(from: value) ?? plain.date(from: value)
    }
}

final class UsageAccumulator {
    private(set) var latest: TokenUsage?
    private(set) var quota: QuotaSnapshot?
    private var activityTracker = ActivityTracker()
    var activity: SessionActivity? { activityTracker.latest }
    func drainActivityEvents() -> [SessionActivity] { activityTracker.drainEvents() }
    private var pending = Data()
    private var discarding = false
    private let maximumLine = 2 * 1024 * 1024
    private static let eventTypes = ["token_count", "task_started", "turn_started", "task_complete", "turn_completed",
        "turn_aborted", "task_failed", "turn_failed", "request_user_input", "exec_approval_request", "apply_patch_approval_request",
        "user_input_response", "exec_approval_response", "apply_patch_approval_response", "item_completed"].map { Data("\"\($0)\"".utf8) }
    private static let itemType = try! NSRegularExpression(pattern: "\"item\"\\s*:\\s*\\{\\s*\"type\"\\s*:\\s*\"([^\"\\\\]+)\"")

    func skipUnreadGap() {
        pending.removeAll(keepingCapacity: false); discarding = false
        // Missing bytes may contain a terminal event. Keep usage, but discard activity evidence.
        activityTracker = ActivityTracker()
    }

    func append(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: 10) {
            let line = pending.prefix(upTo: newline)
            if !discarding && line.count <= maximumLine { consume(line) }
            pending.removeSubrange(...newline)
            discarding = false
        }
        if pending.count > maximumLine {
            pending.removeAll(keepingCapacity: false)
            discarding = true
        }
    }

    private func consume(_ line: Data) {
        let prefix = Data(line.prefix(2048))
        var markers = prefix
        if line.count > 2048 { markers.append(line.suffix(2048)) }
        let isEvent = markers.range(of: Data("\"event_msg\"".utf8)) != nil
        let isResponse = markers.range(of: Data("\"response_item\"".utf8)) != nil
        let usage = markers.range(of: Data("\"token_count\"".utf8)) != nil
        if isEvent {
            guard Self.eventTypes.contains(where: { markers.range(of: $0) != nil }) else { return }
        } else if isResponse {
            let blockingCall = markers.range(of: Data("\"function_call\"".utf8)) != nil && markers.range(of: Data("request_user_input".utf8)) != nil
            let waitingReply = activityTracker.latest?.phase == .waiting && markers.range(of: Data("\"function_call_output\"".utf8)) != nil
            guard blockingCall || waitingReply else { return }
        } else { return }
        var parseData = line
        var compacted = false
        // Progress needs only its small event header; command stdout and message bodies
        // can be large and do not contribute to activity or notification content.
        if line.count > 2048, isEvent, markers.range(of: Data("\"item_completed\"".utf8)) != nil,
           let item = prefix.range(of: Data("\"item\"".utf8)) {
            var header = Data(prefix.prefix(upTo: item.lowerBound))
            while let last = header.last, last == 32 || last == 10 || last == 13 || last == 9 { header.removeLast() }
            if header.last == 44 { header.removeLast() }
            let text = String(decoding:prefix, as:UTF8.self)
            if let match = Self.itemType.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),
               let range = Range(match.range(at:1),in:text),
               let itemData = try? JSONSerialization.data(withJSONObject:["type":String(text[range])]) {
                header.append(Data(",\"item\":".utf8)); header.append(itemData); header.append(Data("}}".utf8))
                parseData = header; compacted = true
            }
        }
        var decoded = (try? JSONSerialization.jsonObject(with: parseData)) as? [String: Any]
        if compacted, decoded?["timestamp"] as? String == nil || (decoded?["payload"] as? [String:Any])?["turn_id"] as? String == nil {
            // The current logger puts metadata before item. For a differently ordered
            // bounded record, fall back to its full JSON rather than infer a false state.
            decoded = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        }
        guard let object = decoded,
              let payload = object["payload"] as? [String: Any],
              let stamp = object["timestamp"] as? String,
              let date = UsageDate.parse(stamp) else { return }
        activityTracker.consume(payload: payload, date: date, responseItem: object["type"] as? String == "response_item")
        guard object["type"] as? String == "event_msg", usage, payload["type"] as? String == "token_count" else { return }
        if let info = payload["info"] as? [String: Any],
           let total = info["total_token_usage"] as? [String: Any],
           let input = (total["input_tokens"] as? NSNumber)?.int64Value,
           let output = (total["output_tokens"] as? NSNumber)?.int64Value,
           let count = (total["total_tokens"] as? NSNumber)?.int64Value,
           count >= 0, input >= 0, output >= 0,
           date >= (latest?.timestamp ?? .distantPast) {
            latest = TokenUsage(input: input,
                                cached: max(0, min(input, (total["cached_input_tokens"] as? NSNumber)?.int64Value ?? 0)),
                                output: output,
                                reasoning: (total["reasoning_output_tokens"] as? NSNumber)?.int64Value ?? 0,
                                total: count, timestamp: date)
        }
        if let limits = payload["rate_limits"] as? [String: Any],
           limits["limit_id"] == nil || limits["limit_id"] is NSNull || limits["limit_id"] as? String == "codex",
           date >= (quota?.timestamp ?? .distantPast) {
            let primary = window(limits["primary"])
            let secondary = window(limits["secondary"])
            if primary != nil || secondary != nil {
                quota = QuotaSnapshot(primary: primary, secondary: secondary, timestamp: date)
            }
        }
    }

    private func window(_ object: Any?) -> QuotaWindow? {
        guard let dict = object as? [String: Any],
              let used = (dict["used_percent"] as? NSNumber)?.doubleValue, used.isFinite else { return nil }
        let reset = (dict["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return QuotaWindow(used: max(0, min(100, used)),
                           minutes: (dict["window_minutes"] as? NSNumber)?.intValue ?? 0,
                           resetsAt: reset)
    }
}

final class TailReader {
    static let initialLimit = 512 * 1024
    static let incrementalLimit = 1024 * 1024
    let path: String
    private(set) var parser = UsageAccumulator()
    private(set) var bytesRead = 0
    private var offset: UInt64 = 0
    private var inode: UInt64?

    init(path: String) { self.path = path }

    func read() throws {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var stats = stat()
        guard fstat(handle.fileDescriptor, &stats) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let size = UInt64(max(0, stats.st_size))
        let currentInode = UInt64(stats.st_ino)
        let reset = inode == nil || inode != currentInode || size < offset
        var skipPartial = false
        if reset {
            parser = UsageAccumulator()
            offset = size > UInt64(Self.initialLimit) ? size - UInt64(Self.initialLimit) : 0
            skipPartial = offset > 0
        } else if size - offset > UInt64(Self.incrementalLimit) {
            // A large tool result must not trigger an unbounded read.
            parser.skipUnreadGap()
            offset = size - UInt64(Self.incrementalLimit)
            skipPartial = true
        }
        inode = currentInode
        guard size > offset else { return }
        try handle.seek(toOffset: offset)
        var data = try handle.read(upToCount: Int(size - offset)) ?? Data()
        offset += UInt64(data.count)
        bytesRead += data.count
        if skipPartial {
            if let newline = data.firstIndex(of: 10) { data.removeSubrange(...newline) }
            else { data.removeAll() }
        }
        parser.append(data)
    }
}

enum UsageFormat {
    static func tokens(_ count: Int64) -> String {
        if count >= 1_000_000 { return String(format: "%.2fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
    static func percent(_ value: Double) -> String { String(format: "%.0f%%", value) }
    static func time(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }
    static func reset(_ date: Date?) -> String {
        guard let date else { return "重置时间未知" }
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日 HH:mm"
        return "\(f.string(from: date)) 重置"
    }
}
