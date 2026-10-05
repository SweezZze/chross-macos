import AppKit
import CoreGraphics
import Observation
import SwiftData
import UserNotifications

/// Notices when the user is genuinely working on something they usually track — a favorite
/// app or site, or anything that belongs to a project — while no session is running, and
/// sends a notification with a "Démarrer" button.
///
/// Rules, all required before a reminder fires:
/// - The app/site is tracked (favorite or project item), isn't a system utility (Finder,
///   System Settings…) and hasn't been ignored by the user. Browsers only count through the
///   site that's open, never as an app.
/// - Over the whole last `delay` minutes (a sliding window, not a running total), at least
///   80 % of the time was spent on tracked things with real keyboard/mouse activity.
/// - The user is still on that item right now, and it's the one they used most in the window.
/// - No session ended in the last 15 minutes, no reminder in the last 30, no "Plus tard".
@MainActor
@Observable
final class WorkReminder: NSObject, UNUserNotificationCenterDelegate {
    static let enabledKey = "workReminderEnabled"
    static let delayMinutesKey = "workReminderDelayMinutes"
    /// Newline-separated app bundle IDs / domains the user asked never to be reminded about.
    static let ignoredKey = "workReminderIgnored"
    static let defaultDelayMinutes: Double = 3
    static let delayOptions: [Double] = [1, 3, 5, 10]

    /// Apps that are never "work" on their own, whatever the user's projects contain.
    static let systemApps: Set<String> = [
        "com.apple.finder", "com.apple.systempreferences", "com.apple.Settings",
        "com.apple.ActivityMonitor", "com.apple.Spotlight", "com.apple.dock",
        "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.loginwindow",
        "com.apple.screencaptureui", "com.apple.ScreenContinuity", "com.apple.Siri",
        "com.apple.AppStore", "com.apple.keychainaccess", "com.apple.archiveutility",
        "com.apple.SecurityAgent", "com.apple.UserNotificationCenter", "com.apple.WindowManager",
    ]

    private static let tickSeconds: TimeInterval = 5
    /// Keyboard/mouse input within this long counts as actively working.
    private static let engagedWithinSeconds: TimeInterval = 45
    /// Share of the window that must be active work on tracked items.
    private static let requiredShare = 0.8
    private static let cooldownSeconds: TimeInterval = 30 * 60
    private static let snoozeSeconds: TimeInterval = 60 * 60
    private static let afterSessionGraceSeconds: TimeInterval = 15 * 60

    private static let categoryID = "chross.work-reminder"
    private static let startActionID = "chross.work-reminder.start"
    private static let laterActionID = "chross.work-reminder.later"
    private static let ignoreActionID = "chross.work-reminder.ignore"

    @ObservationIgnored private weak var tracker: ActivityTracker?
    @ObservationIgnored private weak var coordinator: SessionCoordinator?
    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var openMainWindow: (() -> Void)?
    @ObservationIgnored private var loopTask: Task<Void, Never>?

    @ObservationIgnored private var samples: [Sample] = []
    @ObservationIgnored private var silencedUntil: Date?
    @ObservationIgnored private var lastSessionSeenAt: Date?
    @ObservationIgnored private var pendingMatch: Match?

    /// One observation per tick: what was in front (if tracked) and whether the user was active.
    private struct Sample {
        let date: Date
        let key: String?
        let engaged: Bool
    }

    private struct Match {
        let item: TrackedItem
        let presetID: PersistentIdentifier?
        let presetName: String?
    }

