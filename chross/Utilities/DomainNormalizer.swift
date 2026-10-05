import Foundation

/// Turns free-form user input (a bare domain, or a full URL with scheme/path/query)
/// into the same bare, lowercase host format that `BrowserURLReader` resolves from a
/// live browser tab, so declared websites can be matched against what's detected.
enum DomainNormalizer {
    static func normalize(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let urlString = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        let host = URL(string: urlString)?.host ?? trimmed
        return normalize(host: host)
    }

    static func normalize(host: String) -> String {
        let lower = host.lowercased()
        let withoutPath = lower.split(separator: "/").first.map(String.init) ?? lower
        return withoutPath.hasPrefix("www.") ? String(withoutPath.dropFirst(4)) : withoutPath
    }
}
