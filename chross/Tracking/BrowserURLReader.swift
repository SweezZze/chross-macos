import AppKit
import ApplicationServices
import Foundation

/// Whether chross has been granted the Accessibility permission it needs to read the
/// active tab URL from other apps. This is a single, one-time, system-wide permission
/// (System Settings → Privacy & Security → Accessibility) — unlike Apple Events
/// automation, it doesn't need a separate grant per target browser.
enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    private(set) static var didPromptThisLaunch = false

    /// Shows the system permission prompt at most once per launch — macOS re-displays it on
    /// every call while access is missing, so calling this repeatedly would nag the user.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        guard !isGranted else { return true }
        guard !didPromptThisLaunch else { return false }
        didPromptThisLaunch = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

/// Deep-links into System Settings' privacy panes, since macOS only shows its own
/// Accessibility prompt once — after a denial, the user has to grant it manually.
enum PermissionSettingsOpener {
    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Reads the active tab URL of the frontmost browser window.
///
/// Primary path is the Accessibility API, which works across Safari, every Chromium
/// browser and Firefox with a single system-wide permission. When it comes back empty
/// (tree still building, focus in the address bar, odd window layout…) Safari and the
/// Chromium family are asked directly over Apple Events as a fallback.
enum BrowserURLReader {
    private nonisolated static let browserBundleIdentifiers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.chromium.Chromium",
        "org.mozilla.firefox", "company.thebrowser.Browser",
    ]

    private nonisolated static let safariBundleIdentifiers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
    ]

    nonisolated static func isBrowser(bundleIdentifier: String) -> Bool {
        browserBundleIdentifiers.contains(bundleIdentifier)
    }

    nonisolated static func activeURL(forProcessIdentifier pid: pid_t, bundleIdentifier: String) -> URL? {
        if let url = accessibilityURL(pid: pid, bundleIdentifier: bundleIdentifier) {
            return url
        }
        return AppleScriptURLReader.activeURL(bundleIdentifier: bundleIdentifier)
    }

    /// Only real web pages count as sites — new tab, settings, extensions, PDFs on disk… don't.
    nonisolated static func isWebPage(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return false }
        return true
    }

    // MARK: - Accessibility

    private nonisolated static let enabledLock = NSLock()
    private nonisolated(unsafe) static var enabledPIDs: Set<pid_t> = []

    private nonisolated static func accessibilityURL(pid: pid_t, bundleIdentifier: String) -> URL? {
        guard AXIsProcessTrusted() else { return nil }

        let appElement = AXUIElementCreateApplication(pid)
        // A busy browser must never stall tracking — the default AX timeout is 6 s.
        AXUIElementSetMessagingTimeout(appElement, 0.5)

        if !safariBundleIdentifiers.contains(bundleIdentifier) {
            enableFullAccessibilityTree(appElement, pid: pid)
        }

        guard let window = elementAttribute(appElement, kAXFocusedWindowAttribute as CFString)
                ?? elementAttribute(appElement, kAXMainWindowAttribute as CFString) else { return nil }

        // Safari exposes the tab URL directly on the window.
        if let url = urlAttribute(window, kAXDocumentAttribute as CFString), isWebPage(url) {
            return url
        }

        // Fast path: when focus is inside the page, its web area is a few parents up.
        if let focused = elementAttribute(appElement, kAXFocusedUIElementAttribute as CFString),
           let webArea = ancestorWebArea(of: focused),
           let url = urlAttribute(webArea, "AXURL" as CFString), isWebPage(url) {
            return url
        }

        return firstWebPageURL(under: window)
    }

    /// Chromium and Electron only build the part of their tree that exposes page URLs once an
    /// assistive client asks for it. `AXManualAccessibility` is the switch Chromium documents
    /// for this; `AXEnhancedUserInterface` is only a fallback because it disturbs window
    /// animations and slows the browser down.
    private nonisolated static func enableFullAccessibilityTree(_ appElement: AXUIElement, pid: pid_t) {
        enabledLock.lock()
        let alreadyEnabled = enabledPIDs.contains(pid)
        if !alreadyEnabled { enabledPIDs.insert(pid) }
        enabledLock.unlock()
        guard !alreadyEnabled else { return }

        if AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue) != .success {
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    private nonisolated static func ancestorWebArea(of element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<40 {
            guard let node = current else { return nil }
            if stringAttribute(node, kAXRoleAttribute as CFString) == "AXWebArea" {
                // Nested frames are web areas too — keep climbing to the top-level page.
                if let parent = elementAttribute(node, kAXParentAttribute as CFString),
                   let outer = ancestorWebArea(of: parent) {
                    return outer
                }
                return node
            }
            current = elementAttribute(node, kAXParentAttribute as CFString)
        }
        return nil
    }

    /// Breadth-first so the page (shallow) is found before deep toolbar/tab-strip branches,
    /// with a node budget so a huge window can never make a tick expensive. Web areas are
    /// not descended into: page content can't contain the page's own URL.
    private nonisolated static func firstWebPageURL(under root: AXUIElement) -> URL? {
        var queue: [AXUIElement] = [root]
        var index = 0
        var visited = 0
        while index < queue.count, visited < 800 {
            let element = queue[index]
            index += 1
            visited += 1

            if stringAttribute(element, kAXRoleAttribute as CFString) == "AXWebArea" {
                if let url = urlAttribute(element, "AXURL" as CFString), isWebPage(url) {
                    return url
                }
                continue
            }
            if let children = childrenAttribute(element) {
                queue.append(contentsOf: children)
            }
        }
        return nil
    }

    private nonisolated static func elementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private nonisolated static func childrenAttribute(_ element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }

    private nonisolated static func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        if let string = value as? String { return string }
        if let url = value as? URL { return url.absoluteString }
        return nil
    }

    private nonisolated static func urlAttribute(_ element: AXUIElement, _ attribute: CFString) -> URL? {
        stringAttribute(element, attribute).flatMap { URL(string: $0) }
    }
}

