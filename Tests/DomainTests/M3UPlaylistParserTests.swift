import XCTest
@testable import NostalgiaVision

final class M3UPlaylistParserTests: XCTestCase {

    private let base = URL(string: "https://tunarr.local:8000/api/channels.m3u")!

    /// Shaped like real Tunarr output, plus the malformed entries a real feed eventually grows.
    private let fixture = """
        #EXTM3U x-tvg-url="https://tunarr.local:8000/api/xmltv.xml"

        #EXTINF:-1 tvg-id="1" tvg-name="Cartoon Cavalcade" tvg-logo="https://tunarr.local:8000/logo/1.png" group-title="Kids",Cartoon Cavalcade
        https://tunarr.local:8000/stream/channels/1.m3u8
        #EXTINF:-1 tvg-id="2" tvg-name="Late Nite" tvg-logo="https://tunarr.local:8000/logo/2.png" group-title="Movies, Classic",Late Nite
        stream/channels/2.m3u8
        #EXTGRP:Movies
        #EXTINF:-1 tvg-id="" tvg-name="Rerun Ranch" group-title="Drama",
        https://tunarr.local:8000/stream/channels/3.m3u8
        #EXTINF:-1 tvg-id="4" tvg-name="" group-title="Noise",
        https://tunarr.local:8000/stream/channels/4.m3u8
        #EXTINF:-1 tvg-id="5" tvg-name="Dangling" group-title="Noise",Dangling
        """

    func testParsesTunarrShapedPlaylistInFeedOrder() {
        let parsed = M3UPlaylistParser.parse(fixture, relativeTo: base)

        XCTAssertTrue(parsed.looksLikeAPlaylist)
        XCTAssertEqual(parsed.channels.map { $0.name.description }, ["Cartoon Cavalcade", "Late Nite", "Rerun Ranch"])
        XCTAssertEqual(parsed.channels.map { $0.group }, ["Kids", "Movies, Classic", "Drama"])
        XCTAssertEqual(parsed.channels[0].logo?.absoluteString, "https://tunarr.local:8000/logo/1.png")
        XCTAssertNil(parsed.channels[2].logo)
    }

    func testSkipsTheNamelessEntryAndTheDanglingOne() {
        let parsed = M3UPlaylistParser.parse(fixture, relativeTo: base)

        XCTAssertEqual(parsed.skipped, 2)
        XCTAssertEqual(parsed.channels.count, 3)
    }

    func testRelativeStreamLinesAreResolvedAgainstTheFeedURL() {
        let parsed = M3UPlaylistParser.parse(fixture, relativeTo: base)

        XCTAssertEqual(
            parsed.channels[1].stream.absoluteString,
            "https://tunarr.local:8000/api/stream/channels/2.m3u8"
        )
    }

    func testIdentityComesFromTheFeedTagWhenPresentAndFromTheURLOtherwise() {
        let parsed = M3UPlaylistParser.parse(fixture, relativeTo: base)

        XCTAssertEqual(parsed.channels[0].id, ChannelID(tag: "1", stream: parsed.channels[0].stream))
        XCTAssertEqual(parsed.channels[2].id, ChannelID(tag: nil, stream: parsed.channels[2].stream))
        XCTAssertNotEqual(parsed.channels[0].id, parsed.channels[1].id)
    }

    func testDisplayNameFallsBackToTheFeedSuppliedName() {
        let parsed = M3UPlaylistParser.parse(fixture, relativeTo: base)

        XCTAssertEqual(parsed.channels[2].name.description, "Rerun Ranch")
    }

    func testRejectsNonPlaylistInput() {
        let html = """
            <!DOCTYPE html>
            <html><body><h1>401 Unauthorized</h1></body></html>
            """

        let parsed = M3UPlaylistParser.parse(html, relativeTo: base)

        XCTAssertFalse(parsed.looksLikeAPlaylist)
        XCTAssertTrue(parsed.channels.isEmpty)
        XCTAssertEqual(parsed.skipped, 0)
    }

    func testRejectsEmptyInput() {
        let parsed = M3UPlaylistParser.parse("", relativeTo: base)

        XCTAssertFalse(parsed.looksLikeAPlaylist)
    }

    func testAcceptsAHeaderOnlyPlaylistAsAnEmptyLineup() {
        let parsed = M3UPlaylistParser.parse("#EXTM3U\n", relativeTo: base)

        XCTAssertTrue(parsed.looksLikeAPlaylist)
        XCTAssertTrue(parsed.channels.isEmpty)
        XCTAssertEqual(parsed.skipped, 0)
    }

    func testTwoInfoLinesInARowSkipTheOrphanedOne() {
        let text = """
            #EXTM3U
            #EXTINF:-1 tvg-id="1",First
            #EXTINF:-1 tvg-id="2",Second
            https://tunarr.local:8000/stream/channels/2.m3u8
            """

        let parsed = M3UPlaylistParser.parse(text, relativeTo: base)

        XCTAssertEqual(parsed.skipped, 1)
        XCTAssertEqual(parsed.channels.map { $0.name.description }, ["Second"])
    }

    func testHandlesCarriageReturnsAndBlankLines() {
        let text = "#EXTM3U\r\n\r\n#EXTINF:-1 tvg-id=\"1\",First\r\nhttps://tunarr.local:8000/1.m3u8\r\n"

        let parsed = M3UPlaylistParser.parse(text, relativeTo: base)

        XCTAssertEqual(parsed.channels.count, 1)
        XCTAssertEqual(parsed.channels[0].stream.absoluteString, "https://tunarr.local:8000/1.m3u8")
    }
}
