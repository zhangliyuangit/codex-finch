import Foundation
import SQLite3
import Darwin

struct DailySource {
    var id: String
    var path: String
}
struct DailyTokenTotal: Codable, Equatable {
    var start: Date
    var end: Date
    var timeZone: String
    var tokens: Int64
    var requests: Int
    var files: Int
    var partial: Bool
    var missingFiles: Int
    var bytesRead: Int
    var label: String { (partial ? "≥" : "") + UsageFormat.tokens(tokens) }
}
final class DailyUsageIndex {
    private let cacheURL: URL
    private var db: OpaquePointer?
    private var bytesRead = 0
    private var preciseTurns = Set<String>()
    private static let maxLine = 64 * 1024
    private static let markers = ["token_usage_record", "token_count", "task_started", "turn_started", "turn_context"].map { Data("\"\($0)\"".utf8) }
    init(cacheURL: URL) { self.cacheURL = cacheURL }
    deinit { sqlite3_close(db) }

    func refresh(sources: [DailySource], now: Date, calendar: Calendar) throws -> DailyTokenTotal {
        let interval = calendar.dateInterval(of: .day, for: now)!
        try openCache()
        try execute("BEGIN IMMEDIATE")
        do {
            let generation = "v1|\(calendar.timeZone.identifier)|\(interval.start.timeIntervalSince1970)"
            let stored: [String] = try rows("SELECT value FROM meta WHERE key='day'") { string($0,0) }
            if stored.first != generation {
                try execute("DELETE FROM files");try execute("DELETE FROM events");try execute("DELETE FROM gaps")
                try execute("INSERT OR REPLACE INTO meta VALUES('day',?)",[.text(generation)])
            }
            preciseTurns = Set(try rows("SELECT DISTINCT turn_key FROM events WHERE precise=1") { string($0,0) })
            var missing = 0, damaged = false
            for source in sources {
                do {
                    let values: [Data] = try rows("SELECT state FROM files WHERE id=?",[.text(source.id)]) { blob($0,0) }
                    var state = values.first.flatMap { try? JSONDecoder().decode(DailyFileState.self,from:$0) } ?? DailyFileState()
                    let changed = try read(source:source,state:&state,interval:interval)
                    damaged = damaged || state.damaged
                    if changed {
                        // Persist only the start offset of an incomplete line, never
                        // raw bytes, which might contain user text or tool output.
                        state.offset -= UInt64(state.pending.count)
                        state.pending.removeAll(keepingCapacity:false)
                        try execute("INSERT OR REPLACE INTO files VALUES(?,?)",[.text(source.id),.data(try JSONEncoder().encode(state))])
                    }
                } catch let error as DailyCacheError { throw error }
                catch { missing += 1 }
            }
            let included = "(e.precise=1 OR NOT EXISTS(SELECT 1 FROM events p WHERE p.precise=1 AND p.turn_key=e.turn_key))"
            let stats: [(Int64,Int,Int)] = try rows("SELECT COALESCE(SUM(e.tokens),0),COUNT(*),COALESCE(SUM(CASE WHEN e.precise=0 THEN 1 ELSE 0 END),0) FROM events e WHERE e.at>=? AND e.at<? AND \(included)", [.real(interval.start.timeIntervalSince1970),.real(interval.end.timeIntervalSince1970)]) {
                (sqlite3_column_int64($0,0),Int(sqlite3_column_int($0,1)),Int(sqlite3_column_int($0,2)))
            }
            let gaps: [Int] = try rows("SELECT COUNT(*) FROM gaps g WHERE g.at>=? AND g.at<? AND NOT EXISTS(SELECT 1 FROM events p WHERE p.precise=1 AND p.turn_key=g.turn_key)", [.real(interval.start.timeIntervalSince1970),.real(interval.end.timeIntervalSince1970)]) { Int(sqlite3_column_int($0,0)) }
            try execute("COMMIT")
            let result = stats.first ?? (0,0,0)
            return DailyTokenTotal(start:interval.start,end:interval.end,timeZone:calendar.timeZone.identifier,
                tokens:result.0,requests:result.1,files:sources.count,partial:missing>0 || damaged || result.2>0 || (gaps.first ?? 0)>0,
                missingFiles:missing,bytesRead:bytesRead)
        } catch { try? execute("ROLLBACK");throw error }
    }

