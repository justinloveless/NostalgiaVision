import Foundation

/// The only file in the app that knows the strings `#EXTM3U`, `#EXTINF`, `tvg-id`, `tvg-name`,
/// `tvg-logo`, `group-title`, or that attribute values are double-quoted. Nothing it returns
/// mentions any of them.
enum M3UPlaylistParser {

    /// Pure: no I/O, no clock, no globals. Total: it cannot throw and cannot trap.
    ///
    /// Lenient by design. A single malformed entry must not black out the whole set, so
    /// unparseable entries are skipped and counted rather than failing the parse.
    ///
    /// Parsing rules, in one place:
    /// - The first non-blank line must be `#EXTM3U`; otherwise `looksLikeAPlaylist == false`
    ///   (almost always an HTML login page or a 404 body served with 200).
    /// - Each `#EXTINF:` line pairs with the next following line that is neither blank nor a
    ///   comment; that line is the stream URL.
    /// - The display name is the text after the first comma that is *outside* quotes, so neither a
    ///   comma inside `group-title="Movies, Classic"` nor one inside the name itself splits wrong.
    /// - If that text is blank, `tvg-name` is used; if that is blank too, the entry is skipped (a
    ///   nameless channel has no on-screen identity).
    /// - `id` = `tvg-id` when non-empty, else derived from the resolved stream URL.
    /// - A trailing `#EXTINF` with no following URL line is skipped.
    ///
    /// - Parameter base: the feed URL. Relative stream lines are resolved against it here, so
    ///   relative-vs-absolute is not a concept that exists anywhere else in the app.
    static func parse(_ text: String, relativeTo base: URL) -> Parsed {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let header = lines.first, header.uppercased().hasPrefix("#EXTM3U") else {
            return Parsed(channels: [], skipped: 0, looksLikeAPlaylist: false)
        }

        var channels: [Channel] = []
        var skipped = 0
        var pending: Entry?

        for line in lines.dropFirst() {
            if line.uppercased().hasPrefix("#EXTINF:") {
                if pending != nil { skipped += 1 }
                pending = Entry(line.dropFirst("#EXTINF:".count))
                continue
            }
            if line.hasPrefix("#") { continue }

            guard let entry = pending else { continue }
            pending = nil

            guard let stream = URL(string: line, relativeTo: base)?.absoluteURL, stream.scheme != nil,
                  let name = ChannelName(entry.displayName) ?? entry.attributes["tvg-name"].flatMap({ ChannelName($0) })
            else {
                skipped += 1
                continue
            }

            channels.append(
                Channel(
                    id: ChannelID(tag: entry.attributes["tvg-id"], stream: stream),
                    name: name,
                    stream: stream,
                    logo: entry.attributes["tvg-logo"].flatMap { URL(string: $0) },
                    group: entry.attributes["group-title"].flatMap { $0.isEmpty ? nil : $0 }
                )
            )
        }

        if pending != nil { skipped += 1 }

        return Parsed(channels: channels, skipped: skipped, looksLikeAPlaylist: true)
    }

    struct Parsed: Equatable, Sendable {
        /// Feed order preserved exactly. This ordering is the product feature.
        let channels: [Channel]
        let skipped: Int
        let looksLikeAPlaylist: Bool
    }

    private struct Entry {
        let attributes: [String: String]
        let displayName: String

        init(_ body: Substring) {
            let (head, tail) = Entry.splitAtUnquotedComma(body)
            self.attributes = Entry.attributes(in: head)
            self.displayName = tail.trimmingCharacters(in: .whitespaces)
        }

        private static func splitAtUnquotedComma(_ body: Substring) -> (Substring, Substring) {
            var inQuotes = false
            var index = body.startIndex
            while index < body.endIndex {
                let character = body[index]
                if character == "\"" {
                    inQuotes.toggle()
                } else if character == "," && !inQuotes {
                    return (body[body.startIndex..<index], body[body.index(after: index)...])
                }
                index = body.index(after: index)
            }
            return (body, "")
        }

        private static func attributes(in text: Substring) -> [String: String] {
            var found: [String: String] = [:]
            var rest = text
            while let equals = rest.firstIndex(of: "=") {
                let key = rest[rest.startIndex..<equals]
                    .split(whereSeparator: { $0 == " " || $0 == "\t" })
                    .last
                    .map { String($0).lowercased() }
                let afterEquals = rest.index(after: equals)
                guard afterEquals < rest.endIndex, rest[afterEquals] == "\"" else {
                    rest = rest[afterEquals...]
                    continue
                }
                let valueStart = rest.index(after: afterEquals)
                guard let closing = rest[valueStart...].firstIndex(of: "\"") else { break }
                if let key, !key.isEmpty {
                    found[key] = String(rest[valueStart..<closing])
                }
                rest = rest[rest.index(after: closing)...]
            }
            return found
        }
    }
}
