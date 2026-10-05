import SwiftUI
import WidgetKit

private let widgetAccent = Color(red: 0.839, green: 1.0, blue: 0.247)
private let widgetBackground = Color(red: 0.043, green: 0.043, blue: 0.051)

struct DailyTimeEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedStats.Snapshot
}

struct DailyTimeProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyTimeEntry {
        DailyTimeEntry(date: Date(), snapshot: SharedStats.read())
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyTimeEntry) -> Void) {
        completion(DailyTimeEntry(date: Date(), snapshot: SharedStats.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyTimeEntry>) -> Void) {
        let entry = DailyTimeEntry(date: Date(), snapshot: SharedStats.read())
        // The live-ticking `.timer` text needs no timeline entries of its own — this is
        // just a safety-net refresh in case the app never called `reloadAllTimelines()`.
        let nextRefresh = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct ChrossWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: DailyTimeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "stopwatch.fill")
                    .font(.caption2)
                    .foregroundStyle(.black)
                    .padding(4)
                    .background(widgetAccent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("Chross")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if entry.snapshot.isRunning {
                    Circle().fill(widgetAccent).frame(width: 6, height: 6)
                }
            }

            Spacer(minLength: 2)

            Group {
                if let referenceDate = entry.snapshot.adjustedReferenceDate {
                    Text(referenceDate, style: .timer)
                } else {
                    Text(formattedDuration(entry.snapshot.todaySecondsBeforeCurrentSession))
                }
            }
            .font(.system(size: family == .systemSmall ? 26 : 32, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundStyle(.primary)

            if entry.snapshot.isRunning, let projectName = entry.snapshot.projectName, !projectName.isEmpty {
                Text(projectName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Temps du jour")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 2)

            GeometryReader { proxy in
                let goalSeconds = max(entry.snapshot.dailyGoalHours * 3600, 1)
                let fraction = min(1, entry.snapshot.totalSecondsNow / goalSeconds)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.25))
                    Capsule().fill(widgetAccent).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)

            Text("Objectif \(entry.snapshot.dailyGoalHours.formatted()) h")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }
}

struct ChrossWidget: Widget {
    let kind: String = "ChrossWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyTimeProvider()) { entry in
            if #available(macOS 14.0, iOS 17.0, *) {
                ChrossWidgetEntryView(entry: entry)
                    .containerBackground(widgetBackground, for: .widget)
            } else {
                ChrossWidgetEntryView(entry: entry)
                    .padding()
                    .background(widgetBackground)
            }
        }
        .configurationDisplayName("Temps du jour")
        .description("Suis ton temps de travail du jour, en direct, depuis le centre de notifications.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    ChrossWidget()
} timeline: {
    DailyTimeEntry(
        date: .now,
        snapshot: SharedStats.Snapshot(
            todaySecondsBeforeCurrentSession: 5025,
            isRunning: true,
            currentSessionStart: Date().addingTimeInterval(-600),
            projectName: "Refonte site — Client A",
            dailyGoalHours: 7
        )
    )
    DailyTimeEntry(
        date: .now,
        snapshot: SharedStats.Snapshot(
            todaySecondsBeforeCurrentSession: 9420,
            isRunning: false,
            currentSessionStart: nil,
            projectName: nil,
            dailyGoalHours: 7
        )
    )
}
