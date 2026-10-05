import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Manages the favorite sites and apps that the session pickers offer in one click.
struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteItem.displayName) private var favorites: [FavoriteItem]

    @State private var editorTarget: EditorTarget?
    @State private var hoveredID: PersistentIdentifier?

    /// What the add/edit sheet is working on.
    enum EditorTarget: Identifiable {
        case newWebsite
        case edit(FavoriteItem)

        var id: String {
            switch self {
            case .newWebsite: return "new-website"
            case .edit(let item): return "edit-\(item.persistentModelID.hashValue)"
            }
        }
    }

    private var websites: [FavoriteItem] { favorites.filter { $0.kind == .website } }
    private var apps: [FavoriteItem] { favorites.filter { $0.kind == .app } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if favorites.isEmpty {
                    ContentUnavailableView(
                        "Aucun favori",
                        systemImage: "star",
                        description: Text("Ajoute les sites et apps que tu utilises souvent : ils seront proposés en un clic quand tu lances une session ou un projet.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    section(title: "SITES WEB", items: websites, emptyText: "Aucun site favori.")
                    section(title: "APPLICATIONS", items: apps, emptyText: "Aucune application favorite.")
                }
            }
            .padding(32)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.page)
        .sheet(item: $editorTarget) { target in
            switch target {
            case .newWebsite:
                FavoriteEditorView(existing: nil)
            case .edit(let item):
                FavoriteEditorView(existing: item)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Favoris").font(.largeTitle.bold()).foregroundStyle(Theme.textPrimary)
                Text("Proposés en un clic quand tu choisis quoi suivre.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                addApplication()
            } label: {
                Label("Ajouter une app", systemImage: "plus")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.border))
            }
            .buttonStyle(.chross)

            Button {
                editorTarget = .newWebsite
            } label: {
                Label("Ajouter un site", systemImage: "plus")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.chross)
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    private func section(title: String, items: [FavoriteItem], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(items.count)")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            if items.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        row(item)
                    }
                }
            }
        }
    }

    private func row(_ item: FavoriteItem) -> some View {
        let isHovered = hoveredID == item.persistentModelID

        return HStack(spacing: 12) {
            ItemIconView(kind: item.kind, key: item.key, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if item.displayName != item.key {
                    Text(item.kind == .website ? item.key : appSubtitle(item))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                iconButton("pencil", help: "Modifier") {
                    editorTarget = .edit(item)
                }
                iconButton("trash", help: "Supprimer") {
                    modelContext.delete(item)
                }
            }
            .opacity(isHovered ? 1 : 0.35)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .chrossCard(padding: 0, radius: 14)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredID = item.persistentModelID
            } else if isHovered {
                hoveredID = nil
            }
        }
        .contextMenu {
            Button("Modifier…") { editorTarget = .edit(item) }
            Button("Supprimer", role: .destructive) { modelContext.delete(item) }
        }
    }

    private func iconButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30, height: 30)
                .background(Theme.surfaceRaised, in: Circle())
        }
        .buttonStyle(.chross)
        .help(help)
    }

    private func appSubtitle(_ item: FavoriteItem) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.key) == nil
            ? "Application introuvable sur ce Mac"
            : "Application"
    }

    private func addApplication() {
        guard let picked = ApplicationPicker.pick() else { return }
        if let existing = favorites.first(where: { $0.kind == .app && $0.key == picked.bundleID }) {
            editorTarget = .edit(existing)
            return
        }
        modelContext.insert(FavoriteItem(kind: .app, key: picked.bundleID, displayName: picked.name))
    }
}

/// Opens the system panel on /Applications and returns the chosen app's identity.
enum ApplicationPicker {
    static func pick() -> (bundleID: String, name: String)? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        return (bundleID, name)
    }
}

/// Adds a favorite site, or edits any favorite (rename; change the domain or app).
struct FavoriteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var favorites: [FavoriteItem]

    let existing: FavoriteItem?

    @State private var name = ""
    @State private var domain = ""
    @State private var appBundleID = ""
    @State private var errorMessage: String?

    private var kind: TrackedItem.Kind { existing?.kind ?? .website }
    private var isWebsite: Bool { kind == .website }

    private var normalizedDomain: String? {
        DomainNormalizer.normalize(domain).flatMap { $0.contains(".") ? $0 : nil }
    }

    private var canSave: Bool {
        isWebsite ? normalizedDomain != nil : !appBundleID.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(existing == nil ? "Nouveau site favori" : (isWebsite ? "Modifier le site" : "Modifier l'application"))
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)

            if isWebsite {
                field(label: "DOMAINE", prompt: "ex : github.com", text: $domain)
                if let normalizedDomain {
                    HStack(spacing: 8) {
                        WebsiteIconView(domain: normalizedDomain, size: 18)
                        Text(normalizedDomain)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("APPLICATION")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 10) {
                        ItemIconView(kind: .app, key: appBundleID, size: 26)
                        Text(appBundleID)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Changer…") {
                            if let picked = ApplicationPicker.pick() {
                                appBundleID = picked.bundleID
                                name = picked.name
                            }
                        }
                        .buttonStyle(.chross)
                        .foregroundStyle(Theme.accent)
                    }
                }
            }

            field(label: "NOM AFFICHÉ — optionnel", prompt: isWebsite ? (normalizedDomain ?? "Nom du site") : "Nom de l'app", text: $name)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Annuler") { dismiss() }
                    .buttonStyle(.chross)
                    .foregroundStyle(Theme.textSecondary)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: save) {
                    Text(existing == nil ? "Ajouter" : "Enregistrer")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(canSave ? Theme.accent : Theme.surfaceRaised, in: Capsule())
                }
                .buttonStyle(.chross)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 440, height: isWebsite ? 400 : 360)
        .background(Theme.page)
        .onAppear(perform: load)
    }

    private func field(label: String, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border))
                .onSubmit(save)
        }
    }

    private func load() {
        guard let existing else { return }
        if existing.kind == .website {
            domain = existing.key
            name = existing.displayName == existing.key ? "" : existing.displayName
        } else {
            appBundleID = existing.key
            name = existing.displayName
        }
    }

    private func save() {
        guard canSave else { return }
        let key = isWebsite ? (normalizedDomain ?? "") : appBundleID
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty
            ? (isWebsite ? key : ItemDisplayHelper.cleanDisplayName(key: key, kind: .app, rawName: nil))
            : trimmedName

        let duplicate = favorites.contains {
            $0.kind == kind && $0.key == key && $0.persistentModelID != existing?.persistentModelID
        }
        guard !duplicate else {
            errorMessage = isWebsite ? "Ce site est déjà dans tes favoris." : "Cette application est déjà dans tes favoris."
            return
        }

        if let existing {
            existing.key = key
            existing.displayName = displayName
        } else {
            modelContext.insert(FavoriteItem(kind: kind, key: key, displayName: displayName))
        }
        dismiss()
    }
}
