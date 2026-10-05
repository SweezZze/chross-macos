import SwiftUI

/// Edits which apps and sites count toward the running session, using the same picker as
/// `SessionSetupView`. Changes are applied as a diff on "Enregistrer" so time already
/// tracked is kept.
struct ScopeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ActivityTracker.self) private var tracker
    @Environment(SessionCoordinator.self) private var coordinator

    @State private var items: [TrackedItem] = []
    @State private var didLoad = false

    private var hasWebsites: Bool {
        items.contains { $0.kind == .website }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apps et sites suivis")
                        .font(.title.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text("Les changements s'appliquent tout de suite à la session en cours.")
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

            if didLoad {
                ScrollView {
                    TrackedItemsPicker(items: $items)
                }
            } else {
                Spacer()
            }

            if hasWebsites && !AccessibilityPermission.isGranted {
                AccessibilityPermissionNotice()
            }

            HStack {
                Button("Annuler") { dismiss() }
                    .buttonStyle(.chross)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(action: save) {
                    Label("Enregistrer", systemImage: "checkmark")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.chross)
                .background(Theme.accent, in: Capsule())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 460, height: 600)
        .background(Theme.page)
        .onAppear {
            // Seed before the picker appears — it reads `items` only once, on its own onAppear.
            items = tracker.declaredItems
            didLoad = true
        }
    }

    private func save() {
        if hasWebsites && !AccessibilityPermission.isGranted {
            AccessibilityPermission.requestIfNeeded()
        }
        let current = tracker.declaredItems
        func same(_ a: TrackedItem, _ b: TrackedItem) -> Bool { a.kind == b.kind && a.key == b.key }

        for item in current where !items.contains(where: { same($0, item) }) {
            coordinator.removeDeclaredItem(item, tracker: tracker)
        }
        for item in items where !current.contains(where: { same($0, item) }) {
            coordinator.addDeclaredItem(item, tracker: tracker)
        }
        dismiss()
    }
}
