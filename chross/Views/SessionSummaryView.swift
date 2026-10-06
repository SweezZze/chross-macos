import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SessionSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ActivityTracker.self) private var tracker
    @Environment(SessionCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

    let session: WorkSession
    var showBreadcrumb = false
    /// Set when shown inside the Historique tab: "back to the list" instead of dismissing.
    var onBack: (() -> Void)? = nil
    /// Shown in its own window at the end of a session: adds a close button and more room.
    var isStandaloneWindow = false

    @State private var showBillingEditor = false
    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false
    @State private var showTimeEditor = false
    @State private var hoveredSegmentID: String?
    @AppStorage(AppPreferences.defaultIdleMinutesKey) private var defaultIdleMinutes: Double = AppPreferences.defaultIdleMinutes
    @AppStorage(AppPreferences.companyNameKey) private var companyName: String = ""
    @AppStorage(AppPreferences.companyAddressKey) private var companyAddress: String = ""
    @AppStorage(AppPreferences.companySiretKey) private var companySiret: String = ""
    @AppStorage(AppPreferences.companyIBANKey) private var companyIBAN: String = ""
    @AppStorage(AppPreferences.companyLogoDataKey) private var companyLogoData: Data = Data()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    private var timeRange: String {
        let end = session.endDate ?? session.startDate
        return "\(Self.timeFormatter.string(from: session.startDate)) → \(Self.timeFormatter.string(from: end))"
    }

    private var billingResult: BillingResult? {
        guard let billing = session.billing else { return nil }
        return BillingCalculator.calculate(
            activeSeconds: session.activeSeconds,
            usage: session.usage,
            settings: billing
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                topBar
                if !session.notes.isEmpty || !session.tags.isEmpty {
                    notesCard
                }
                statCards
                // Side by side when there's room, stacked otherwise — never squeezed.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        timelineCard
                            .frame(minWidth: 420, maxWidth: .infinity, alignment: .leading)
                        billingColumn
                            .frame(width: 320)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        timelineCard
                        billingColumn
                    }
                }
            }
            .padding(isStandaloneWindow ? 32 : 28)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: isStandaloneWindow ? 760 : 560, minHeight: isStandaloneWindow ? 600 : 520)
        .background(Theme.page)
        .sheet(isPresented: $showBillingEditor) {
            BillingPromptView(
                summary: (session.projectName, timeRange, session.activeSeconds, session.usage),
                initialSettings: session.billing ?? .defaultSettings,
                applyByDefault: true
            ) { billing in
                applyBilling(billing)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            SessionEditView(session: session)
        }
        .sheet(isPresented: $showTimeEditor) {
            SessionTimeEditView(session: session)
        }
    }

    private var billingColumn: some View {
        Group {
            if let result = billingResult {
                billingCard(result)
            } else {
                noBillingCard
            }
        }
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !session.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(session.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.surfaceRaised, in: Capsule())
                    }
                }
            }
            if !session.notes.isEmpty {
                Text(session.notes)
                    .font(.callout)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chrossCard()
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showBreadcrumb {
                HStack(spacing: 8) {
                    if let onBack {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Historique")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.surfaceRaised, in: Capsule())
                        }
                        .buttonStyle(.chross)
                        .keyboardShortcut(.cancelAction)
                    }
                    Text("\(Self.dateFormatter.string(from: session.startDate).capitalized) · \(timeRange)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if session.timeAdjusted {
                        adjustedBadge
                    }
                }
            }
            if isStandaloneWindow {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                    Text("SESSION TERMINÉE · \(Self.dateFormatter.string(from: session.startDate).uppercased()) · \(timeRange)")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.accentDim, in: Capsule())
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    titleText
                    Spacer(minLength: 12)
                    actionButtons
                }
                VStack(alignment: .leading, spacing: 14) {
                    titleText
                    actionButtons
                }
            }
        }
    }

    private var adjustedBadge: some View {
        Label("Horaires corrigés", systemImage: "clock.arrow.2.circlepath")
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.surfaceRaised, in: Capsule())
            .help("Les heures de cette session ont été ajustées à la main")
    }

    private var titleText: some View {
        Text(session.projectName.isEmpty ? "Session sans titre" : session.projectName)
            .font(.title.bold())
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.chross)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border))
                .help("Modifier")

                Button {
                    showTimeEditor = true
                } label: {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.chross)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border))
                .help("Corriger les horaires")
                .demoAnchor("summary.retime")

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.chross)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border))
                .help("Supprimer la session")
                .confirmationDialog("Supprimer cette session ?", isPresented: $showDeleteConfirmation) {
                    Button("Supprimer", role: .destructive, action: deleteSession)
                    Button("Annuler", role: .cancel) {}
                } message: {
                    Text("Elle sera définitivement retirée de l'historique.")
                }

                Button {
                    resume()
                } label: {
                    Label("Reprendre", systemImage: "play.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.chross)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border))
                .disabled(tracker.isRunning)

                Button {
                    exportInvoice()
                } label: {
                    Label("Exporter la facture", systemImage: "arrow.down.circle")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.chross)
                .background(Theme.accent, in: Capsule())

                if isStandaloneWindow {
                    Button {
                        dismiss()
                    } label: {
                        Text("Fermer")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.chross)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.border))
                    .keyboardShortcut(.cancelAction)
                }
        }
        .fixedSize()
    }

    private var statCards: some View {
        HStack(spacing: 16) {
            statCard(
                dotColor: Theme.accent,
                title: "Temps actif",
                value: DurationFormatter.format(session.activeSeconds),
                caption: percentageCaption
            )
            statCard(
                dotColor: Color.white.opacity(0.3),
                title: "Hors sélection",
                value: DurationFormatter.format(session.outOfScopeSeconds),
                caption: "Apps non suivies"
            )
            statCard(
                dotColor: Color.white.opacity(0.15),
                title: "Inactif",
                value: DurationFormatter.format(session.idleSeconds),
                caption: "Pauses auto"
            )
        }
    }

    private var percentageCaption: String {
        let total = session.activeSeconds + session.outOfScopeSeconds + session.idleSeconds
        guard total > 0 else { return "—" }
        let percentage = Int((session.activeSeconds / total) * 100)
        return "\(percentage) % de la session"
    }

    private func statCard(dotColor: Color, title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(dotColor).frame(width: 8, height: 8)
                Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Text(value).font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text(caption).font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chrossCard()
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Chronologie").font(.headline).foregroundStyle(Theme.textPrimary)
                TimelineBar(
                    segments: timelineSegments,
                    hoveredID: $hoveredSegmentID,
                    startLabel: Self.timeFormatter.string(from: session.startDate),
                    endLabel: Self.timeFormatter.string(from: session.endDate ?? session.startDate)
                )
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("Détail par app / site").font(.headline).foregroundStyle(Theme.textPrimary)
                VStack(spacing: 14) {
                    ForEach(Array(sortedUsage.enumerated()), id: \.element.id) { index, record in
                        usageRow(record, color: Theme.seriesColor(at: index))
                    }
                    if outOfScopeTotal > 0 {
                        outOfScopeRow
                    }
                }
            }
        }
        .chrossCard()
    }

    /// Only what the session actually tracks is listed one by one; everything else is
    /// summed into a single "Hors sélection" entry so dozens of visited domains never
    /// flood the breakdown.
    private var sortedUsage: [UsageRecord] {
        session.usage.filter(\.isDeclared).sorted { $0.seconds > $1.seconds }
    }

    private var outOfScopeRecords: [UsageRecord] {
        session.usage.filter { !$0.isDeclared }
    }

    private var outOfScopeTotal: TimeInterval {
        session.outOfScopeSeconds > 0
            ? session.outOfScopeSeconds
            : outOfScopeRecords.reduce(0) { $0 + $1.seconds }
    }

    private var outOfScopeSummary: String {
        let count = outOfScopeRecords.count
        switch count {
        case 0: return "Apps et sites non suivis"
        case 1: return "1 app ou site non suivi"
        default: return "\(count) apps et sites non suivis"
        }
    }

    private static let outOfScopeID = "chross.out-of-scope"

    private var outOfScopeRow: some View {
        let sessionTotal = session.activeSeconds + outOfScopeTotal + session.idleSeconds
        let fraction = sessionTotal > 0 ? min(1, outOfScopeTotal / sessionTotal) : 0
        let isHovered = hoveredSegmentID == Self.outOfScopeID

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "slash.circle")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Hors sélection")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(outOfScopeSummary + " · non comptabilisé")
                        .font(.caption2)
                        .foregroundStyle(.orange.opacity(0.85))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(DurationFormatter.formatShort(outOfScopeTotal))
                        .font(.callout.monospacedDigit().weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(Int(fraction * 100))% de la session")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Color.white.opacity(0.3)).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            isHovered ? Color.white.opacity(0.05) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredSegmentID = Self.outOfScopeID
            } else if isHovered {
                hoveredSegmentID = nil
            }
        }
    }

    private var timelineSegments: [TimelineSegment] {
        var segments = sortedUsage.enumerated().map { index, record in
            TimelineSegment(
                id: record.key,
                title: ItemDisplayHelper.cleanDisplayName(key: record.key, kind: record.kind, rawName: record.displayName),
                item: (record.kind, record.key),
                systemImage: nil,
                detail: record.kind == .website ? "Site web" : "Application",
                seconds: record.seconds,
                color: Theme.seriesColor(at: index),
                status: record.isDeclared ? .tracked : .outOfScope,
                estimatedValue: record.isDeclared ? estimatedValue(of: record.seconds) : nil
            )
        }
        if outOfScopeTotal > 0 {
            segments.append(TimelineSegment(
                id: Self.outOfScopeID,
                title: "Hors sélection",
                item: nil,
                systemImage: "slash.circle",
                detail: outOfScopeSummary,
                seconds: outOfScopeTotal,
                color: Color.white.opacity(0.3),
                status: .outOfScope,
                estimatedValue: nil
            ))
        }
        if session.idleSeconds > 0 {
            segments.append(TimelineSegment(
                id: "chross.idle",
                title: "Inactif",
                item: nil,
                systemImage: "moon.fill",
                detail: "Pauses automatiques",
                seconds: session.idleSeconds,
                color: Color.white.opacity(0.15),
                status: .idle,
                estimatedValue: nil
            ))
        }
        return segments
    }

    private func estimatedValue(of seconds: TimeInterval) -> String? {
        guard let billing = session.billing, billing.hourlyRate > 0 else { return nil }
        let value = billing.hourlyRate * Decimal(seconds) / 3600
        return "≈ " + CurrencyFormatter.format(value, currencyCode: billing.currencyCode) + " HT"
    }

    private func usageRow(_ record: UsageRecord, color: Color) -> some View {
        let cleanName = ItemDisplayHelper.cleanDisplayName(key: record.key, kind: record.kind, rawName: record.displayName)
        let fraction = session.activeSeconds > 0 ? min(1, record.seconds / session.activeSeconds) : 0
        let percentage = Int(fraction * 100)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ItemIconView(kind: record.kind, key: record.key, size: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(cleanName)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        Text(record.kind == .website ? "Web" : "App")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                        if record.isDeclared {
                            Text("· Suivi")
                                .font(.caption2)
                                .foregroundStyle(Theme.accent.opacity(0.85))
                        } else {
                            Text("· Hors sélection")
                                .font(.caption2)
                                .foregroundStyle(.orange.opacity(0.85))
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(DurationFormatter.formatShort(record.seconds))
                        .font(.callout.monospacedDigit().weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(percentage)%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(color).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            hoveredSegmentID == record.key ? Color.white.opacity(0.05) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredSegmentID = record.key
            } else if hoveredSegmentID == record.key {
                hoveredSegmentID = nil
            }
        }
    }

    private func billingCard(_ result: BillingResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Facturation").font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                if let billing = session.billing {
                    Text("\(billing.hourlyRate.formatted())€/h · arrondi \(billing.rounding.label)")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            VStack(spacing: 10) {
                billingRow("Durée facturée", DurationFormatter.format(result.roundedSeconds))
                billingRow("Sous-total HT", result.formattedSubtotal)
                if result.vatEnabled {
                    billingRow("TVA", result.formattedVAT)
                }
                Divider().background(Theme.border)
                HStack {
                    Text("Total TTC").font(.headline).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(result.formattedTotal).font(.title2.bold()).foregroundStyle(Theme.accent)
                }
            }

            Button {
                showBillingEditor = true
            } label: {
                Text("Modifier le taux")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.chross)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border))
        }
        .chrossCard()
    }

    private var noBillingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Facturation").font(.headline).foregroundStyle(Theme.textPrimary)
            Text("Cette session n'a pas été facturée.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)

            Button {
                showBillingEditor = true
            } label: {
                Text("Ajouter une facturation")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.chross)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .chrossCard()
    }

    private func billingRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Theme.textPrimary).monospacedDigit()
        }
        .font(.callout)
    }

    private func applyBilling(_ billing: BillingSettings?) {
        session.billing = billing
        if let billing {
            let calculation = BillingCalculator.calculate(activeSeconds: session.activeSeconds, usage: session.usage, settings: billing)
            session.billedTotal = calculation.total
        } else {
            session.billedTotal = nil
        }
    }

    /// Leaves the screen first, then deletes — the view must not render a deleted model.
    private func deleteSession() {
        let session = session
        close()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            coordinator.deleteSession(session, tracker: tracker, modelContext: modelContext)
        }
    }

    private func resume() {
        guard !tracker.isRunning else { return }
        coordinator.startSession(
            tracker: tracker,
            projectName: session.projectName,
            declaredItems: session.declaredItems,
            idleThresholdMinutes: defaultIdleMinutes,
            modelContext: modelContext
        )
        close()
    }

    private func close() {
        if let onBack {
            onBack()
        } else {
            dismiss()
        }
    }

    private func exportInvoice() {
        if session.invoiceNumber == nil {
            session.invoiceNumber = AppPreferences.reserveNextInvoiceNumber()
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(session.projectName.isEmpty ? "session" : session.projectName) - \(Self.dateFormatter.string(from: session.startDate)).pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let document = InvoiceDocumentView(
            session: session,
            result: billingResult,
            invoiceNumber: session.invoiceNumber ?? 1,
            companyName: companyName,
            companyAddress: companyAddress,
            companySiret: companySiret,
            companyIBAN: companyIBAN,
            logo: NSImage(data: companyLogoData)
        )
        PDFExporter.render(document, size: CGSize(width: 595, height: 842), to: url)
    }
}