    private func read(source: DailySource, state: inout DailyFileState, interval: DateInterval) throws -> Bool {
        let f = try FileHandle(forReadingFrom:URL(fileURLWithPath:source.path));defer { try? f.close() }
        var s = stat()
        guard fstat(f.fileDescriptor,&s)==0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno)) }
        let size = UInt64(max(0,s.st_size)), inode = UInt64(s.st_ino), device = UInt64(s.st_dev)
        let reset = state.inode != inode || state.device != device || size < state.offset
        if reset { state = DailyFileState(inode:inode,device:device) }
        guard size > state.offset else { return reset }
        try f.seek(toOffset:state.offset)
        while state.offset < size {
            let data = try f.read(upToCount:Int(min(UInt64(64*1024),size-state.offset))) ?? Data()
            guard !data.isEmpty else { throw NSError(domain:"DailyUsage",code:1) }
            state.offset += UInt64(data.count);bytesRead += data.count
            try autoreleasepool {
                var cursor = data.startIndex
                while let newline = data[cursor...].firstIndex(of:10) {
                    try fragment(Data(data[cursor..<newline]),ending:true,source:source,state:&state)
                    cursor = data.index(after:newline)
                }
                if cursor < data.endIndex { try fragment(Data(data[cursor...]),ending:false,source:source,state:&state) }
            }
        }
        return true
    }

    private func fragment(_ data: Data, ending: Bool, source: DailySource, state: inout DailyFileState) throws {
        if !state.discarding {
            if state.pending.count + data.count <= Self.maxLine {
                state.pending.append(data)
                if ending { try consume(state.pending,source:source,state:&state) }
            } else {
                let head = state.pending.isEmpty ? data : state.pending
                if head.prefix(1024).range(of:Data("\"token_usage_record\"".utf8)) != nil { state.damaged = true }
                state.discarding = true
            }
        }
        if ending || state.discarding { state.pending.removeAll(keepingCapacity:false) }
        if ending { state.discarding = false }
    }

    private func consume(_ line: Data, source: DailySource, state: inout DailyFileState) throws {
        var markers = Data(line.prefix(2048));if line.count>2048 { markers.append(line.suffix(2048)) }
        guard Self.markers.contains(where: { markers.range(of:$0) != nil }) else { return }
        guard let object = (try? JSONSerialization.jsonObject(with:line)) as? [String:Any],
              let payload = object["payload"] as? [String:Any],let type = object["type"] as? String,
              let stamp = object["timestamp"] as? String,let date = UsageDate.parse(stamp) else {
            if markers.range(of:Data("\"token_usage_record\"".utf8)) != nil { state.damaged = true };return
        }
        let event = payload["type"] as? String
        if type == "turn_context" || (type == "event_msg" && (event == "task_started" || event == "turn_started")) {
            state.turnID = payload["turn_id"] as? String;return
        }
        if type == "token_usage_record" || (type == "event_msg" && event == "token_usage_record") {
            let turn = payload["turn_id"] as? String ?? state.turnID
            if state.turnID == nil { state.turnID = turn }
            let turnKey = turn ?? "source|\(source.id)"
            guard let id = payload["response_id"] as? String,!id.isEmpty,
                  let usage = DailyCounts(payload["usage"]),usage.actual else {
                try gap(key:"record|\(turnKey)|\(stamp)",turn:turnKey,date:date);return
            }
            try execute("INSERT INTO events VALUES(?,?,?,?,1) ON CONFLICT(key) DO UPDATE SET tokens=MAX(tokens,excluded.tokens),at=MIN(at,excluded.at)",
                        [.text("response|"+id),.text(turnKey),.real(date.timeIntervalSince1970),.integer(usage.total)])
            preciseTurns.insert(turnKey);return
        }
        guard type == "event_msg",event == "token_count",let info = payload["info"] as? [String:Any],
              let current = DailyCounts(info["total_token_usage"]) else { return }
        let previous = state.previous;state.previous = current
        let turn = payload["turn_id"] as? String ?? state.turnID
        let turnKey = turn ?? "source|\(source.id)"
        guard !preciseTurns.contains(turnKey) else { return }
        if let previous,current.input == previous.input && current.output == previous.output && current.total == previous.total { return }
        let delta = previous.map { current.subtract($0) } ?? current
        guard let delta,delta.actual,delta.total>0 else { return }
        let last = DailyCounts(info["last_token_usage"])
        let identity = [current.input,current.cached,current.output,current.reasoning,current.total].map(String.init).joined(separator:",")
        let key = "legacy|\(turn ?? stamp)|\(identity)"
        if previous == nil && (last == nil || current.input != last?.input || current.output != last?.output || current.total != last?.total) {
            try gap(key:key,turn:turnKey,date:date);return
        }
        let amount: Int64
        if let last {
            guard last.actual,last.total>0,delta.input>=last.input,delta.output>=last.output,delta.total>=last.total else { return }
            amount = last.total
            if delta.total != last.total { try gap(key:key+"|gap",turn:turnKey,date:date) }
        } else { amount = delta.total }
        try execute("INSERT OR IGNORE INTO events VALUES(?,?,?,?,0)", [.text(key),.text(turnKey),.real(date.timeIntervalSince1970),.integer(amount)])
    }

    private func gap(key: String, turn: String, date: Date) throws {
        try execute("INSERT OR IGNORE INTO gaps VALUES(?,?,?)",[.text(key),.text(turn),.real(date.timeIntervalSince1970)])
    }

    private func openCache() throws {
        if db != nil { return }
        try FileManager.default.createDirectory(at:cacheURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        guard sqlite3_open_v2(cacheURL.path,&db,SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX,nil)==SQLITE_OK else { throw DailyCacheError() }
        sqlite3_busy_timeout(db,500)
        for sql in ["PRAGMA journal_mode=WAL","PRAGMA synchronous=NORMAL","PRAGMA cache_size=-1024",
                    "CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY,value TEXT)",
                    "CREATE TABLE IF NOT EXISTS files(id TEXT PRIMARY KEY,state BLOB)",
                    "CREATE TABLE IF NOT EXISTS events(key TEXT PRIMARY KEY,turn_key TEXT,at REAL,tokens INTEGER,precise INTEGER)",
                    "CREATE INDEX IF NOT EXISTS events_day ON events(at)",
                    "CREATE INDEX IF NOT EXISTS events_turn ON events(turn_key,precise)",
                    "CREATE TABLE IF NOT EXISTS gaps(key TEXT PRIMARY KEY,turn_key TEXT,at REAL)"] { try execute(sql) }
    }
    private func prepare(_ sql: String, _ values: [DailyValue]) throws -> OpaquePointer {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&s,nil)==SQLITE_OK,let s else { throw DailyCacheError() }
        let transient = unsafeBitCast(-1,to:sqlite3_destructor_type.self)
        for (index,value) in values.enumerated() {
            let i = Int32(index+1)
            switch value {
            case .text(let v):sqlite3_bind_text(s,i,v,-1,transient)
            case .real(let v):sqlite3_bind_double(s,i,v)
            case .integer(let v):sqlite3_bind_int64(s,i,v)
            case .data(let v):v.withUnsafeBytes { _ = sqlite3_bind_blob(s,i,$0.baseAddress,Int32(v.count),transient) }
            }
        }
        return s
    }
    private func execute(_ sql: String, _ values: [DailyValue] = []) throws {
        let s = try prepare(sql,values);defer { sqlite3_finalize(s) }
        var status = sqlite3_step(s)
        while status == SQLITE_ROW { status = sqlite3_step(s) }
        guard status == SQLITE_DONE else { throw DailyCacheError() }
    }
    private func rows<T>(_ sql: String, _ values: [DailyValue] = [], map: (OpaquePointer)->T) throws -> [T] {
        let s = try prepare(sql,values);defer { sqlite3_finalize(s) }
        var result:[T] = [],status = sqlite3_step(s)
        while status == SQLITE_ROW { result.append(map(s));status = sqlite3_step(s) }
        guard status == SQLITE_DONE else { throw DailyCacheError() };return result
    }
    private func string(_ s: OpaquePointer,_ column: Int32) -> String { sqlite3_column_text(s,column).map { String(cString:$0) } ?? "" }
    private func blob(_ s: OpaquePointer,_ column: Int32) -> Data { sqlite3_column_blob(s,column).map { Data(bytes:$0,count:Int(sqlite3_column_bytes(s,column))) } ?? Data() }
}

