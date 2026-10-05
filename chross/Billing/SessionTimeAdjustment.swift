import Foundation

/// Recomputes a session's totals after its times are corrected by hand: new start/end
/// times and/or periods to remove (a lunch break left running…).
///
/// Sessions only keep totals — not a minute-by-minute timeline — so removed time is taken
/// from the buckets most likely to contain it: idle first (auto-pause usually caught the
/// break), then out-of-scope, then active time, which shrinks every tracked app/site in
/// proportion. Added time (an earlier start, a later end) counts as active and goes to the
/// app/site the user picks.
struct SessionTimeAdjustment {
    struct Period: Identifiable, Equatable {
        let id = UUID()
        var start: Date
        var end: Date
    }

    struct Result {
        var startDate: Date
        var endDate: Date
        var activeSeconds: TimeInterval
        var idleSeconds: TimeInterval
        var outOfScopeSeconds: TimeInterval
        var usage: [UsageRecord]
        var addedSeconds: TimeInterval
        var removedFromIdle: TimeInterval
        var removedFromOutOfScope: TimeInterval
        var removedFromActive: TimeInterval

        var removedSeconds: TimeInterval { removedFromIdle + removedFromOutOfScope + removedFromActive }
    }

    static let manualKey = "chross.manual"

    let originalStart: Date
    let originalEnd: Date
    let activeSeconds: TimeInterval
    let idleSeconds: TimeInterval
    let outOfScopeSeconds: TimeInterval
    let usage: [UsageRecord]

    init(session: WorkSession) {
        originalStart = session.startDate
        originalEnd = session.endDate ?? session.startDate
        activeSeconds = session.activeSeconds
        idleSeconds = session.idleSeconds
        outOfScopeSeconds = session.outOfScopeSeconds
        usage = session.usage
    }

    func apply(newStart: Date, newEnd: Date, removing periods: [Period], addedTimeKey: String?) -> Result {
        let end = max(newEnd, newStart)

        let added = max(0, originalStart.timeIntervalSince(newStart)) + max(0, end.timeIntervalSince(originalEnd))
        let trimmed = max(0, newStart.timeIntervalSince(originalStart)) + max(0, originalEnd.timeIntervalSince(end))

        // Removed periods only count where they overlap the original session that's kept.
        let keptStart = max(originalStart, newStart)
        let keptEnd = min(originalEnd, end)
        let removedInside = keptEnd > keptStart
            ? Self.mergedLength(of: periods, clampedTo: keptStart...keptEnd)
            : 0

        var toRemove = trimmed + removedInside
        let fromIdle = min(idleSeconds, toRemove)
        toRemove -= fromIdle
        let fromOutOfScope = min(outOfScopeSeconds, toRemove)
        toRemove -= fromOutOfScope
        let fromActive = min(activeSeconds, toRemove)

        var newUsage = usage
        if fromActive > 0 {
            newUsage = Self.shrink(newUsage, tracked: true, by: fromActive)
        }
        if fromOutOfScope > 0 {
            newUsage = Self.shrink(newUsage, tracked: false, by: fromOutOfScope)
        }
        if added > 0 {
            newUsage = Self.addTracked(newUsage, seconds: added, toKey: addedTimeKey)
        }

        return Result(
            startDate: newStart,
            endDate: end,
            activeSeconds: max(0, activeSeconds - fromActive + added),
            idleSeconds: idleSeconds - fromIdle,
            outOfScopeSeconds: outOfScopeSeconds - fromOutOfScope,
            usage: newUsage.filter { $0.seconds >= 1 },
            addedSeconds: added,
            removedFromIdle: fromIdle,
            removedFromOutOfScope: fromOutOfScope,
            removedFromActive: fromActive
        )
    }

    /// Total length of the union of `periods` inside `bounds` — overlapping periods count once.
    static func mergedLength(of periods: [Period], clampedTo bounds: ClosedRange<Date>) -> TimeInterval {
        let clamped = periods
            .map { (start: max($0.start, bounds.lowerBound), end: min($0.end, bounds.upperBound)) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }

        var total: TimeInterval = 0
        var current: (start: Date, end: Date)?
        for period in clamped {
            if let open = current, period.start <= open.end {
                current = (open.start, max(open.end, period.end))
            } else {
                if let open = current { total += open.end.timeIntervalSince(open.start) }
                current = period
            }
        }
        if let open = current { total += open.end.timeIntervalSince(open.start) }
        return total
    }

    /// Scales down every tracked (or every untracked) record so their total drops by `seconds`.
    private static func shrink(_ usage: [UsageRecord], tracked: Bool, by seconds: TimeInterval) -> [UsageRecord] {
        let total = usage.filter { $0.isDeclared == tracked }.reduce(0) { $0 + $1.seconds }
        guard total > 0 else { return usage }
        let ratio = max(0, 1 - seconds / total)
        return usage.map { record in
            guard record.isDeclared == tracked else { return record }
            var copy = record
            copy.seconds = record.seconds * ratio
            return copy
        }
    }

    private static func addTracked(_ usage: [UsageRecord], seconds: TimeInterval, toKey key: String?) -> [UsageRecord] {
        var copy = usage
        var index: Int?
        if let key {
            index = copy.firstIndex { $0.key == key }
        }
        if index == nil {
            let trackedIndices = copy.indices.filter { copy[$0].isDeclared }
            index = trackedIndices.max { copy[$0].seconds < copy[$1].seconds }
        }
        guard let index else {
            // Nothing tracked to attach it to: keep it visible (and billable) on its own line.
            copy.append(UsageRecord(kind: .app, key: manualKey, displayName: "Ajout manuel", seconds: seconds, isDeclared: true))
            return copy
        }
        copy[index].seconds += seconds
        return copy
    }
}
