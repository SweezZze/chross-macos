import AppKit

struct RunningAppInfo: Identifiable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let name: String
    let icon: NSImage
}

enum RunningAppsProvider {
    static func currentRunningApps() -> [RunningAppInfo] {
        let all = NSWorkspace.shared.runningApplications
        let regular = all.filter { $0.activationPolicy == .regular }
        // Fall back to the full list if nothing qualifies as "regular" — better to show
        // more than expected than to leave the picker empty.
        let candidates = regular.isEmpty ? all : regular
        let ownPID = ProcessInfo.processInfo.processIdentifier

        return candidates
            .compactMap { app -> RunningAppInfo? in
                guard app.processIdentifier != ownPID,
                      let bundleID = app.bundleIdentifier,
                      let name = app.localizedName else { return nil }
                return RunningAppInfo(bundleIdentifier: bundleID, name: name, icon: app.icon ?? NSImage())
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