/// Apple Events fallback for browsers that support scripting (Safari and the Chromium
/// family — Firefox doesn't). macOS asks the user once per browser; after a refusal the
/// browser is skipped for the rest of the launch so no prompt or slow call ever repeats.
enum AppleScriptURLReader {
    private nonisolated static let queue = DispatchQueue(label: "chross.applescript-url-reader")
    private nonisolated(unsafe) static var deniedBundleIDs: Set<String> = []
    private nonisolated(unsafe) static var askedBundleIDs: Set<String> = []
    private nonisolated(unsafe) static var compiledScripts: [String: NSAppleScript] = [:]

    private nonisolated static let chromiumBundleIdentifiers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.chromium.Chromium",
        "company.thebrowser.Browser",
    ]

    nonisolated static func activeURL(bundleIdentifier: String) -> URL? {
        let tabExpression: String
        if bundleIdentifier.hasPrefix("com.apple.Safari") {
            tabExpression = "URL of current tab of front window"
        } else if chromiumBundleIdentifiers.contains(bundleIdentifier) {
            tabExpression = "URL of active tab of front window"
        } else {
            return nil
        }

        return queue.sync {
            guard !deniedBundleIDs.contains(bundleIdentifier), isAuthorized(bundleIdentifier) else { return nil }

            let script: NSAppleScript
            if let cached = compiledScripts[bundleIdentifier] {
                script = cached
            } else {
                let source = """
                tell application id "\(bundleIdentifier)"
                    if (count of windows) is 0 then return ""
                    return \(tabExpression)
                end tell
                """
                guard let compiled = NSAppleScript(source: source) else { return nil }
                compiledScripts[bundleIdentifier] = compiled
                script = compiled
            }

            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if let code = error?[NSAppleScript.errorNumber] as? Int, code == -1743 {
                deniedBundleIDs.insert(bundleIdentifier)
                return nil
            }
            guard let string = result.stringValue, let url = URL(string: string),
                  BrowserURLReader.isWebPage(url) else { return nil }
            return url
        }
    }

    /// Checks Automation consent without blocking on a dialog, and only lets macOS show
    /// its prompt once per browser per launch.
    private nonisolated static func isAuthorized(_ bundleIdentifier: String) -> Bool {
        var target = AEAddressDesc()
        guard let data = bundleIdentifier.data(using: .utf8) else { return false }
        let created = data.withUnsafeBytes { bytes in
            AECreateDesc(typeApplicationBundleID, bytes.baseAddress, data.count, &target)
        }
        guard created == noErr else { return false }
        defer { AEDisposeDesc(&target) }

        let shouldAsk = !askedBundleIDs.contains(bundleIdentifier)
        if shouldAsk { askedBundleIDs.insert(bundleIdentifier) }
        let status = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, shouldAsk)

        switch status {
        case noErr:
            return true
        case OSStatus(errAEEventNotPermitted):
            deniedBundleIDs.insert(bundleIdentifier)
            return false
        default:
            // -1744: would need consent but we've already asked this launch; -600: not running.
            return false
        }
    }
}
