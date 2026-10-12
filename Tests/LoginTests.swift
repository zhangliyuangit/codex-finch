import Foundation

@main struct LoginTests {
    static func main() throws {
        var failures = 0
        func check(_ value: Bool, _ name: String) { print("\(value ? "PASS" : "FAIL") \(name)"); if !value { failures += 1 } }
        let executable = "/Applications/Codex Finch.app/Contents/MacOS/CodexFinch"
        let expected: [String: Any] = ["Label":"local.codexusage.menu", "ProgramArguments":[executable], "RunAtLoad":true]
        func data(_ object: [String:Any]) -> Data { try! PropertyListSerialization.data(fromPropertyList:object,format:.xml,options:0) }
        check(LegacyLoginAgent.isOwned(data(expected), executable:executable), "recognizes the existing owned startup agent")
        var other = expected;other["Label"] = "another.app"
        check(!LegacyLoginAgent.isOwned(data(other), executable:executable), "does not remove another app's agent")
        other=expected;other["ProgramArguments"] = [executable,"--dump","/tmp/private.json"]
        check(!LegacyLoginAgent.isOwned(data(other), executable:executable), "rejects unexpected startup arguments")
        other=expected;other["ProgramArguments"] = ["/tmp/CodexFinch"]
        check(!LegacyLoginAgent.isOwned(data(other), executable:executable), "rejects an executable from another install")
        check(!LegacyLoginAgent.isOwned(Data("broken".utf8), executable:executable), "corrupt config remains untouched")
        check(!LoginItemState.approvalRequired.isEnabled, "pending system approval is not shown as enabled")
        check(LoginItemState.legacy.isEnabled && LoginItemState.enabled.isEnabled, "both supported startup mechanisms show their real state")
        if failures > 0 { exit(1) };print("ALL LOGIN TESTS PASSED")
    }
}
