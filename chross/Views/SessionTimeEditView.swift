import SwiftUI

/// Corrects a finished session's times: move its start/end, or take out periods that
/// shouldn't count (lunch left running…). Shows exactly what will change before applying.
struct SessionTimeEditView: View {
    @Environment(\.dismiss) private var dismiss
    let session: WorkSession

    @State private var start: Date
    @State private var end: Date
    @State private var removedPeriods: [SessionTimeAdjustment.Period] = []
    @State private var addedTimeKey: String?

    private let adjustment: SessionTimeAdjustment

    init(session: WorkSession) {
        self.session = session
        adjustment = SessionTimeAdjustment(session: session)
        _start = State(initialValue: session.startDate)
        _end = State(initialValue: session.endDate ?? session.startDate)
        let topTracked = session.usage.filter(\.isDeclared).max { $0.seconds < $1.seconds }
        _addedTimeKey = State(initialValue: topTracked?.key)
    }

    private var result: SessionTimeAdjustment.Result {
        adjustment.apply(newStart: start, newEnd: end, removing: removedPeriods, addedTimeKey: addedTimeKey)
    }

    private var trackedUsage: [UsageRecord] {
        session.usage.filter(\.isDeclared).sorted { $0.seconds > $1.seconds }
    }

    private var hasChanges: Bool {
        let result = result
        return result.addedSeconds > 0 || result.removedSeconds > 0
            || start != adjustment.originalStart || end != adjustment.originalEnd
    }

