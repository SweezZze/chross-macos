import AppKit
import Observation
import ServiceManagement
import UserNotifications

/// Live view of the system permissions and login-item state chross depends on, shared by
/// the introduction and the settings. `refresh()` is cheap and is polled while those
/// screens are visible so toggles made in System Settings show up within a second or two.
@MainActor
@Observable
final class SystemPermissions {
    enum NotificationState {
        case notAsked, granted, denied
    }

    private(set) var accessibilityGranted = AccessibilityPermission.isGranted
    private(set) var notifications: NotificationState = .notAsked
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    func refresh() async {
        accessibilityGranted = AccessibilityPermission.isGranted
        launchAtLogin = SMAppService.mainApp.status == .enabled
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: notifications = .granted
        case .denied: notifications = .denied
        default: notifications = .notAsked
        }
    }

    /// Keeps the state fresh for as long as the calling view's task lives.
    func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    func requestAccessibility() {
        // The system dialog only shows once per launch; after that, go straight to Settings.
        if AccessibilityPermission.didPromptThisLaunch {
            PermissionSettingsOpener.openAccessibilitySettings()
        } else {
            AccessibilityPermission.requestIfNeeded()
        }
    }

    func requestNotifications() async {
        if notifications == .denied {
            openNotificationSettings()
            return
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refresh()
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // macOS may need the user to approve it in Login Items; open that pane.
            SMAppService.openSystemSettingsLoginItems()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
