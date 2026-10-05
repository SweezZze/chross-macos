import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ActivityTracker.self) private var tracker
    @Environment(SessionCoordinator.self) private var coordinator
    @Query(sort: \WorkSession.startDate, order: .reverse) private var sessions: [WorkSession]

    @State private var hoveredSession: WorkSession?
    @State private var sessionToDelete: WorkSession?
    @State private var sessionToRetime: WorkSession?
    /// The session opened from the list. Plain state (not a NavigationStack push) so that
    /// switching sidebar tabs always shows the new tab instead of a leftover detail page.
    @State private var openedSession: WorkSession?

    var body: some View {
        Group {
            if let openedSession, sessions.contains(openedSession) {
                SessionSummaryView(session: openedSession, showBreadcrumb: true) {
                    self.openedSession = nil
                }
            } else {
                Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "Aucune session enregistrée",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Tes sessions de travail terminées apparaîtront ici.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(sessions) { session in
                                Button {
                                    openedSession = session
                                } label: {
                                    row(session)
                                }
                                .buttonStyle(.chross)
                                .onHover { hovering in
                                    if hovering {
                                        hoveredSession = session
                                    } else if hoveredSession == session {
                                        hoveredSession = nil
                                    }
                                }
                                .contextMenu {
                                    Button("Corriger les horaires…") {
                                        sessionToRetime = session
                                    }
                                    Divider()
                                    Button("Supprimer…", role: .destructive) {
                                        sessionToDelete = session
                                    }
                                }
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .background(Theme.page)
            .toolbar {
                ToolbarItem {
                    Button(action: exportCSV) {
                        Label("Exporter en CSV", systemImage: "arrow.down.doc")
                    }
                    .disabled(sessions.isEmpty)
                }
            }
            }
        }
        .navigationTitle("Historique")
            .sheet(item: $sessionToRetime) { session in
                SessionTimeEditView(session: session)
            }
            .confirmationDialog(
                "Supprimer cette session ?",
                isPresented: Binding(
                    get: { sessionToDelete != nil },
                    set: { if !$0 { sessionToDelete = nil } }
                ),
                presenting: sessionToDelete
            ) { session in
                Button("Supprimer", role: .destructive) {
                    coordinator.deleteSession(session, tracker: tracker, modelContext: modelContext)
                    sessionToDelete = nil
                }
                Button("Annuler", role: .cancel) {
                    sessionToDelete = nil
                }
            } message: { session in
                Text("« \(session.projectName.isEmpty ? "Session sans titre" : session.projectName) » sera définitivement retirée de l'historique.")
            }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "chross-historique.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? CSVExporter.export(sessions).write(to: url, atomically: true, encoding: .utf8)
    }

    private func row(_ session: WorkSession) -> some View {
        HStack(spacing: 12) {
            let letter = session.projectName.first.map(String.init)?.uppercased() ?? "?"
            let color = Theme.seriesColor(at: abs(session.projectName.hashValue) % Theme.seriesColors.count)
            Text(letter)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName.isEmpty ? "Session sans titre" : session.projectName)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 6) {
                    if session.timeAdjusted {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .help("Horaires corrigés")
                    }
                    Text(session.startDate.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "fr_FR"))))
                    Text("·")
                    Text(DurationFormatter.format(session.activeSeconds)).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if let total = session.billedTotal, let billing = session.billing {
                Text(CurrencyFormatter.format(total, currencyCode: billing.currencyCode))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }

            Button {
                sessionToDelete = session
            } label: {
                Image(systemName: "trash")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.chross)
            .help("Supprimer la session")
            .opacity(hoveredSession == session ? 1 : 0)
            .allowsHitTesting(hoveredSession == session)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(16)
        .chrossCard(padding: 0, radius: 16)
    }
}

#Preview {
    let container = try! ModelContainer(for: WorkSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let a = WorkSession(projectName: "Refonte site — Client A", startDate: Date().addingTimeInterval(-5000), declaredItems: [])
    a.activeSeconds = 4632
    a.endDate = Date()
    a.billing = BillingSettings(hourlyRate: 50, currencyCode: "EUR", rounding: .fiveMinutes, vatEnabled: true, vatRatePercent: 20, billingBase: .totalDuration)
    a.billedTotal = 85
    let b = WorkSession(projectName: "App mobile — Client B", startDate: Date().addingTimeInterval(-90000), declaredItems: [])
    b.activeSeconds = 11400
    b.endDate = Date().addingTimeInterval(-86000)
    container.mainContext.insert(a)
    container.mainContext.insert(b)

    return HistoryView()
        .environment(ActivityTracker())
        .environment(SessionCoordinator())
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
