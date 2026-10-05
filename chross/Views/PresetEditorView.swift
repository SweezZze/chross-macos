import SwiftData
import SwiftUI

/// Creates a reusable project preset: apps, sites, idle threshold, and billing bundled
/// together so starting a recurring project is a single tap from `PresetsView`.
struct PresetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let existingPreset: Preset?

    @State private var presetName: String
    @State private var projectName: String
    @State private var declaredItems: [TrackedItem]
    @State private var idleMinutes: Double
    @State private var applyBilling: Bool
    @State private var billing: BillingSettings

    init(existingPreset: Preset? = nil) {
        self.existingPreset = existingPreset
        _presetName = State(initialValue: existingPreset?.name ?? "")
        _projectName = State(initialValue: existingPreset?.projectName ?? "")
        _declaredItems = State(initialValue: existingPreset?.declaredItems ?? [])
        _idleMinutes = State(initialValue: existingPreset?.idleThresholdMinutes ?? AppPreferences.defaultIdleMinutes)
        _applyBilling = State(initialValue: existingPreset?.applyBilling ?? false)
        _billing = State(initialValue: existingPreset?.billing ?? .defaultSettings)
    }

    private var hasWebsites: Bool {
        declaredItems.contains { $0.kind == .website }
    }

    private var canSave: Bool {
        !presetName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                Text(existingPreset == nil ? "Nouveau preset" : "Modifier le preset")
                    .font(.title.bold())
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.chross)
            }

            labeledField("NOM DU PRESET", text: $presetName, placeholder: "ex: Client Dupont")
            labeledField("PROJET / CLIENT", text: $projectName, placeholder: "Nom du projet / client")

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TrackedItemsPicker(items: $declaredItems)

                    if hasWebsites && !AccessibilityPermission.isGranted {
                        AccessibilityPermissionNotice()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("PAUSE AUTO SI INACTIF")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        PillSegmentedControl(options: AppPreferences.idleOptions, label: AppPreferences.idleLabel, selection: $idleMinutes)
                    }

                    billingSection
                }
            }

            HStack {
                Button("Annuler") { dismiss() }
                    .buttonStyle(.chross)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(action: save) {
                    Text(existingPreset == nil ? "Enregistrer le preset" : "Enregistrer les modifications")
                        .font(.headline)
                        .foregroundStyle(canSave ? .black : Theme.textTertiary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.chross)
                .background(canSave ? Theme.accent : Theme.surfaceRaised, in: Capsule())
                .disabled(!canSave)
            }
        }
        .padding(28)
        .frame(width: 480, height: 700)
        .background(Theme.page)
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .strokeBorder(Theme.border)
                )
        }
    }

    private var billingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ThemedToggle("Appliquer un taux horaire", isOn: $applyBilling)

            if applyBilling {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TAUX HORAIRE").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        HStack {
                            TextField("ex: 50", value: $billing.hourlyRate, format: .number)
                                .textFieldStyle(.plain)
                                .foregroundStyle(Theme.textPrimary)
                            Text("€ / h").font(.callout).foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DEVISE").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        Picker("", selection: $billing.currencyCode) {
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
                    .frame(width: 120)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("ARRONDI").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    PillSegmentedControl(
                        options: BillingSettings.RoundingIncrement.allCases,
                        label: \.label,
                        selection: $billing.rounding
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("BASE DE CALCUL").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    PillSegmentedControl(
                        options: BillingSettings.BillingBase.allCases,
                        label: \.label,
                        selection: $billing.billingBase
                    )
                }

                HStack {
                    ThemedToggle("TVA", isOn: $billing.vatEnabled)
                    if billing.vatEnabled {
                        HStack(spacing: 4) {
                            TextField("%", value: $billing.vatRatePercent, format: .number)
                                .textFieldStyle(.plain)
                                .foregroundStyle(Theme.textPrimary)
                                .frame(width: 36)
                            Text("%").foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border))
                    }
                }
            }
        }
    }

    private func save() {
        if let existingPreset {
            existingPreset.name = presetName.trimmingCharacters(in: .whitespaces)
            existingPreset.projectName = projectName.trimmingCharacters(in: .whitespaces)
            existingPreset.declaredItems = declaredItems
            existingPreset.idleThresholdMinutes = idleMinutes
            existingPreset.applyBilling = applyBilling
            existingPreset.billing = billing
        } else {
            let preset = Preset(
                name: presetName.trimmingCharacters(in: .whitespaces),
                projectName: projectName.trimmingCharacters(in: .whitespaces),
                declaredItems: declaredItems,
                idleThresholdMinutes: idleMinutes,
                applyBilling: applyBilling,
                billing: billing
            )
            modelContext.insert(preset)
        }
        dismiss()
    }
}

#Preview {
    PresetEditorView()
        .modelContainer(for: [Preset.self, FavoriteItem.self], inMemory: true)
}
