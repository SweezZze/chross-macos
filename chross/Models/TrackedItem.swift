import Foundation

struct TrackedItem: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case app
        case website
    }

    var id: String { key }
    let kind: Kind
    let key: String
    let displayName: String
}
