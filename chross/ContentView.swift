import SwiftData
import SwiftUI

enum ContentScreen: String, CaseIterable, Identifiable {
    case chrono = "Chrono"
    case history = "Historique"
    case presets = "Projets"
    case favoris = "Favoris"
    case rapports = "Rapports"
    case reglages = "Réglages"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chrono: return "timer"
        case .history: return "clock.arrow.circlepath"
        case .presets: return "folder"
        case .favoris: return "star"
        case .rapports: return "chart.bar.xaxis"
        case .reglages: return "slider.horizontal.3"
        }
    }

    /// Nav items rendered in the main sidebar list — `reglages` gets its own row below.
    static var primary: [ContentScreen] { [.chrono, .history, .presets, .favoris, .rapports] }

    /// Stable identifier for persisting the sidebar layout (labels may change, these won't).
    var storageKey: String {
        switch self {
        case .chrono: return "chrono"
        case .history: return "history"
        case .presets: return "presets"
        case .favoris: return "favoris"
        case .rapports: return "rapports"
        case .reglages: return "reglages"
        }
    }

    /// The timer is the heart of the app — it can be moved but never hidden.
    var canBeHidden: Bool { self != .chrono }
}

/// The user's sidebar arrangement, stored as comma-separated keys in UserDefaults.
enum SidebarLayout {
    static func order(from stored: String) -> [ContentScreen] {
        let saved = stored.split(separator: ",").compactMap { key in
            ContentScreen.primary.first { $0.storageKey == key }
        }
        // Tabs added in a later version show up at the end instead of disappearing.
        return saved + ContentScreen.primary.filter { !saved.contains($0) }
    }

    static func hidden(from stored: String) -> Set<ContentScreen> {
        Set(stored.split(separator: ",").compactMap { key in
            ContentScreen.primary.first { $0.storageKey == key && $0.canBeHidden }
        })
    }

    static func encode(_ screens: [ContentScreen]) -> String {
        screens.map(\.storageKey).joined(separator: ",")
    }

    static func encode(_ screens: Set<ContentScreen>) -> String {
        encode(ContentScreen.primary.filter { screens.contains($0) })
    }
}

struct ContentView: View {
    static let windowID = "main"

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(ActivityTracker.self) private var tracker
    @Environment(SessionCoordinator.self) private var coordinator
    @Environment(WorkReminder.self) private var workReminder
    @Query(sort: \WorkSession.startDate, order: .reverse) private var sessions: [WorkSession]
    @AppStorage(AppPreferences.dailyGoalHoursKey) private var dailyGoalHours: Double = AppPreferences.defaultDailyGoalHours

