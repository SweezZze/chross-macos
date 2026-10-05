import SwiftUI

extension Color {
    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)
        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }
}

/// Shared dark, lime-accented visual language — colors, card chrome, and the pill
/// segmented control used throughout the redesigned chrono/session/billing screens.
enum Theme {
    static let accent = Color(hex: "D6FF3F")
    static let accentDim = accent.opacity(0.14)

    static let page = Color(hex: "0B0B0D")
    static let sidebar = Color(hex: "0E0E10")
    static let surface = Color(hex: "151518")
    static let surfaceRaised = Color(hex: "1C1C20")

    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.18)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)

    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 14

    /// Cycled, in order, across a sorted usage breakdown so the busiest app/site is
    /// always the brand lime and the rest stay visually distinct but muted.
    static let seriesColors: [Color] = [accent, Color(hex: "5B9CF6"), Color(hex: "F6935B"), Color.white.opacity(0.4)]

    static func seriesColor(at index: Int) -> Color {
        seriesColors[min(index, seriesColors.count - 1)]
    }
}

extension View {
    func chrossCard(padding: CGFloat = 20, radius: CGFloat = Theme.cardRadius) -> some View {
        self
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.border)
            )
    }
}

/// A bordered row of equal-width options with a soft highlight on the active one —
/// the "Jamais / 2 min / 5 min…" and "Aucun / 1 min / 5 min…" pickers in the mockups.
struct PillSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.callout.weight(selection == option ? .semibold : .regular))
                        .foregroundStyle(selection == option ? Theme.textPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selection == option ? Color.white.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.chross)
            }
        }
        .padding(4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Theme.border)
        )
    }
}

/// A small lime-tinted switch label used for "Facturer cette session" / "TVA" rows.
struct ThemedToggle: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.accent)
        }
    }
}

/// Decorative ruler/waveform under the giant timer — ticks progress through the lime
/// accent while the session is live, and sit flat gray once more are at rest.
struct WaveformTicker: View {
    var activeFraction: Double
    var tickCount: Int = 48

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let spacing: CGFloat = 3
            let tickWidth = max(1.5, (width - spacing * CGFloat(tickCount - 1)) / CGFloat(tickCount))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<tickCount, id: \.self) { index in
                    let progress = Double(index) / Double(tickCount - 1)
                    let isActive = activeFraction > 0 && progress < activeFraction
                    Capsule()
                        .fill(isActive ? Theme.accent : Color.white.opacity(0.12))
                        .frame(width: tickWidth, height: tickHeight(for: index))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 20)
    }

    private func tickHeight(for index: Int) -> CGFloat {
        let pattern: [CGFloat] = [8, 14, 20, 14, 8, 6]
        return pattern[index % pattern.count]
    }
}

/// Plain-looking button whose whole frame (padding and background included) is clickable,
/// with a subtle press feedback. Use instead of `.plain`, which only hit-tests opaque content.
struct ChrossButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ChrossButtonStyle {
    static var chross: ChrossButtonStyle { ChrossButtonStyle() }
}
