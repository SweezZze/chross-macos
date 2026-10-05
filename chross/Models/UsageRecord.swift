import Foundation

struct UsageRecord: Codable, Hashable, Identifiable {
    var id: String { key }
    let kind: TrackedItem.Kind
    let key: String
    let displayName: String
    var seconds: TimeInterval
    var isDeclared: Bool
}
