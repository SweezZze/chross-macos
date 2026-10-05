import SwiftData
import SwiftUI

struct PresetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ActivityTracker.self) private var tracker
    @Environment(SessionCoordinator.self) private var coordinator
    @Query(sort: \Preset.createdDate, order: .reverse) private var presets: [Preset]

    @Binding var selectedScreen: ContentScreen?

    @State private var showEditor = false
    @State private var presetToEdit: Preset?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Projets").font(.largeTitle.bold()).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button {
                        showEditor = true
                    } label: {
                        Label("Nouveau preset", systemImage: "plus")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.chross)
                    .background(Theme.accent, in: Capsule())
                }

                if presets.isEmpty {
                    ContentUnavailableView(
                        "Aucun preset",
                        systemImage: "rectangle.stack",
                        description: Text("Crée un preset pour lancer une session déjà configurée — apps, sites et taux horaire — en un clic.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    VStack(spacing: 10) {
                        ForEach(presets) { preset in
                            Button {
                                launch(preset)
                            } label: {
                                presetRow(preset)
                            }
                            .buttonStyle(.chross)
                            .disabled(tracker.isRunning)
                            .contextMenu {
                                Button("Modifier") {
                                    presetToEdit = preset
                                }
                                Button("Dupliquer") {
                                    duplicate(preset)
                                }
                                Button("Supprimer", role: .destructive) {
                                    modelContext.delete(preset)
                                }
                            }
                        }
                    }
                }
            }
            .padding(32)
        }
        .background(Theme.page)
        .sheet(isPresented: $showEditor) {
            PresetEditorView()
        }
        .sheet(item: $presetToEdit) { preset in
            PresetEditorView(existingPreset: preset)
        }
    }

    private func presetRow(_ preset: Preset) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name).font(.headline).foregroundStyle(Theme.textPrimary)
                Text(summary(for: preset))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if preset.applyBilling {
                Text(CurrencyFormatter.format(preset.billing.hourlyRate, currencyCode: preset.billing.currencyCode) + "/h")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }

            Image(systemName: "play.fill")
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 32, height: 32)
                .background(Theme.surfaceRaised, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border))
        }
        .padding(16)
        .chrossCard(padding: 0, radius: 16)
    }

    private func summary(for preset: Preset) -> String {
        let appCount = preset.declaredItems.filter { $0.kind == .app }.count
        let siteCount = preset.declaredItems.filter { $0.kind == .website }.count
        var parts: [String] = []
        if appCount > 0 { parts.append("\(appCount) app\(appCount > 1 ? "s" : "")") }
        if siteCount > 0 { parts.append("\(siteCount) site\(siteCount > 1 ? "s" : "")") }
        return parts.isEmpty ? "Aucun élément déclaré" : parts.joined(separator: " · ")
    }

    private func duplicate(_ preset: Preset) {
        let copy = Preset(
            name: "\(preset.name) (copie)",
            projectName: preset.projectName,
            declaredItems: preset.declaredItems,
            idleThresholdMinutes: preset.idleThresholdMinutes,
            applyBilling: preset.applyBilling,
            billing: preset.billing
        )
        modelContext.insert(copy)
    }

    private func launch(_ preset: Preset) {
        guard !tracker.isRunning else { return }
        coordinator.startSession(fromPreset: preset, tracker: tracker, modelContext: modelContext)
        selectedScreen = .chrono
    }
}

#Preview {
    PresetsView(selectedScreen: .constant(.presets))
        .environment(ActivityTracker())
        .environment(SessionCoordinator())
        .modelContainer(for: [Preset.self, FavoriteItem.self], inMemory: true)
}
