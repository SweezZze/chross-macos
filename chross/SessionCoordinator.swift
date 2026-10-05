import AppKit
import Observation
import SwiftData
import SwiftUI
import WidgetKit

@MainActor
@Observable
final class SessionCoordinator {
    var showSetup = false
    /// Apps/sites pre-selected the next time "Nouvelle session" opens (set by the work reminder).
    var setupPrefillItems: [TrackedItem] = []
    var showBillingPrompt = false
    var summarySession: WorkSession?
    var autoFinalizePending = false

    @ObservationIgnored @AppStorage("lastHourlyRate") private var lastHourlyRate: Double = 0
    @ObservationIgnored @AppStorage("lastCurrencyCode") private var lastCurrencyCode: String = Locale.current.currency?.identifier ?? "EUR"
    @ObservationIgnored @AppStorage("lastRoundingMinutes") private var lastRoundingMinutes: Int = BillingSettings.RoundingIncrement.fifteenMinutes.rawValue
    @ObservationIgnored @AppStorage("lastVATEnabled") private var lastVATEnabled: Bool = false
    @ObservationIgnored @AppStorage("lastVATRate") private var lastVATRate: Double = 20
    @ObservationIgnored @AppStorage("lastBillingBase") private var lastBillingBase: String = BillingSettings.BillingBase.totalDuration.rawValue
    @ObservationIgnored @AppStorage("lastApplyBilling") private var lastApplyBilling: Bool = false

    /// How the billing step should resolve once the running session stops: either ask
    /// via `BillingPromptView` (manual sessions), or finalize right away with the
    /// settings carried over from a preset (`startSession(fromPreset:)`), with no
    /// settings at all if that preset didn't opt into billing.
    private enum PendingBilling {
        case manual
        case automatic(BillingSettings?)
    }

    private var pendingStopResult: ActivityTracker.StopResult?
    private var pendingProjectName = ""
    private var pendingDeclaredItems: [TrackedItem] = []
    private var pendingBillingMode: PendingBilling = .manual

    var lastBillingSettings: BillingSettings {
        BillingSettings(
            hourlyRate: Decimal(lastHourlyRate),
            currencyCode: lastCurrencyCode,
            rounding: BillingSettings.RoundingIncrement(rawValue: lastRoundingMinutes) ?? .fifteenMinutes,
            vatEnabled: lastVATEnabled,
            vatRatePercent: Decimal(lastVATRate),
            billingBase: BillingSettings.BillingBase(rawValue: lastBillingBase) ?? .totalDuration
        )
    }

    var applyBillingByDefault: Bool { lastApplyBilling }

    /// The project name of the session currently running, if any — `pendingProjectName`
    /// is set the moment `startSession` is called, before the stop/finalize flow begins.
    var runningProjectName: String? {
        pendingProjectName.isEmpty ? nil : pendingProjectName
    }

    /// Everything `BillingPromptView` needs to show "Refonte site — Client A ·
    /// 15:30 → 16:54" and compute a live preview, without exposing `pendingStopResult`.
    var pendingSummary: (title: String, timeRange: String, activeSeconds: TimeInterval, usage: [UsageRecord])? {
        guard let result = pendingStopResult else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let title = pendingProjectName.isEmpty ? "Session sans titre" : pendingProjectName
        let range = "\(formatter.string(from: result.startDate)) → \(formatter.string(from: result.endDate))"
        return (title, range, result.activeSeconds, result.usage)
    }

    func startSession(
        tracker: ActivityTracker,
        projectName: String,
        declaredItems: [TrackedItem],
        idleThresholdMinutes: Double,
        modelContext: ModelContext
    ) {
        pendingProjectName = projectName
        pendingDeclaredItems = declaredItems
        pendingBillingMode = .manual
        tracker.idleThreshold = idleThresholdMinutes * 60
        tracker.start(declaredItems: declaredItems)
        syncWidgetSnapshot(isRunning: true, currentSessionStart: tracker.sessionStart, modelContext: modelContext)
    }

    /// Starts a session fully configured from a preset — project name, apps/sites, idle
    /// threshold, and billing all come from `preset`, so stopping finalizes immediately
    /// instead of showing the setup or billing prompts.
    func startSession(fromPreset preset: Preset, tracker: ActivityTracker, modelContext: ModelContext) {
        pendingProjectName = preset.projectName
        pendingDeclaredItems = preset.declaredItems
        pendingBillingMode = .automatic(preset.applyBilling ? preset.billing : nil)
        tracker.idleThreshold = preset.idleThresholdMinutes * 60
        tracker.start(declaredItems: preset.declaredItems)
        syncWidgetSnapshot(isRunning: true, currentSessionStart: tracker.sessionStart, modelContext: modelContext)
    }