    private var isValid: Bool { end > start }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(28)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    timelineSection
                    if result.addedSeconds > 0, !trackedUsage.isEmpty {
                        addedTimeSection
                    }
                    previewSection
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }

            footer
                .padding(28)
        }
        .frame(width: 780, height: 760)
        .background(Theme.page)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Corriger les horaires")
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("Chrono oublié pendant une pause, lancé en retard ou arrêté trop tard.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("SESSION")
                Spacer()
                Button {
                    start = adjustment.originalStart
                    end = adjustment.originalEnd
                    removedPeriods = []
                } label: {
                    Label("Réinitialiser", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.chross)
                .disabled(!hasChanges)
            }

            TimeRangeEditor(
                originalStart: adjustment.originalStart,
                originalEnd: adjustment.originalEnd,
                start: $start,
                end: $end,
                periods: $removedPeriods
            )
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 6) {
                hint("arrow.left.and.right", "Tire les poignées vertes pour avancer ou reculer le début et la fin.")
                hint("scissors", "Glisse sur la barre pour retirer une période (pause déjeuner…). Déplace-la ou étire ses bords ensuite.")
                hint("xmark.circle", "Survole une période retirée et clique sur la croix pour l'annuler.")
            }

            HStack(spacing: 14) {
                legend(color: Theme.accent.opacity(0.5), label: "Temps gardé")
                legend(color: Color.orange.opacity(0.6), label: "Retiré")
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Theme.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .frame(width: 14, height: 10)
                    Text("Horaires d'origine")
                }
                Spacer()
                Button {
                    removedPeriods.append(defaultPeriod())
                } label: {
                    Label("Retirer une période", systemImage: "scissors")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.surfaceRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.border))
                }
                .buttonStyle(.chross)
            }
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
        }
        .chrossCard()
    }

    private func hint(_ systemImage: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .frame(width: 16)
        }
        .font(.caption)
        .foregroundStyle(Theme.textTertiary)
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 14, height: 10)
            Text(label)
        }
    }

    private var addedTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("TEMPS AJOUTÉ (\(DurationFormatter.formatShort(result.addedSeconds))) ATTRIBUÉ À")
            Picker("", selection: $addedTimeKey) {
                ForEach(trackedUsage) { record in
                    Text(ItemDisplayHelper.cleanDisplayName(key: record.key, kind: record.kind, rawName: record.displayName))
                        .tag(Optional(record.key))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .chrossCard()
    }

    private var previewSection: some View {
        let result = result
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("APERÇU")
            previewRow("Temps actif", before: adjustment.activeSeconds, after: result.activeSeconds, highlight: true)
            previewRow("Inactif", before: adjustment.idleSeconds, after: result.idleSeconds)
            previewRow("Hors sélection", before: adjustment.outOfScopeSeconds, after: result.outOfScopeSeconds)

            if result.removedSeconds > 0 || result.addedSeconds > 0 {
                Divider().background(Theme.border)
                Text(explanation(result))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .chrossCard()
    }

    private var footer: some View {
        HStack {
            Button("Annuler") { dismiss() }
                .buttonStyle(.chross)
                .foregroundStyle(Theme.textSecondary)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(action: apply) {
                Text("Appliquer")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(hasChanges && isValid ? Theme.accent : Theme.surfaceRaised, in: Capsule())
            }
            .buttonStyle(.chross)
            .disabled(!hasChanges || !isValid)
            .keyboardShortcut(.defaultAction)
            .demoAnchor("editor.apply")
        }
    }

    // MARK: - Pieces

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
    }

    private func previewRow(_ label: String, before: TimeInterval, after: TimeInterval, highlight: Bool = false) -> some View {
        let changed = abs(after - before) >= 1
        return HStack {
            Text(label)
                .font(highlight ? .callout.weight(.semibold) : .callout)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(DurationFormatter.format(before))
                .foregroundStyle(changed ? Theme.textTertiary : Theme.textSecondary)
                .strikethrough(changed, color: Theme.textTertiary)
            if changed {
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                Text(DurationFormatter.format(after))
                    .foregroundStyle(highlight ? Theme.accent : Theme.textPrimary)
                    .fontWeight(.semibold)
            }
        }
        .font(.callout.monospacedDigit())
    }

    private func explanation(_ result: SessionTimeAdjustment.Result) -> String {
        var parts: [String] = []
        if result.addedSeconds > 0 {
            parts.append("\(DurationFormatter.formatShort(result.addedSeconds)) ajoutées au temps actif")
        }
        var removed: [String] = []
        if result.removedFromIdle > 0 { removed.append("\(DurationFormatter.formatShort(result.removedFromIdle)) d'inactivité") }
        if result.removedFromOutOfScope > 0 { removed.append("\(DurationFormatter.formatShort(result.removedFromOutOfScope)) hors sélection") }
        if result.removedFromActive > 0 { removed.append("\(DurationFormatter.formatShort(result.removedFromActive)) de temps actif") }
        if !removed.isEmpty {
            parts.append("retrait de " + removed.joined(separator: ", "))
        }
        let sentence = parts.joined(separator: " · ")
        let note = result.removedFromActive > 0
            ? " Le temps actif retiré est réparti sur les apps et sites suivis."
            : ""
        return sentence.prefix(1).uppercased() + sentence.dropFirst() + "." + note
    }

    /// Suggests 12:00–13:00 when it falls inside the session, otherwise the middle hour.
    private func defaultPeriod() -> SessionTimeAdjustment.Period {
        let calendar = Calendar.current
        if let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start),
           let one = calendar.date(byAdding: .hour, value: 1, to: noon),
           noon >= start, one <= end {
            return .init(start: noon, end: one)
        }
        let middle = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        let length = min(3600, end.timeIntervalSince(start) / 4)
        return .init(start: middle.addingTimeInterval(-length / 2), end: middle.addingTimeInterval(length / 2))
    }

    private func apply() {
        guard hasChanges, isValid else { return }
        let result = result
        session.startDate = result.startDate
        session.endDate = result.endDate
        session.activeSeconds = result.activeSeconds
        session.idleSeconds = result.idleSeconds
        session.outOfScopeSeconds = result.outOfScopeSeconds
        session.usage = result.usage
        session.timeAdjusted = true
        if let billing = session.billing {
            session.billedTotal = BillingCalculator.calculate(
                activeSeconds: result.activeSeconds,
                usage: result.usage,
                settings: billing
            ).total
        }
        dismiss()
    }
}
