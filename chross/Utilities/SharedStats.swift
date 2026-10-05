import Foundation

/// Bridges today's tracked time from the main app to the ChrossWidget extension via an
/// App Group `UserDefaults` suite — the only data the widget needs, so this stays far
/// simpler than sharing the full SwiftData store.
///
/// Kept as two identical copies (here and in `ChrossWidget/SharedStats.swift`) since the
/// app and widget extension are separate compile targets with no shared framework target.
enum SharedStats {
    static let suiteName = "group.com.louismenthonnex.chross"

    private static let sessionStartKey = "sessionStartDate"
    private static let todaySecondsKey = "todaySecondsBeforeCurrentSession"
    private static let isRunningKey = "isRunning"
    private static let projectNameKey = "projectName"
    private static let dailyGoalHoursKey = "dailyGoalHours"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    struct Snapshot {
        var todaySecondsBeforeCurrentSession: TimeInterval
        var isRunning: Bool
        var currentSessionStart: Date?
        var projectName: String?
        var dailyGoalHours: Double

        /// Feed this into `Text(_:style: .timer)` so the widget ticks up live from
        /// today's already-completed total instead of restarting from zero.
        var adjustedReferenceDate: Date? {
            guard isRunning, let currentSessionStart else { return nil }
            return currentSessionStart.addingTimeInterval(-todaySecondsBeforeCurrentSession)
        }

        var totalSecondsNow: TimeInterval {
            guard isRunning, let currentSessionStart else { return todaySecondsBeforeCurrentSession }
            return todaySecondsBeforeCurrentSession + Date().timeIntervalSince(currentSessionStart)
        }
    }

    static func write(
        todaySecondsBeforeCurrentSession: TimeInterval,
        isRunning: Bool,
        currentSessionStart: Date?,
        projectName: String?,
        dailyGoalHours: Double
    ) {
        guard let defaults else { return }
        defaults.set(todaySecondsBeforeCurrentSession, forKey: todaySecondsKey)
        defaults.set(isRunning, forKey: isRunningKey)
        defaults.set(currentSessionStart, forKey: sessionStartKey)
        defaults.set(projectName, forKey: projectNameKey)
        defaults.set(dailyGoalHours, forKey: dailyGoalHoursKey)
    }

    static func read() -> Snapshot {
        guard let defaults else {
            return Snapshot(todaySecondsBeforeCurrentSession: 0, isRunning: false, currentSessionStart: nil, projectName: nil, dailyGoalHours: 7)
        }
        let goal = defaults.double(forKey: dailyGoalHoursKey)
        return Snapshot(
            todaySecondsBeforeCurrentSession: defaults.double(forKey: todaySecondsKey),
            isRunning: defaults.bool(forKey: isRunningKey),
            currentSessionStart: defaults.object(forKey: sessionStartKey) as? Date,
            projectName: defaults.string(forKey: projectNameKey),
            dailyGoalHours: goal == 0 ? 7 : goal
        )
    }
}