    /// Pushes today's tracked time to the ChrossWidget extension via the shared App Group
    /// store and asks WidgetKit to refresh immediately, instead of waiting for its own
    /// periodic timeline — called on every start/stop so the widget stays live.
    func syncWidgetSnapshot(isRunning: Bool, currentSessionStart: Date?, modelContext: ModelContext) {
        let allSessions = (try? modelContext.fetch(FetchDescriptor<WorkSession>())) ?? []
        let todaySeconds = allSessions
            .filter { Calendar.current.isDateInToday($0.startDate) }
            .reduce(0) { $0 + $1.activeSeconds }
        let goalHours = UserDefaults.standard.double(forKey: AppPreferences.dailyGoalHoursKey)
        SharedStats.write(
            todaySecondsBeforeCurrentSession: todaySeconds,
            isRunning: isRunning,
            currentSessionStart: currentSessionStart,
            projectName: runningProjectName,
            dailyGoalHours: goalHours == 0 ? AppPreferences.defaultDailyGoalHours : goalHours
        )
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Permanently removes a finished session from the history and refreshes the widget,
    /// since today's total may have changed.
    func deleteSession(_ session: WorkSession, tracker: ActivityTracker, modelContext: ModelContext) {
        modelContext.delete(session)
        try? modelContext.save()
        syncWidgetSnapshot(isRunning: tracker.isRunning, currentSessionStart: tracker.sessionStart, modelContext: modelContext)
    }

    /// Starts a one-click session with no setup UI — used by the Chrome extension's
    /// "Démarrer" button, which has no way to show `SessionSetupView`. Tracks every
    /// app/site (no declared scope) and finalizes without a billing prompt on stop.
    func startQuickSession(tracker: ActivityTracker, projectName: String, modelContext: ModelContext) {
        pendingProjectName = projectName
        pendingDeclaredItems = []
        pendingBillingMode = .automatic(nil)
        tracker.idleThreshold = AppPreferences.defaultIdleMinutes * 60
        tracker.start(declaredItems: [])
        syncWidgetSnapshot(isRunning: true, currentSessionStart: tracker.sessionStart, modelContext: modelContext)
    }

    /// Brings a newly visited site into the running session's scope — called when the
    /// Chrome extension's "Ajouter ce site" button posts a URL to the local server.
    func addDeclaredItem(_ item: TrackedItem, tracker: ActivityTracker) {
        guard tracker.isRunning else { return }
        if !pendingDeclaredItems.contains(where: { $0.key == item.key && $0.kind == item.kind }) {
            pendingDeclaredItems.append(item)
        }
        tracker.addDeclaredItem(item)
    }

    /// Removes a declared item from the running session's scope.
    func removeDeclaredItem(_ item: TrackedItem, tracker: ActivityTracker) {
        guard tracker.isRunning else { return }
        pendingDeclaredItems.removeAll { $0.key == item.key && $0.kind == item.kind }
        tracker.removeDeclaredItem(item)
    }

    /// Stops and finalizes immediately with no billing prompt — used by callers (the
    /// Chrome extension's local server) that have no UI to resolve `showBillingPrompt`.
    func stopAndFinalizeWithoutBilling(tracker: ActivityTracker, modelContext: ModelContext) {
        guard tracker.isRunning else { return }
        pendingStopResult = tracker.stop()
        let billing: BillingSettings? = {
            if case .automatic(let settings) = pendingBillingMode { return settings }
            return nil
        }()
        finalizeSession(billing: billing, modelContext: modelContext)
        pendingBillingMode = .manual
    }

    func requestStop(tracker: ActivityTracker) {
        guard tracker.isRunning else { return }
        pendingStopResult = tracker.stop()
        NSApp.activate(ignoringOtherApps: true)
        switch pendingBillingMode {
        case .manual:
            showBillingPrompt = true
        case .automatic:
            autoFinalizePending = true
        }
    }

    /// Called by `ContentView` (which owns a `modelContext`) when a preset-started
    /// session stops, so the summary can be saved without any further user input.
    func finalizeAutoSession(modelContext: ModelContext) {
        guard case .automatic(let billing) = pendingBillingMode else { return }
        finalizeSession(billing: billing, modelContext: modelContext)
        pendingBillingMode = .manual
        autoFinalizePending = false
    }

    func finalizeSession(billing: BillingSettings?, modelContext: ModelContext) {
        guard let result = pendingStopResult else { return }
        let session = WorkSession(
            projectName: pendingProjectName.isEmpty ? "Session sans titre" : pendingProjectName,
            startDate: result.startDate,
            declaredItems: pendingDeclaredItems
        )
        session.endDate = result.endDate
        session.activeSeconds = result.activeSeconds
        session.idleSeconds = result.idleSeconds
        session.outOfScopeSeconds = result.outOfScopeSeconds
        session.usage = result.usage

        if let billing {
            session.billing = billing
            let calculation = BillingCalculator.calculate(
                activeSeconds: result.activeSeconds,
                usage: result.usage,
                settings: billing
            )
            session.billedTotal = calculation.total

            lastHourlyRate = (billing.hourlyRate as NSDecimalNumber).doubleValue
            lastCurrencyCode = billing.currencyCode
            lastRoundingMinutes = billing.rounding.rawValue
            lastVATEnabled = billing.vatEnabled
            lastVATRate = (billing.vatRatePercent as NSDecimalNumber).doubleValue
            lastBillingBase = billing.billingBase.rawValue
            lastApplyBilling = true
        } else {
            lastApplyBilling = false
        }

        modelContext.insert(session)
        // Saving gives the session its permanent ID, which the summary window is opened with.
        try? modelContext.save()
        pendingStopResult = nil
        pendingProjectName = ""
        pendingDeclaredItems = []
        summarySession = session
        syncWidgetSnapshot(isRunning: false, currentSessionStart: nil, modelContext: modelContext)
    }
}
