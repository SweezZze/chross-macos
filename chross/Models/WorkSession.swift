import Foundation
import SwiftData

@Model
final class WorkSession {
    var projectName: String
    var startDate: Date
    var endDate: Date?
    var activeSeconds: TimeInterval = 0
    var idleSeconds: TimeInterval = 0
    var outOfScopeSeconds: TimeInterval = 0
    var declaredItems: [TrackedItem]
    var usage: [UsageRecord] = []
    var billing: BillingSettings?
    var billedTotal: Decimal?
    var notes: String = ""
    var tags: [String] = []
    var invoiceNumber: Int?
    /// Set once the start/end times or removed periods were corrected by hand.
    var timeAdjusted: Bool = false

    init(projectName: String, startDate: Date, declaredItems: [TrackedItem]) {
        self.projectName = projectName
        self.startDate = startDate
        self.endDate = nil
        self.activeSeconds = 0
        self.idleSeconds = 0
        self.outOfScopeSeconds = 0
        self.declaredItems = declaredItems
        self.usage = []
        self.billing = nil
        self.billedTotal = nil
        self.notes = ""
        self.tags = []
        self.invoiceNumber = nil
    }
}
