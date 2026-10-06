import SwiftUI

/// One slice of the session breakdown bar, with everything its hover card shows.
struct TimelineSegment: Identifiable {
    enum Status {
        case tracked, outOfScope, idle

        var label: String {
            switch self {
            case .tracked: return "Suivi"
            case .outOfScope: return "Hors sélection"
            case .idle: return "Inactif"
            }
        }

        var color: Color {
            switch self {
            case .tracked: return Theme.accent
            case .outOfScope: return .orange
            case .idle: return Theme.textTertiary
            }
        }
    }

    let id: String
    let title: String
    /// Set for apps and sites (shows their icon); nil for the out-of-scope / idle totals.
    let item: (kind: TrackedItem.Kind, key: String)?
    let systemImage: String?
    let detail: String?
    let seconds: TimeInterval
    let color: Color
    let status: Status
    /// Value of this time at the session's hourly rate, when the session is billed.
    let estimatedValue: String?
}

/// Proportional bar of a session's time with a fixed-height detail strip underneath.
/// The strip shows the session's start/end times at rest and the hovered slice's details
/// on hover — it always occupies the same space, so nothing is covered and nothing jumps.
/// Shares the hovered slice through `hoveredID` so the matching list row lights up too.
struct TimelineBar: View {
    let segments: [TimelineSegment]
    @Binding var hoveredID: String?
    let startLabel: String
    let endLabel: String
    var height: CGFloat = 28

    private let spacing: CGFloat = 2
    private let stripHeight: CGFloat = 48

    private var total: TimeInterval {
        max(segments.reduce(0) { $0 + $1.seconds }, 1)
    }

    private var hoveredSegment: TimelineSegment? {
        hoveredID.flatMap { id in segments.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            bar
            detailStrip
                .frame(height: stripHeight)
                .animation(.easeOut(duration: 0.12), value: hoveredID)
        }
    }

    private var bar: some View {
        GeometryReader { proxy in
            let widths = segmentWidths(totalWidth: proxy.size.width)

            HStack(spacing: spacing) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(segment.color)
                        .frame(width: widths[index])
                        .opacity(hoveredID == nil || hoveredID == segment.id ? 1 : 0.35)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredID = segmentID(at: location.x, widths: widths)
                case .ended:
                    hoveredID = nil
                }
            }
            .animation(.easeOut(duration: 0.12), value: hoveredID)
        }
        .frame(height: height)
        .demoAnchor("timelineBar")
    }

    @ViewBuilder
    private var detailStrip: some View {
        if let segment = hoveredSegment {
            segmentDetail(segment)
                .transition(.opacity)
        } else {
            VStack(spacing: 6) {
                HStack {
                    Text(startLabel)
                    Spacer()
                    Text(endLabel)
                }
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                Text("Survole la barre pour voir le détail")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary.opacity(0.7))
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .transition(.opacity)
        }
    }

    private func segmentDetail(_ segment: TimelineSegment) -> some View {
        let share = Int((segment.seconds / total * 100).rounded())

        return HStack(spacing: 12) {
            if let item = segment.item {
                ItemIconView(kind: item.kind, key: item.key, size: 26)
            } else if let systemImage = segment.systemImage {
                Image(systemName: systemImage)
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(segment.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let detail = segment.detail {
                        Text(detail).foregroundStyle(Theme.textTertiary)
                        Text("·").foregroundStyle(Theme.textTertiary)
                    }
                    Text(segment.status.label).foregroundStyle(segment.status.color)
                }
                .font(.caption2)
                .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            if let estimatedValue = segment.estimatedValue {
                Text(estimatedValue)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .fixedSize()
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(DurationFormatter.format(segment.seconds))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(share) % de la session")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border))
    }

    private func segmentWidths(totalWidth: CGFloat) -> [CGFloat] {
        let gaps = spacing * CGFloat(max(segments.count - 1, 0))
        let usable = max(0, totalWidth - gaps)
        return segments.map { usable * CGFloat($0.seconds / total) }
    }

    private func segmentID(at x: CGFloat, widths: [CGFloat]) -> String? {
        var cursor: CGFloat = 0
        for (index, width) in widths.enumerated() {
            // Each slice also owns half of the gap on either side, so there are no dead zones.
            if x < cursor + width + spacing / 2 {
                return segments[index].id
            }
            cursor += width + spacing
        }
        return segments.last?.id
    }
}
