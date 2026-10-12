import Foundation

enum SessionFilter: String, CaseIterable, Identifiable {
    case all, running, waiting
    var id: String { rawValue }
    var label: String { self == .all ? "全部" : self == .running ? "处理中" : "待确认" }
    func matches(_ session: SessionRecord, now: Date) -> Bool {
        let phase = session.activity?.effectivePhase(at: now)
        return self == .all || (self == .running && phase == .running) || (self == .waiting && phase == .waiting)
    }
}
