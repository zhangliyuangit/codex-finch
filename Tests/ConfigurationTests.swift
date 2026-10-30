import Foundation

@main struct ConfigurationTests {
    static func main() throws {
        var failures = 0
        func check(_ value: Bool, _ text: String) {
            print("\(value ? "PASS" : "FAIL") \(text)"); if !value { failures += 1 }
        }
        let origin = Date(timeIntervalSince1970:1791446400)
        func record(_ type: String, at seconds: Double, payload: [String:Any]) -> Data {
            let object:[String:Any] = ["type":type,"timestamp":UsageDate.fractional.string(from:origin.addingTimeInterval(seconds)),"payload":payload]
            var bytes = try! JSONSerialization.data(withJSONObject:object); bytes.append(10);return bytes
        }
        func settings(_ tier: Any = "priority", effort: Any = "high", model: String = "test", at: Double = 1, owner: String = "session") -> Data {
            record("event_msg",at:at,payload:["type":"thread_settings_applied","thread_id":owner,
                "thread_settings":["model":model,"reasoning_effort":effort,"service_tier":tier]])
        }
        func context(_ fields: [String:Any], at seconds: Double = 2) -> Data { record("turn_context",at:seconds,payload:fields) }
        let parser = UsageAccumulator(sessionID:"session")
        parser.append(settings())
        check(parser.configuration?.modeLabel == "Fast" && parser.configuration?.effortLabel == "高","同会话 priority/high 显示明确 Fast 和高思考")
        parser.append(settings("default",at:0))
        check(parser.configuration?.isFast == true,"旧时间配置不能覆盖新记录")
        parser.append(settings("default",at:3,owner:"another"))
        check(parser.configuration?.isFast == true,"另一会话的设置不能污染当前会话")
        parser.append(context(["model":"test","effort":"high"]))
        check(parser.configuration?.isFast == true,"相同配置的后续轮上下文保留已记录模式")
        check(parser.configuration?.tierTimestamp == origin.addingTimeInterval(1),"后续上下文不会伪造模式观察时间")
        parser.append(context(["model":"test","effort":"medium"],at:4))
        check(parser.configuration?.effortLabel == "中" && parser.configuration?.serviceTier == nil,"思考变化而缺少模式时不继承旧 Fast")
        parser.append(settings("default",effort:"medium",at:5))
        check(parser.configuration?.modeLabel == "标准","明确 default 显示标准")
        parser.append(settings("fast",at:6))
        check(parser.configuration?.isFast == true,"fast 别名显示 Fast")
        parser.append(context(["model":"other","effort":"high"],at:7))
        check(parser.configuration?.serviceTier == nil,"切换模型使继承的模式失效")
        parser.append(settings(NSNull(),effort:NSNull(),at:8))
        check(parser.configuration?.modeLabel == "模式未知" && parser.configuration?.effortLabel == "未知","显式 null 不代表标准或默认思考")
        parser.append(settings(at:9))
        parser.append(record("event_msg",at:10,payload:["type":"thread_settings_applied","thread_id":"session","thread_settings":["model":"test"]]))
        check(parser.configuration?.serviceTier == nil && parser.configuration?.effort == nil,"完整设置快照缺字段会清除旧值")
        parser.append(settings(at:11));parser.skipUnreadGap()
        check(parser.configuration == nil,"日志跳读清除可能过期的配置证据")
        parser.append(context(["model":"test","effort":"high"],at:12))
        check(parser.configuration?.modeLabel == "模式未知","只有思考和模型不能推断 Fast")
        for tier in ["flex","ultrafast","auto","future"] {
            let p = UsageAccumulator(sessionID:"session");p.append(settings(tier))
            check(p.configuration?.isFast == false && p.configuration?.modeLabel != "标准","非标准 tier 保留自身含义：\(tier)")
        }
        let future = UsageAccumulator(sessionID:"session");future.append(settings("future-tier"))
        check(future.configuration?.modeLabel == "future-tier", "未知但明确记录的服务等级保留原始名称")
        let partial = UsageAccumulator(sessionID:"session");let bytes = settings()
        partial.append(bytes.prefix(30));check(partial.configuration == nil,"半行设置不提前应用")
        partial.append(bytes.dropFirst(30));check(partial.configuration?.isFast == true,"半行拼接后解析设置")
        partial.append(context(["model":"test","effort":NSNull()],at:3))
        check(partial.configuration?.effort == nil,"显式清除思考程度不会沿用旧值")
        check(partial.configuration?.serviceTier == nil,"思考重置为未知时不保留先前 Fast 证据")
        let foreign = UsageAccumulator(sessionID:"session")
        foreign.append(context(["model":"foreign","thread_id":"other","effort":"high"]))
        check(foreign.configuration == nil,"带有异会话归属的 turn_context 被忽略")
        let cfg = SessionConfiguration(model:"test",effort:"high",serviceTier:"priority",timestamp:origin,tierTimestamp:origin)
        check(cfg.resolving(metadataModel:"test",metadataEffort:"high").isFast,"一致的本地元数据保留模式证据")
        check(!cfg.resolving(metadataModel:"new-model",metadataEffort:"high").isFast,"当前元数据模型不同不能挂上旧 Fast")
        check(cfg.resolving(metadataModel:"test",metadataEffort:"low").serviceTier == nil,"当前元数据思考不同不挂旧模式")
        check(SessionConfiguration().resolving(metadataModel:"test",metadataEffort:"xhigh").effortLabel == "超高","旧日志仍可使用明确的元数据思考程度")
        check(SessionConfiguration().resolving(metadataModel:"test",metadataEffort:"high").modeLabel == "模式未知","元数据回退不能制造模式默认值")
        let invalid = UsageAccumulator(sessionID:"session");invalid.append(settings(true,effort:42))
        check(invalid.configuration?.serviceTier == nil && invalid.configuration?.effort == nil,"拒绝布尔模式与数字思考程度")
        check(SessionConfiguration.value("injected\nvalue") == nil,"配置字段不允许控制字符")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let file = folder.appendingPathComponent("session.jsonl")
        try settings().write(to:file)
        let reader = TailReader(path:file.path,sessionID:"session");try reader.read()
        check(reader.parser.configuration?.isFast == true,"TailReader 将预期会话ID传给配置解析器")
        try context(["model":"test","effort":"medium"],at:3).write(to:file,options:.atomic)
        try reader.read()
        check(reader.parser.configuration?.modeLabel == "模式未知","文件替换重置旧配置")
        var large = settings();large.append(Data(repeating:120,count:600*1024));large.append(10)
        large.append(context(["model":"test","effort":"high"],at:3));try large.write(to:file,options:.atomic)
        try reader.read()
        check(reader.parser.configuration?.serviceTier == nil && reader.bytesRead < 600*1024,"有界尾读不拿被跳过的文件头冒充最近模式")
        let modern = UsageAccumulator(sessionID:"session")
        modern.append(record("turn_context",at:1,payload:["model":"test","collaboration_mode":["settings":["reasoning_effort":"max"]]]))
        check(modern.configuration?.effort == "max","识别上下文嵌套思考程度")
        if failures > 0 { exit(1) }
        print("ALL CONFIGURATION TESTS PASSED")
    }
}
