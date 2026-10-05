import AppKit
import SwiftUI

struct MenuBarView: View {
    var tracker: ActivityTracker
    var coordinator: SessionCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if tracker.isRunning {
                Text(DurationFormatter.format(tracker.elapsed))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(tracker.isPaused ? .orange : Theme.accent)
                if tracker.isPaused {
                    HStack(spacing: 6) {
                        Circle().fill(.orange).frame(width: 6, height: 6)
                        Text("En pause").foregroundStyle(.orange)
                    }
                    .font(.caption.weight(.medium))
                } else if let key = tracker.currentItemKey, let kind = tracker.currentItemKind {
                    let clean = ItemDisplayHelper.cleanDisplayName(key: key, kind: kind, rawName: tracker.currentItemName)
                    HStack(spacing: 8) {
                        ItemIconView(kind: kind, key: key, size: 16)
                        Text(clean)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if tracker.isOutOfScope {
                            Text("Hors sélection")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Divider()
                Button(tracker.isPaused ? "Reprendre" : "Mettre en pause") {
                    if tracker.isPaused {
                        tracker.resumeManually()
                    } else {
                        tracker.pauseManually()
                    }
                }
                Button("Terminer la session") {
                    coordinator.requestStop(tracker: tracker)
                }
            } else {
                Text("Aucune session en cours")
                Divider()
                Button("Nouvelle session") {
                    NSApp.activate(ignoringOtherApps: true)
                    coordinator.showSetup = true
                }
            }
            Button("Ouvrir chross") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Quitter") {
                NSApp.terminate(nil)
            }
        }
        .padding(8)
        .frame(width: 220)
    }
}