    /// Safe to call every time the main window appears: only the first call starts the
    /// loop; later ones just refresh the window-opening action.
    func start(
        tracker: ActivityTracker,
        coordinator: SessionCoordinator,
        modelContext: ModelContext,
        openMainWindow: @escaping () -> Void
    ) {
        self.tracker = tracker
        self.coordinator = coordinator
        self.modelContext = modelContext
        self.openMainWindow = openMainWindow
        guard loopTask == nil else { return }

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryID,
                actions: [
                    UNNotificationAction(identifier: Self.startActionID, title: "Démarrer", options: [.foreground]),
                    UNNotificationAction(identifier: Self.laterActionID, title: "Plus tard (1 h)", options: []),
                    UNNotificationAction(identifier: Self.ignoreActionID, title: "Ne plus me rappeler pour ça", options: []),
                ],
                intentIdentifiers: []
            ),
        ])
        // On first launch the introduction asks for this at the right moment instead.
        if UserDefaults.standard.bool(forKey: AppPreferences.hasCompletedOnboardingKey) {
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(Self.tickSeconds))
            }
        }
    }

    // MARK: - Ignored items

    static func ignoredKeys(from stored: String) -> [String] {
        stored.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private var ignoredKeys: Set<String> {
        Set(Self.ignoredKeys(from: UserDefaults.standard.string(forKey: Self.ignoredKey) ?? ""))
    }

    private func ignore(_ key: String) {
        var keys = Self.ignoredKeys(from: UserDefaults.standard.string(forKey: Self.ignoredKey) ?? "")
        guard !keys.contains(key) else { return }
        keys.append(key)
        UserDefaults.standard.set(keys.joined(separator: "\n"), forKey: Self.ignoredKey)
        samples.removeAll { $0.key == key }
    }

    // MARK: - Detection

    private func tick() async {
        let now = Date()
        guard let tracker else { return }

        if tracker.isRunning {
            lastSessionSeenAt = now
            samples.removeAll()
            return
        }
        guard isEnabled else {
            samples.removeAll()
            return
        }

        let windowLength = delayMinutes * 60
        let engaged = secondsSinceLastInput() < Self.engagedWithinSeconds
        let match = engaged ? await currentMatch() : nil

        samples.append(Sample(date: now, key: match?.item.key, engaged: engaged))
        samples.removeAll { now.timeIntervalSince($0.date) > windowLength }

        guard let match, shouldNotify(about: match, now: now, windowLength: windowLength) else { return }

        samples.removeAll()
        silencedUntil = now.addingTimeInterval(Self.cooldownSeconds)
        await notify(match)
    }

    private func shouldNotify(about match: Match, now: Date, windowLength: TimeInterval) -> Bool {
        if let silencedUntil, now < silencedUntil { return false }
        if let lastSessionSeenAt, now.timeIntervalSince(lastSessionSeenAt) < Self.afterSessionGraceSeconds { return false }

        // The window must be fully observed — no deciding from a few seconds of data.
        guard let oldest = samples.first?.date,
              now.timeIntervalSince(oldest) >= windowLength - Self.tickSeconds * 1.5 else { return false }

        let workSamples = samples.filter { $0.engaged && $0.key != nil }
        let expected = max(1, windowLength / Self.tickSeconds)
        guard Double(workSamples.count) >= expected * Self.requiredShare else { return false }

        // Name the thing they've mostly been on — and only if they're still on it.
        let counts = Dictionary(grouping: workSamples.compactMap(\.key), by: { $0 }).mapValues(\.count)
        guard let dominant = counts.max(by: { $0.value < $1.value })?.key else { return false }
        return dominant == match.item.key
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    private var delayMinutes: Double {
        let stored = UserDefaults.standard.double(forKey: Self.delayMinutesKey)
        return stored > 0 ? stored : Self.defaultDelayMinutes
    }

    private func secondsSinceLastInput() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return .infinity }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// What the user is on right now, if it's something they track. Only sites count inside
    /// a browser ("github.com", never "Google Chrome"); system utilities never count.
    private func currentMatch() async -> Match? {
        guard let modelContext,
              let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              !Self.systemApps.contains(bundleID) else { return nil }

        let ignored = ignoredKeys
        let favorites = (try? modelContext.fetch(FetchDescriptor<FavoriteItem>())) ?? []
        let presets = (try? modelContext.fetch(FetchDescriptor<Preset>(sortBy: [SortDescriptor(\.createdDate, order: .reverse)]))) ?? []

        if BrowserURLReader.isBrowser(bundleIdentifier: bundleID) {
            let watchedSites = (favorites.filter { $0.kind == .website }.map(\.key)
                + presets.flatMap { $0.declaredItems.filter { $0.kind == .website }.map(\.key) })
                .filter { !ignored.contains($0) }
            guard !watchedSites.isEmpty, AccessibilityPermission.isGranted else { return nil }

            let pid = front.processIdentifier
            let url = await Task.detached(priority: .utility) {
                BrowserURLReader.activeURL(forProcessIdentifier: pid, bundleIdentifier: bundleID)
            }.value
            guard let url, BrowserURLReader.isWebPage(url), let host = url.host else { return nil }
            let domain = DomainNormalizer.normalize(host: host)
            guard let site = watchedSites.first(where: { domain == $0 || domain.hasSuffix("." + $0) }) else { return nil }
            let favoriteName = favorites.first { $0.kind == .website && $0.key == site }?.displayName
            return match(TrackedItem(kind: .website, key: site, displayName: favoriteName ?? site), presets: presets)
        }

        guard !ignored.contains(bundleID) else { return nil }
        let isWatchedApp = favorites.contains { $0.kind == .app && $0.key == bundleID }
            || presets.contains { $0.declaredItems.contains { $0.kind == .app && $0.key == bundleID } }
        guard isWatchedApp else { return nil }
        let name = ItemDisplayHelper.cleanDisplayName(key: bundleID, kind: .app, rawName: front.localizedName)
        return match(TrackedItem(kind: .app, key: bundleID, displayName: name), presets: presets)
    }

    private func match(_ item: TrackedItem, presets: [Preset]) -> Match {
        let preset = presets.first { preset in
            preset.declaredItems.contains { declared in
                declared.kind == item.kind && (declared.key == item.key
                    || (item.kind == .website && item.key.hasSuffix("." + declared.key)))
            }
        }
        return Match(item: item, presetID: preset?.persistentModelID, presetName: preset?.name)
    }

    // MARK: - Notification

    /// Sends an example reminder right away (from Réglages) so the user can see what it looks like.
    func sendTestNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "Tu travailles sans chrono"
        content.body = "Exemple : github.com depuis \(Int(delayMinutes)) minutes. Démarrer une session ?"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "chross.work-reminder.test", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func notify(_ match: Match) async {
        pendingMatch = match

        let content = UNMutableNotificationContent()
        content.title = "Tu travailles sans chrono"
        let minutes = Int(delayMinutes)
        let duration = minutes <= 1 ? "1 minute" : "\(minutes) minutes"
        if let presetName = match.presetName {
            content.body = "\(match.item.displayName) depuis \(duration). Démarrer « \(presetName) » ?"
        } else {
            content.body = "\(match.item.displayName) depuis \(duration). Démarrer une session ?"
        }
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["key": match.item.key]

        let request = UNNotificationRequest(identifier: "chross.work-reminder", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let key = response.notification.request.content.userInfo["key"] as? String
        guard response.notification.request.identifier == "chross.work-reminder" else { return }
        await MainActor.run {
            switch action {
            case Self.laterActionID:
                silencedUntil = Date().addingTimeInterval(Self.snoozeSeconds)
            case Self.ignoreActionID:
                if let key { ignore(key) }
                pendingMatch = nil
            case Self.startActionID, UNNotificationDefaultActionIdentifier:
                startFromReminder()
            default:
                break
            }
        }
    }

    /// Starts the matching project right away; with no project, opens "Nouvelle session"
    /// with the app/site already selected so the user only has to name it.
    private func startFromReminder() {
        guard let match = pendingMatch, let tracker, let coordinator, let modelContext else { return }
        pendingMatch = nil
        NSApp.activate(ignoringOtherApps: true)
        guard !tracker.isRunning else { return }

        if let presetID = match.presetID,
           let preset = modelContext.model(for: presetID) as? Preset, !preset.isDeleted {
            coordinator.startSession(fromPreset: preset, tracker: tracker, modelContext: modelContext)
            return
        }

        let hasVisibleWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        if !hasVisibleWindow {
            openMainWindow?()
        }
        coordinator.setupPrefillItems = [match.item]
        coordinator.showSetup = true
    }
}
