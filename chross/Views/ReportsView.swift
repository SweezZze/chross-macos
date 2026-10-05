import SwiftData
import SwiftUI

struct ReportsView: View {
    @Query(sort: \WorkSession.startDate, order: .reverse) private var sessions: [WorkSession]
    @State private var period: Period = .month

    private enum Period: String, CaseIterable, Identifiable {
        case week = "Cette semaine"
        case month = "Ce mois"
        case all = "Tout"
        var id: String { rawValue }
    }

    private struct ProjectAggregate: Identifiable {
        let name: String
        let seconds: TimeInterval
        let billed: Decimal
        let currencyCode: String?
        var id: String { name }
    }

    private var filteredSessions: [WorkSession] {
        switch period {
        case .week:
            return sessions.filter { Calendar.current.isDate($0.startDate, equalTo: Date(), toGranularity: .weekOfYear) }
        case .month:
            return sessions.filter { Calendar.current.isDate($0.startDate, equalTo: Date(), toGranularity: .month) }
        case .all:
            return sessions
        }
    }

    private var projectAggregates: [ProjectAggregate] {
        var totals: [String: (seconds: TimeInterval, billed: Decimal, currency: String?)] = [:]
        for session in filteredSessions {
            let name = session.projectName.isEmpty ? "Session sans titre" : session.projectName
            var entry = totals[name] ?? (0, 0, nil)
            entry.seconds += session.activeSeconds
            if let total = session.billedTotal, let billing = session.billing {
                entry.billed += total
                entry.currency = billing.currencyCode
            }
            totals[name] = entry
        }
        return totals
            .map { ProjectAggregate(name: $0.key, seconds: $0.value.seconds, billed: $0.value.billed, currencyCode: $0.value.currency) }
            .sorted { $0.seconds > $1.seconds }
    }

    private var totalSeconds: TimeInterval {
        filteredSessions.reduce(0) { $0 + $1.activeSeconds }
    }

    private var totalBilled: Decimal {
        filteredSessions.compactMap(\.billedTotal).reduce(0, +)
    }

    private var billedCurrencyCode: String? {
        filteredSessions.first { $0.billing != nil }?.billing?.currencyCode
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statCards
                projectBreakdown
            }
            .padding(32)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.page)
    }

    private var header: some View {
        HStack {
            Text("Rapports").font(.largeTitle.bold()).foregroundStyle(Theme.textPrimary)
            Spacer()
            PillSegmentedControl(options: Period.allCases, label: \.rawValue, selection: $period)
                .frame(width: 340)
        }
    }

    private var statCards: some View {
        HStack(spacing: 16) {
            statCard(title: "Temps total", value: DurationFormatter.format(totalSeconds))
            statCard(title: "Sessions", value: "\(filteredSessions.count)")
            statCard(
                title: "Facturé",
                value: billedCurrencyCode.map { CurrencyFormatter.format(totalBilled, currencyCode: $0) } ?? "—",
                accent: true
            )
        }
    }

    private func statCard(title: String, value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(accent ? Theme.accent : Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chrossCard()
    }

    private var projectBreakdown: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Par projet").font(.headline).foregroundStyle(Theme.textPrimary)

            if projectAggregates.isEmpty {
                Text("Aucune session sur cette période.")
                    .font(.callout)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 16) {
                    ForEach(projectAggregates) { aggregate in
                        projectRow(aggregate)
                    }
                }
            }
        }
        .chrossCard()
    }

    private func projectRow(_ aggregate: ProjectAggregate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(aggregate.name)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if let currencyCode = aggregate.currencyCode, aggregate.billed > 0 {
                    Text(CurrencyFormatter.format(aggregate.billed, currencyCode: currencyCode))
                        .foregroundStyle(Theme.accent)
                }
                Text(DurationFormatter.format(aggregate.seconds))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            .font(.callout)

            GeometryReader { proxy in
                let fraction = totalSeconds > 0 ? min(1, aggregate.seconds / totalSeconds) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Theme.accent).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: WorkSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let a = WorkSession(projectName: "Refonte site — Client A", startDate: Date().addingTimeInterval(-5000), declaredItems: [])
    a.activeSeconds = 12400
    a.billing = BillingSettings(hourlyRate: 50, currencyCode: "EUR", rounding: .fiveMinutes, vatEnabled: true, vatRatePercent: 20, billingBase: .totalDuration)
    a.billedTotal = 172
    let b = WorkSession(projectName: "App mobile — Client B", startDate: Date().addingTimeInterval(-90000), declaredItems: [])
    b.activeSeconds = 28000
    b.billing = BillingSettings(hourlyRate: 40, currencyCode: "EUR", rounding: .fiveMinutes, vatEnabled: false, vatRatePercent: 0, billingBase: .totalDuration)
    b.billedTotal = 311
    let c = WorkSession(projectName: "Maintenance WordPress", startDate: Date().addingTimeInterval(-10000), declaredItems: [])
    c.activeSeconds = 2700
    container.mainContext.insert(a)
    container.mainContext.insert(b)
    container.mainContext.insert(c)

    return ReportsView()
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
