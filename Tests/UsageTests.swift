import Foundation

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ description: String) {
    if condition() { print("PASS \(description)") }
    else { print("FAIL \(description)"); failures += 1 }
}
func event(total: Int, cached: Int = 50, output: Int = 10, percent: Double = 40, timestamp: String = "2026-10-08T08:00:00.000Z") -> Data {
    let obj: [String: Any] = ["timestamp":timestamp, "type":"event_msg", "payload": [
        "type":"token_count", "info": ["total_token_usage": ["input_tokens":total-output,"cached_input_tokens":cached,"output_tokens":output,"reasoning_output_tokens":5,"total_tokens":total]],
        "rate_limits": ["limit_id":"codex","primary":["used_percent":percent,"window_minutes":10080,"resets_at":1791969059]]]]
    var data = try! JSONSerialization.data(withJSONObject: obj)
    data.append(10)
    return data
}
@main struct Tests {
    static func main() throws {
        let parser = UsageAccumulator()
        parser.append(event(total: 100))
        parser.append(event(total: 150))
        check(parser.latest?.total == 150, "累计 token 使用最后一条，不累加快照")
        check(parser.latest?.input == 140 && parser.latest?.output == 10, "缓存与推理不重复相加")
        check(abs((parser.latest?.cacheRatio ?? 0) - 50.0/140.0) < 0.001, "缓存比例以输入 token 为分母")
        check(parser.quota?.primary?.remaining == 60, "额度使用百分比转换剩余百分比")
        let split = UsageAccumulator()
        let bytes = event(total: 200)
        split.append(bytes.prefix(20)); check(split.latest == nil, "半行不提前解析")
        split.append(bytes.dropFirst(20)); check(split.latest?.total == 200, "半行拼接后解析")
        split.append(Data("not json\n".utf8)); check(split.latest?.total == 200, "损坏行不覆盖有效值")
        split.append(Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":null}}\n".utf8))
        check(split.latest?.total == 200, "空 usage 不清空统计")
        split.append(event(total: 80, percent: 99, timestamp: "2026-10-07T00:00:00.000Z"))
        check(split.latest?.total == 200 && split.quota?.primary?.remaining == 60, "旧快照不覆盖新快照")
        check(CodexLink.url(for: "00000000-0000-4000-8000-000000000001")?.absoluteString == "codex://threads/00000000-0000-4000-8000-000000000001", "会话 deep link")
        check(CodexLink.url(for: "../../settings") == nil, "拒绝非法会话 ID")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("usage.jsonl").path
        try event(total: 100).write(to: URL(fileURLWithPath:path))
        let reader = TailReader(path: path)
        try reader.read()
        let firstBytes = reader.bytesRead
        try reader.read()
        check(reader.bytesRead == firstBytes, "文件不变时零读取")
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath:path))
        try handle.seekToEnd(); try handle.write(contentsOf: event(total: 200)); try handle.close()
        try reader.read()
        check(reader.parser.latest?.total == 200, "仅解析新增内容")
        check(reader.bytesRead < firstBytes * 3, "增量不重新读取历史")
        try event(total: 11).write(to: URL(fileURLWithPath:path), options: .atomic)
        try reader.read()
        check(reader.parser.latest?.total == 11, "文件替换后重置 offset 和累计值")
        let huge = dir.appendingPathComponent("huge.jsonl")
        var hugeBytes = Data(repeating: 120, count: 2*1024*1024)
        hugeBytes.append(10); hugeBytes.append(event(total: 500))
        try hugeBytes.write(to: huge)
        let bounded = TailReader(path: huge.path)
        try bounded.read()
        check(bounded.bytesRead <= TailReader.initialLimit, "初始尾读有严格上限")
        check(bounded.parser.latest?.total == 500, "跳过被截断的首行后解析尾部")
        let gap = dir.appendingPathComponent("gap.jsonl")
        var initial = event(total:700)
        initial.append(Data("{\"type\":\"event_msg\",\"timestamp\":\"2026-10-08T08:00:01Z\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"A\"}}\n{\"type\":\"event_msg\"".utf8))
        try initial.write(to: gap)
        let gapReader = TailReader(path:gap.path)
        try gapReader.read()
        let gapHandle = try FileHandle(forWritingTo:gap)
        try gapHandle.seekToEnd()
        var gapBytes = Data(repeating:120,count:2*1024*1024)
        gapBytes.append(10)
        gapBytes.append(event(total:800,timestamp:"2026-10-08T08:00:02Z"))
        try gapHandle.write(contentsOf:gapBytes); try gapHandle.close()
        try gapReader.read()
        check(gapReader.parser.latest?.total == 800, "大增量跳读不把旧半行拼接到新记录")
        check(gapReader.parser.activity == nil, "跳读可能漏掉结束事件时不保留旧活跃状态")
        if failures > 0 { exit(1) }
        print("ALL TESTS PASSED")
    }
}
