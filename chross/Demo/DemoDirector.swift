#if DEBUG
import AppKit
import SwiftData
import SwiftUI

/// Plays one README scenario: sets the stage, tells the recorder what to capture, waits for
/// it to start, then performs the interactions with real mouse events.
@MainActor
enum DemoDirector {
    struct Stage {
        let tracker: ActivityTracker
        let coordinator: SessionCoordinator
        let modelContext: ModelContext
        let setScreen: (ContentScreen) -> Void
    }

    private static var didStart = false

    static func run(_ stage: Stage) async {
        guard DemoMode.isActive, !didStart else { return }
        didStart = true
        DemoMode.log("scenario \(DemoMode.scenario) starting")
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .seconds(1))

        switch DemoMode.scenario {
        case "timeline": await timeline(stage)
        case "retime": await retime(stage)
        case "sidebar": await sidebar(stage)
        case "onboarding": await onboarding(stage)
        default: await live(stage)
        }
        write("done")
    }

    // MARK: - Scenarios

    private static func live(_ stage: Stage) async {
        stage.setScreen(.chrono)
        stage.coordinator.startSession(
            tracker: stage.tracker,
            projectName: DemoData.featuredProject,
            declaredItems: [DemoData.figma, DemoData.vscode, DemoData.github, DemoData.tailwind],
            idleThresholdMinutes: 0,
            modelContext: stage.modelContext
        )
        let usage = [
            record(DemoData.figma, 52 * 60, true),
            record(DemoData.vscode, 41 * 60, true),
            record(DemoData.github, 14 * 60, true),
            record(DemoData.tailwind, 6 * 60, true),
        ]
        stage.tracker.applyDemoState(
            startedAgo: 2 * 3600 + 14 * 60,
            usage: usage,
            idleSeconds: 3 * 60,
            outOfScopeSeconds: 4 * 60,
            script: [
                DemoData.vscode, DemoData.figma,
                TrackedItem(kind: .website, key: "youtube.com", displayName: "youtube.com"),
                DemoData.github,
            ]
        )
        guard let window = mainWindow() else { return }
        await record(window, size: CGSize(width: 1240, height: 860))

        await DemoMouse.move(to: center(of: window).offset(dx: 120, dy: -40), duration: 1.2)
        try? await Task.sleep(for: .seconds(13))
    }

    private static func timeline(_ stage: Stage) async {
        guard let window = await openFeaturedSummary(stage) else { return }
        await record(window, size: CGSize(width: 1120, height: 820))

        guard let bar = DemoAnchors.shared.screenRect("timelineBar") else { return }
        await DemoMouse.move(to: CGPoint(x: bar.minX + 6, y: bar.minY + 14), duration: 1)
        for fraction in [0.12, 0.36, 0.55, 0.68, 0.78, 0.86, 0.95] {
            await DemoMouse.move(to: CGPoint(x: bar.minX + bar.width * fraction, y: bar.minY + 14), duration: 0.6)
            try? await Task.sleep(for: .seconds(1.1))
        }
        await DemoMouse.move(to: CGPoint(x: bar.midX, y: bar.maxY + 160), duration: 0.8)
        try? await Task.sleep(for: .seconds(1.5))
    }

    private static func retime(_ stage: Stage) async {
        guard let window = await openFeaturedSummary(stage) else { return }
        await record(window, size: CGSize(width: 1120, height: 900))

        guard let button = DemoAnchors.shared.screenRect("summary.retime") else { return }
        await DemoMouse.click(at: CGPoint(x: button.midX, y: button.midY))
        try? await Task.sleep(for: .seconds(1.4))

        if let start = DemoAnchors.shared.screenRect("editor.start") {
            let from = CGPoint(x: start.midX, y: start.midY + 20)
            await DemoMouse.drag(from: from, to: from.offset(dx: -62, dy: 0), duration: 1.1)
            try? await Task.sleep(for: .seconds(0.8))
        }
        if let track = DemoAnchors.shared.screenRect("editor.track") {
            let y = track.midY
            await DemoMouse.drag(
                from: CGPoint(x: track.minX + track.width * 0.47, y: y),
                to: CGPoint(x: track.minX + track.width * 0.555, y: y),
                duration: 1.3
            )
            try? await Task.sleep(for: .seconds(0.8))
        }
        if let end = DemoAnchors.shared.screenRect("editor.end") {
            let from = CGPoint(x: end.midX, y: end.midY + 20)
            await DemoMouse.drag(from: from, to: from.offset(dx: -48, dy: 0), duration: 1)
            try? await Task.sleep(for: .seconds(1.6))
        }
        if let apply = DemoAnchors.shared.screenRect("editor.apply") {
            await DemoMouse.move(to: CGPoint(x: apply.midX, y: apply.midY), duration: 0.9)
            try? await Task.sleep(for: .seconds(1.2))
            await DemoMouse.click(at: CGPoint(x: apply.midX, y: apply.midY))
        }
        try? await Task.sleep(for: .seconds(2.5))
    }

    private static func sidebar(_ stage: Stage) async {
        stage.setScreen(.chrono)
        guard let window = mainWindow() else { return }
        await record(window, size: CGSize(width: 1240, height: 820))

        if let favoris = DemoAnchors.shared.screenRect("sidebar.favoris"),
           let history = DemoAnchors.shared.screenRect("sidebar.history") {
            await DemoMouse.drag(
                from: CGPoint(x: favoris.midX, y: favoris.midY),
                to: CGPoint(x: history.midX, y: history.minY + 6),
                duration: 1.6
            )
            try? await Task.sleep(for: .seconds(1.4))
        }
        for anchor in ["sidebar.favoris", "sidebar.reglages", "settings.sidebar"] {
            if let rect = DemoAnchors.shared.screenRect(anchor) {
                await DemoMouse.click(at: CGPoint(x: rect.midX, y: rect.midY))
                try? await Task.sleep(for: .seconds(2.2))
            }
        }
        try? await Task.sleep(for: .seconds(1.5))
    }

    private static func onboarding(_ stage: Stage) async {
        guard let window = mainWindow() else { return }
        await record(window, size: CGSize(width: 1100, height: 800))

        try? await Task.sleep(for: .seconds(2.5))
        for pause in [2.8, 2.8, 3.2] {
            if let next = DemoAnchors.shared.screenRect("onboarding.next") {
                await DemoMouse.click(at: CGPoint(x: next.midX, y: next.midY))
            }
            try? await Task.sleep(for: .seconds(pause))
        }
        if let next = DemoAnchors.shared.screenRect("onboarding.next") {
            await DemoMouse.click(at: CGPoint(x: next.midX, y: next.midY))
        }
        try? await Task.sleep(for: .seconds(3))
    }

    // MARK: - Stage helpers

    private static func openFeaturedSummary(_ stage: Stage) async -> NSWindow? {
        stage.setScreen(.history)
        let descriptor = FetchDescriptor<WorkSession>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        let sessions = (try? stage.modelContext.fetch(descriptor)) ?? []
        guard let featured = sessions.first(where: { $0.projectName == DemoData.featuredProject }) else {
            DemoMode.log("featured session not found among \(sessions.count)")
            return nil
        }
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        stage.coordinator.summarySession = featured
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(100))
            // The summary opens as a new window — don't rely on its title.
            if let window = NSApp.windows.first(where: {
                !existing.contains(ObjectIdentifier($0)) && $0.isVisible && $0.canBecomeKey
            }) {
                DemoMode.log("summary window found: \(window.title)")
                return window
            }
        }
        DemoMode.log("summary window not found; windows: \(NSApp.windows.map { "\($0.title) visible=\($0.isVisible)" })")
        return nil
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    }

    /// Places the window, hands its area to the recorder and waits for recording to begin.
    private static func record(_ window: NSWindow, size: CGSize) async {
        let screen = NSScreen.screens.first?.visibleFrame ?? .zero
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.maxY
        let origin = CGPoint(x: screen.minX + 40, y: screen.maxY - 30 - size.height)
        window.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .seconds(1.2))

        let frame = window.frame
        DemoMode.log("recording window \(NSStringFromRect(frame))")
        let topLeftY = mainHeight - frame.maxY
        write("rect", "\(Int(frame.minX)),\(Int(topLeftY)),\(Int(frame.width)),\(Int(frame.height))")
        await waitFor("go")
        try? await Task.sleep(for: .seconds(0.8))
    }

    private static func center(of window: NSWindow) -> CGPoint {
        let mainHeight = NSScreen.screens.first?.frame.height ?? window.frame.maxY
        return CGPoint(x: window.frame.midX, y: mainHeight - window.frame.midY)
    }

    private static func record(_ item: TrackedItem, _ seconds: TimeInterval, _ declared: Bool) -> UsageRecord {
        UsageRecord(kind: item.kind, key: item.key, displayName: item.displayName, seconds: seconds, isDeclared: declared)
    }

    private static func write(_ name: String, _ contents: String = "") {
        guard let directory = DemoMode.outputDirectory else { return }
        try? contents.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private static func waitFor(_ name: String) async {
        guard let directory = DemoMode.outputDirectory else { return }
        let url = directory.appendingPathComponent(name)
        for _ in 0..<300 where !FileManager.default.fileExists(atPath: url.path) {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}

private extension CGPoint {
    func offset(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }
}
#endif