#Preview {
    let session = WorkSession(
        projectName: "Refonte site — Client A",
        startDate: Date().addingTimeInterval(-5077),
        declaredItems: [
            TrackedItem(kind: .app, key: "com.apple.dt.Xcode", displayName: "Xcode"),
            TrackedItem(kind: .app, key: "com.google.Chrome", displayName: "Google Chrome"),
        ]
    )
    session.endDate = Date()
    session.activeSeconds = 4632
    session.outOfScopeSeconds = 185
    session.idleSeconds = 260
    session.usage = [
        UsageRecord(kind: .app, key: "com.apple.dt.Xcode", displayName: "Xcode", seconds: 3130, isDeclared: true),
        UsageRecord(kind: .app, key: "com.google.Chrome", displayName: "Google Chrome", seconds: 1262, isDeclared: true),
        UsageRecord(kind: .app, key: "com.apple.finder", displayName: "Finder", seconds: 240, isDeclared: false),
    ]
    session.billing = BillingSettings(hourlyRate: 50, currencyCode: "EUR", rounding: .fiveMinutes, vatEnabled: true, vatRatePercent: 20, billingBase: .totalDuration)
    session.billedTotal = 85

    return SessionSummaryView(session: session, showBreadcrumb: true)
        .environment(ActivityTracker())
        .environment(SessionCoordinator())
}

#Preview("Sans facturation") {
    let session = WorkSession(
        projectName: "Maintenance WordPress",
        startDate: Date().addingTimeInterval(-2700),
        declaredItems: []
    )
    session.endDate = Date()
    session.activeSeconds = 2700
    session.usage = [
        UsageRecord(kind: .website, key: "wordpress.com", displayName: "wordpress.com", seconds: 2700, isDeclared: true),
    ]

    return SessionSummaryView(session: session, showBreadcrumb: true)
        .environment(ActivityTracker())
        .environment(SessionCoordinator())
}
