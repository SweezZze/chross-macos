import SwiftData
import SwiftUI

struct ChronoPane: View {
    @Environment(ActivityTracker.self) private var tracker
    @Environment(SessionCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkSession.startDate, order: .reverse) private var sessions: [WorkSession]

    @Binding var selectedScreen: ContentScreen?

    @State private var quickProjectName = ""
    @State private var showScopeEditor = false
    @FocusState private var quickFieldFocused: Bool
    @AppStorage(AppPreferences.defaultIdleMinutesKey) private var defaultIdleMinutes: Double = AppPreferences.defaultIdleMinutes

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var statusColor: Color {
        guard tracker.isRunning else { return Theme.textSecondary }
        if tracker.isPaused { return .orange }
        if tracker.isOutOfScope { return Theme.textSecondary }
        return Theme.accent
    }

    private var statusLabel: String {
        guard tracker.isRunning else { return "PRÊT" }
        if tracker.isPaused { return "EN PAUSE" }
        if tracker.isOutOfScope { return "HORS SÉLECTION" }
        return "EN COURS"
    }

    private var todaysSessions: [WorkSession] {
        sessions.filter { Calendar.current.isDateInToday($0.startDate) }
    }

    private var recentProjects: [WorkSession] {
        var seen: Set<String> = []
        var result: [WorkSession] = []
        for session in sessions where !session.projectName.isEmpty {
            guard !seen.contains(session.projectName) else { continue }
            seen.insert(session.projectName)
            result.append(session)
            if result.count == 3 { break }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                AccessibilityStatusBanner()
                mainCard
                if tracker.isRunning {
                    scopeCard
                    activitySection
                } else {
                    bottomRow
                }
            }
            .padding(32)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.page)
        .sheet(isPresented: $showScopeEditor) {
            ScopeEditorView()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            if tracker.isRunning {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Démarrée à \(Self.timeFormatter.string(from: tracker.sessionStart ?? Date()))")
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                    Text(coordinator.runningProjectName ?? "Session en cours")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "moon.fill")
                    Text(tracker.idleThreshold > 0 ? "Pause auto après \(Int(tracker.idleThreshold / 60)) min" : "Pause auto désactivée")
                }
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.dateFormatter.string(from: Date()).capitalized)
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Chrono")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Button {
                    coordinator.showSetup = true
                } label: {
                    HStack(spacing: 8) {
                        Text("Nouvelle session")
                        Text("⌘N")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.chross)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border))
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    // MARK: - Main card

    private var mainCard: some View {
        VStack(spacing: 24) {
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(statusLabel)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(statusColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.12), in: Capsule())

            timerDisplay

            WaveformTicker(activeFraction: tracker.isRunning ? tickerFraction : 0)
                .frame(maxWidth: 480)

            if tracker.isRunning {
                currentActiveItemBanner
                runningControls
            } else {
                idleControls
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .chrossCard()
    }

    private var tickerFraction: Double {
        (tracker.elapsed.truncatingRemainder(dividingBy: 8)) / 8
    }

    private var timerDisplay: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(DurationFormatter.format(tracker.elapsed))
                .font(.system(size: 76, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .animation(.default, value: tracker.elapsed)
            Text(",\(DurationFormatter.centiseconds(tracker.elapsed))")
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var idleControls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(Theme.textTertiary)
                TextField("Projet ou client…", text: $quickProjectName)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.textPrimary)
                    .focused($quickFieldFocused)
                    .onSubmit(startQuickSession)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(quickFieldFocused ? Theme.accent : Theme.border, lineWidth: quickFieldFocused ? 1.5 : 1)
            )
            .frame(maxWidth: 420)

            Button(action: startQuickSession) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Démarrer").font(.headline)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .buttonStyle(.chross)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var runningControls: some View {
        HStack(spacing: 12) {
            Button {
                if tracker.isPaused {
                    tracker.resumeManually()
                } else {
                    tracker.pauseManually()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: tracker.isPaused ? "play.fill" : "pause.fill")
                    Text(tracker.isPaused ? "Reprendre" : "Pause").font(.headline)
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
            .buttonStyle(.chross)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border))

            Button {
                coordinator.requestStop(tracker: tracker)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.fill")
                    Text("Terminer").font(.headline)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
            .buttonStyle(.chross)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func startQuickSession() {
        let name = quickProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        coordinator.startSession(tracker: tracker, projectName: name, declaredItems: [], idleThresholdMinutes: defaultIdleMinutes, modelContext: modelContext)
        quickProjectName = ""
    }

    // MARK: - Bannière d'activité en cours

    @ViewBuilder
    private var currentActiveItemBanner: some View {
        if tracker.isPaused {
            HStack(spacing: 12) {
                Image(systemName: "pause.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session en pause")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Le chrono est arrêté · Reprenez pour continuer")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.3)))
        } else if let key = tracker.currentItemKey, let kind = tracker.currentItemKind {
            let cleanName = ItemDisplayHelper.cleanDisplayName(key: key, kind: kind, rawName: tracker.currentItemName)
            let isOut = tracker.isOutOfScope

            HStack(spacing: 12) {
                ItemIconView(kind: kind, key: key, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(cleanName)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(kind == .website ? "Site web" : "Application")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.surfaceRaised, in: Capsule())
                    }

                    if isOut {
                        Text("Hors sélection pour ce projet · temps non comptabilisé")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        HStack(spacing: 4) {
                            Circle().fill(Theme.accent).frame(width: 6, height: 6)
                            Text("Activité en cours d'enregistrement")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                Spacer(minLength: 8)

                if isOut {
                    Button {
                        addCurrentItemToSession(key: key, kind: kind, name: cleanName)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Suivre cet élément")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.chross)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: 480)
            .background(isOut ? Color.orange.opacity(0.08) : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isOut ? Color.orange.opacity(0.3) : Theme.border)
            )
        }
    }

    private func addCurrentItemToSession(key: String, kind: TrackedItem.Kind, name: String) {
        let item = TrackedItem(kind: kind, key: key, displayName: name)
        coordinator.addDeclaredItem(item, tracker: tracker)
    }

    // MARK: - Apps et sites suivis (running)

    private var scopeCard: some View {
        let items = tracker.declaredItems
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Apps et sites suivis").font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    showScopeEditor = true
                } label: {
                    Label("Ajouter / modifier", systemImage: "plus")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Theme.surfaceRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.border))
                }
                .buttonStyle(.chross)
            }

            if items.isEmpty {
                Text("Aucune sélection : tout ce que tu fais est comptabilisé.")
                    .font(.callout)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        scopeChip(item)
                    }
                }
            }
        }
        .chrossCard()
    }

    private func scopeChip(_ item: TrackedItem) -> some View {
        HStack(spacing: 8) {
            ItemIconView(kind: item.kind, key: item.key, size: 18)
            Text(ItemDisplayHelper.cleanDisplayName(key: item.key, kind: item.kind, rawName: item.displayName))
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                coordinator.removeDeclaredItem(item, tracker: tracker)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.chross)
            .help("Ne plus suivre")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .background(Theme.surfaceRaised, in: Capsule())
    }

    // MARK: - Activité en direct (running)

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Activité en direct").font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("Mis à jour en direct").font(.caption).foregroundStyle(Theme.textTertiary)
            }

            if tracker.liveUsage.isEmpty {
                Text("En attente de la première activité…")
                    .font(.callout)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 8)
            } else {
                let entries = legendEntries
                StackedBar(segments: entries.map { ($0.seconds, $0.color) })
                    .frame(height: 10)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(Array(trackedLiveUsage.enumerated()), id: \.element.id) { index, record in
                        liveUsageCard(record, color: Theme.seriesColor(at: index))
                    }
                    if tracker.liveOutOfScopeSeconds > 0 {
                        specialUsageCard(
                            title: "Hors sélection",
                            subtitle: liveOutOfScopeSubtitle,
                            seconds: tracker.liveOutOfScopeSeconds,
                            color: Color.white.opacity(0.25),
                            iconSystemName: "slash.circle"
                        )
                    }
                    if tracker.liveIdleSeconds > 0 {
                        specialUsageCard(
                            title: "Inactif",
                            subtitle: "Pauses d'inactivité",
                            seconds: tracker.liveIdleSeconds,
                            color: Color.white.opacity(0.12),
                            iconSystemName: "moon.fill"
                        )
                    }
                }
            }
        }
        .chrossCard()
    }

    private func liveUsageCard(_ record: UsageRecord, color: Color) -> some View {
        let cleanName = ItemDisplayHelper.cleanDisplayName(key: record.key, kind: record.kind, rawName: record.displayName)
        let totalElapsed = max(1, tracker.elapsed)
        let percentage = Int((record.seconds / totalElapsed) * 100)

        return HStack(spacing: 10) {
            ItemIconView(kind: record.kind, key: record.key, size: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text(cleanName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(record.kind == .website ? "Web" : "App")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                    if !record.isDeclared {
                        Text("· Hors sélection")
                            .font(.caption2)
                            .foregroundStyle(.orange.opacity(0.85))
                    }
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text(DurationFormatter.formatShort(record.seconds))
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(percentage)%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.border)
        )
    }

    private func specialUsageCard(title: String, subtitle: String, seconds: TimeInterval, color: Color, iconSystemName: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color)
                    .frame(width: 24, height: 24)
                Image(systemName: iconSystemName)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text(title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 6)

            Text(DurationFormatter.formatShort(seconds))
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.border)
        )
    }

    /// Untracked apps/sites are folded into the single "Hors sélection" card.
    private var trackedLiveUsage: [UsageRecord] {
        tracker.liveUsage.filter(\.isDeclared)
    }

    private var liveOutOfScopeSubtitle: String {
        let count = tracker.liveUsage.filter { !$0.isDeclared }.count
        switch count {
        case 0, 1: return "Apps/sites non suivis"
        default: return "\(count) apps/sites non suivis"
        }
    }

    private struct LegendEntry {
        let label: String
        let seconds: TimeInterval
        let color: Color
    }

    private var legendEntries: [LegendEntry] {
        var entries: [LegendEntry] = []
        for (index, record) in trackedLiveUsage.enumerated() {
            let clean = ItemDisplayHelper.cleanDisplayName(key: record.key, kind: record.kind, rawName: record.displayName)
            entries.append(LegendEntry(label: clean, seconds: record.seconds, color: Theme.seriesColor(at: index)))
        }
        if tracker.liveOutOfScopeSeconds > 0 {
            entries.append(LegendEntry(label: "Hors sélection", seconds: tracker.liveOutOfScopeSeconds, color: Color.white.opacity(0.25)))
        }
        if tracker.liveIdleSeconds > 0 {
            entries.append(LegendEntry(label: "Inactif", seconds: tracker.liveIdleSeconds, color: Color.white.opacity(0.12)))
        }
        return entries
    }

    // MARK: - Bottom row (idle)

    private var bottomRow: some View {
        HStack(alignment: .top, spacing: 20) {
            recentProjectsCard
                .frame(maxWidth: .infinity, alignment: .leading)
            todayCard
                .frame(width: 280)
        }
    }

    private var recentProjectsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Reprendre un projet").font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Tout voir") { selectedScreen = .history }
                    .buttonStyle(.chross)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.bottom, 12)

            if recentProjects.isEmpty {
                Text("Aucun projet récent.")
                    .font(.callout)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentProjects.enumerated()), id: \.element.id) { index, session in
                        if index > 0 {
                            Divider().background(Theme.border)
                        }
                        recentProjectRow(session)
                    }
                }
            }
        }
        .chrossCard()
    }

    private func recentProjectRow(_ session: WorkSession) -> some View {
        HStack(spacing: 12) {
            initialBadge(for: session.projectName)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName).font(.headline).foregroundStyle(Theme.textPrimary)
                Text("\(relativeDay(session.startDate)) · \(appNames(session))")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(DurationFormatter.formatShort(session.activeSeconds))
                .font(.callout.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            Button {
                resume(session)
            } label: {
                Image(systemName: "play.fill")
                    .font(.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(Theme.surfaceRaised, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.border))
            }
            .buttonStyle(.chross)
            .disabled(tracker.isRunning)
        }
        .padding(.vertical, 10)
    }

    private func initialBadge(for name: String) -> some View {
        let letter = name.first.map(String.init)?.uppercased() ?? "?"
        let color = Theme.seriesColor(at: abs(name.hashValue) % Theme.seriesColors.count)
        return Text(letter)
            .font(.headline)
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func relativeDay(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Aujourd'hui" }
        if Calendar.current.isDateInYesterday(date) { return "Hier" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: date)
    }

    private func appNames(_ session: WorkSession) -> String {
        let names = session.declaredItems.prefix(2).map { item in
            ItemDisplayHelper.cleanDisplayName(key: item.key, kind: item.kind, rawName: item.displayName)
        }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    private func resume(_ session: WorkSession) {
        guard !tracker.isRunning else { return }
        coordinator.startSession(
            tracker: tracker,
            projectName: session.projectName,
            declaredItems: session.declaredItems,
            idleThresholdMinutes: defaultIdleMinutes,
            modelContext: modelContext
        )
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Aujourd'hui").font(.headline).foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Temps suivi").font(.caption).foregroundStyle(Theme.textSecondary)
                Text(DurationFormatter.format(todaysActiveSeconds))
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sessions").font(.caption).foregroundStyle(Theme.textSecondary)
                    Text("\(todaysSessions.count)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Facturé TTC").font(.caption).foregroundStyle(Theme.textSecondary)
                    Text(todaysBilledTotalFormatted)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .chrossCard()
    }

    private var todaysActiveSeconds: TimeInterval {
        todaysSessions.reduce(0) { $0 + $1.activeSeconds }
    }

    private var todaysBilledTotalFormatted: String {
        let billedSessions = todaysSessions.compactMap { session -> (Decimal, String)? in
            guard let total = session.billedTotal, let billing = session.billing else { return nil }
            return (total, billing.currencyCode)
        }
        guard let currencyCode = billedSessions.first?.1 else { return "—" }
        let total = billedSessions.reduce(Decimal(0)) { $0 + $1.0 }
        return CurrencyFormatter.format(total, currencyCode: currencyCode)
    }
}

#Preview("En cours") {
    let container = try! ModelContainer(for: WorkSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let tracker = ActivityTracker()
    let coordinator = SessionCoordinator()
    coordinator.startSession(
        tracker: tracker,
        projectName: "Refonte site — Client A",
        declaredItems: [TrackedItem(kind: .app, key: "com.apple.dt.Xcode", displayName: "Xcode")],
        idleThresholdMinutes: 5,
        modelContext: container.mainContext
    )

    return ContentView()
        .environment(tracker)
        .environment(coordinator)
        .modelContainer(container)
        .preferredColorScheme(.dark)
}

#Preview("Prêt") {
    let container = try! ModelContainer(for: WorkSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let a = WorkSession(projectName: "Refonte site — Client A", startDate: Date().addingTimeInterval(-3600), declaredItems: [])
    a.activeSeconds = 5100
    a.endDate = Date()
    a.billing = .defaultSettings
    a.billedTotal = 85
    let b = WorkSession(projectName: "App mobile — Client B", startDate: Date().addingTimeInterval(-90000), declaredItems: [])
    b.activeSeconds = 11400
    b.endDate = Date().addingTimeInterval(-86000)
    container.mainContext.insert(a)
    container.mainContext.insert(b)

    return ContentView()
        .environment(ActivityTracker())
        .environment(SessionCoordinator())
        .modelContainer(container)
        .preferredColorScheme(.dark)
}

/// A single rounded, proportionally-segmented bar — the "Activité en direct" /
/// "Chronologie" composition visual shared across the chrono and history screens.
struct StackedBar: View {
    let segments: [(seconds: TimeInterval, color: Color)]

    var body: some View {
        GeometryReader { proxy in
            let total = max(segments.reduce(0) { $0 + $1.seconds }, 1)
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(segment.color)
                        .frame(width: proxy.size.width * (segment.seconds / total))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
