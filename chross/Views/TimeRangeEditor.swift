import SwiftUI

/// Graphical editor for a session's time span: drag the two handles to crop the start/end,
/// drag across the bar to cut out a period, then move or resize those cut-outs. Everything
/// snaps to 5 minutes (and back onto the original times when dragged close to them).
struct TimeRangeEditor: View {
    let originalStart: Date
    let originalEnd: Date
    @Binding var start: Date
    @Binding var end: Date
    @Binding var periods: [SessionTimeAdjustment.Period]

    @State private var drag: DragState?
    @State private var hoveredPeriodID: UUID?

    private enum DragState {
        case start
        case end
        case create(id: UUID, anchor: Date)
        case move(id: UUID, original: SessionTimeAdjustment.Period)
        case resizeStart(id: UUID)
        case resizeEnd(id: UUID)
    }

    private let labelHeight: CGFloat = 26
    private let trackHeight: CGFloat = 52
    private let tickHeight: CGFloat = 22
    private let snapStep: TimeInterval = 5 * 60
    private let minimumLength: TimeInterval = 5 * 60

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// Fixed for the whole edit (based on the original times) so the scale never shifts
    /// under the cursor while dragging. Leaves room on both sides to extend the session.
    private var domain: ClosedRange<Date> {
        let length = max(originalEnd.timeIntervalSince(originalStart), 15 * 60)
        let padding = min(3 * 3600, max(45 * 60, length * 0.3))
        return originalStart.addingTimeInterval(-padding)...originalEnd.addingTimeInterval(padding)
    }

