import AppKit
import CryptoKit
import Foundation
import Observation

/// Finds, downloads and caches website icons.
///
/// Sites declare their icon in many different ways, so several sources are tried in order
/// until one returns a real image:
///   1. Google's favicon service (fast, covers most sites, 404s when it only has a generic globe)
///   2. The icons the page itself declares in its HTML (`<link rel="icon" | "apple-touch-icon">`)
///   3. `/favicon.ico` at the site root
///   4. DuckDuckGo's icon service
/// Subdomains with nothing of their own fall back to the parent domain (docs.foo.com → foo.com).
/// Results are kept in memory and on disk; misses are remembered for a day so a site without
/// an icon is not re-fetched on every render.
@Observable
final class FaviconProvider {
    static let shared = FaviconProvider()

    private(set) var images: [String: NSImage] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var misses: [String: Date] = [:]

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.httpAdditionalHeaders = [
            // Some sites only serve their real markup (and icons) to browser-like clients.
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
        ]
        return URLSession(configuration: configuration)
    }()

    private let cacheDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("chross/favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    private init() {}

    func image(for domain: String) -> NSImage? {
        images[domain]
    }

    func load(_ rawDomain: String) async {
        let domain = DomainNormalizer.normalize(rawDomain) ?? rawDomain
        guard !domain.isEmpty, images[domain] == nil, !inFlight.contains(domain) else { return }
        if let missedAt = misses[domain], Date().timeIntervalSince(missedAt) < 86_400 { return }

        if let cached = loadFromDisk(domain) {
            images[domain] = cached
            return
        }

        inFlight.insert(domain)
        defer { inFlight.remove(domain) }

        var image: NSImage?
        for candidate in Self.candidateDomains(for: domain) {
            if let found = await fetchIcon(for: candidate) {
                image = found
                break
            }
        }

        if let image {
            images[domain] = image
            saveToDisk(image, for: domain)
        } else {
            misses[domain] = Date()
        }
    }

    // MARK: - Sources

    private func fetchIcon(for domain: String) async -> NSImage? {
        let encoded = domain.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? domain

        if let url = URL(string: "https://www.google.com/s2/favicons?domain=\(encoded)&sz=64"),
           let image = await fetchImage(url) {
            return image
        }

        for url in await declaredIconURLs(for: domain) {
            if let image = await fetchImage(url) {
                return image
            }
        }

        if let url = URL(string: "https://\(domain)/favicon.ico"), let image = await fetchImage(url) {
            return image
        }

        if let url = URL(string: "https://icons.duckduckgo.com/ip3/\(encoded).ico"), let image = await fetchImage(url) {
            return image
        }

        return nil
    }

    /// Reads the site's home page and returns the icons it declares, best first.
    private func declaredIconURLs(for domain: String) async -> [URL] {
        guard let pageURL = URL(string: "https://\(domain)/"),
              let (data, response) = try? await session.data(from: pageURL),
              let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
              let html = String(data: data.prefix(300_000), encoding: .utf8)
                ?? String(data: data.prefix(300_000), encoding: .isoLatin1) else { return [] }

        let baseURL = http.url ?? pageURL
        var scored: [(url: URL, score: Int)] = []

        for tag in Self.matches(of: "<link\\b[^>]*>", in: html) {
            guard let rel = Self.attribute("rel", in: tag)?.lowercased(),
                  rel.contains("icon"),
                  let href = Self.attribute("href", in: tag),
                  let url = URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: baseURL)?.absoluteURL
            else { continue }

            var score = 0
            if rel.contains("apple-touch-icon") { score += 50 }
            if let sizes = Self.attribute("sizes", in: tag),
               let first = sizes.split(separator: "x").first, let size = Int(first) {
                score += min(size, 256) / 4
            }
            if url.pathExtension.lowercased() == "svg" { score += 20 }
            scored.append((url, score))
        }

        return scored.sorted { $0.score > $1.score }.map(\.url)
    }

    private func fetchImage(_ url: URL) async -> NSImage? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              !data.isEmpty,
              let image = NSImage(data: data),
              image.size.width >= 8, image.size.height >= 8 else { return nil }
        return image
    }

    // MARK: - Helpers

    /// `docs.github.com` → [`docs.github.com`, `github.com`]. Stops at the registrable
    /// domain (keeps two labels, three for `co.uk`-style suffixes).
    static func candidateDomains(for domain: String) -> [String] {
        var labels = domain.split(separator: ".").map(String.init)
        var candidates = [domain]
        let shortSecondLevel: Set<String> = ["co", "com", "net", "org", "gov", "ac", "edu"]
        while labels.count > 2 {
            labels.removeFirst()
            if labels.count == 2, shortSecondLevel.contains(labels[0]) { break }
            candidates.append(labels.joined(separator: "."))
        }
        return candidates
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for group in 1...3 {
            if let range = Range(match.range(at: group), in: tag) {
                return String(tag[range])
            }
        }
        return nil
    }

    private func diskURL(for domain: String) -> URL {
        let hash = SHA256.hash(data: Data(domain.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(hash).appendingPathExtension("png")
    }

    private func loadFromDisk(_ domain: String) -> NSImage? {
        let url = diskURL(for: domain)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < 30 * 86_400 else { return nil }
        return NSImage(contentsOf: url)
    }

    private func saveToDisk(_ image: NSImage, for domain: String) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: diskURL(for: domain), options: .atomic)
    }
}
