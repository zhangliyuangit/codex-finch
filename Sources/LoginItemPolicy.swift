import Foundation

enum LoginItemState: String {
    case disabled, enabled, approvalRequired, legacy, unavailable
    var isEnabled: Bool { self == .enabled || self == .legacy }
}
enum LegacyLoginAgent {
    static func isOwned(_ data: Data, executable: String) -> Bool {
        guard let value = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String:Any] else { return false }
        return value["Label"] as? String == "local.codexusage.menu"
            && value["ProgramArguments"] as? [String] == [executable]
            && value["RunAtLoad"] as? Bool == true
    }
}
