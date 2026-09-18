import Foundation

/// Stable identity across feed refreshes. Minted from the feed's own identifier when it has one,
/// otherwise derived deterministically from the stream URL, so resume-after-refresh works even for
/// feeds that omit identifiers.
struct ChannelID: Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// - Parameter tag: the feed-supplied identifier, if any. Blank is treated as absent.
    init(tag: String?, stream: URL) {
        let trimmed = tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.rawValue = trimmed.isEmpty ? "stream:\(stream.absoluteString)" : "feed:\(trimmed)"
    }
}

/// Non-empty display name. A blank channel name is unrepresentable.
struct ChannelName: Hashable, Codable, Sendable, CustomStringConvertible {
    private let value: String

    /// Trims whitespace; `nil` when nothing is left.
    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.value = trimmed
    }

    var description: String { value }
}

/// A tunable channel as the rest of the app sees it. Carries no playlist vocabulary, no HTTP types,
/// no wire text.
struct Channel: Identifiable, Hashable, Codable, Sendable {
    let id: ChannelID
    let name: ChannelName
    /// Absolute. The parser resolves relative playlist entries against the feed URL, so nothing
    /// downstream ever handles a relative URL.
    let stream: URL
    let logo: URL?
    /// Feed grouping, carried only for the on-screen channel bug. Never affects order.
    let group: String?
}

/// A feed URL that has already been proven usable: absolute, scheme http or https, with a host.
/// A `String` never reaches the networking layer.
struct FeedURL: Hashable, Codable, Sendable {
    private let raw: String
    private let resolved: URL

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        self.raw = trimmed
        self.resolved = url
    }

    var url: URL { resolved }

    /// Round-trips to exactly the text the viewer typed, for redisplay in settings.
    var text: String { raw }
}
