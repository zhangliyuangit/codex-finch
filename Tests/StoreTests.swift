import Foundation
import SQLite3

@main struct StoreTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexUsageTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var db: OpaquePointer?
        precondition(sqlite3_open(root.appendingPathComponent("state_5.sqlite").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        func sql(_ value: String) {
            precondition(sqlite3_exec(db, value, nil, nil, nil) == SQLITE_OK)
        }
        sql("PRAGMA journal_mode=WAL")
        sql("CREATE TABLE threads(id TEXT,title TEXT,name TEXT,rollout_path TEXT,updated_at INTEGER,model TEXT,tokens_used INTEGER,archived INTEGER,agent_path TEXT,thread_source TEXT,project_id TEXT,cwd TEXT)")
        sql("CREATE TABLE projects(id TEXT,name TEXT,position INTEGER)")
        sql("CREATE TABLE project_roots(project_id TEXT,path TEXT,position INTEGER)")
        sql("INSERT INTO projects VALUES('repo','sample-api',0),('explicit','sample-web',1)")
        sql("INSERT INTO project_roots VALUES('repo','/repos/sample-api',0),('explicit','/repos/frontend',0)")
        func version() -> Int32 {
            var statement: OpaquePointer?
            precondition(sqlite3_prepare_v2(db, "PRAGMA data_version", -1, &statement, nil) == SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            precondition(sqlite3_step(statement) == SQLITE_ROW)
            return sqlite3_column_int(statement, 0)
        }
        let dataVersion = version()
        let path = root.appendingPathComponent("session.jsonl")
        func fixture(_ count: Int, stamp: String = "2026-10-08T08:00:00Z") -> Data {
            Data("{\"type\":\"event_msg\",\"timestamp\":\"\(stamp)\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":\(count-10),\"output_tokens\":10,\"total_tokens\":\(count)}},\"rate_limits\":{\"primary\":{\"used_percent\":40,\"window_minutes\":10080}}}}\n".utf8)
        }
        try fixture(100).write(to: path)
        let id = "00000000-0000-4000-8000-000000000001"
        sql("INSERT INTO threads VALUES('\(id)','原始标题','显示名称','\(path.path)',1791446400,'test-model',100,0,NULL,'user',NULL,'/repos/sample-api/src')")
        sql("INSERT INTO threads VALUES('\(UUID().uuidString)','子智能体',NULL,'\(path.path)',1791446401,'test-model',999,0,'/agent','subagent',NULL,'/repos/sample-api')")
        sql("INSERT INTO threads VALUES('\(UUID().uuidString)','已归档',NULL,'\(path.path)',1791446402,'test-model',999,1,NULL,'user',NULL,'/repos/sample-api')")
        let store = UsageStore(root: root, dailyCacheURL:root.appendingPathComponent("cache/daily.sqlite"))
        var failures = 0
        func check(_ result: Bool, _ message: String) {
            print("\(result ? "PASS" : "FAIL") \(message)"); if !result { failures += 1 }
        }
        func awaitCondition(_ condition: () -> Bool, timeout: TimeInterval = 5) {
            let until = Date().addingTimeInterval(timeout)
            while !condition(), Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        }
        store.start()
        awaitCondition { store.snapshot.refreshCount >= 1 }
        check(store.snapshot.sessions.count == 1, "过滤归档和子智能体，不重复统计")
        check(store.snapshot.sessions.first?.title == "显示名称", "优先使用用户可见会话名")
        check(store.snapshot.sessions.first?.tokens == 100, "读取真实 fixture usage")
        check(store.snapshot.sessions.first?.projectName == "sample-api", "读取真实项目根目录并匹配子目录")
        let initialBytes = store.snapshot.bytesRead
        store.refresh()
        awaitCondition { store.snapshot.refreshCount >= 2 }
        check(store.snapshot.bytesRead == initialBytes, "无变动手动刷新不重读日志")
        let handle = try FileHandle(forWritingTo: path)
        try handle.seekToEnd(); try handle.write(contentsOf: fixture(200)); try handle.close()
        awaitCondition { store.snapshot.sessions.first?.tokens == 200 }
        check(store.snapshot.sessions.first?.tokens == 200, "文件通知自动更新，不需要轮询")
        check(store.snapshot.bytesRead == initialBytes + fixture(200).count, "文件通知仅读取新字节")
        func lifecycle(_ type: String, at stamp: String) throws {
            let handle = try FileHandle(forWritingTo:path)
            try handle.seekToEnd()
            try handle.write(contentsOf:Data("{\"type\":\"event_msg\",\"timestamp\":\"\(stamp)\",\"payload\":{\"type\":\"\(type)\",\"turn_id\":\"A\"}}\n".utf8))
            try handle.close()
        }
        try lifecycle("task_started",at:"2026-10-08T08:00:01Z")
        awaitCondition { store.snapshot.sessions.first?.activity?.phase == .running }
        check(store.snapshot.sessions.first?.activity?.phase == .running, "文件事件更新会话活动状态")
        try lifecycle("task_complete",at:"2026-10-08T08:00:02Z")
        awaitCondition { store.snapshot.sessions.first?.activity?.phase == .completed }
        check(store.snapshot.activityEvents.first?.activity.phase == .completed, "采集器发布结束信号")
        let eventCount = store.snapshot.refreshCount
        store.refresh()
        awaitCondition { store.snapshot.refreshCount > eventCount }
        check(store.snapshot.activityEvents.isEmpty, "再次刷新不重放结束信号")
        let beforeRename = store.snapshot.bytesRead
        sql("UPDATE projects SET name='sample-api renamed' WHERE id='repo'")
        awaitCondition { store.snapshot.sessions.first?.projectName == "sample-api renamed" }
        check(store.snapshot.sessions.first?.projectName == "sample-api renamed", "项目重命名通过 WAL 通知更新")
        check(store.snapshot.bytesRead == beforeRename, "改变项目元数据不重读日志")
        sql("UPDATE threads SET project_id='explicit' WHERE id='\(id)'")
        awaitCondition { store.snapshot.sessions.first?.projectName == "sample-web" }
        check(store.snapshot.sessions.first?.projectID == "explicit", "显式项目归属覆盖路径推断")
        store.paused = true
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let pausedCount = store.snapshot.refreshCount
        let nextHandle = try FileHandle(forWritingTo: path)
        try nextHandle.seekToEnd(); try nextHandle.write(contentsOf: fixture(300)); try nextHandle.close()
        RunLoop.current.run(until: Date().addingTimeInterval(1.8))
        check(store.snapshot.refreshCount == pausedCount, "暂停时停止文件监听")
        store.paused = false
        awaitCondition { store.snapshot.sessions.first?.tokens == 300 }
        check(store.snapshot.sessions.first?.tokens == 300, "恢复时补读暂停期间增量")
        let newPath = root.appendingPathComponent("new-session.jsonl")
        try fixture(400).write(to: newPath)
        sql("INSERT INTO threads VALUES('\(UUID().uuidString)','新会话',NULL,'\(newPath.path)',1791446405,'test-model',400,0,NULL,'user',NULL,'/Documents/Codex/temp')")
        awaitCondition { store.snapshot.sessions.first?.title == "新会话" }
        check(store.snapshot.sessions.first?.tokens == 400, "数据库 WAL 事件发现新会话")
        check(store.snapshot.sessions.first?.projectID == nil, "未匹配的临时聊天保留未归属状态")
        var dailyExpected = Int(store.snapshot.daily?.tokens ?? 0)
        let actualToday = UsageDate.fractional.string(from:Date())
        for index in 0..<26 {
            let usagePath = root.appendingPathComponent("daily-\(index).jsonl")
            let count = 100+index;dailyExpected += count
            let obj:[String:Any] = ["type":"token_usage_record","timestamp":actualToday,"payload":["response_id":"daily-\(index)","turn_id":"daily-turn-\(index)","usage":["input_tokens":count-10,"output_tokens":10,"total_tokens":count]]]
            var data = try JSONSerialization.data(withJSONObject:obj);data.append(10);try data.write(to:usagePath)
            let archived = index%2, source = index%3 == 0 ? "subagent" : "user"
            sql("INSERT INTO threads VALUES('\(UUID().uuidString)','daily',NULL,'\(usagePath.path)',\(Int(Date().timeIntervalSince1970)), 'test',0,\(archived),NULL,'\(source)',NULL,'/Documents/Codex/temp')")
        }
        awaitCondition { store.snapshot.daily?.tokens == Int64(dailyExpected) }
        check(store.snapshot.daily?.tokens == Int64(dailyExpected), "今日总量覆盖超过24条、已归档和子智能体日志")
        check(store.snapshot.menuValue(for:.tokens,at:Date()) == store.snapshot.daily?.label, "菜单栏 token 指标使用今日总量")
        let dailyBefore = store.snapshot.daily?.bytesRead
        let dailyCount = store.snapshot.refreshCount
        store.refresh();awaitCondition { store.snapshot.refreshCount > dailyCount }
        check(store.snapshot.daily?.bytesRead == dailyBefore, "今日索引无变动时不重扫历史")
        store.stopMonitoring()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        check(version() == dataVersion, "采集器未写入 Codex 元数据")
        if failures > 0 { exit(1) }
        print("ALL STORE TESTS PASSED")
    }
}
