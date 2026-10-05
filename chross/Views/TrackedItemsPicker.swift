import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Lets the user pick which apps and which websites belong to a session or preset.
/// Favorited apps/sites (clic droit → Ajouter aux favoris) show up here even when
/// the app isn't currently running, so a recurring project never needs retyping.
struct TrackedItemsPicker: View {
    @Binding var items: [TrackedItem]

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteItem.displayName) private var favorites: [FavoriteItem]

    @State private var runningApps: [RunningAppInfo] = []
    @State private var selectedBundleIDs: Set<String> = []
    @State private var websites: [String] = []
    @State private var websiteInput = ""
    @State private var didSeed = false
    /// Apps that were already selected when the picker opened — kept visible and selectable
    /// even if they've since been quit and aren't favorites (e.g. editing a running session).
    @State private var seededApps: [TrackedItem] = []

    private struct AppCell: Identifiable {
        let bundleID: String
        let name: String
        let icon: NSImage?
        var id: String { bundleID }
    }

    private var favoriteApps: [FavoriteItem] { favorites.filter { $0.kind == .app } }
    private var favoriteWebsites: [FavoriteItem] { favorites.filter { $0.kind == .website } }

    private var appCells: [AppCell] {
        var seen: Set<String> = []
        var cells: [AppCell] = []
        for app in runningApps {
            cells.append(AppCell(bundleID: app.bundleIdentifier, name: app.name, icon: app.icon))
            seen.insert(app.bundleIdentifier)
        }
        for favorite in favoriteApps where !seen.contains(favorite.key) {
            let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: favorite.key)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
            cells.append(AppCell(bundleID: favorite.key, name: favorite.displayName, icon: icon))
            seen.insert(favorite.key)
        }
        for app in seededApps where !seen.contains(app.key) {
            let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.key)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
            cells.append(AppCell(bundleID: app.key, name: app.displayName, icon: icon))
            seen.insert(app.key)
        }
        return cells
    }

    private var pendingFavoriteWebsites: [FavoriteItem] {
        favoriteWebsites.filter { !websites.contains($0.key) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            appsSection
            websitesSection
        }
        .onAppear {
            runningApps = RunningAppsProvider.currentRunningApps()
            seedFromItemsIfNeeded()
        }
        .onChange(of: selectedBundleIDs) { _, _ in pushItems() }
        .onChange(of: websites) { _, _ in pushItems() }
    }

    private func seedFromItemsIfNeeded() {
        guard !didSeed else { return }
        didSeed = true
        seededApps = items.filter { $0.kind == .app }
        selectedBundleIDs = Set(items.filter { $0.kind == .app }.map(\.key))
        websites = items.filter { $0.kind == .website }.map(\.key)
    }

    private func pushItems() {
        let appItems: [TrackedItem] = selectedBundleIDs.compactMap { id in
            if let running = runningApps.first(where: { $0.bundleIdentifier == id }) {
                return TrackedItem(kind: .app, key: id, displayName: running.name)
            }
            if let favorite = favoriteApps.first(where: { $0.key == id }) {
                return TrackedItem(kind: .app, key: id, displayName: favorite.displayName)
            }
            if let seeded = seededApps.first(where: { $0.key == id }) {
                return seeded
            }
            return nil
        }
        let siteItems = websites.map { TrackedItem(kind: .website, key: $0, displayName: $0) }
        items = appItems + siteItems
    }

    // MARK: - Apps

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("APPLICATIONS SUIVIES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(selectedBundleIDs.count) sélectionnée\(selectedBundleIDs.count > 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(appCells) { cell in
                    appCard(cell)
                }
                addApplicationTile
            }
        }
    }

    private func appCard(_ cell: AppCell) -> some View {
        let isSelected = selectedBundleIDs.contains(cell.bundleID)
        return Button {
            toggle(cell.bundleID)
        } label: {
            VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    iconView(for: cell)
                        .frame(width: 44, height: 44)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.accent)
                            .background(Circle().fill(Theme.surface))
                            .offset(x: 6, y: -6)
                    }
                }
                Text(cell.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.chross)
        .contextMenu {
            if isFavorite(kind: .app, key: cell.bundleID) {
                Button("Retirer des favoris", role: .destructive) {
                    removeFavorite(kind: .app, key: cell.bundleID)
                }
            } else {
                Button("Ajouter aux favoris") {
                    modelContext.insert(FavoriteItem(kind: .app, key: cell.bundleID, displayName: cell.name))
                }
            }
        }
    }

    @ViewBuilder
    private func iconView(for cell: AppCell) -> some View {
        if let icon = cell.icon {
            Image(nsImage: icon).resizable().frame(width: 26, height: 26)
        } else {
            Image(systemName: "app.dashed")
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var addApplicationTile: some View {
        Button(action: pickApplication) {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                Text("Ajouter…")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
        }
        .buttonStyle(.chross)
    }

    private func toggle(_ bundleID: String) {
        if selectedBundleIDs.contains(bundleID) {
            selectedBundleIDs.remove(bundleID)
        } else {
            selectedBundleIDs.insert(bundleID)
        }
    }

    private func pickApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path)
        if !favoriteApps.contains(where: { $0.key == bundleID }) {
            modelContext.insert(FavoriteItem(kind: .app, key: bundleID, displayName: name))
        }
        selectedBundleIDs.insert(bundleID)
    }

    // MARK: - Websites

    private var websitesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SITES WEB — optionnel")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 8) {
                ForEach(websites, id: \.self) { site in
                    websiteChip(site)
                }
                TextField("Ajouter un domaine…", text: $websiteInput)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.textPrimary)
                    .onSubmit(addWebsite)
                    .frame(minWidth: 120)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(Theme.border)
            )

            if !pendingFavoriteWebsites.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(pendingFavoriteWebsites) { favorite in
                            Button {
                                websites.append(favorite.key)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill").font(.caption2)
                                    Text(favorite.displayName)
                                }
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.surfaceRaised, in: Capsule())
                            }
                            .buttonStyle(.chross)
                            .contextMenu {
                                Button("Retirer des favoris", role: .destructive) {
                                    removeFavorite(kind: .website, key: favorite.key)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func websiteChip(_ site: String) -> some View {
        HStack(spacing: 6) {
            WebsiteIconView(domain: site, size: 16)
            Text(site).font(.callout).foregroundStyle(Theme.textPrimary)
            Button {
                websites.removeAll { $0 == site }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.chross)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surfaceRaised, in: Capsule())
        .contextMenu {
            if isFavorite(kind: .website, key: site) {
                Button("Retirer des favoris", role: .destructive) {
                    removeFavorite(kind: .website, key: site)
                }
            } else {
                Button("Ajouter aux favoris") {
                    modelContext.insert(FavoriteItem(kind: .website, key: site, displayName: site))
                }
            }
        }
    }

    private func addWebsite() {
        guard let domain = DomainNormalizer.normalize(websiteInput), !websites.contains(domain) else { return }
        websites.append(domain)
        websiteInput = ""
    }

    // MARK: - Favorites

    private func isFavorite(kind: TrackedItem.Kind, key: String) -> Bool {
        favorites.contains { $0.kind == kind && $0.key == key }
    }

    private func removeFavorite(kind: TrackedItem.Kind, key: String) {
        guard let existing = favorites.first(where: { $0.kind == kind && $0.key == key }) else { return }
        modelContext.delete(existing)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: FavoriteItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(FavoriteItem(kind: .website, key: "github.com", displayName: "github.com"))
    container.mainContext.insert(FavoriteItem(kind: .app, key: "com.figma.Desktop", displayName: "Figma"))

    return ScrollView {
        TrackedItemsPicker(items: .constant([]))
            .padding(24)
    }
    .background(Theme.page)
    .modelContainer(container)
}
