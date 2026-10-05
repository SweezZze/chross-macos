import Foundation

struct BillingSettings: Codable, Hashable {
    enum RoundingIncrement: Int, Codable, CaseIterable, Identifiable {
        case none = 0
        case oneMinute = 1
        case fiveMinutes = 5
        case fifteenMinutes = 15

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .none: return "Aucun"
            case .oneMinute: return "1 min"
            case .fiveMinutes: return "5 min"
            case .fifteenMinutes: return "15 min"
            }
        }
    }

    enum BillingBase: String, Codable, CaseIterable, Identifiable {
        case totalDuration
        case declaredItemsOnly

        var id: String { rawValue }

        var label: String {
            switch self {
            case .totalDuration: return "Temps total"
            case .declaredItemsOnly: return "Déclarés uniquement"
            }
        }
    }

    var hourlyRate: Decimal
    var currencyCode: String
    var rounding: RoundingIncrement
    var vatEnabled: Bool
    var vatRatePercent: Decimal
    var billingBase: BillingBase

    static let defaultSettings = BillingSettings(
        hourlyRate: 0,
        currencyCode: Locale.current.currency?.identifier ?? "EUR",
        rounding: .fifteenMinutes,
        vatEnabled: false,
        vatRatePercent: 20,
        billingBase: .totalDuration
    )
}