    private var domainLength: TimeInterval {
        domain.upperBound.timeIntervalSince(domain.lowerBound)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                trackBackground(width: width)
                originalOutline(width: width)
                keptRange(width: width)
                ForEach(periods) { period in
                    periodBlock(period, width: width)
                }
                handle(isStart: true, width: width)
                handle(isStart: false, width: width)
                ticks(width: width)
            }
            .coordinateSpace(name: "timeline")
        }
        .frame(height: labelHeight + trackHeight + tickHeight)
    }

    // MARK: - Layers

    private func trackBackground(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border))
            .frame(width: width, height: trackHeight)
            .offset(y: labelHeight)
            .contentShape(Rectangle())
            .gesture(createPeriodGesture(width: width))
            .pointerStyle(.horizontalText)
            .demoAnchor("editor.track")
    }

    /// Dashed outline of the times as recorded, so it's obvious what was changed.
    private func originalOutline(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Theme.textTertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(width: max(0, x(originalEnd, width) - x(originalStart, width)), height: trackHeight - 8)
            .offset(x: x(originalStart, width), y: labelHeight + 4)
            .allowsHitTesting(false)
    }

    private func keptRange(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.accent.opacity(0.22))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.8), lineWidth: 1.5)
            )
            .frame(width: max(0, x(end, width) - x(start, width)), height: trackHeight - 8)
            .offset(x: x(start, width), y: labelHeight + 4)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func periodBlock(_ period: SessionTimeAdjustment.Period, width: CGFloat) -> some View {
        let visibleStart = max(period.start, start)
        let visibleEnd = min(period.end, end)
        let blockWidth = x(visibleEnd, width) - x(visibleStart, width)
        let isHovered = hoveredPeriodID == period.id

        if blockWidth > 0 {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.surface)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.orange.opacity(isHovered ? 0.4 : 0.28))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.9), lineWidth: 1.5)
                if blockWidth > 74 {
                    VStack(spacing: 1) {
                        Image(systemName: "scissors")
                            .font(.caption2.weight(.semibold))
                        Text(DurationFormatter.formatShort(visibleEnd.timeIntervalSince(visibleStart)))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                    }
                    .foregroundStyle(Color.orange)
                } else if blockWidth > 18 {
                    Image(systemName: "scissors")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.orange)
                }
            }
            .frame(width: blockWidth, height: trackHeight - 8)
            .contentShape(Rectangle())
            .gesture(movePeriodGesture(period, width: width))
            .pointerStyle(.grabIdle)
            .overlay(alignment: .leading) { resizeZone(period, isStart: true, width: width) }
            .overlay(alignment: .trailing) { resizeZone(period, isStart: false, width: width) }
            .overlay(alignment: .top) {
                if isHovered {
                    Button {
                        periods.removeAll { $0.id == period.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.white, Color.orange)
                    }
                    .buttonStyle(.chross)
                    .help("Ne plus retirer cette période")
                    .offset(y: -10)
                }
            }
            .onHover { hovering in
                if hovering {
                    hoveredPeriodID = period.id
                } else if hoveredPeriodID == period.id {
                    hoveredPeriodID = nil
                }
            }
            .contextMenu {
                Button("Ne plus retirer cette période", role: .destructive) {
                    periods.removeAll { $0.id == period.id }
                }
            }
            .offset(x: x(visibleStart, width), y: labelHeight + 4)
            .overlay(alignment: .topLeading) {
                if isHovered || isDragging(period.id) {
                    timeChip("\(format(period.start)) – \(format(period.end))", tint: .orange)
                        .fixedSize()
                        .offset(x: clampLabelX(x(visibleStart, width) + blockWidth / 2, width: width) - 46, y: 0)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func resizeZone(_ period: SessionTimeAdjustment.Period, isStart: Bool, width: CGFloat) -> some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline"))
                    .onChanged { value in
                        guard let index = periods.firstIndex(where: { $0.id == period.id }) else { return }
                        let date = snapped(date(at: value.location.x, width: width))
                        if isStart {
                            drag = .resizeStart(id: period.id)
                            periods[index].start = min(max(date, start), periods[index].end.addingTimeInterval(-minimumLength))
                        } else {
                            drag = .resizeEnd(id: period.id)
                            periods[index].end = max(min(date, end), periods[index].start.addingTimeInterval(minimumLength))
                        }
                    }
                    .onEnded { _ in drag = nil }
            )
    }

    private func handle(isStart: Bool, width: CGFloat) -> some View {
        let date = isStart ? start : end
        let position = x(date, width)

        return ZStack(alignment: .top) {
            Capsule()
                .fill(Theme.accent)
                .frame(width: 6, height: trackHeight + 6)
                .overlay(
                    VStack(spacing: 3) {
                        ForEach(0..<3) { _ in
                            Capsule().fill(Color.black.opacity(0.45)).frame(width: 2, height: 4)
                        }
                    }
                )
                .shadow(color: .black.opacity(0.4), radius: 3)
                .offset(y: labelHeight - 3)
        }
        .frame(width: 22, height: labelHeight + trackHeight + 6, alignment: .top)
        .demoAnchor(isStart ? "editor.start" : "editor.end")
        .contentShape(Rectangle())
        .pointerStyle(.columnResize)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline"))
                .onChanged { value in
                    let original = isStart ? originalStart : originalEnd
                    let newDate = snapped(self.date(at: value.location.x, width: width), magnetTo: original)
                    if isStart {
                        drag = .start
                        start = min(max(newDate, domain.lowerBound), end.addingTimeInterval(-minimumLength))
                    } else {
                        drag = .end
                        end = max(min(newDate, domain.upperBound), start.addingTimeInterval(minimumLength))
                    }
                }
                .onEnded { _ in drag = nil }
        )
        .offset(x: position - 11)
        .overlay(alignment: .topLeading) {
            timeChip(format(date), tint: Theme.accent)
                .fixedSize()
                .offset(x: clampLabelX(position, width: width) - 22, y: 0)
                .allowsHitTesting(false)
        }
    }

    private func ticks(width: CGFloat) -> some View {
        let step = tickStep(width: width)
        let first = (domain.lowerBound.timeIntervalSinceReferenceDate / step).rounded(.up) * step
        let dates = stride(from: first, through: domain.upperBound.timeIntervalSinceReferenceDate, by: step)
            .map { Date(timeIntervalSinceReferenceDate: $0) }

        return ZStack(alignment: .topLeading) {
            ForEach(dates, id: \.self) { date in
                let position = x(date, width)
                VStack(spacing: 2) {
                    Rectangle()
                        .fill(Theme.textTertiary.opacity(0.5))
                        .frame(width: 1, height: 4)
                    Text(format(date))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize()
                }
                .frame(width: 40)
                .offset(x: position - 20)
            }
        }
        .offset(y: labelHeight + trackHeight + 2)
        .allowsHitTesting(false)
    }

    private func timeChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint, in: Capsule())
    }

    // MARK: - Gestures

    /// Dragging across the kept part of the bar cuts out that period.
    private func createPeriodGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("timeline"))
            .onChanged { value in
                let current = min(max(snapped(date(at: value.location.x, width: width)), start), end)
                if case .create(let id, let anchor) = drag,
                   let index = periods.firstIndex(where: { $0.id == id }) {
                    periods[index].start = min(anchor, current)
                    periods[index].end = max(anchor, current)
                } else if drag == nil {
                    let anchor = snapped(date(at: value.startLocation.x, width: width))
                    guard anchor >= start, anchor <= end else { return }
                    let period = SessionTimeAdjustment.Period(start: anchor, end: anchor)
                    periods.append(period)
                    drag = .create(id: period.id, anchor: anchor)
                }
            }
            .onEnded { _ in
                if case .create(let id, _) = drag {
                    periods.removeAll { $0.id == id && $0.end.timeIntervalSince($0.start) < minimumLength }
                }
                drag = nil
            }
    }

    private func movePeriodGesture(_ period: SessionTimeAdjustment.Period, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("timeline"))
            .onChanged { value in
                if drag == nil {
                    drag = .move(id: period.id, original: period)
                }
                guard case .move(let id, let original) = drag,
                      let index = periods.firstIndex(where: { $0.id == id }) else { return }
                let length = original.end.timeIntervalSince(original.start)
                let delta = TimeInterval(value.translation.width / width) * domainLength
                var newStart = snapped(original.start.addingTimeInterval(delta))
                newStart = min(max(newStart, start), max(start, end.addingTimeInterval(-length)))
                periods[index].start = newStart
                periods[index].end = newStart.addingTimeInterval(length)
            }
            .onEnded { _ in drag = nil }
    }

    // MARK: - Geometry & time

    private func x(_ date: Date, _ width: CGFloat) -> CGFloat {
        CGFloat(date.timeIntervalSince(domain.lowerBound) / domainLength) * width
    }

    private func date(at x: CGFloat, width: CGFloat) -> Date {
        let fraction = min(max(Double(x / max(width, 1)), 0), 1)
        return domain.lowerBound.addingTimeInterval(fraction * domainLength)
    }

    private func snapped(_ date: Date, magnetTo original: Date? = nil) -> Date {
        if let original, abs(date.timeIntervalSince(original)) < 3 * 60 {
            return original
        }
        let seconds = (date.timeIntervalSinceReferenceDate / snapStep).rounded() * snapStep
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    private func tickStep(width: CGFloat) -> TimeInterval {
        let maxTicks = max(2, Double(width / 64))
        let candidates: [TimeInterval] = [5, 10, 15, 30, 60, 120, 180, 240, 360].map { $0 * 60 }
        return candidates.first { domainLength / $0 <= maxTicks } ?? 720 * 60
    }

    private func clampLabelX(_ x: CGFloat, width: CGFloat) -> CGFloat {
        min(max(x, 24), width - 24)
    }

    private func format(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private func isDragging(_ id: UUID) -> Bool {
        switch drag {
        case .create(let dragID, _), .move(let dragID, _), .resizeStart(let dragID), .resizeEnd(let dragID):
            return dragID == id
        default:
            return false
        }
    }
}
