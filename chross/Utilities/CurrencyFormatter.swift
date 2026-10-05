import Foundation

enum CurrencyFormatter {
    /// Pinned to fr_FR regardless of the system locale, since the whole UI is in French
    /// and a mismatched locale would format amounts as "€50" instead of "50 €".
    static func format(_ value: Decimal, currencyCode: String) -> String {
        value.formatted(.currency(code: currencyCode).locale(Locale(identifier: "fr_FR")))
    }
}
