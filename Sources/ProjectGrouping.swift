import Foundation

struct ProjectRoot {
    let path: String
    let position: Int
}

struct ProjectRecord {
    let id: String
    let name: String
    let position: Int
    var roots: [ProjectRoot]
}

struct ProjectCatalog {
    let projects: [ProjectRecord]

    func resolve(projectID: String?, cwd: String) -> ProjectRecord? {
        if let projectID, let explicit = projects.first(where: { $0.id == projectID }) { return explicit }
        guard cwd.hasPrefix("/") else { return nil }
        let directory = normalize(cwd)
        var candidates: [(project: ProjectRecord, length: Int, rootPosition: Int)] = []
        for project in projects {
            for entry in project.roots where entry.path.hasPrefix("/") {
                let root = normalize(entry.path)
                if directory == root || directory.hasPrefix(root == "/" ? "/" : root + "/") {
                    candidates.append((project, root.count, entry.position))
                }
            }
        }
        return candidates.sorted {
            if $0.length != $1.length { return $0.length > $1.length }
            if $0.rootPosition != $1.rootPosition { return $0.rootPosition < $1.rootPosition }
            if $0.project.position != $1.project.position { return $0.project.position < $1.project.position }
            return $0.project.id < $1.project.id
        }.first?.project
    }

    private func normalize(_ path: String) -> String {
        var normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        while normalized.count > 1 && normalized.hasSuffix("/") { normalized.removeLast() }
        return normalized
    }
}

struct SessionGroup: Identifiable {
    static let unassignedID = "__unassigned__"
    let id: String
    let name: String
    let sessions: [SessionRecord]
    var isUnassigned: Bool { id == Self.unassignedID }
    var latest: Date { sessions.first?.updatedAt ?? .distantPast }

    static func make(from sessions: [SessionRecord]) -> [SessionGroup] {
        Dictionary(grouping: sessions, by: { $0.projectID ?? unassignedID }).map { id, values in
            let ordered = values.sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id < $1.id
            }
            return SessionGroup(id: id, name: id == unassignedID ? "未归属项目" : (ordered.first?.projectName ?? "未命名项目"), sessions: ordered)
        }.sorted {
            if $0.isUnassigned != $1.isUnassigned { return !$0.isUnassigned }
            if $0.latest != $1.latest { return $0.latest > $1.latest }
            return $0.id < $1.id
        }
    }
}
