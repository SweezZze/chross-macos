import Foundation
import SwiftData

/// A saved project configuration — apps, sites, idle threshold, and billing — that
/// can be launched with a single tap instead of filling out the setup form each time.
@Model
final class Preset {
    var name: String
    var projectName: String
    var declaredItems: [TrackedItem]
    var idleThresholdMinutes: Double
    var applyBilling: Bool
    var billing: BillingSettings
    var createdDate: Date

    init(
        name: String,
        projectName: String,
        declaredItems: [TrackedItem],
        idleThresholdMinutes: Double,
        applyBilling: Bool,
        billing: BillingSettings
    ) {
        self.name = name
        self.projectName = projectName
        self.declaredItems = declaredItems
        self.idleThresholdMinutes = idleThresholdMinutes
        self.applyBilling = applyBilling
        self.billing = billing
        self.createdDate = Date()
    }
}
