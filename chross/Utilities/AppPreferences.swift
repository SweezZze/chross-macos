import Foundation

/// Centralized `@AppStorage` key names so the same preference is never typo'd
/// differently across the views that read or write it.
enum AppPreferences {
    static let dailyGoalHoursKey = "dailyGoalHours"
    static let defaultIdleMinutesKey = "defaultIdleMinutes"

    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    static let showMenuBarExtraKey = "showMenuBarExtra"
    static let sidebarOrderKey = "sidebarOrder"
    static let sidebarHiddenKey = "sidebarHidden"

    static let defaultDailyGoalHours: Double = 7
    static let defaultIdleMinutes: Double = 5
    static let idleOptions: [Double] = [0, 2, 5, 10, 15]

    static func idleLabel(_ minutes: Double) -> String {
        minutes == 0 ? "Jamais" : "\(Int(minutes)) min"
    }

    // MARK: - Company info (used on exported invoices)

    static let companyNameKey = "companyName"
    static let companyAddressKey = "companyAddress"
    static let companySiretKey = "companySiret"
    static let companyIBANKey = "companyIBAN"
    static let companyLogoDataKey = "companyLogoData"

    private static let nextInvoiceNumberKey = "nextInvoiceNumber"

    /// Hands out a new invoice number and persists the counter — called once per
    /// session the first time it's exported, then reused on any re-export.
    static func reserveNextInvoiceNumber() -> Int {
        let defaults = UserDefaults.standard
        let next = defaults.integer(forKey: nextInvoiceNumberKey)
        let number = next == 0 ? 1 : next
        defaults.set(number + 1, forKey: nextInvoiceNumberKey)
        return number
    }
}
