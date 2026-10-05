import SwiftUI

struct BillingPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings: BillingSettings
    @State private var applyBilling: Bool

    let summary: (title: String, timeRange: String, activeSeconds: TimeInterval, usage: [UsageRecord])?
    let onConfirm: (_ settings: BillingSettings?) -> Void

    init(
        summary: (title: String, timeRange: String, activeSeconds: TimeInterval, usage: [UsageRecord])?,
        initialSettings: BillingSettings,
        applyByDefault: Bool,
        onConfirm: @escaping (_ settings: BillingSettings?) -> Void
    ) {
        self.summary = summary
        _settings = State(initialValue: initialSettings)
        _applyBilling = State(initialValue: applyByDefault)
        self.onConfirm = onConfirm
    }

    private var result: BillingResult {
        BillingCalculator.calculate(
            activeSeconds: summary?.activeSeconds ?? 0,
            usage: summary?.usage ?? [],
            settings: settings
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                Text("SESSION TERMINÉE")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.accentDim, in: Capsule())

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary?.title ?? "Session")
                        .font(.title.bold())
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let timeRange = summary?.timeRange {
                        Text(timeRange)
                            .font(.callout)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                Text(DurationFormatter.format(summary?.activeSeconds ?? 0))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize()
            }

            ThemedToggle("Facturer cette session", subtitle: "Appliquer un taux horaire", isOn: $applyBilling)

            if applyBilling {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("TAUX HORAIRE").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                                HStack {
                                    TextField("ex: 50", value: $settings.hourlyRate, format: .number)
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("€ / h").font(.callout).foregroundStyle(Theme.textTertiary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.accent, lineWidth: 1.5))
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text("DEVISE").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                                Picker("", selection: $settings.currencyCode) {
                                    ForEach(["EUR", "USD", "GBP", "CHF", "CAD"], id: \.self) { code in
                                        Text(code).tag(code)
                                    }
                                }
                                .labelsHidden()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border))
                            }
                            .frame(width: 140)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("ARRONDI").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                            PillSegmentedControl(
                                options: BillingSettings.RoundingIncrement.allCases,
                                label: \.label,
                                selection: $settings.rounding
                            )
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("BASE DE CALCUL").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                            PillSegmentedControl(
                                options: BillingSettings.BillingBase.allCases,
                                label: \.label,
                                selection: $settings.billingBase
                            )
                        }

                        HStack {
                            ThemedToggle("TVA", isOn: $settings.vatEnabled)
                            if settings.vatEnabled {
                                HStack(spacing: 2) {
                                    TextField("%", value: $settings.vatRatePercent, format: .number)
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(Theme.textPrimary)
                                        .frame(width: 30)
                                    Text("%").foregroundStyle(Theme.textTertiary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border))
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            summaryRow("Durée facturée", DurationFormatter.format(result.roundedSeconds))
                            summaryRow("Sous-total HT", result.formattedSubtotal)
                            if result.vatEnabled {
                                summaryRow("TVA \(settings.vatRatePercent.formatted()) %", result.formattedVAT)
                            }
                            Divider().background(Theme.border)
                            HStack {
                                Text("Total TTC").font(.headline).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(result.formattedTotal)
                                    .font(.title2.bold())
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border))
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Button("Ne pas facturer") {
                    onConfirm(nil)
                    dismiss()
                }
                .buttonStyle(.chross)
                .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    onConfirm(applyBilling ? settings : nil)
                    dismiss()
                } label: {
                    Text("Enregistrer la session")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.chross)
                .background(Theme.accent, in: Capsule())
            }
        }
        .padding(28)
        .frame(width: 600, height: applyBilling ? 760 : 360)
        .animation(.easeInOut(duration: 0.2), value: applyBilling)
        .background(Theme.page)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Theme.textPrimary).monospacedDigit()
        }
        .font(.callout)
    }
}

#Preview {
    BillingPromptView(
        summary: ("Refonte site — Client A", "15:30 → 16:54", 5077, []),
        initialSettings: BillingSettings(hourlyRate: 50, currencyCode: "EUR", rounding: .fiveMinutes, vatEnabled: true, vatRatePercent: 20, billingBase: .totalDuration),
        applyByDefault: true
    ) { _ in }
}
