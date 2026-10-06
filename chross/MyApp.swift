import SwiftData
import SwiftUI

@main
struct MyApp: App {
    @State private var tracker = ActivityTracker()
    @State private var coordinator = SessionCoordinator()
    /// Owned by the app, not the window, so reminders keep working with the window closed.
    @State private var workReminder = WorkReminder()
    @AppStorage(AppPreferences.showMenuBarExtraKey) private var showMenuBarExtra = true

    /// One container shared by every window, so the end-of-session window and the main
    /// window always see the same data immediately.
    private let modelContainer: ModelContainer = {
        #if DEBUG
        if DemoMode.isActive {
            return DemoData.makeContainer()
        }
        #endif
        do {
            return try ModelContainer(for: WorkSession.self, Preset.self, FavoriteItem.self)
        } catch {
            fatalError("Impossible d'ouvrir la base de données chross : \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup(id: ContentView.windowID) {
            ContentView()
                .environment(tracker)
                .environment(coordinator)
                .environment(workReminder)
                .preferredColorScheme(.dark)
        }
        .modelContainer(modelContainer)

        WindowGroup("Résumé de session", id: SessionSummaryWindow.id, for: PersistentIdentifier.self) { $sessionID in
            SessionSummaryWindow(sessionID: sessionID)
                .environment(tracker)
                .environment(coordinator)
                .preferredColorScheme(.dark)
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1040, height: 780)
        .windowResizability(.contentMinSize)

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarView(tracker: tracker, coordinator: coordinator)
        } label: {
            if tracker.isRunning {
                Text(DurationFormatter.format(tracker.elapsed))
                    .monospacedDigit()
            } else {
                Image(systemName: "timer")
            }
        }
    }
}
