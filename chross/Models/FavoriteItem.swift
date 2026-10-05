import Foundation
import SwiftData

@Model
final class FavoriteItem {
    var kind: TrackedItem.Kind
    var key: String
    var displayName: String
    var createdDate: Date

    init(kind: TrackedItem.Kind, key: String, displayName: String) {
        self.kind = kind
        self.key = key
        self.displayName = displayName
        self.createdDate = Date()
    }
}
