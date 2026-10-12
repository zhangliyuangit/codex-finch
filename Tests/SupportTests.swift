import Foundation

@main struct SupportTests {
    static func main() {
        var failures=0
        func check(_ value: Bool,_ title: String) { print("\(value ? "PASS" : "FAIL") \(title)");if !value { failures+=1 } }
        let now=Date()
        var session=SessionRecord(id:"00000000-0000-4000-8000-000000000001",title:"Secret conversation",path:"/private/secret.jsonl",updatedAt:now,model:"",metadataTokens:20,projectName:"Atlas API")
        session.activity=SessionActivity(phase:.running,timestamp:now)
        check(SessionFilter.running.matches(session,now:now),"running filter includes current activity")
        check(!SessionFilter.running.matches(session,now:now.addingTimeInterval(601)),"stale running activity is excluded from running filter")
        session.activity=SessionActivity(phase:.waiting,timestamp:now)
        check(SessionFilter.waiting.matches(session,now:now),"waiting filter includes a blocked conversation")
        check(!SessionFilter.running.matches(session,now:now),"waiting is separate from running")
        check(SessionFilter.all.matches(session,now:now),"all filter includes waiting conversations")
        var snapshot=UsageSnapshot();snapshot.sessions=[session];snapshot.error="/private/secret.jsonl"
        let diagnostic=snapshot.sanitizedDiagnostics
        check(!diagnostic.contains("Secret conversation") && !diagnostic.contains("/private/") && !diagnostic.contains("Atlas API"),"diagnostic excludes titles paths and project names")
        check(diagnostic.contains("sourceError") && diagnostic.contains("sessions"),"diagnostic retains useful state")
        check(ReleaseVersion.newer("v0.10.0",than:"0.9.9"),"release comparison uses numeric components")
        check(!ReleaseVersion.newer("v0.5.0",than:"0.6.0") && !ReleaseVersion.newer("v0.6.0",than:"0.6.0"),"old and same releases do not prompt update")
        check(!ReleaseVersion.newer("v0.7.0-extra",than:"0.6.0") && !ReleaseVersion.newer("v999999999999999999999.0.0",than:"0.6.0"),"malformed and overflowing versions are rejected")
        if failures>0 { exit(1) }; print("ALL SUPPORT TESTS PASSED")
    }
}
