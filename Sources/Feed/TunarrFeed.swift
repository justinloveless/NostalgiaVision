import Foundation

/// The only file in the app that imports or names `URLSession`.
///
/// One GET, one parse, one outcome. There is no lineup cache: the playlist is tiny, it is fetched
/// at launch and on URL change only, and a cold start with no server briefly shows trouble on the
/// settings slot rather than resurrecting a stale lineup.
struct TunarrFeed: ChannelFeed {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lineup(from url: FeedURL) async -> FeedOutcome {
        var request = URLRequest(url: url.url)
        request.timeoutInterval = 10
        // Playlists change whenever the viewer edits channels on the server; HTTP caching here
        // only produces confusing staleness.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return FeedOutcome(cycle: .deadAir, trouble: .unreachable)
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 401, 403:
                return FeedOutcome(cycle: .deadAir, trouble: .rejected)
            case 200..<300:
                break
            default:
                return FeedOutcome(cycle: .deadAir, trouble: .unreachable)
            }
        }

        // Some IPTV sources still emit Latin-1.
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return FeedOutcome(cycle: .deadAir, trouble: .notAPlaylist)
        }

        let parsed = M3UPlaylistParser.parse(text, relativeTo: url.url)
        guard parsed.looksLikeAPlaylist else {
            return FeedOutcome(cycle: .deadAir, trouble: .notAPlaylist)
        }
        guard !parsed.channels.isEmpty else {
            return FeedOutcome(cycle: .deadAir, trouble: .empty)
        }
        return FeedOutcome(
            cycle: TuningCycle(channels: parsed.channels),
            trouble: parsed.skipped > 0 ? .skippedEntries(parsed.skipped) : nil
        )
    }
}
