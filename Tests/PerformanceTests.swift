import Foundation

@main struct PerformanceTests {
    static func main() {
        var failures = 0
        func check(_ result: Bool, _ message: String) {
            print("\(result ? "PASS" : "FAIL") \(message)"); if !result { failures += 1 }
        }
        let base = Date(timeIntervalSince1970: 1791446400)
        func event(_ parser: UsageAccumulator, _ kind: String, _ turn: String = "A", at seconds: Double,
                   fields: [String:Any] = [:], root: String? = nil) {
            var payload = fields
            payload["turn_id"] = turn; payload["root_turn_id"] = root ?? turn
            if kind != "token_usage_record" { payload["type"] = kind }
            let record: [String:Any] = ["type":kind == "token_usage_record" ? kind : "event_msg",
                "timestamp":UsageDate.fractional.string(from:base.addingTimeInterval(seconds)), "payload":payload]
            var bytes = try! JSONSerialization.data(withJSONObject:record); bytes.append(10); parser.append(bytes)
        }
        func usage(_ parser: UsageAccumulator, _ turn: String = "A", output: Any, at: Double,
                   root: String? = nil) {
            event(parser,"token_usage_record",turn,at:at,fields:["response_id":"duplicate-is-safe",
                "usage":["output_tokens":9999],"thread_token_usage":["output_tokens":999999],
                "turn_token_usage":["output_tokens":output,"reasoning_output_tokens":100]],root:root)
        }
        func complete(_ parser: UsageAccumulator, _ turn: String = "A", at: Double,
                      duration: Any = 26000, first: Any = 1800, root: String? = nil) {
            event(parser,"task_complete",turn,at:at,fields:["duration_ms":duration,
                "time_to_first_token_ms":first],root:root)
        }
        let parser = UsageAccumulator()
        event(parser,"task_started",at:0)
        usage(parser,output:200,at:1); usage(parser,output:420,at:2); usage(parser,output:420,at:2)
        complete(parser,at:26)
        check(parser.performance?.outputTokens == 420,"单轮累计快照替换，不加总响应、线程或推理 token")
        check(abs((parser.performance?.averageTokensPerSecond ?? 0)-420.0/26) < 0.001,"均速按本轮输出除以整轮耗时")
        check(parser.performance?.firstTokenMilliseconds == 1800,"保留日志首 token 延迟")
        event(parser,"task_started","B",at:30); usage(parser,"B",output:9000,at:31)
        check(parser.performance?.turnID == "A" && parser.performance?.outputTokens == 420,"下一轮开始保留上轮指标")
        complete(parser,"child",at:32,root:"B")
        check(parser.performance?.turnID == "A","子轮完成不覆盖主会话上轮")
        usage(parser,"B",output:99999,at:33,root:"other")
        complete(parser,"B",at:40)
        check(parser.performance?.outputTokens == 9000,"交错轮次按ID匹配，忽略异根记录")
        usage(parser,output:500,at:3)
        check(parser.performance?.turnID == "B","迟到旧轮 usage 不替换最新完成轮")

        let late = UsageAccumulator()
        complete(late,at:26)
        check(late.performance?.averageTokensPerSecond == nil,"只有结束耗时不能猜测输出")
        usage(late,output:420,at:25)
        check(late.performance?.outputTokens == 420,"乱序到达的同轮 usage 可补齐指标")
        usage(late,output:9000,at:27)
        check(late.performance?.outputTokens == 420,"完成时间之后的快照不计入已完成轮")
        event(late,"turn_completed",at:26)
        check(late.performance?.durationMilliseconds == 26000,"无字段的重复结束事件不擦除已有耗时")
        event(late,"task_started","new",at:30)
        complete(late,"new",at:50,duration:NSNull(),first:NSNull())
        check(late.performance?.turnID == "new" && late.performance?.durationLabel == "—",
              "最新完成轮缺字段显示破折号，不沿用旧轮数值")

        let gap = UsageAccumulator()
        usage(gap,output:420,at:1); gap.skipUnreadGap(); complete(gap,at:26)
        check(gap.performance?.outputTokens == nil,"跳读不能把旧的不完整 usage 接到结束事件")
        let retained = gap.performance
        gap.skipUnreadGap()
        check(gap.performance == retained,"跳读保留已完成结果")
        usage(gap,"B",output:800,at:30); complete(gap,"B",at:40)
        check(gap.performance?.outputTokens == 800,"跳读后的单轮累计快照独立可用")

        for bad in [-1, true, "26000", NSNull()] as [Any] {
            let invalid = UsageAccumulator(); usage(invalid,output:420,at:1)
            complete(invalid,at:26,duration:bad,first:bad)
            check(invalid.performance?.durationMilliseconds == nil && invalid.performance?.firstTokenMilliseconds == nil,
                  "拒绝负数、布尔、字符串及空耗时：\(bad)")
        }
        let zero = UsageAccumulator(); usage(zero,output:0,at:1); complete(zero,at:2,duration:0,first:0)
        check(zero.performance?.averageTokensPerSecond == nil && zero.performance?.firstTokenLabel == "0.0 s",
              "零耗时不可除，明确记录的零首 token 可展示")
        complete(zero,"B",at:30,duration:1000,first:2000)
        check(zero.performance?.firstTokenMilliseconds == nil,"首 token 不能大于整轮耗时")
        let missing = UsageAccumulator()
        event(missing,"token_usage_record",at:1,fields:["usage":["output_tokens":9999]])
        complete(missing,at:26)
        check(missing.performance?.outputTokens == nil,"缺少单轮快照不退回响应或线程累计")
        let stale = UsageAccumulator()
        event(stale,"task_started",at:10); usage(stale,output:420,at:1); complete(stale,at:26)
        check(stale.performance?.outputTokens == nil,"开始时间之前的快照不计入该轮")
        let lateStart = UsageAccumulator()
        usage(lateStart,output:420,at:1); complete(lateStart,at:26)
        event(lateStart,"task_started",at:10)
        check(lateStart.performance?.outputTokens == nil,"乱序开始事件使轮次范围不合法时撤销均速")
        for bad in [-1, true, "420", 420.5, NSNull()] as [Any] {
            let invalid = UsageAccumulator(); usage(invalid,output:bad,at:1); complete(invalid,at:26)
            check(invalid.performance?.outputTokens == nil,"拒绝无效单轮输出：\(bad)")
        }
        let bounded = UsageAccumulator()
        for i in 0..<100 { complete(bounded,"T\(i)",at:Double(i+1)) }
        check(bounded.performance?.turnID == "T99","大量轮次有界处理并保留最新完成记录")
        if failures > 0 { exit(1) }
        print("ALL PERFORMANCE TESTS PASSED")
    }
}