private struct DailyFileState: Codable {
    var inode: UInt64?
    var device: UInt64?
    var offset: UInt64 = 0
    var pending = Data()
    var discarding = false
    var previous: DailyCounts?
    var turnID: String?
    var damaged = false
}
private struct DailyCounts: Codable {
    var input: Int64
    var cached: Int64
    var output: Int64
    var reasoning: Int64
    var total: Int64
    var actual: Bool {
        let sum = input.addingReportingOverflow(output)
        return input>=0 && output>=0 && total>=0 && !sum.overflow && sum.partialValue == total
    }
    init?(_ value: Any?) {
        guard let value = value as? [String:Any],let input = value["input_tokens"] as? NSNumber,
              let output = value["output_tokens"] as? NSNumber,let total = value["total_tokens"] as? NSNumber else { return nil }
        self.input = input.int64Value;self.output = output.int64Value;self.total = total.int64Value
        cached = (value["cached_input_tokens"] as? NSNumber)?.int64Value ?? 0
        reasoning = (value["reasoning_output_tokens"] as? NSNumber)?.int64Value ?? 0
    }
    private init(input: Int64,cached: Int64,output: Int64,reasoning: Int64,total: Int64) {
        self.input=input;self.cached=cached;self.output=output;self.reasoning=reasoning;self.total=total
    }
    func subtract(_ previous: DailyCounts) -> DailyCounts? {
        guard input>=previous.input,output>=previous.output,total>=previous.total,
              previous.input>=0,previous.output>=0,previous.total>=0 else { return nil }
        return DailyCounts(input:input-previous.input,cached:0,output:output-previous.output,reasoning:0,total:total-previous.total)
    }
}
private enum DailyValue { case text(String),real(Double),integer(Int64),data(Data) }
private struct DailyCacheError: LocalizedError {
    var errorDescription: String? { "今日用量缓存暂不可用" }
}
