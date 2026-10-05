import SwiftUI

/// A4-proportioned, print-styled invoice layout — deliberately plain black-on-white
/// regardless of the app's dark theme, since this is a document meant to be sent/printed.
struct InvoiceDocumentView: View {
    let session: WorkSession
    let result: BillingResult?
    let invoiceNumber: Int
    let companyName: String
    let companyAddress: String
    let companySiret: String
    let companyIBAN: String
    let logo: NSImage?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header
            Divider().overlay(Color.black.opacity(0.2))
            billedTo
            lineItemsTable
            if let result {
                totals(result)
            }
            Spacer()
            if !companyIBAN.isEmpty {
                paymentInfo
            }
        }
        .padding(48)
        .frame(width: 595, height: 842, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    private var header: some View {
        HStack(alignment: .top) {
            if let logo {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(companyName.isEmpty ? "Mon entreprise" : companyName)
                    .font(.headline)
                if !companyAddress.isEmpty {
                    Text(companyAddress).font(.caption).foregroundStyle(.gray)
                }
                if !companySiret.isEmpty {
                    Text("SIRET : \(companySiret)").font(.caption2).foregroundStyle(.gray)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(result == nil ? "RÉCAPITULATIF" : "FACTURE")
                    .font(.title2.bold())
                Text("N° \(String(format: "%04d", invoiceNumber))")
                    .font(.callout)
                Text(Self.dateFormatter.string(from: session.endDate ?? session.startDate))
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
    }

    private var billedTo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("FACTURÉ À").font(.caption.weight(.semibold)).foregroundStyle(.gray)
            Text(session.projectName.isEmpty ? "Session sans titre" : session.projectName)
                .font(.headline)
        }
    }

    private var lineItemsTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Description").font(.caption.weight(.semibold))
                Spacer()
                Text("Durée").font(.caption.weight(.semibold)).frame(width: 80, alignment: .trailing)
                if result != nil {
                    Text("Taux").font(.caption.weight(.semibold)).frame(width: 70, alignment: .trailing)
                    Text("Montant").font(.caption.weight(.semibold)).frame(width: 80, alignment: .trailing)
                }
            }
            .foregroundStyle(.gray)
            .padding(.bottom, 8)

            Divider().overlay(Color.black.opacity(0.2))

            ForEach(sortedUsage, id: \.id) { record in
                let cleanName = ItemDisplayHelper.cleanDisplayName(key: record.key, kind: record.kind, rawName: record.displayName)
                HStack {
                    Text(cleanName).lineLimit(1)
                    Spacer()
                    Text(DurationFormatter.formatShort(record.seconds))
                        .monospacedDigit()
                        .frame(width: 80, alignment: .trailing)
                    if result != nil {
                        Text("").frame(width: 70, alignment: .trailing)
                        Text("").frame(width: 80, alignment: .trailing)
                    }
                }
                .font(.callout)
                .padding(.vertical, 6)
            }

            Divider().overlay(Color.black.opacity(0.2))

            HStack {
                Text("Total").font(.callout.weight(.semibold))
                Spacer()
                Text(DurationFormatter.format(result?.roundedSeconds ?? session.activeSeconds))
                    .monospacedDigit()
                    .frame(width: 80, alignment: .trailing)
                if let result {
                    Text(hourlyRateLabel).frame(width: 70, alignment: .trailing)
                    Text(result.formattedSubtotal).frame(width: 80, alignment: .trailing)
                }
            }
            .font(.callout.weight(.semibold))
            .padding(.top, 6)
        }
    }

    /// Only tracked apps/sites belong on an invoice — out-of-scope time isn't billed.
    private var sortedUsage: [UsageRecord] {
        session.usage.filter(\.isDeclared).sorted { $0.seconds > $1.seconds }
    }

    private var hourlyRateLabel: String {
        guard let billing = session.billing else { return "" }
        return CurrencyFormatter.format(billing.hourlyRate, currencyCode: billing.currencyCode) + "/h"
    }

    private func totals(_ result: BillingResult) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack {
                Text("Sous-total HT")
                Spacer()
                Text(result.formattedSubtotal)
            }
            if result.vatEnabled {
                HStack {
                    Text("TVA")
                    Spacer()
                    Text(result.formattedVAT)
                }
            }
            Divider().overlay(Color.black.opacity(0.2))
            HStack {
                Text("Total TTC").font(.headline)
                Spacer()
                Text(result.formattedTotal).font(.headline)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var paymentInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("COORDONNÉES DE PAIEMENT").font(.caption.weight(.semibold)).foregroundStyle(.gray)
            Text("IBAN : \(companyIBAN)").font(.caption)
        }
    }
}

#Preview {
    let session = WorkSession(
        projectName: "Refonte site — Client A",
        startDate: Date().addingTimeInterval(-5077),
        declaredItems: []
    )
    session.endDate = Date()
    session.activeSeconds = 5077
    session.usage = [
        UsageRecord(kind: .app, key: "com.apple.dt.Xcode", displayName: "Xcode", seconds: 3600, isDeclared: true),
        UsageRecord(kind: .app, key: "com.google.Chrome", displayName: "Google Chrome", seconds: 1477, isDeclared: true),
    ]
    let billing = BillingSettings(hourlyRate: 50, currencyCode: "EUR", rounding: .fiveMinutes, vatEnabled: true, vatRatePercent: 20, billingBase: .totalDuration)
    session.billing = billing
    let result = BillingCalculator.calculate(activeSeconds: session.activeSeconds, usage: session.usage, settings: billing)

    return InvoiceDocumentView(
        session: session,
        result: result,
        invoiceNumber: 12,
        companyName: "Selim Usenmez — Freelance",
        companyAddress: "12 rue des Lilas, 75011 Paris",
        companySiret: "123 456 789 00012",
        companyIBAN: "FR76 1234 5678 9012 3456 7890 123",
        logo: nil
    )
}