    @State private var selectedScreen: ContentScreen? = .chrono
    @State private var hoveredScreen: ContentScreen?
    @State private var dropTargetScreen: ContentScreen?
    @State private var isEndDropTargeted = false
    @AppStorage(AppPreferences.sidebarOrderKey) private var sidebarOrder = ""
    @AppStorage(AppPreferences.sidebarHiddenKey) private var sidebarHidden = ""
    @AppStorage(AppPreferences.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @State private var controlServer = LocalControlServer()

    private var todaysActiveSeconds: TimeInterval {
        let persisted = sessions
            .filter { Calendar.current.isDateInToday($0.startDate) }
            .reduce(0) { $0 + $1.activeSeconds }
        return persisted + (tracker.isRunning ? tracker.elapsed : 0)
    }

    var body: some View {
        @Bindable var coordinator = coordinator

        NavigationSplitView {
            sidebar
        } detail: {
            switch selectedScreen {
            case .history:
                HistoryView()
            case .presets:
                PresetsView(selectedScreen: $selectedScreen)
            case .favoris:
                FavoritesView()
            case .reglages:
                SettingsView()
            case .rapports:
                ReportsView()
            default:
                ChronoPane(selectedScreen: $selectedScreen)
            }
        }
        .overlay {
            if !hasCompletedOnboarding {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hasCompletedOnboarding = true
                    }
                }
                .transition(.opacity)
            }
        }
        .task {
            // Site detection reads the browser's address bar through Accessibility — ask up
            // front so tracking works whichever way a session is started.
            // First launch: the introduction asks for permissions one by one instead.
            if hasCompletedOnboarding && !AccessibilityPermission.isGranted {
                AccessibilityPermission.requestIfNeeded()
            }
            coordinator.syncWidgetSnapshot(isRunning: tracker.isRunning, currentSessionStart: tracker.sessionStart, modelContext: modelContext)
            workReminder.start(tracker: tracker, coordinator: coordinator, modelContext: modelContext) {
                openWindow(id: ContentView.windowID)
            }
            controlServer.start(tracker: tracker, coordinator: coordinator, modelContext: modelContext)
        }
        .onChange(of: coordinator.autoFinalizePending) { _, pending in
            if pending {
                coordinator.finalizeAutoSession(modelContext: modelContext)
            }
        }
        .sheet(isPresented: $coordinator.showSetup, onDismiss: { coordinator.setupPrefillItems = [] }) {
            SessionSetupView(initialItems: coordinator.setupPrefillItems) { projectName, declaredItems, idleMinutes in
                coordinator.startSession(
                    tracker: tracker,
                    projectName: projectName,
                    declaredItems: declaredItems,
                    idleThresholdMinutes: idleMinutes,
                    modelContext: modelContext
                )
            }
        }
        .sheet(isPresented: $coordinator.showBillingPrompt) {
            BillingPromptView(
                summary: coordinator.pendingSummary,
                initialSettings: coordinator.lastBillingSettings,
                applyByDefault: coordinator.applyBillingByDefault
            ) { billing in
                coordinator.finalizeSession(billing: billing, modelContext: modelContext)
            }
        }
        .onChange(of: coordinator.summarySession) { _, session in
            guard let session else { return }
            // A real window rather than a sheet: the summary needs room, and opening a sheet
            // while the billing sheet is still closing made SwiftUI drop or glitch it.
            openWindow(id: SessionSummaryWindow.id, value: session.persistentModelID)
            coordinator.summarySession = nil
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "stopwatch.fill")
                    .foregroundStyle(.black)
                    .padding(8)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("Chross").font(.title3.bold()).foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)

            VStack(spacing: 2) {
                ForEach(visibleScreens) { screen in
                    navRow(screen)
                        .draggable(screen.storageKey) {
                            Label(screen.rawValue, systemImage: screen.icon)
                                .padding(8)
                                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .dropDestination(for: String.self) { keys, _ in
                            guard let key = keys.first else { return false }
                            moveScreen(withKey: key, before: screen)
                            return true
                        } isTargeted: { targeted in
                            if targeted {
                                dropTargetScreen = screen
                            } else if dropTargetScreen == screen {
                                dropTargetScreen = nil
                            }
                        }
                        .overlay(alignment: .top) {
                            if dropTargetScreen == screen {
                                Capsule().fill(Theme.accent).frame(height: 2).offset(y: -2)
                            }
                        }
                }

                // Dropping below the last tab moves the dragged one to the end.
                Color.clear
                    .frame(height: 18)
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { keys, _ in
                        guard let key = keys.first else { return false }
                        moveScreen(withKey: key, before: nil)
                        return true
                    } isTargeted: { targeted in
                        isEndDropTargeted = targeted
                    }
                    .overlay(alignment: .top) {
                        if isEndDropTargeted {
                            Capsule().fill(Theme.accent).frame(height: 2)
                        }
                    }
            }
            .padding(.horizontal, 12)

            Spacer()

            todayWidget
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            navRow(.reglages)
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
        }
        .frame(minWidth: 220)
        .background(Theme.sidebar)
    }

    private func navRow(_ screen: ContentScreen) -> some View {
        Button {
            selectedScreen = screen
        } label: {
            HStack(spacing: 10) {
                Image(systemName: screen.icon)
                    .frame(width: 18)
                Text(screen.rawValue)
                Spacer()
                if screen == .chrono && tracker.isRunning {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7)
                }
            }
            .font(.callout.weight(selectedScreen == screen ? .semibold : .regular))
            .foregroundStyle(selectedScreen == screen ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                navRowFill(screen),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .animation(.easeOut(duration: 0.12), value: hoveredScreen)
        }
        .buttonStyle(.chross)
        .onHover { hovering in
            if hovering {
                hoveredScreen = screen
            } else if hoveredScreen == screen {
                hoveredScreen = nil
            }
        }
    }

    private var visibleScreens: [ContentScreen] {
        let hidden = SidebarLayout.hidden(from: sidebarHidden)
        return SidebarLayout.order(from: sidebarOrder).filter { !hidden.contains($0) }
    }

    /// Drag & drop in the sidebar: drops the dragged tab just above the one it's released on.
    private func moveScreen(withKey key: String, before target: ContentScreen?) {
        var order = SidebarLayout.order(from: sidebarOrder)
        guard let moving = order.first(where: { $0.storageKey == key }), moving != target else { return }
        order.removeAll { $0 == moving }
        let index = target.flatMap { order.firstIndex(of: $0) } ?? order.endIndex
        order.insert(moving, at: index)
        withAnimation(.easeOut(duration: 0.15)) {
            sidebarOrder = SidebarLayout.encode(order)
        }
    }

    private func navRowFill(_ screen: ContentScreen) -> Color {
        if selectedScreen == screen { return Color.white.opacity(0.08) }
        if hoveredScreen == screen { return Color.white.opacity(0.04) }
        return .clear
    }

    private var todayWidget: some View {
        let goalSeconds = dailyGoalHours * 3600
        let fraction = goalSeconds > 0 ? min(1, todaysActiveSeconds / goalSeconds) : 0
        let hours = Int(todaysActiveSeconds) / 3600
        let minutes = (Int(todaysActiveSeconds) % 3600) / 60

        return VStack(alignment: .leading, spacing: 10) {
            Text("AUJOURD'HUI")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
            Text("\(hours) h \(String(format: "%02d", minutes))")
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(Theme.accent).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)
            Text("Objectif \(dailyGoalHours.formatted()) h")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border))
    }
}

#Preview {
    ContentView()
        .environment(ActivityTracker())
        .environment(SessionCoordinator())
        .environment(WorkReminder())
        .modelContainer(for: [WorkSession.self, Preset.self, FavoriteItem.self], inMemory: true)
        .preferredColorScheme(.dark)
}
