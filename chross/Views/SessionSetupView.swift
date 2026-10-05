import SwiftData
import SwiftUI

struct SessionSetupView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var projectName = ""
    @State private var declaredItems: [TrackedItem] = []
    @State private var idleMinutes: Double = AppPreferences.defaultIdleMinutes
    @State private var showPermissionAlert = false
    @FocusState private var projectFieldFocused: Bool
    @AppStorage(AppPreferences.defaultIdleMinutesKey) private var defaultIdleMinutes: Double = AppPreferences.defaultIdleMinutes

    let onStart: (_ projectName: String, _ declaredItems: [TrackedItem], _ idleThresholdMinutes: Double) -> Void

    init(
        initialItems: [TrackedItem] = [],
        onStart: @escaping (_ projectName: String, _ declaredItems: [TrackedItem], _ idleThresholdMinutes: Double) -> Void
    ) {
        _declaredItems = State(initialValue: initialItems)
        self.onStart = onStart
    }

    private var hasWebsites: Bool {
        declaredItems.contains { $0.kind == .website }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nouvelle session")
                        .font(.title.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text("Chross ne compte que ce que tu sélectionnes.")
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                }
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

            VStack(alignment: .leading, spacing: 10) {
                Text("PROJET / CLIENT")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Nom du projet / client", text: $projectName)
                    .textFieldStyle(.plain)
                    .focused($projectFieldFocused)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                            .strokeBorder(projectFieldFocused ? Theme.accent : Theme.border, lineWidth: projectFieldFocused ? 1.5 : 1)
                    )
            }

            ScrollView {
                TrackedItemsPicker(items: $declaredItems)
            }

            if hasWebsites && !AccessibilityPermission.isGranted {
                AccessibilityPermissionNotice()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("PAUSE AUTO SI INACTIF")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                PillSegmentedControl(options: AppPreferences.idleOptions, label: AppPreferences.idleLabel, selection: $idleMinutes)
            }

            HStack {
                Button("Annuler") { dismiss() }
                    .buttonStyle(.chross)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(action: attemptStart) {
                    Label("Lancer le chrono", systemImage: "play.fill")
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
        .frame(width: 460, height: 660)
        .background(Theme.page)
        .onAppear { idleMinutes = defaultIdleMinutes }
        .alert("Autorisation Accessibilité requise", isPresented: $showPermissionAlert) {
            Button("Ouvrir les Réglages Système") {
                AccessibilityPermission.requestIfNeeded()
                PermissionSettingsOpener.openAccessibilitySettings()
            }
            Button("Continuer sans détecter les sites") { startSession() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Pour détecter automatiquement les sites web que tu visites, chross a besoin de l'autorisation Accessibilité (Réglages Système → Confidentialité et sécurité → Accessibilité).")
        }
    }

    private func attemptStart() {
        if hasWebsites && !AccessibilityPermission.isGranted {
            showPermissionAlert = true
            return
        }
        startSession()
    }

    private func startSession() {
        defaultIdleMinutes = idleMinutes
        onStart(
            projectName.trimmingCharacters(in: .whitespaces),
            declaredItems,
            idleMinutes
        )
        dismiss()
    }
}

#Preview {
    SessionSetupView { _, _, _ in }
        .modelContainer(for: [FavoriteItem.self], inMemory: true)
}
