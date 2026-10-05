import Foundation

struct BillingResult {
    let billableSeconds: TimeInterval
    let roundedSeconds: TimeInterval
    let subtotal: Decimal
    let vatAmount: Decimal
    let total: Decimal
    let currencyCode: String
    let vatEnabled: Bool

    var formattedSubtotal: String { Self.format(subtotal, currencyCode: currencyCode) }
    var formattedVAT: String { Self.format(vatAmount, currencyCode: currencyCode) }
    var formattedTotal: String { Self.format(total, currencyCode: currencyCode) }

    private static func format(_ value: Decimal, currencyCode: String) -> String {
        CurrencyFormatter.format(value, currencyCode: currencyCode)
    }
}

enum BillingCalculator {
    static func calculate(
        activeSeconds: TimeInterval,
        usage: [UsageRecord],
        settings: BillingSettings
    ) -> BillingResult {
        let base: TimeInterval
        switch settings.billingBase {
        case .totalDuration:
            base = activeSeconds
        case .declaredItemsOnly:
            base = usage.filter { $0.isDeclared }.reduce(0) { $0 + $1.seconds }
        }

        let roundedSeconds = roundUpSeconds(base, toNearestMinutes: settings.rounding.rawValue)
        let hours = Decimal(roundedSeconds) / 3600
        let subtotal = (hours * settings.hourlyRate).rounded(toPlaces: 2)
        let vat = settings.vatEnabled
            ? (subtotal * settings.vatRatePercent / 100).rounded(toPlaces: 2)
            : Decimal(0)
        let total = subtotal + vat

        return BillingResult(
            billableSeconds: base,
            roundedSeconds: TimeInterval(roundedSeconds),
            subtotal: subtotal,
            vatAmount: vat,
            total: total,
            currencyCode: settings.currencyCode,
            vatEnabled: settings.vatEnabled
        )
    }

    private static func roundUpSeconds(_ seconds: TimeInterval, toNearestMinutes minutes: Int) -> Int {
        let wholeSeconds = max(0, Int(seconds.rounded()))
        guard minutes > 0, wholeSeconds > 0 else { return wholeSeconds }
        let increment = minutes * 60
        return ((wholeSeconds + increment - 1) / increment) * increment
    }
}

private extension Decimal {
    func rounded(toPlaces places: Int) -> Decimal {
        var result = Decimal()
        var mutableSelf = self
        NSDecimalRound(&result, &mutableSelf, places, .plain)
        return result
    }
}
