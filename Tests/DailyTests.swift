import Foundation

@main struct DailyTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexDaily-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        var failures = 0
        func check(_ value: Bool, _ title: String) { print("\(value ? "PASS" : "FAIL") \(title)"); if !value { failures += 1 } }
        var calendar = Calendar(identifier:.gregorian);calendar.timeZone = TimeZone(identifier:"Asia/Shanghai")!
        let now = UsageDate.parse("2026-10-08T12:00:00+08:00")!
        func json(_ type: String, at: String, payload: [String:Any]) -> Data {
            var data = try! JSONSerialization.data(withJSONObject:["type":type,"timestamp":at,"payload":payload]);data.append(10);return data
        }
        func counts(_ total: Int) -> [String:Any] { ["input_tokens":total-10,"cached_input_tokens":max(0,total-20),"output_tokens":10,"reasoning_output_tokens":5,"total_tokens":total] }
        func record(_ id: String, total: Int, at: String = "2026-10-08T01:00:00+08:00", turn: String = "turn-A", cumulative: Int = 1000) -> Data {
            json("token_usage_record",at:at,payload:["response_id":id,"turn_id":turn,"thread_id":"source-A","usage":counts(total),"thread_token_usage":counts(cumulative)])
        }
        func start(_ id: String) -> Data { json("event_msg",at:"2026-10-08T00:00:00+08:00",payload:["type":"task_started","turn_id":id]) }
        func counter(_ total: Int, last: Int?, at: String, turn: String? = nil) -> Data {
            var info:[String:Any] = ["total_token_usage":counts(total)]
            if let last { info["last_token_usage"] = counts(last) }
            var payload:[String:Any] = ["type":"token_count","info":info]
            if let turn { payload["turn_id"] = turn }
            return json("event_msg",at:at,payload:payload)
        }
        func write(_ name: String, _ data: Data) throws -> DailySource {
            let path = root.appendingPathComponent(name);try data.write(to:path);return DailySource(id:name,path:path.path)
        }
        func append(_ source: DailySource, _ data: Data) throws {
            let f = try FileHandle(forWritingTo:URL(fileURLWithPath:source.path));try f.seekToEnd();try f.write(contentsOf:data);try f.close()
        }
        let a = try write("a.jsonl",record("yesterday",total:100,at:"2026-10-07T23:59:59+08:00") + record("midnight",total:200,at:"2026-10-08T00:00:00+08:00") + record("today",total:300) + record("tomorrow",total:400,at:"2026-10-09T00:00:00+08:00"))
        let cache = root.appendingPathComponent("index.sqlite")
        let index = DailyUsageIndex(cacheURL:cache)
        let initial = try index.refresh(sources:[a],now:now,calendar:calendar)
        check(initial.tokens == 500, "今日总量以本地午夜划分，不包含昨天或明天")
        check(initial.requests == 2 && !initial.partial, "独立响应记录提供可去重的本地统计")
        check(initial.tokens != 2000, "继承的会话累计不会计入今日消费")
        let unchanged = try index.refresh(sources:[a],now:now,calendar:calendar)
        check(unchanged.bytesRead == initial.bytesRead, "文件未变化时零重读")
        try append(a,record("today",total:300,at:"2026-10-08T02:00:00+08:00"))
        check(try index.refresh(sources:[a],now:now,calendar:calendar).tokens == 500, "同一响应 ID 重复发出不累加")
        let clone = try write("clone.jsonl",try Data(contentsOf:URL(fileURLWithPath:a.path)))
        check(try index.refresh(sources:[a,clone],now:now,calendar:calendar).tokens == 500, "分叉复制历史响应跨文件去重")
        let extra = record("new",total:50)
        try append(a,extra)
        let changed = try index.refresh(sources:[a,clone],now:now,calendar:calendar)
        check(changed.tokens == 550, "新增响应更新今日总量")
        let restarted = DailyUsageIndex(cacheURL:cache)
        let warm = try restarted.refresh(sources:[a,clone],now:now,calendar:calendar)
        check(warm.tokens == 550 && warm.bytesRead == 0, "重启复用缓存与读取位置，不再扫描历史")
        let half = record("half",total:60);try append(a,half.prefix(half.count/2))
        check(try restarted.refresh(sources:[a,clone],now:now,calendar:calendar).tokens == 550, "半行不提前计入")
        let halfRestart = DailyUsageIndex(cacheURL:cache)
        try append(a,half.dropFirst(half.count/2))
        check(try halfRestart.refresh(sources:[a,clone],now:now,calendar:calendar).tokens == 610, "半行跨重启可恢复拼接")
        try record("replacement",total:70).write(to:URL(fileURLWithPath:a.path),options:.atomic)
        check(try halfRestart.refresh(sources:[a,clone],now:now,calendar:calendar).tokens == 680, "日志替换仍保留已经记录的今日消耗")
        let mixed = try write("mixed.jsonl",start("mixed") + record("mixed-real",total:80,turn:"mixed",cumulative:10000) + counter(9999,last:80,at:"2026-10-08T02:00:00+08:00"))
        let mixedIndex = DailyUsageIndex(cacheURL:root.appendingPathComponent("mixed.sqlite"))
        let mixedResult = try mixedIndex.refresh(sources:[mixed],now:now,calendar:calendar)
        check(mixedResult.tokens == 80 && !mixedResult.partial, "存在响应记录的轮次不重复计入滞后的累计快照")
        let reversed = try write("reversed.jsonl",start("mixed") + counter(9999,last:80,at:"2026-10-08T02:00:00+08:00") + record("mixed-real",total:80,turn:"mixed",cumulative:10000))
        let reverseIndex = DailyUsageIndex(cacheURL:root.appendingPathComponent("reverse.sqlite"))
        let reverseResult = try reverseIndex.refresh(sources:[reversed],now:now,calendar:calendar)
        check(reverseResult.tokens == 80 && !reverseResult.partial, "记录顺序改变仍优先独立响应用量")
        let old = try write("old.jsonl",start("old") + counter(1000,last:nil,at:"2026-10-07T23:50:00+08:00") + counter(1200,last:nil,at:"2026-10-08T01:00:00+08:00") + counter(1200,last:nil,at:"2026-10-08T02:00:00+08:00"))
        let oldIndex = DailyUsageIndex(cacheURL:root.appendingPathComponent("old.sqlite"))
        let oldResult = try oldIndex.refresh(sources:[old],now:now,calendar:calendar)
        check(oldResult.tokens == 200 && oldResult.partial, "旧格式只计算跨天后新增量，并标记不完整")
        let missingBaseline = try write("missing-baseline.jsonl",counter(1_000_000,last:nil,at:"2026-10-08T01:00:00+08:00"))
        let unknownIndex = DailyUsageIndex(cacheURL:root.appendingPathComponent("unknown.sqlite"))
        let unknown = try unknownIndex.refresh(sources:[missingBaseline],now:now,calendar:calendar)
        check(unknown.tokens == 0 && unknown.partial, "缺少累计基线时不把历史百万 token 算到今天")
        let huge = try write("huge.jsonl",Data(repeating:120,count:2*1024*1024) + Data([10]) + record("after-huge",total:90))
        let hugeIndex = DailyUsageIndex(cacheURL:root.appendingPathComponent("huge.sqlite"))
        check(try hugeIndex.refresh(sources:[huge],now:now,calendar:calendar).tokens == 90, "跳过大段正文后仍统计用量记录")
        let absent = DailySource(id:"missing",path:root.appendingPathComponent("absent.jsonl").path)
        let absentResult = try hugeIndex.refresh(sources:[huge,absent],now:now,calendar:calendar)
        check(absentResult.partial && absentResult.missingFiles == 1, "缺失日志不能显示完整总量")
        let nextDay = try restarted.refresh(sources:[clone],now:now.addingTimeInterval(86400),calendar:calendar)
        check(nextDay.tokens == 400, "跨午夜切换日期重新覆盖当天记录")
        var ny = Calendar(identifier:.gregorian);ny.timeZone = TimeZone(identifier:"America/New_York")!
        let dst = try index.refresh(sources:[],now:UsageDate.parse("2026-03-08T12:00:00-04:00")!,calendar:ny)
        check(dst.end.timeIntervalSince(dst.start) == 23*3600, "本地日期区间正确处理夏令时的23小时")
        var owned = a; owned.id = "source-A"; owned.projectID = "api"; owned.projectName = "Atlas API"; owned.model = "model-A"
        var copied = clone; copied.projectID = "web"; copied.projectName = "Atlas Web"; copied.model = "model-B"
        let attributionIndex = DailyUsageIndex(cacheURL: root.appendingPathComponent("attribution.sqlite"))
        let attributed = try attributionIndex.refresh(sources: [owned,copied], now:now, calendar:calendar)
        check(attributed.projects.reduce(Int64(0)) { $0+$1.tokens } == attributed.tokens, "项目拆分总和与今日去重总量一致")
        check(attributed.projects.first(where: { $0.id == "api" })?.tokens == attributed.tokens, "复制响应保留原项目归属，不计入复制项目或会话累计")
        check(attributed.models.contains(where: { $0.id == "model-A" }), "按响应模型汇总今日用量")
        check(attributed.history.contains(where: { $0.start == calendar.startOfDay(for:now) && $0.tokens == attributed.tokens }), "历史含已观察的今日数据")
        let tomorrow = try attributionIndex.refresh(sources: [owned,copied], now:now.addingTimeInterval(86400), calendar:calendar)
        check(tomorrow.history.contains(where: { $0.start == calendar.startOfDay(for:now) && $0.tokens == attributed.tokens }), "跨日保留已记录历史")
        check(tomorrow.history.first(where: { $0.start == calendar.startOfDay(for:now) })?.partial == true, "历史不承诺完整采集，旧日期显示为已记录下限")
        let renamedBytes = tomorrow.bytesRead
        owned.projectName = "Renamed API"
        let rename = try attributionIndex.refresh(sources:[owned,copied], now:now, calendar:calendar)
        check(rename.projects.first(where: { $0.id == "api" })?.name == "Renamed API" && rename.bytesRead == renamedBytes, "项目更名无需重读日志")
        check(rename.projects.allSatisfy { $0.input+$0.output == $0.tokens && $0.cached <= $0.input }, "输入输出组成总量，缓存是输入子集")
        var orphan = try write("orphan.jsonl",record("orphan-response",total:120))
        orphan.projectID = "clone-project";orphan.projectName = "Clone"
        let orphanIndex = DailyUsageIndex(cacheURL:root.appendingPathComponent("orphan.sqlite"))
        let orphanResult = try orphanIndex.refresh(sources:[orphan],now:now,calendar:calendar)
        check(orphanResult.projects.first?.id == "__unassigned__", "复制记录声明原会话但原归属不可见时保留未归属，不归给复制项目")
        if failures > 0 { exit(1) }
        print("ALL DAILY TESTS PASSED")
    }
}
