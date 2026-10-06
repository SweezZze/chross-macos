#if DEBUG
import Foundation
import SwiftData

/// Fictional projects, favorites and sessions for the README recordings — written to an
/// in-memory store only, never to the user's real data.
@MainActor
enum DemoData {
    static let featuredProject = "Refonte site — Atelier Lumen"

    static let figma = TrackedItem(kind: .website, key: "figma.com", displayName: "figma.com")
    static let vscode = TrackedItem(kind: .app, key: "com.microsoft.VSCode", displayName: "Visual Studio Code")
    static let xcode = TrackedItem(kind: .app, key: "com.apple.dt.Xcode", displayName: "Xcode")
    static let notion = TrackedItem(kind: .app, key: "notion.id", displayName: "Notion")
    static let github = TrackedItem(kind: .website, key: "github.com", displayName: "github.com")
    static let appleDev = TrackedItem(kind: .website, key: "developer.apple.com", displayName: "developer.apple.com")
    static let stackOverflow = TrackedItem(kind: .website, key: "stackoverflow.com", displayName: "stackoverflow.com")
    static let tailwind = TrackedItem(kind: .website, key: "tailwindcss.com", displayName: "tailwindcss.com")

    static let billing = BillingSettings(
        hourlyRate: 55,
        currencyCode: "EUR",
        rounding: .fiveMinutes,
        vatEnabled: true,
        vatRatePercent: 20,
        billingBase: .totalDuration
    )

    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: WorkSession.self, Preset.self, FavoriteItem.self, configurations: configuration)
        seed(container.mainContext)
        // Permanent IDs: the summary window looks its session up by ID.
        try? container.mainContext.save()
        return container
    }

    private static func seed(_ context: ModelContext) {
        let lumenItems = [figma, vscode, github, tailwind]
        let appItems = [xcode, github, appleDev, stackOverflow]

        context.insert(Preset(name: "Atelier Lumen", projectName: featuredProject, declaredItems: lumenItems, idleThresholdMinutes: 5, applyBilling: true, billing: billing))
        context.insert(Preset(name: "App iOS — Boulangerie Martin", projectName: "App iOS — Boulangerie Martin", declaredItems: appItems, idleThresholdMinutes: 5, applyBilling: true, billing: billing))
        context.insert(Preset(name: "Docs internes", projectName: "Documentation", declaredItems: [notion], idleThresholdMinutes: 10, applyBilling: false, billing: billing))

        for item in [figma, github, tailwind, appleDev, stackOverflow] {
            context.insert(FavoriteItem(kind: item.kind, key: item.key, displayName: item.displayName))
        }
        let terminal = TrackedItem(kind: .app, key: "com.apple.Terminal", displayName: "Terminal")
        for item in [vscode, notion, terminal] {
            context.insert(FavoriteItem(kind: item.kind, key: item.key, displayName: item.displayName))
        }

        // The session the summary / retime videos open: yesterday 9:05 → 17:40.
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let featured = session(
            featuredProject,
            start: calendar.date(bySettingHour: 9, minute: 5, second: 0, of: yesterday) ?? yesterday,
            end: calendar.date(bySettingHour: 17, minute: 40, second: 0, of: yesterday) ?? yesterday,
            declared: lumenItems,
            usage: [
                (figma, TimeInterval(2 * 3600 + 35 * 60), true),
                (vscode, TimeInterval(2 * 3600 + 5 * 60), true),
                (github, TimeInterval(50 * 60), true),
                (tailwind, TimeInterval(32 * 60), true),
                (TrackedItem(kind: .website, key: "youtube.com", displayName: "youtube.com"), TimeInterval(18 * 60), false),
                (TrackedItem(kind: .app, key: "com.hnc.Discord", displayName: "Discord"), TimeInterval(12 * 60), false),
                (TrackedItem(kind: .app, key: "com.apple.mail", displayName: "Mail"), TimeInterval(6 * 60), false),
            ],
            idle: 58 * 60,
            billed: true
        )
        featured.tags = ["design", "front-end"]
        featured.notes = "Maquettes de la page d'accueil validées, intégration du header et du menu."
        context.insert(featured)

        let history: [(String, Int, Int, Int, [TrackedItem], Bool)] = [
            ("App iOS — Boulangerie Martin", 0, 9, 12, appItems, true),
            ("App iOS — Boulangerie Martin", 2, 14, 18, appItems, true),
            (featuredProject, 3, 9, 13, lumenItems, true),
            ("Documentation", 4, 16, 17, [notion], false),
            ("App iOS — Boulangerie Martin", 6, 10, 17, appItems, true),
            (featuredProject, 8, 13, 18, lumenItems, true),
        ]
        for (name, daysAgo, startHour, endHour, items, billed) in history {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
            let start = calendar.date(bySettingHour: startHour, minute: 10, second: 0, of: day) ?? day
            let end = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: day) ?? day
            let total = end.timeIntervalSince(start)
            let usage = items.enumerated().map { index, item in
                (item, total * [0.42, 0.28, 0.14, 0.08][min(index, 3)], true)
            }
            context.insert(session(name, start: start, end: end, declared: items, usage: usage, idle: total * 0.05, billed: billed))
        }
    }

    private static func session(
        _ name: String,
        start: Date,
        end: Date,
        declared: [TrackedItem],
        usage: [(TrackedItem, TimeInterval, Bool)],
        idle: TimeInterval,
        billed: Bool
    ) -> WorkSession {
        let session = WorkSession(projectName: name, startDate: start, declaredItems: declared)
        session.endDate = end
        session.usage = usage.map { item, seconds, declared in
            UsageRecord(kind: item.kind, key: item.key, displayName: item.displayName, seconds: seconds, isDeclared: declared)
        }
        session.activeSeconds = usage.filter(\.2).reduce(0) { $0 + $1.1 }
        session.outOfScopeSeconds = usage.filter { !$0.2 }.reduce(0) { $0 + $1.1 }
        session.idleSeconds = idle
        if billed {
            session.billing = billing
            session.billedTotal = BillingCalculator.calculate(activeSeconds: session.activeSeconds, usage: session.usage, settings: billing).total
        }
        return session
    }
}
#endif
