import AppKit
import SwiftUI

enum ItemDisplayHelper {
    /// Resolves the application icon for a bundle identifier.
    static func appIcon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }

        // 1. Try running applications first (fastest and handles custom Dock icons)
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
           let icon = running.icon {
            return icon
        }

        // 2. Try URL for application bundle
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        return nil
    }

    /// Cleans and formats the display name for an app or website so it never shows raw bundle IDs or URLs with query strings.
    static func cleanDisplayName(key: String, kind: TrackedItem.Kind, rawName: String?) -> String {
        if kind == .website {
            if let normalized = DomainNormalizer.normalize(rawName ?? key) {
                return normalized
            }
            return key.trimmingCharacters(in: .whitespaces).lowercased()
        }

        // Kind is .app:
        if let rawName, !rawName.isEmpty {
            let trimmed = rawName.trimmingCharacters(in: .whitespaces)
            // If it's a clean human name (not "com.apple.dt.Xcode" or "com.google.Chrome")
            if !trimmed.contains(".") || !trimmed.hasPrefix("com.") {
                return trimmed
            }
        }

        // Lookup from bundle identifier
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) {
            let bundleName = Bundle(url: url)?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                ?? Bundle(url: url)?.infoDictionary?["CFBundleDisplayName"] as? String
                ?? Bundle(url: url)?.infoDictionary?["CFBundleName"] as? String
            if let bundleName, !bundleName.isEmpty {
                return bundleName
            }
            let fileDisplay = FileManager.default.displayName(atPath: url.path)
            return fileDisplay.replacingOccurrences(of: ".app", with: "")
        }

        // Special common fallbacks
        if key == "com.apple.dt.Xcode" { return "Xcode" }
        if key.contains("Chrome") { return "Google Chrome" }
        if key.contains("Safari") { return "Safari" }
        if key.contains("Terminal") { return "Terminal" }
        if key.contains("Finder") { return "Finder" }
        if key.contains("chross") { return "Chross" }

        return rawName ?? key
    }
}

/// A unified visual representation for an application or website.
struct ItemIconView: View {
    let kind: TrackedItem.Kind
    let key: String
    var size: CGFloat = 24

    var body: some View {
        Group {
            if kind == .app {
                if let icon = ItemDisplayHelper.appIcon(forBundleID: key) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .fill(Theme.surfaceRaised)
                        Image(systemName: "app.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: size * 0.55, height: size * 0.55)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(width: size, height: size)
                }
            } else {
                WebsiteIconView(domain: key, size: size)
            }
        }
    }
}

/// Shows a site's favicon once `FaviconProvider` has it, with the globe badge meanwhile
/// (and for sites that really have no icon).
struct WebsiteIconView: View {
    let domain: String
    var size: CGFloat = 24

    private var provider: FaviconProvider { .shared }
    private var normalizedDomain: String { DomainNormalizer.normalize(domain) ?? domain }

    var body: some View {
        Group {
            if let image = provider.image(for: normalizedDomain) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.8, height: size * 0.8)
                    .frame(width: size, height: size)
                    .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                        .fill(Theme.accent.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                                .strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1)
                        )
                    Image(systemName: "globe")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size * 0.55, height: size * 0.55)
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: size, height: size)
            }
        }
        .task(id: normalizedDomain) {
            await provider.load(normalizedDomain)
        }
    }
}
