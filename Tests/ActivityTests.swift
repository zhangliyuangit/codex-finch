import Foundation

@main struct ActivityTests {
    static func main() {
        var failures = 0
        func check(_ result: Bool, _ description: String) {
            print("\(result ? "PASS" : "FAIL") \(description)"); if !result { failures += 1 }
        }
        let now = Date(timeIntervalSince1970: 1791449100)
        func stamp(_ delta: Double) -> String { UsageDate.fractional.string(from: now.addingTimeInterval(delta)) }
        func event(_ type: String, turn: String = "A", at: Double = 0, extra: [String: Any] = [:]) -> Data {
            var payload: [String: Any] = ["type": type, "turn_id": turn]
            payload.merge(extra) { _, new in new }
            var bytes = try! JSONSerialization.data(withJSONObject: ["type":"event_msg", "timestamp":stamp(at), "payload":payload])
            bytes.append(10); return bytes
        }
        let p = UsageAccumulator()
        p.append(event("task_started"))
        check(p.activity?.phase == .running, "任务开始标记处理中")
        p.append(event("task_complete", at: 1))
        check(p.activity?.phase == .completed, "任务结束标记已结束")
        check(p.drainActivityEvents().filter { $0.phase == .completed }.count == 1, "产生明确结束事件")
        check(p.drainActivityEvents().isEmpty, "已消费事件不重复推送")
        p.append(event("item_completed", at: 2, extra: ["item": ["type":"AgentMessage"]]))
        check(p.activity?.phase == .completed, "迟到进度不能重开已结束轮次")
        p.append(event("task_started", turn: "B", at: 3))
        p.append(event("task_complete", turn: "A", at: 4))
        check(p.activity?.phase == .running && p.activity?.turnID == "B", "上一轮结束不覆盖新一轮")
        p.append(event("turn_aborted", turn: "B", at: 5))
        check(p.activity?.phase == .interrupted, "中断不误标完成")
        let waiting = UsageAccumulator()
        waiting.append(event("task_started"))
        waiting.append(event("request_user_input", at: 1, extra: ["id":"question-1"]))
        check(waiting.activity?.phase == .waiting, "明确阻塞输入请求标记等待")
        waiting.append(event("user_input_response", at: 2, extra: ["id":"other-question"]))
        check(waiting.activity?.phase == .waiting, "无关输入回复不解除等待")
        waiting.append(event("user_input_response", at: 3, extra: ["id":"question-1"]))
        check(waiting.activity?.phase == .running, "匹配输入回复恢复处理中")
        let async = UsageAccumulator()
        async.append(event("task_started"))
        var asyncLine = try! JSONSerialization.data(withJSONObject: ["type":"response_item","timestamp":stamp(1),"payload":["type":"function_call","name":"request_user_input_async","call_id":"optional"]])
        asyncLine.append(10); async.append(asyncLine)
        check(async.activity?.phase == .running, "非阻塞问题不误标等待")
        check(async.activity?.effectivePhase(at: now.addingTimeInterval(601)) == .unknown, "长时间无进展标记状态待更新")
        let partial = UsageAccumulator()
        partial.append(event("item_completed", extra: ["item":["type":"CommandExecution","stdout":String(repeating:"x",count:100_000)]]))
        check(partial.activity?.phase == .running, "尾部缺少开始事件时使用轮次进度证据")
        let newer = UsageAccumulator()
        newer.append(event("task_complete"))
        newer.append(event("item_completed", turn:"B", at:1, extra:["item":["type":"Reasoning"]]))
        check(newer.activity?.phase == .running && newer.activity?.turnID == "B", "错过新轮开始后可由新轮进度恢复状态")
        let legacy = UsageAccumulator()
        legacy.append(event("task_complete"))
        legacy.append(Data("{\"timestamp\":\"\(stamp(1))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}\n".utf8))
        check(legacy.activity?.phase == .running && legacy.activity?.turnID == nil, "无轮次 ID 的开始不沿用已结束轮次")
        let queued = UsageAccumulator()
        queued.append(event("item_completed", extra:["item":["type":"UserMessage","content":"新输入"]]))
        check(queued.activity == nil, "用户消息入队不等同于模型处理中")
        let reordered = UsageAccumulator()
        reordered.append(Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"item_completed\",\"item\":{\"type\":\"Reasoning\"},\"turn_id\":\"A\"},\"timestamp\":\"\(stamp(0))\"}\n".utf8))
        check(reordered.activity?.phase == .running, "短事件字段顺序改变仍可读取进度")
        let policy = NoticePolicy()
        let settings = NotificationPreferences(enabled: true)
        func snapshot(_ phase: ActivityPhase, turn: String = "A", at: Double = 0, quota: Double? = nil, reset: Double = 1791969059) -> UsageSnapshot {
            let activity = SessionActivity(phase: phase, turnID: turn, timestamp: now.addingTimeInterval(at), requestID: nil)
            let session = SessionRecord(id:"00000000-0000-4000-8000-000000000001",title:"会话",path:"",updatedAt:now,model:"",metadataTokens:0,activity:activity)
            var x = UsageSnapshot(sessions:[session])
            x.activityEvents = [SessionSignal(sessionID:session.id,title:session.title,projectName:nil,activity:activity)]
            if let quota { x.quota = QuotaSnapshot(primary:QuotaWindow(used:100-quota,minutes:10080,resetsAt:Date(timeIntervalSince1970:reset)),secondary:nil,timestamp:now.addingTimeInterval(at)) }
            return x
        }
        check(policy.evaluate(snapshot(.completed), preferences:settings, now:now).isEmpty, "冷启动不补推历史通知")
        let finished = policy.evaluate(snapshot(.completed, turn:"B", at:1), preferences:settings, now:now.addingTimeInterval(1))
        check(finished.count == 1 && finished.first?.kind == .completed, "新轮次完成产生通知")
        check(policy.evaluate(snapshot(.completed, turn:"B", at:1), preferences:settings, now:now.addingTimeInterval(2)).isEmpty, "同一轮完成只提醒一次")
        check(policy.evaluate(snapshot(.waiting, turn:"C", at:3), preferences:settings, now:now.addingTimeInterval(3)).first?.kind == .attention, "明确待输入可提醒")
        var answered = snapshot(.waiting,turn:"resolved",at:3.5)
        answered.sessions[0].activity?.phase = .running
        check(policy.evaluate(answered,preferences:settings,now:now.addingTimeInterval(3.5)).isEmpty, "同批次已经解除等待时不再发送过时确认通知")
        var disabled = settings; disabled.enabled = false
        check(policy.evaluate(snapshot(.completed, turn:"D", at:4), preferences:disabled, now:now.addingTimeInterval(4)).isEmpty, "关闭通知不发送")
        check(policy.evaluate(snapshot(.completed, turn:"D", at:4), preferences:settings, now:now.addingTimeInterval(5)).isEmpty, "重新开启不补推已忽略通知")
        let q = NoticePolicy()
        _ = q.evaluate(snapshot(.running, quota:25), preferences:settings, now:now)
        check(q.evaluate(snapshot(.running, at:1, quota:19), preferences:settings, now:now.addingTimeInterval(1)).first?.kind == .quota, "额度低于阈值提醒")
        check(q.evaluate(snapshot(.running, at:2, quota:18), preferences:settings, now:now.addingTimeInterval(2)).isEmpty, "同一额度周期不重复提醒")
        check(q.evaluate(snapshot(.running, at:3, quota:15, reset:1792573859), preferences:settings, now:now.addingTimeInterval(3)).first?.kind == .quota, "新额度周期可再次提醒")
        let stale = NoticePolicy(); _ = stale.evaluate(snapshot(.running), preferences:settings, now:now)
        check(stale.evaluate(snapshot(.completed, turn:"old", at:-1800, quota:1), preferences:settings, now:now).isEmpty, "过期状态和额度不推送")
        let restart = NoticePolicy(seenKeys: policy.seenKeys)
        _ = restart.evaluate(snapshot(.running), preferences:settings, now:now)
        check(restart.evaluate(snapshot(.completed, turn:"B", at:1), preferences:settings, now:now.addingTimeInterval(1)).isEmpty, "重启后仍然去重")
        if failures > 0 { exit(1) }
        print("ALL ACTIVITY AND NOTICE TESTS PASSED")
    }
}
