import SwiftData
import SwiftUI

/// Hosts `SessionSummaryView` in its own resizable window, opened when a session ends.
/// Looks the session up through a query so the window closes itself if it gets deleted.
struct SessionSummaryWindow: View {
    static let id = "session-summary"

    let sessionID: PersistentIdentifier?

    @Environment(\.dismiss) private var dismiss
    @Query private var sessions: [WorkSession]

    private var session: WorkSession? {
        guard let sessionID else { return nil }
        return sessions.first { $0.persistentModelID == sessionID }
    }

    var body: some View {
        Group {
            if let session {
                SessionSummaryView(session: session, isStandaloneWindow: true)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear { dismiss() }
            }
        }
        .background(Theme.page)
    }
}
