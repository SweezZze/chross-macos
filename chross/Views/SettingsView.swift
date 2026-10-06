import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Réglages, grouped by theme with their own category list — like System Settings.
struct SettingsView: View {
    enum Category: String, CaseIterable, Identifiable {
        case general = "Général"
        case tracking = "Suivi"
        case reminders = "Rappels"
        case billing = "Facturation"
        case sidebar = "Menu latéral"
        case permissions = "Autorisations"
        case chrome = "Extension Chrome"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .tracking: return "scope"
            case .reminders: return "bell"
            case .billing: return "eurosign.circle"
            case .sidebar: return "sidebar.left"
            case .permissions: return "lock.shield"
            case .chrome: return "puzzlepiece.extension"
            }
        }
    }

    @State private var category: Category = .general
    @State private var permissions = SystemPermissions()
    @State private var serverReachable: Bool?
    @State private var extensionFolder: URL?

    @AppStorage(AppPreferences.dailyGoalHoursKey) private var dailyGoalHours: Double = AppPreferences.defaultDailyGoalHours
    @AppStorage(AppPreferences.defaultIdleMinutesKey) private var defaultIdleMinutes: Double = AppPreferences.defaultIdleMinutes
    @AppStorage(AppPreferences.showMenuBarExtraKey) private var showMenuBarExtra = true
    @AppStorage(AppPreferences.hasCompletedOnboardingKey) private var hasCompletedOnboarding = true
    @AppStorage(AppPreferences.sidebarOrderKey) private var sidebarOrder = ""
    @AppStorage(AppPreferences.sidebarHiddenKey) private var sidebarHidden = ""
    @AppStorage(WorkReminder.enabledKey) private var workReminderEnabled = true
    @AppStorage(WorkReminder.delayMinutesKey) private var workReminderDelay: Double = WorkReminder.defaultDelayMinutes
    @AppStorage(WorkReminder.ignoredKey) private var workReminderIgnored = ""
    @Environment(WorkReminder.self) private var workReminder

    // Defaults pre-filled in the end-of-session billing prompt (same keys as SessionCoordinator).
    @AppStorage("lastApplyBilling") private var billingByDefault = false
    @AppStorage("lastHourlyRate") private var defaultHourlyRate: Double = 0
    @AppStorage("lastCurrencyCode") private var defaultCurrency: String = Locale.current.currency?.identifier ?? "EUR"
    @AppStorage("lastRoundingMinutes") private var defaultRounding: Int = BillingSettings.RoundingIncrement.fifteenMinutes.rawValue
    @AppStorage("lastVATEnabled") private var defaultVATEnabled = false
    @AppStorage("lastVATRate") private var defaultVATRate: Double = 20
    @AppStorage("lastBillingBase") private var defaultBillingBase: String = BillingSettings.BillingBase.totalDuration.rawValue

    @AppStorage(AppPreferences.companyNameKey) private var companyName: String = ""
    @AppStorage(AppPreferences.companyAddressKey) private var companyAddress: String = ""
    @AppStorage(AppPreferences.companySiretKey) private var companySiret: String = ""
    @AppStorage(AppPreferences.companyIBANKey) private var companyIBAN: String = ""
    @AppStorage(AppPreferences.companyLogoDataKey) private var companyLogoData: Data = Data()

    var body: some View {
        HStack(spacing: 0) {
            categoryList
            Divider().background(Theme.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(category.rawValue)
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.textPrimary)
                    content
                }
                .padding(32)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.page)
        .task { await permissions.poll() }
    }

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Category.allCases) { item in
                Button {
                    category = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon).frame(width: 18)
                        Text(item.rawValue)
                        Spacer()
                        if item == .permissions && !allPermissionsGranted {
                            Circle().fill(.orange).frame(width: 7, height: 7)
                        }
                    }
                    .font(.callout.weight(category == item ? .semibold : .regular))
                    .foregroundStyle(category == item ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        category == item ? Color.white.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                }
                .buttonStyle(.chross)
                .demoAnchor("settings.\(item)")
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 32)
        .frame(width: 210)
    }

    @ViewBuilder
    private var content: some View {
        switch category {
        case .general: generalSection
        case .tracking: trackingSection
        case .reminders: reminderSection
        case .billing:
            billingDefaultsSection
            companySection
        case .sidebar: sidebarSection
        case .permissions: permissionsSection
        case .chrome: chromeExtensionSection
        }
    }

    private var allPermissionsGranted: Bool {
        permissions.accessibilityGranted && permissions.notifications == .granted
    }

    // MARK: - Général

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            card("OBJECTIF QUOTIDIEN") {
                HStack {
                    Text("Temps de travail visé par jour")
                        .font(.callout)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Stepper(value: $dailyGoalHours, in: 1...16, step: 0.5) {
                        Text("\(dailyGoalHours.formatted()) h")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                    }
                    .fixedSize()
                }
            }

            card("DÉMARRAGE ET BARRE DES MENUS") {
                ThemedToggle(
                    "Ouvrir Chross au démarrage du Mac",
                    subtitle: "Pour ne jamais oublier le chrono ni les rappels",
                    isOn: Binding(get: { permissions.launchAtLogin }, set: { permissions.setLaunchAtLogin($0) })
                )
                ThemedToggle(
                    "Afficher Chross dans la barre des menus",
                    subtitle: "Le temps écoulé reste visible et accessible même fenêtre fermée",
                    isOn: $showMenuBarExtra
                )
            }

            card("INTRODUCTION") {
                HStack {
                    Text("Revoir l'écran de bienvenue et les autorisations")
                        .font(.callout)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button("Revoir") { hasCompletedOnboarding = false }
                }
            }
        }
    }

    // MARK: - Suivi

    private var trackingSection: some View {
        card("PAUSE AUTO PAR DÉFAUT", caption: "Le chrono se met en pause quand tu ne touches plus ni clavier ni souris. Utilisée pour les nouvelles sessions et pré-remplie dans les projets.") {
            PillSegmentedControl(options: AppPreferences.idleOptions, label: AppPreferences.idleLabel, selection: $defaultIdleMinutes)
        }
    }

    // MARK: - Rappels

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            card("RAPPEL SANS CHRONO") {
                ThemedToggle(
                    "Me prévenir si je travaille sans chrono",
                    subtitle: "Sur un favori ou un élément d'un projet, sans session en cours",
                    isOn: $workReminderEnabled
                )
                if workReminderEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Après")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                        PillSegmentedControl(
                            options: WorkReminder.delayOptions,
                            label: { "\(Int($0)) min" },
                            selection: $workReminderDelay
                        )
                    }
                    HStack {
                        Text("La notification propose « Démarrer », « Plus tard (1 h) » ou « Ne plus me rappeler pour ça ».")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Tester le rappel") {
                            Task { await workReminder.sendTestNotification() }
                        }
                        .disabled(permissions.notifications != .granted)
                    }
                    if permissions.notifications != .granted {
                        warning("Les notifications ne sont pas autorisées : les rappels ne peuvent pas s'afficher.", button: "Autoriser") {
                            Task { await permissions.requestNotifications() }
                        }
                    }
                }
            }

            if workReminderEnabled {
                card("QUAND LE RAPPEL SE DÉCLENCHE") {
                    VStack(alignment: .leading, spacing: 8) {
                        rule("checkmark.circle", "Tu es sur un favori ou un élément d'un de tes projets, sans session en cours.")
                        rule("timer", "Tu y as vraiment travaillé (clavier ou souris) au moins 80 % des \(Int(workReminderDelay)) dernières minutes, et tu y es encore.")
                        rule("globe", "Dans un navigateur, seul le site ouvert compte — jamais le navigateur lui-même.")
                        rule("moon.zzz", "Jamais dans les 15 min qui suivent une session, ni plus d'une fois toutes les 30 min.")
                        rule("nosign", "Jamais pour les apps système : Finder, Réglages Système, Moniteur d'activité, Spotlight…")
                    }
                }

                card("NE JAMAIS ME RAPPELER POUR", caption: "Ajoutés depuis le bouton « Ne plus me rappeler pour ça » d'une notification.") {
                    let ignored = WorkReminder.ignoredKeys(from: workReminderIgnored)
                    if ignored.isEmpty {
                        Text("Aucune exclusion pour l'instant.")
                            .font(.callout)
                            .foregroundStyle(Theme.textTertiary)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(ignored, id: \.self) { key in
                                ignoredRow(key)
                            }
                        }
                    }
                }
            }
        }
    }

    private func rule(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).frame(width: 16).foregroundStyle(Theme.accent)
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
    }

    private func ignoredRow(_ key: String) -> some View {
        let isApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) != nil
        let kind: TrackedItem.Kind = isApp ? .app : .website
        return HStack(spacing: 10) {
            ItemIconView(kind: kind, key: key, size: 22)
            Text(ItemDisplayHelper.cleanDisplayName(key: key, kind: kind, rawName: nil))
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Réactiver") {
                let remaining = WorkReminder.ignoredKeys(from: workReminderIgnored).filter { $0 != key }
                withAnimation { workReminderIgnored = remaining.joined(separator: "\n") }
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Facturation

    private var billingDefaultsSection: some View {
        card("PAR DÉFAUT EN FIN DE SESSION", caption: "Pré-remplit la fenêtre de facturation qui s'ouvre quand tu termines une session. Ces valeurs suivent aussi tes derniers choix.") {
            ThemedToggle("Facturer les sessions par défaut", isOn: $billingByDefault)

            HStack(spacing: 12) {
                labeled("TAUX HORAIRE") {
                    HStack {
                        TextField("50", value: $defaultHourlyRate, format: .number)
                            .textFieldStyle(.plain)
                            .foregroundStyle(Theme.textPrimary)
                        Text("/ h").foregroundStyle(Theme.textTertiary)
                    }
                    .fieldStyle()
                }
                labeled("DEVISE") {
                    Picker("", selection: $defaultCurrency) {
                        ForEach(["EUR", "USD", "GBP", "CHF", "CAD"], id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
                .frame(width: 120)
            }

            labeled("ARRONDI") {
                PillSegmentedControl(
                    options: BillingSettings.RoundingIncrement.allCases.map(\.rawValue),
                    label: { BillingSettings.RoundingIncrement(rawValue: $0)?.label ?? "" },
                    selection: $defaultRounding
                )
            }

            labeled("BASE DE CALCUL") {
                PillSegmentedControl(
                    options: BillingSettings.BillingBase.allCases.map(\.rawValue),
                    label: { BillingSettings.BillingBase(rawValue: $0)?.label ?? "" },
                    selection: $defaultBillingBase
                )
            }

            HStack {
                ThemedToggle("TVA", isOn: $defaultVATEnabled)
                if defaultVATEnabled {
                    HStack(spacing: 2) {
                        TextField("20", value: $defaultVATRate, format: .number)
                            .textFieldStyle(.plain)
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 34)
                        Text("%").foregroundStyle(Theme.textTertiary)
                    }
                    .fieldStyle()
                    .fixedSize()
                }
            }
        }
    }

    // MARK: - Menu latéral

    private var sidebarSection: some View {
        let order = SidebarLayout.order(from: sidebarOrder)
        let hidden = SidebarLayout.hidden(from: sidebarHidden)

        return card("ONGLETS", caption: "Glisse les lignes pour changer l'ordre, ou fais-le directement dans le menu de gauche. L'œil masque un onglet ; Chrono reste toujours visible.") {
            VStack(spacing: 6) {
                ForEach(Array(order.enumerated()), id: \.element) { index, screen in
                    let isHidden = hidden.contains(screen)
                    HStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(Theme.textTertiary)
                        Image(systemName: screen.icon)
                            .frame(width: 18)
                            .foregroundStyle(isHidden ? Theme.textTertiary : Theme.accent)
                        Text(screen.rawValue)
                            .font(.callout)
                            .foregroundStyle(isHidden ? Theme.textTertiary : Theme.textPrimary)
                            .strikethrough(isHidden, color: Theme.textTertiary)
                        Spacer()
                        orderButton("chevron.up", enabled: index > 0) { move(screen, by: -1) }
                        orderButton("chevron.down", enabled: index < order.count - 1) { move(screen, by: 1) }
                        Button {
                            toggleHidden(screen)
                        } label: {
                            Image(systemName: isHidden ? "eye.slash" : "eye")
                                .foregroundStyle(screen.canBeHidden ? Theme.textPrimary : Theme.textTertiary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.chross)
                        .disabled(!screen.canBeHidden)
                        .help(screen.canBeHidden ? (isHidden ? "Afficher" : "Masquer") : "Chrono est toujours affiché")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .draggable(screen.storageKey)
                    .dropDestination(for: String.self) { keys, _ in
                        guard let key = keys.first, let moving = order.first(where: { $0.storageKey == key }) else { return false }
                        place(moving, before: screen)
                        return true
                    }
                }
            }

            HStack {
                Text("Réglages reste toujours en bas du menu.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button("Rétablir l'ordre par défaut") {
                    withAnimation {
                        sidebarOrder = ""
                        sidebarHidden = ""
                    }
                }
                .disabled(sidebarOrder.isEmpty && sidebarHidden.isEmpty)
            }
        }
    }

    private func orderButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textTertiary.opacity(0.5))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.chross)
        .disabled(!enabled)
    }

    private func move(_ screen: ContentScreen, by offset: Int) {
        var order = SidebarLayout.order(from: sidebarOrder)
        guard let index = order.firstIndex(of: screen) else { return }
        let target = min(max(index + offset, 0), order.count - 1)
        order.remove(at: index)
        order.insert(screen, at: target)
        withAnimation(.easeOut(duration: 0.15)) { sidebarOrder = SidebarLayout.encode(order) }
    }

    private func place(_ screen: ContentScreen, before target: ContentScreen) {
        guard screen != target else { return }
        var order = SidebarLayout.order(from: sidebarOrder)
        order.removeAll { $0 == screen }
        order.insert(screen, at: order.firstIndex(of: target) ?? order.endIndex)
        withAnimation(.easeOut(duration: 0.15)) { sidebarOrder = SidebarLayout.encode(order) }
    }

    private func toggleHidden(_ screen: ContentScreen) {
        guard screen.canBeHidden else { return }
        var hidden = SidebarLayout.hidden(from: sidebarHidden)
        if hidden.contains(screen) { hidden.remove(screen) } else { hidden.insert(screen) }
        withAnimation(.easeOut(duration: 0.15)) { sidebarHidden = SidebarLayout.encode(hidden) }
    }

    // MARK: - Autorisations

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            permissionCard(
                icon: "globe",
                title: "Accessibilité",
                text: "Permet de savoir sur quel site tu es dans ton navigateur. Sans elle, seules les applications sont détectées.",
                isGranted: permissions.accessibilityGranted,
                deniedLabel: "Non autorisée",
                button: "Autoriser",
                action: { permissions.requestAccessibility() }
            )
            permissionCard(
                icon: "bell.badge",
                title: "Notifications",
                text: "Nécessaires pour le rappel « Tu travailles sans chrono ».",
                isGranted: permissions.notifications == .granted,
                deniedLabel: permissions.notifications == .denied ? "Refusées" : "Pas encore demandées",
                button: permissions.notifications == .denied ? "Ouvrir les réglages" : "Autoriser",
                action: { Task { await permissions.requestNotifications() } }
            )
            card("CONTRÔLE DES NAVIGATEURS") {
                Text("Si un site n'est pas détecté par l'Accessibilité, Chross demande l'adresse directement au navigateur. macOS te le demande une seule fois par navigateur (« chross souhaite contrôler Google Chrome »). Tu peux le gérer dans Réglages Système → Confidentialité et sécurité → Automatisation.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Ouvrir Automatisation") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private func permissionCard(
        icon: String,
        title: String,
        text: String,
        isGranted: Bool,
        deniedLabel: String,
        button: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isGranted ? Theme.accent : .orange)
                .frame(width: 40, height: 40)
                .background((isGranted ? Theme.accent : Color.orange).opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Label(isGranted ? "Autorisée" : deniedLabel, systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isGranted ? Theme.accent : .orange)
                }
                Text(text)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !isGranted {
                    Button(button, action: action)
                        .padding(.top, 4)
                }
            }
        }
        .chrossCard()
    }

    // MARK: - Extension Chrome

    private var chromeExtensionSection: some View {
        card("EXTENSION GOOGLE CHROME", caption: "Contrôle ton chrono, ajoute des sites à la session et affiche le temps écoulé en direct depuis ton navigateur (Chrome, Brave, Arc, Edge).") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Serveur local Chross")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    switch serverReachable {
                    case .some(true):
                        Text("Port 52847 (127.0.0.1) · Actif").font(.caption).foregroundStyle(Theme.accent)
                    case .some(false):
                        Text("Port 52847 · Ne répond pas (un autre programme l'utilise peut-être)").font(.caption).foregroundStyle(.orange)
                    case .none:
                        Text("Vérification…").font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
            }

            Divider().background(Theme.border)

            VStack(alignment: .leading, spacing: 8) {
                Text("Installer l'extension")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("1. Ouvre chrome://extensions et active le « Mode développeur ».\n2. Clique « Charger l'extension non empaquetée » et choisis le dossier ChrossChromeExtension.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(extensionFolder == nil ? "Choisir le dossier…" : "Afficher le dossier") {
                        revealExtensionFolder()
                    }
                    if let extensionFolder {
                        Text(extensionFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .task {
            extensionFolder = Self.findExtensionFolder()
            serverReachable = await Self.isLocalServerReachable()
        }
    }

    private static func findExtensionFolder() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = ["Downloads/chross", "Desktop/chross", "Developer/chross", "Documents/chross"]
            .map { home.appendingPathComponent($0).appendingPathComponent("ChrossChromeExtension") }
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }
    }

    private static func isLocalServerReachable() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:52847/status") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
    }

    private func revealExtensionFolder() {
        if let extensionFolder {
            NSWorkspace.shared.activateFileViewerSelecting([extensionFolder])
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choisis le dossier ChrossChromeExtension"
        if panel.runModal() == .OK, let url = panel.url,
           FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path) {
            extensionFolder = url
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // MARK: - Building blocks

    private func card<Content: View>(_ title: String, caption: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chrossCard()
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            content()
        }
    }

    private func warning(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.caption).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button(button, action: action)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var companySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TON ENTREPRISE (FACTURES PDF)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("Utilisées pour générer tes factures PDF depuis une session.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)

            HStack(spacing: 14) {
                logoPicker
                VStack(spacing: 10) {
                    companyField("Nom de l'entreprise", text: $companyName)
                    companyField("Adresse", text: $companyAddress)
                }
            }

            HStack(spacing: 10) {
                companyField("SIRET", text: $companySiret)
                companyField("IBAN", text: $companyIBAN)
            }
        }
        .chrossCard()
    }

    private var logoPicker: some View {
        Button(action: pickLogo) {
            Group {
                if let image = NSImage(data: companyLogoData) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "photo").foregroundStyle(Theme.textTertiary)
                        Text("Logo").font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .frame(width: 64, height: 64)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border))
        }
        .buttonStyle(.chross)
    }

    private func companyField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border))
    }

    private func pickLogo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        companyLogoData = pngData
    }
}

private extension View {
    func fieldStyle() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border))
    }
}

#Preview {
    SettingsView()
        .environment(WorkReminder())
        .preferredColorScheme(.dark)
}
