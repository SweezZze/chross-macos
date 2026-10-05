import SwiftUI

struct AccessibilityPermissionNotice: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Autorisation requise pour détecter les sites")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("macOS va te demander d'autoriser chross dans Réglages Système → Confidentialité et sécurité → Accessibilité.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
    }
}

/// Persistent, non-modal reminder shown while site detection can't work. Re-checks the
/// permission every couple of seconds so it disappears as soon as access is granted —
/// no system prompt is ever re-triggered from here.
struct AccessibilityStatusBanner: View {
    @State private var isGranted = AccessibilityPermission.isGranted

    var body: some View {
        Group {
            if !isGranted {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Détection des sites désactivée")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Active chross dans Réglages Système → Confidentialité et sécurité → Accessibilité.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Button {
                        PermissionSettingsOpener.openAccessibilitySettings()
                    } label: {
                        Text("Ouvrir les réglages")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.chross)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.3)))
            }
        }
        .task {
            while !Task.isCancelled && !isGranted {
                try? await Task.sleep(for: .seconds(2))
                isGranted = AccessibilityPermission.isGranted
            }
        }
    }
}
