import Foundation
import Combine
import SQLite3
import Darwin
import CryptoKit

struct SessionRecord: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let path: String
    let updatedAt: Date
    let model: String
    let metadataTokens: Int64
    var projectID: String?
    var projectName: String?
    var usage: TokenUsage?
    var activity: SessionActivity?
    var tokens: Int64 { usage?.total ?? metadataTokens }
}

struct UsageSnapshot: Codable {
    var sessions: [SessionRecord] = []
    var quota: QuotaSnapshot?
    var daily: DailyTokenTotal?
    var dailyError: String?
    var syncedAt: Date?
    var error: String?
    var activityEvents: [SessionSignal] = []
    var bytesRead: Int = 0
    var refreshCount: Int = 0
    var loadMilliseconds: Double = 0
    func activeCount(at date: Date) -> Int { sessions.filter { $0.activity?.effectivePhase(at: date) == .running }.count }
    var waitingCount: Int { sessions.filter { $0.activity?.phase == .waiting }.count }
    func menuValue(for metric: MenuMetric, at date: Date) -> String {
        switch metric {
        case .tokens:
            guard let daily,daily.start<=date,date<daily.end,dailyError == nil else { return "—" }
            return daily.label
        case .quota:
            guard let q = quota?.displayWindow,q.resetsAt.map({ $0>date }) ?? true else { return "—" }
            return UsageFormat.percent(q.remaining)
        case .activity:return "\(activeCount(at:date))"
        case .icon:return ""
        }
    }
}

enum MenuMetric: String, CaseIterable, Identifiable {
    case quota, tokens, activity, icon
    var id: String { rawValue }
    var label: String {
        switch self {
        case .quota: return "剩余额度"
        case .tokens: return "今日 token"
        case .icon: return "仅图标"
        case .activity: return "活跃会话"
        }
    }
}

