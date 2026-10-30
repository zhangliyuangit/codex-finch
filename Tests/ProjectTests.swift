import Foundation

@main struct ProjectTests {
    static func main() {
        var failures = 0
        func check(_ result: Bool, _ text: String) {
            print("\(result ? "PASS" : "FAIL") \(text)"); if !result { failures += 1 }
        }
        let catalog = ProjectCatalog(projects: [
            ProjectRecord(id: "main", name: "sample-api", position: 2, roots: [ProjectRoot(path: "/work/sample-api", position: 0)]),
            ProjectRecord(id: "multi", name: "demo-workspace", position: 1, roots: [ProjectRoot(path: "/work/agent", position: 0), ProjectRoot(path: "/work/sample-api", position: 1)]),
            ProjectRecord(id: "nested", name: "nested", position: 3, roots: [ProjectRoot(path: "/work/sample-api/tools", position: 0)]),
            ProjectRecord(id: "same-name", name: "sample-api", position: 4, roots: [ProjectRoot(path: "/other/sample-api", position: 0)])
        ])
        check(catalog.resolve(projectID: "multi", cwd: "/work/sample-api")?.id == "multi", "明确项目 ID 优先于路径")
        check(catalog.resolve(projectID: nil, cwd: "/work/sample-api")?.id == "main", "相同根目录优先主根目录")
        check(catalog.resolve(projectID: nil, cwd: "/work/sample-api/tools/lib")?.id == "nested", "子目录最长路径匹配")
        check(catalog.resolve(projectID: nil, cwd: "/work/sample-api-old") == nil, "目录边界避免同名前缀误归属")
        check(catalog.resolve(projectID: nil, cwd: "/work/agent/src")?.id == "multi", "多根目录项目识别")
        check(catalog.resolve(projectID: nil, cwd: "/work/sample-api/src/../")?.id == "main", "规范化目录路径")
        check(catalog.resolve(projectID: "deleted", cwd: "/work/sample-api")?.id == "main", "失效项目关联回退路径匹配")
        check(catalog.resolve(projectID: nil, cwd: "/Documents/Codex/chat") == nil, "普通聊天不按临时目录伪造项目")
        let repeated = ProjectCatalog(projects: [
            ProjectRecord(id: "late", name: "late", position: 5, roots: [ProjectRoot(path: "/shared", position: 0)]),
            ProjectRecord(id: "early", name: "early", position: 1, roots: [ProjectRoot(path: "/shared", position: 0)])
        ])
        check(repeated.resolve(projectID: nil, cwd: "/shared/src")?.id == "early", "完全相同根目录以侧栏顺序稳定消歧")
        func session(_ id: String, _ project: String?, _ name: String?, _ date: Double) -> SessionRecord {
            SessionRecord(id: id, title: id, path: "", updatedAt: Date(timeIntervalSince1970: date),
                          model: "", metadataTokens: 10, projectID: project, projectName: name)
        }
        let groups = SessionGroup.make(from: [session("a", "main", "sample-api", 100), session("b", nil, nil, 999), session("c", "same-name", "sample-api", 90), session("d", "main", "sample-api", 110)])
        check(groups.count == 3, "同名项目以 ID 分开")
        check(groups.last?.id == SessionGroup.unassignedID && groups.last?.name == "未归属项目", "未归属会话独立置底")
        check(groups.first?.sessions.map(\.id) == ["d", "a"], "组内会话按最近更新时间排列")
        check(groups.first?.id == "main", "项目按最近活跃时间排列")
        check(groups.flatMap(\.sessions).count == 4, "分组不丢失或重复会话")
        let initial = [session("a", "main", "sample-api", 100), session("b", "main", "sample-api", 90),
                       session("c", "web", "sample-web", 80)]
        let order = SessionListOrder(sessions: initial)
        let fresh = [session("b", "web", "renamed", 1000), session("c", "web", "sample-web", 900),
                     session("a", "main", "sample-api", 500), session("d", "main", "sample-api", 1100)]
        let frozen = order.groups(from:fresh)
        check(frozen.map(\.id) == ["main", "web"], "面板打开期间项目顺序不被并行更新改变")
        check(frozen.first?.sessions.map(\.id) == ["a", "b"], "会话更新时间与归属变化不搬动原有行")
        check(frozen.first?.sessions.last?.updatedAt == Date(timeIntervalSince1970:1000), "固定顺序仍展示最新会话字段")
        check(frozen.flatMap(\.sessions).count == 3 && order.pendingCount(in:fresh) == 1, "新会话留到下次打开且明确计数")
        check(SessionListOrder(sessions:fresh).groups(from:fresh).first?.sessions.first?.id == "d", "重新打开时重新计算最新排序")
        check(order.groups(from:Array(fresh.dropFirst())).flatMap(\.sessions).map(\.id) == ["a", "c"], "已删除会话不保留可点击的陈旧行")
        if failures > 0 { exit(1) }
        print("ALL PROJECT TESTS PASSED")
    }
}
