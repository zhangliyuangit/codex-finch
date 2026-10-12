import Foundation

enum SessionFilter: String, CaseIterable, Identifiable {
    case all, running, waiting
    var id: String { rawValue }
    var label: String { self == .all ? "全部" : self == .running ? "处理中" : "待确认" }
    func matches(_ session: SessionRecord, search: String, now: Date) -> Bool {
        let phase = session.activity?.effectivePhase(at: now)
        let selected = self == .all || (self == .running && phase == .running) || (self == .waiting && phase == .waiting)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return selected && (query.isEmpty || session.title.localizedCaseInsensitiveContains(query) || (session.projectName ?? "").localizedCaseInsensitiveContains(query))
    }
}