final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot()
    @Published var metric: MenuMetric {
        didSet { UserDefaults.standard.set(metric.rawValue, forKey: "menuMetric") }
    }
    @Published var paused = false {
        didSet { paused ? stopMonitoring() : resume() }
    }
    @Published var notifications: NotificationPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(notifications) { UserDefaults.standard.set(data, forKey: "notificationPreferences") }
        }
    }
    @Published var notificationMessage = "开启后由 macOS 请求通知授权"
    var onTestNotification: (() -> Void)?
    var onUpdate: (() -> Void)?
    var diagnosticsURL: URL?
    private let queue = DispatchQueue(label: "local.codexusage.collector", qos: .utility)
    private let root: URL
    private let dailyIndex: DailyUsageIndex
    private var readers: [String: TailReader] = [:]
    private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    private var pending: DispatchWorkItem?
    private var isMonitoring = false
    private var refreshCount = 0
    private var totalBytes = 0
    private var previous = UsageSnapshot()

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"), dailyCacheURL: URL? = nil) {
        self.root = root
        let hash = SHA256.hash(data:Data(root.standardizedFileURL.path.utf8)).prefix(12).map { String(format:"%02x",$0) }.joined()
        let support = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!
        dailyIndex = DailyUsageIndex(cacheURL:dailyCacheURL ?? support.appendingPathComponent("CodexUsage/daily-\(hash).sqlite"))
        self.metric = MenuMetric(rawValue: UserDefaults.standard.string(forKey: "menuMetric") ?? "") ?? .quota
        self.notifications = UserDefaults.standard.data(forKey: "notificationPreferences")
            .flatMap { try? JSONDecoder().decode(NotificationPreferences.self, from: $0) } ?? NotificationPreferences()
    }

    func start() {
        queue.async { self.isMonitoring = true; self.reload() }
    }

    func refresh() {
        guard !paused else { return }
        queue.async { self.pending?.cancel(); self.pending = nil; self.reload() }
    }

    func stopMonitoring() {
        queue.async {
            self.isMonitoring = false
            self.pending?.cancel(); self.pending = nil
            self.watchers.values.forEach { $0.cancel() }
            self.watchers.removeAll()
        }
    }

    private func resume() {
        queue.async { self.isMonitoring = true; self.reload() }
    }

    private func scheduleReload() {
        guard isMonitoring, pending == nil else { return }
        // Throttle notifications: a stream of writes cannot postpone updates indefinitely.
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isMonitoring else { return }
            self.pending = nil
            self.reload()
        }
        pending = item
        queue.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    private func reload() {
        let began = DispatchTime.now().uptimeNanoseconds
        var next = previous
        next.activityEvents = []
        do {
            var sessions = try querySessions()
            var quota = previous.quota
            let paths = Set(sessions.map(\.path))
            readers = readers.filter { paths.contains($0.key) }
            for index in sessions.indices {
                let path = sessions[index].path
                let reader = readers[path] ?? TailReader(path: path)
                readers[path] = reader
                let before = reader.bytesRead
                try? reader.read()
                totalBytes += reader.bytesRead - before
                sessions[index].usage = reader.parser.latest
                sessions[index].activity = reader.parser.activity
                next.activityEvents += reader.parser.drainActivityEvents().map {
                    SessionSignal(sessionID: sessions[index].id, title: sessions[index].title,
                                  projectName: sessions[index].projectName, activity: $0)
                }
                if let candidate = reader.parser.quota,
                   candidate.timestamp >= (quota?.timestamp ?? .distantPast) {
                    quota = candidate
                }
            }
            next.sessions = sessions
            next.quota = quota
            next.error = nil
            next.syncedAt = Date()
            let calendar = Calendar.autoupdatingCurrent
            let start = calendar.startOfDay(for:Date())
            var dailyPaths = Set<String>()
            do {
                let sources = try queryDailySources(since:start)
                dailyPaths = Set(sources.map(\.path))
                next.daily = try dailyIndex.refresh(sources:sources,now:Date(),calendar:calendar)
                next.dailyError = nil
            } catch { next.dailyError = error.localizedDescription }
            if isMonitoring { updateWatchers(paths: paths.union(dailyPaths)) }
        } catch {
            next.error = error.localizedDescription
            if isMonitoring { updateWatchers(paths: []) }
        }
        refreshCount += 1
        next.refreshCount = refreshCount
        next.bytesRead = totalBytes
        next.loadMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
        previous = next
        let published = next
        DispatchQueue.main.async {
            self.snapshot = published
            if let url = self.diagnosticsURL,
               let data = try? JSONEncoder().encode(published) { try? data.write(to: url, options: .atomic) }
            self.onUpdate?()
        }
    }

    private func querySessions() throws -> [SessionRecord] {
        let path = root.appendingPathComponent("state_5.sqlite").path
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw NSError(domain: "UsageStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "未能读取 Codex 会话数据"])
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 150)
        let catalog = queryProjects(db: db)
        let sql = """
            SELECT id, COALESCE(NULLIF(name,''),title), rollout_path, updated_at,
                   COALESCE(model,''), tokens_used, project_id, cwd
            FROM threads
            WHERE archived=0 AND agent_path IS NULL
                  AND (thread_source IS NULL OR thread_source='user')
            ORDER BY updated_at DESC, id ASC LIMIT 24
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "UsageStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Codex 数据格式暂不兼容"])
        }
        defer { sqlite3_finalize(statement) }
        func string(_ column: Int32) -> String {
            sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
        }
        var result: [SessionRecord] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            let id = string(0)
            if CodexLink.url(for: id) != nil {
                let title = string(1).trimmingCharacters(in: .whitespacesAndNewlines)
                let project = catalog.resolve(projectID: string(6), cwd: string(7))
                result.append(SessionRecord(id: id, title: title.isEmpty ? "未命名会话" : title,
                                            path: string(2), updatedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 3))),
                                            model: string(4), metadataTokens: sqlite3_column_int64(statement, 5),
                                            projectID: project?.id, projectName: project?.name))
            }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else {
            throw NSError(domain: "UsageStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "Codex 数据暂时忙，请稍后刷新"])
        }
        return result
    }

    private func queryProjects(db: OpaquePointer?) -> ProjectCatalog {
        let sql = """
            SELECT p.id, p.name, p.position, r.path, r.position
            FROM projects p LEFT JOIN project_roots r ON r.project_id=p.id
            ORDER BY p.position, p.id, r.position
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return ProjectCatalog(projects: [])
        }
        defer { sqlite3_finalize(statement) }
        func string(_ column: Int32) -> String {
            sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
        }
        var projects: [ProjectRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = string(0)
            if projects.last?.id != id {
                let name = string(1).trimmingCharacters(in: .whitespacesAndNewlines)
                projects.append(ProjectRecord(id: id, name: name.isEmpty ? "未命名项目" : name,
                                              position: Int(sqlite3_column_int(statement, 2)), roots: []))
            }
            let path = string(3)
            if !path.isEmpty {
                projects[projects.count - 1].roots.append(ProjectRoot(path: path, position: Int(sqlite3_column_int(statement, 4))))
            }
        }
        return ProjectCatalog(projects: projects)
    }

    private func queryDailySources(since start: Date) throws -> [DailySource] {
        var db: OpaquePointer?
        let path = root.appendingPathComponent("state_5.sqlite").path
        guard sqlite3_open_v2(path,&db,SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,nil)==SQLITE_OK else {
            if let db { sqlite3_close(db) };throw NSError(domain:"UsageStore",code:4,userInfo:[NSLocalizedDescriptionKey:"今日会话范围暂不可用"])
        }
        defer { sqlite3_close(db) };sqlite3_busy_timeout(db,150)
        var statement: OpaquePointer?
        let sql = "SELECT id,rollout_path FROM threads WHERE updated_at>=? ORDER BY id"
        guard sqlite3_prepare_v2(db,sql,-1,&statement,nil)==SQLITE_OK else { throw NSError(domain:"UsageStore",code:5) }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement,1,Int64(start.timeIntervalSince1970))
        var result:[DailySource] = [],status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            let id = sqlite3_column_text(statement,0).map { String(cString:$0) } ?? ""
            let path = sqlite3_column_text(statement,1).map { String(cString:$0) } ?? ""
            if !id.isEmpty { result.append(DailySource(id:id,path:path)) }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw NSError(domain:"UsageStore",code:6) }
        return result
    }

    private func updateWatchers(paths: Set<String>) {
        let db = root.appendingPathComponent("state_5.sqlite").path
        let desired = paths.union([root.path, db, db + "-wal"])
        for path in watchers.keys where !desired.contains(path) {
            watchers.removeValue(forKey: path)?.cancel()
        }
        for path in desired where watchers[path] == nil {
            let fd = open(path, O_EVTONLY | O_CLOEXEC)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                eventMask: [.write, .extend, .delete, .rename, .revoke], queue: queue)
            source.setEventHandler { [weak self, weak source] in
                guard let self, let source else { return }
                if !source.data.intersection([.delete, .rename, .revoke]).isEmpty {
                    self.watchers.removeValue(forKey: path)?.cancel()
                }
                self.scheduleReload()
            }
            source.setCancelHandler { close(fd) }
            watchers[path] = source
            source.resume()
        }
    }
}
