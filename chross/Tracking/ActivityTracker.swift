import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ActivityTracker {
    struct StopResult {
        let startDate: Date
        let endDate: Date
        let activeSeconds: TimeInterval
        let idleSeconds: TimeInterval
        let outOfScopeSeconds: TimeInterval
        let usage: [UsageRecord]
    }

    private(set) var isRunning = false
    /// True while genuinely away from the keyboard/mouse.
    private(set) var isPaused = false
    /// True while active but on an app/site that wasn't declared for this session.
    private(set) var isOutOfScope = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var currentAppName: String?
    private(set) var currentDetail: String?
    private(set) var currentKind: TrackedItem.Kind?
    var currentItemKey: String? { segmentKey }
    var currentItemKind: TrackedItem.Kind? { segmentKind }
    var currentItemName: String { segmentDisplayName ?? currentDetail ?? "Application inconnue" }
    private(set) var liveUsage: [UsageRecord] = []
    /// True once the user has hit "Pause" themselves, as opposed to `isPaused` kicking
    /// in automatically from inactivity — both route through the same idle accounting.
    private(set) var isManuallyPaused = false

    /// Seconds spent idle so far, including whatever idle segment is still ongoing —
    /// for live display only, mirrors the final `StopResult.idleSeconds` on stop.
    var liveIdleSeconds: TimeInterval {
        idleAccumulated + (idleStart.map { Date().timeIntervalSince($0) } ?? 0)
    }

    /// Seconds spent out of scope so far, including any ongoing segment — live
    /// counterpart to `StopResult.outOfScopeSeconds`.
    var liveOutOfScopeSeconds: TimeInterval {
        outOfScopeAccumulated + (outOfScopeStart.map { Date().timeIntervalSince($0) } ?? 0)
    }

    /// 0 disables auto-pause entirely ("Jamais" in the setup pill control).
    var idleThreshold: TimeInterval = 300

    private(set) var declaredItems: [TrackedItem] = []
    private(set) var sessionStart: Date?
    private var lastActivityDate = Date()

    private var idleStart: Date?
    private var idleAccumulated: TimeInterval = 0
    private var outOfScopeStart: Date?
    private var outOfScopeAccumulated: TimeInterval = 0

    private var frontBundleID: String?
    private var frontAppName: String?
    private var frontProcessIdentifier: pid_t?

    private var segmentStart: Date?
    private var segmentKey: String?
    private var segmentKind: TrackedItem.Kind?
    private var segmentDisplayName: String?

    private var usageByKey: [String: UsageRecord] = [:]
    private var clockTask: Task<Void, Never>?
    private var browserTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var globalActivityMonitor: Any?
    private var localActivityMonitor: Any?

    /// Everything currently declared in scope for this session — exposed so external
    /// triggers (the Chrome extension's local server) can show what's already tracked.
    var declaredWebsites: [TrackedItem] {
        declaredItems.filter { $0.kind == .website }
    }

    /// Adds a site to the running session's scope, e.g. when the Chrome extension asks
    /// to start counting a newly visited site toward the active timer.
    func addDeclaredItem(_ item: TrackedItem) {
        guard isRunning, !declaredItems.contains(where: { $0.key == item.key && $0.kind == item.kind }) else { return }
        declaredItems.append(item)
    }

    func removeDeclaredItem(_ item: TrackedItem) {
        guard isRunning else { return }
        declaredItems.removeAll { $0.key == item.key && $0.kind == item.kind }
    }

    func start(declaredItems: [TrackedItem]) {
        guard !isRunning else { return }
        self.declaredItems = declaredItems
        usageByKey = [:]
        idleAccumulated = 0
        outOfScopeAccumulated = 0
        idleStart = nil
        outOfScopeStart = nil
        elapsed = 0
        liveUsage = []

        let now = Date()
        sessionStart = now
        lastActivityDate = now
        isRunning = true
        isPaused = false
        isOutOfScope = false
        DockTileAnimator.start()

        let front = NSWorkspace.shared.frontmostApplication
        frontBundleID = front?.bundleIdentifier
        frontAppName = front?.localizedName
        frontProcessIdentifier = front?.processIdentifier
        beginSegment(at: now)

        let activityMask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .scrollWheel,
        ]
        globalActivityMonitor = NSEvent.addGlobalMonitorForEvents(matching: activityMask) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lastActivityDate = Date()
            }
        }
        localActivityMonitor = NSEvent.addLocalMonitorForEvents(matching: activityMask.union([.keyDown])) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.lastActivityDate = Date()
            }
            return event
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let bundleID = app.bundleIdentifier
            let name = app.localizedName
            let pid = app.processIdentifier
            Task { @MainActor [weak self] in
                self?.handleActivation(bundleID: bundleID, name: name, pid: pid)
            }
        }

        clockTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.tickClock()
                try? await Task.sleep(for: .seconds(1))
            }
        }

        browserTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.tickBrowser()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Freezes the clock immediately, reusing the same idle accounting as an automatic
    /// pause — so `isPaused`, segment-closing, and the live totals all stay correct.
    func pauseManually() {
        guard isRunning, !isManuallyPaused else { return }
        let now = Date()
        isManuallyPaused = true
        lastActivityDate = now
        if idleStart == nil {
            closeSegment(at: now)
            idleStart = now
            isPaused = true
            if let outOfScopeStart {
                outOfScopeAccumulated += now.timeIntervalSince(outOfScopeStart)
                self.outOfScopeStart = nil
            }
            isOutOfScope = false
            currentDetail = "En pause"
        }
    }

    /// Resumes from either a manual pause or an automatic idle pause — the "Reprendre"
    /// button covers both, since the person's intent is the same either way.
    func resumeManually() {
        guard isRunning else { return }
        let now = Date()
        isManuallyPaused = false
        lastActivityDate = now
        if let idleStart {
            idleAccumulated += now.timeIntervalSince(idleStart)
            self.idleStart = nil
        }
        isPaused = false
        beginSegment(at: now)
    }

    func stop() -> StopResult {
        let now = Date()

        // Fold any pause/out-of-scope period still in progress into the final totals.
        if let idleStart {
            idleAccumulated += now.timeIntervalSince(idleStart)
            self.idleStart = nil
        }
        if let outOfScopeStart {
            outOfScopeAccumulated += now.timeIntervalSince(outOfScopeStart)
            self.outOfScopeStart = nil
        }
        if let sessionStart {
            elapsed = now.timeIntervalSince(sessionStart) - idleAccumulated - outOfScopeAccumulated
        }
        closeSegment(at: now)

        clockTask?.cancel()
        clockTask = nil
        browserTask?.cancel()
        browserTask = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        if let globalActivityMonitor {
            NSEvent.removeMonitor(globalActivityMonitor)
            self.globalActivityMonitor = nil
        }
        if let localActivityMonitor {
            NSEvent.removeMonitor(localActivityMonitor)
            self.localActivityMonitor = nil
        }

        let result = StopResult(
            startDate: sessionStart ?? now,
            endDate: now,
            activeSeconds: max(0, elapsed),
            idleSeconds: idleAccumulated,
            outOfScopeSeconds: outOfScopeAccumulated,
            usage: Array(usageByKey.values).sorted { $0.seconds > $1.seconds }
        )

        isRunning = false
        isPaused = false
        isOutOfScope = false
        DockTileAnimator.stop()
        currentAppName = nil
        currentDetail = nil
        currentKind = nil
        segmentStart = nil
        segmentKey = nil
        segmentKind = nil
        segmentDisplayName = nil
        sessionStart = nil
        return result
    }

    private func beginSegment(at date: Date) {
        segmentStart = date
        let key = frontBundleID ?? "unknown"
        let cleanName = ItemDisplayHelper.cleanDisplayName(key: key, kind: .app, rawName: frontAppName)
        segmentKey = key
        segmentKind = .app
        segmentDisplayName = cleanName
        currentAppName = cleanName
        currentKind = .app
        currentDetail = cleanName
    }

    private func closeSegment(at date: Date) {
        guard let start = segmentStart, let key = segmentKey, let kind = segmentKind,
              let name = segmentDisplayName else { return }
        let duration = date.timeIntervalSince(start)
        guard duration > 0 else { return }
        recordUsage(key: key, kind: kind, displayName: name, seconds: duration)
    }

    private func matchesDeclared(key: String, kind: TrackedItem.Kind) -> Bool {
        declaredItems.contains { item in
            guard item.kind == kind else { return false }
            if kind == .website {
                return key == item.key || key.hasSuffix("." + item.key)
            }
            return key == item.key
        }
    }

    /// Whether the currently open segment (app or resolved website) is one of the
    /// declared items for this session. If nothing was declared, everything counts.
    private func currentSegmentIsInScope() -> Bool {
        guard !declaredItems.isEmpty else { return true }
        guard let key = segmentKey, let kind = segmentKind else { return false }
        return matchesDeclared(key: key, kind: kind)
    }

    private func recordUsage(key: String, kind: TrackedItem.Kind, displayName: String, seconds: TimeInterval) {
        let isDeclared = declaredItems.isEmpty || matchesDeclared(key: key, kind: kind)
        if var existing = usageByKey[key] {
            existing.seconds += seconds
            existing.isDeclared = existing.isDeclared || isDeclared
            usageByKey[key] = existing
        } else {
            usageByKey[key] = UsageRecord(kind: kind, key: key, displayName: displayName, seconds: seconds, isDeclared: isDeclared)
        }
        liveUsage = Array(usageByKey.values).sorted { $0.seconds > $1.seconds }
    }

    private func handleActivation(bundleID: String?, name: String?, pid: pid_t?) {
        frontBundleID = bundleID
        frontAppName = name
        frontProcessIdentifier = pid
        guard isRunning, !isPaused else { return }
        let now = Date()
        closeSegment(at: now)
        beginSegment(at: now)

        unresolvedBrowserTicks = 0
        if let bundleID, BrowserURLReader.isBrowser(bundleIdentifier: bundleID), let pid {
            Task { @MainActor [weak self] in
                await self?.resolveBrowserActiveTab(pid: pid, bundleID: bundleID)
            }
        }
    }

    /// Clock + idle + scope bookkeeping. Never touches the network or other apps, so it
    /// can never be blocked by a slow or stuck Apple Events call (e.g. a pending
    /// Automation permission prompt from `tickBrowser`).
    private func tickClock() async {
        guard isRunning, let sessionStart else { return }
        let now = Date()
        let timeSinceActivity = now.timeIntervalSince(lastActivityDate)
        let nowIdle = isManuallyPaused || (idleThreshold > 0 && timeSinceActivity >= idleThreshold)

        if nowIdle {
            if idleStart == nil {
                let idleBeganAt = now.addingTimeInterval(-timeSinceActivity)
                closeSegment(at: idleBeganAt)
                idleStart = idleBeganAt
                isPaused = true
                if let outOfScopeStart, outOfScopeStart < idleBeganAt {
                    outOfScopeAccumulated += idleBeganAt.timeIntervalSince(outOfScopeStart)
                }
                outOfScopeStart = nil
                isOutOfScope = false
                currentAppName = nil
                currentDetail = "Inactif"
                currentKind = nil
            }
        } else if let idleStart {
            idleAccumulated += now.timeIntervalSince(idleStart)
            self.idleStart = nil
            isPaused = false
            beginSegment(at: now)
        }

        if !nowIdle {
            let inScope = currentSegmentIsInScope()
            currentDetail = currentKind == .website ? segmentDisplayName : frontAppName
            if inScope {
                if let outOfScopeStart {
                    outOfScopeAccumulated += now.timeIntervalSince(outOfScopeStart)
                    self.outOfScopeStart = nil
                }
                isOutOfScope = false
            } else {
                if outOfScopeStart == nil {
                    outOfScopeStart = now
                }
                isOutOfScope = true
            }
        }

        let ongoingIdle = idleStart.map { now.timeIntervalSince($0) } ?? 0
        let ongoingOutOfScope = (!nowIdle ? outOfScopeStart.map { now.timeIntervalSince($0) } : nil) ?? 0
        elapsed = max(0, now.timeIntervalSince(sessionStart) - idleAccumulated - ongoingIdle - outOfScopeAccumulated - ongoingOutOfScope)
        DockTileAnimator.updateBadge(elapsedSeconds: elapsed)

        refreshLiveUsage(at: now)
    }

    /// `usageByKey` only grows when a segment actually closes (app switch, idle, stop),
    /// so sitting on a single app/site would otherwise show an empty breakdown the whole
    /// time. This merges the still-open segment's running duration in for display only —
    /// it's never written back to `usageByKey`, which stays the source of truth.
    private func refreshLiveUsage(at now: Date) {
        guard let key = segmentKey, let kind = segmentKind, let name = segmentDisplayName,
              let segmentStart, idleStart == nil else {
            liveUsage = Array(usageByKey.values).sorted { $0.seconds > $1.seconds }
            return
        }
        let ongoingSeconds = now.timeIntervalSince(segmentStart)
        var merged = usageByKey
        let isDeclared = declaredItems.isEmpty || matchesDeclared(key: key, kind: kind)
        if var existing = merged[key] {
            existing.seconds += ongoingSeconds
            existing.isDeclared = existing.isDeclared || isDeclared
            merged[key] = existing
        } else {
            merged[key] = UsageRecord(
                kind: kind, key: key, displayName: name,
                seconds: ongoingSeconds, isDeclared: isDeclared
            )
        }
        liveUsage = Array(merged.values).sorted { $0.seconds > $1.seconds }
    }

    /// Consecutive ticks where the browser's URL couldn't be read at all. A single miss
    /// (tab switching, page loading, AX tree rebuilding) must not bounce the time from the
    /// site back to the browser app.
    private var unresolvedBrowserTicks = 0

    /// Resolves the active tab URL for a browser process and switches between website and app segments smoothly.
    private func resolveBrowserActiveTab(pid: pid_t, bundleID: String) async {
        guard isRunning, frontProcessIdentifier == pid else { return }

        let resolvedURL = await Task.detached(priority: .userInitiated) {
            BrowserURLReader.activeURL(forProcessIdentifier: pid, bundleIdentifier: bundleID)
        }.value

        guard isRunning, !isPaused, frontProcessIdentifier == pid else { return }

        guard let resolvedURL else {
            unresolvedBrowserTicks += 1
            if segmentKind == .website && unresolvedBrowserTicks >= 3 {
                let now = Date()
                closeSegment(at: now)
                beginSegment(at: now)
            }
            return
        }
        unresolvedBrowserTicks = 0

        if let host = resolvedURL.host, BrowserURLReader.isWebPage(resolvedURL) {
            let domain = DomainNormalizer.normalize(host: host)
            if segmentKind == .website && segmentKey == domain {
                return
            }
            let now = Date()
            closeSegment(at: now)
            segmentStart = now
            segmentKey = domain
            segmentKind = .website
            segmentDisplayName = domain
            currentKind = .website
            currentAppName = ItemDisplayHelper.cleanDisplayName(key: bundleID, kind: .app, rawName: frontAppName)
            if !isOutOfScope {
                currentDetail = domain
            }
        } else if segmentKind == .website {
            // Not a web page (new tab, settings, local file): count it as the browser app.
            let now = Date()
            closeSegment(at: now)
            beginSegment(at: now)
        }
    }

    /// Runs on its own cadence so a slow Accessibility query never freezes the visible
    /// timer. Deliberately not gated on isPaused / isOutOfScope: it must keep resolving
    /// the URL even while "out of scope" so it can detect navigation onto a declared
    /// site and bring the session back in scope.
    private func tickBrowser() async {
        guard isRunning, let bundleID = frontBundleID, let pid = frontProcessIdentifier,
              BrowserURLReader.isBrowser(bundleIdentifier: bundleID) else { return }
        await resolveBrowserActiveTab(pid: pid, bundleID: bundleID)
    }

}

