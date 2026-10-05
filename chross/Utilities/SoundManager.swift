import AppKit
import Foundation

@MainActor
final class SoundManager {
    static let shared = SoundManager()

    private init() {}

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "soundEffectsEnabled") as? Bool ?? true
    }

    func playStart() {
        guard isEnabled else { return }
        NSSound(named: "Ping")?.play()
    }

    func playPause() {
        guard isEnabled else { return }
        NSSound(named: "Tink")?.play()
    }

    func playResume() {
        guard isEnabled else { return }
        NSSound(named: "Pop")?.play()
    }

    func playPomodoroBreak() {
        guard isEnabled else { return }
        NSSound(named: "Glass")?.play()
    }

    func playPomodoroFocus() {
        guard isEnabled else { return }
        NSSound(named: "Ping")?.play()
    }

    func playGoalReached() {
        guard isEnabled else { return }
        NSSound(named: "Hero")?.play()
    }
}
