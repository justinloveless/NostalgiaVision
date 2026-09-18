import Foundation

/// Everything between "a URL the viewer typed" and "an ordered lineup of playable channels".
///
/// Hidden behind this one method: HTTP, redirects, timeouts, response-code handling, text encoding
/// sniffing, M3U syntax, relative URL resolution and malformed-entry tolerance. Nothing on this
/// surface is a transport type — no `URLSession`, no `URLResponse`, no `Data`, no playlist line.
protocol ChannelFeed: Sendable {
    func lineup(from url: FeedURL) async -> FeedOutcome
}

/// Deliberately not `Result`: "a usable lineup that nonetheless had trouble" is a real state (some
/// entries were skipped), and so is "no lineup, and here is why". A `Result` would force one of
/// them to be smuggled inside the other.
struct FeedOutcome: Sendable, Equatable {
    /// Possibly `.deadAir`. Never nil — the dial always has something to point at.
    let cycle: TuningCycle
    /// Non-nil even when `cycle` is perfectly usable.
    let trouble: FeedTrouble?
}

/// Domain-level trouble. `URLError`, status codes, and encoding failures are mapped to these inside
/// `TunarrFeed` and never escape it.
enum FeedTrouble: Sendable, Equatable {
    case notConfigured
    /// DNS, refused, timeout, 5xx.
    case unreachable
    /// 401/403 — the server is behind auth.
    case rejected
    /// 200 with an HTML body, the classic captive-portal case.
    case notAPlaylist
    /// Valid playlist, zero channels.
    case empty
    /// Usable lineup, some entries dropped.
    case skippedEntries(Int)
}