#if DEBUG
extension ActivityTracker {
    /// README recordings only: turns the just-started session into a convincing one already in
    /// progress — past usage, idle and out-of-scope time — then cycles through `script` instead of
    /// following the real frontmost app.
    func applyDemoState(
        startedAgo: TimeInterval,
        usage: [UsageRecord],
        idleSeconds: TimeInterval,
        outOfScopeSeconds: TimeInterval,
        script: [TrackedItem],
        secondsPerItem: TimeInterval = 3.5
    ) {
        guard isRunning else { return }
        // Detach from the real world: no app switches, no idle detection, no browser reads.
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        browserTask?.cancel()
        browserTask = nil
        idleThreshold = 0

        let now = Date()
        sessionStart = now.addingTimeInterval(-startedAgo)
        idleAccumulated = idleSeconds
        outOfScopeAccumulated = outOfScopeSeconds
        usageByKey = Dictionary(uniqueKeysWithValues: usage.map { ($0.key, $0) })

        Task { @MainActor [weak self] in
            var index = 0
            while let self, self.isRunning, !script.isEmpty {
                let item = script[index % script.count]
                let switchedAt = Date()
                self.closeSegment(at: switchedAt)
                self.segmentStart = switchedAt
                self.segmentKey = item.key
                self.segmentKind = item.kind
                self.segmentDisplayName = item.displayName
                self.currentKind = item.kind
                self.currentDetail = item.displayName
                self.currentAppName = item.displayName
                index += 1
                try? await Task.sleep(for: .seconds(secondsPerItem))
            }
        }
    }
}
#endif
