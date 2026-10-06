import AppKit
import SwiftUI

// Tooling used to record the README videos. Everything that does something lives behind
// `#if DEBUG`, so Release builds only keep the no-op `demoAnchor` modifier.
//
// Recorded with scripts/record-demo.sh, which launches a Debug build with:
//   -ChrossDemo -ChrossDemoScenario <live|timeline|retime|sidebar|onboarding> -ChrossDemoOutput <dir>
// The app then uses an in-memory store filled with sample data (the real store is never
// opened), lays out its window, writes `<dir>/rect` (the screen area to record), waits for
// `<dir>/go`, plays the scenario with real mouse events and writes `<dir>/done`.

extension View {
    /// Marks a view so demo scenarios can find it on screen. No-op outside Debug demo runs.
    func demoAnchor(_ id: String) -> some View {
        #if DEBUG
        background(DemoAnchorRepresentable(id: id))
        #else
        self
        #endif
    }
}

#if DEBUG
enum DemoMode {
    static let isActive = CommandLine.arguments.contains("-ChrossDemo")

    static var scenario: String {
        value(after: "-ChrossDemoScenario") ?? "live"
    }

    static var outputDirectory: URL? {
        value(after: "-ChrossDemoOutput").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Appends a line to `<output>/log` — the system log redacts or drops these.
    static func log(_ message: String) {
        guard let directory = outputDirectory else { return }
        let url = directory.appendingPathComponent("log")
        let line = "\(Date().formatted(.dateTime.hour().minute().second())) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func value(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

// MARK: - Anchors

@MainActor
final class DemoAnchors {
    static let shared = DemoAnchors()
    private var views: [String: WeakView] = [:]

    private struct WeakView { weak var view: NSView? }

    func register(_ view: NSView, id: String) {
        views[id] = WeakView(view: view)
    }

    /// The anchor's frame in Quartz screen coordinates (origin at the top-left of the main display).
    func screenRect(_ id: String) -> CGRect? {
        guard let view = views[id]?.view, let window = view.window else { return nil }
        let inWindow = view.convert(view.bounds, to: nil)
        let onScreen = window.convertToScreen(inWindow)
        let mainHeight = NSScreen.screens.first?.frame.height ?? onScreen.maxY
        return CGRect(x: onScreen.minX, y: mainHeight - onScreen.maxY, width: onScreen.width, height: onScreen.height)
    }
}

private final class DemoAnchorView: NSView {
    var anchorID = ""

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        MainActor.assumeIsolated {
            DemoAnchors.shared.register(self, id: anchorID)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct DemoAnchorRepresentable: NSViewRepresentable {
    let id: String

    func makeNSView(context: Context) -> NSView {
        let view = DemoAnchorView()
        view.anchorID = id
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DemoAnchorView)?.anchorID = id
        if nsView.window != nil {
            DemoAnchors.shared.register(nsView, id: id)
        }
    }
}

// MARK: - Mouse

/// Drives the real cursor with synthesized events (chross holds the Accessibility permission).
enum DemoMouse {
    private static var position: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    static func move(to target: CGPoint, duration: TimeInterval = 0.7) async {
        let start = position
        let steps = max(1, Int(duration * 60))
        for step in 1...steps {
            let t = easeInOut(Double(step) / Double(steps))
            let point = CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t)
            post(.mouseMoved, at: point)
            try? await Task.sleep(for: .seconds(duration / Double(steps)))
        }
    }

    static func click(at point: CGPoint) async {
        await move(to: point)
        try? await Task.sleep(for: .milliseconds(120))
        post(.leftMouseDown, at: point)
        try? await Task.sleep(for: .milliseconds(90))
        post(.leftMouseUp, at: point)
    }

    /// Posted from a background thread: a drag & drop runs a modal tracking loop on the main
    /// thread, which would otherwise freeze the very task that has to finish the drag.
    static func drag(from start: CGPoint, to end: CGPoint, duration: TimeInterval = 1.2) async {
        await move(to: start)
        await Task.detached {
            Thread.sleep(forTimeInterval: 0.15)
            post(.leftMouseDown, at: start)
            // Press, hold, then nudge — SwiftUI only starts a drag & drop after a held press
            // followed by a few small moves.
            Thread.sleep(forTimeInterval: 0.6)
            for nudge in 1...6 {
                post(.leftMouseDragged, at: CGPoint(x: start.x + CGFloat(nudge), y: start.y + CGFloat(nudge)))
                Thread.sleep(forTimeInterval: 0.03)
            }
            let steps = max(1, Int(duration * 60))
            for step in 1...steps {
                let t = easeInOut(Double(step) / Double(steps))
                let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
                post(.leftMouseDragged, at: point)
                Thread.sleep(forTimeInterval: duration / Double(steps))
            }
            Thread.sleep(forTimeInterval: 0.25)
            post(.leftMouseUp, at: end)
        }.value
    }

    nonisolated private static func post(_ type: CGEventType, at point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    nonisolated private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
}
#endif
