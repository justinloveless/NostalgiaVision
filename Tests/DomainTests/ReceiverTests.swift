import XCTest
@testable import NostalgiaVision

/// Nothing here reaches the network: the assertions are about what `Receiver` leaves its
/// `KSPlayerLayer` pointing at, which `set(url:)` applies synchronously on the main actor.
/// A discarded port keeps the decoder's own open attempt from outliving the test.
@MainActor
final class ReceiverTests: XCTestCase {
    private func channel(_ name: String) -> Channel {
        let stream = URL(string: "http://127.0.0.1:9/\(name).m3u8")!
        return Channel(
            id: ChannelID(tag: name, stream: stream),
            name: ChannelName(name)!,
            stream: stream,
            logo: nil,
            group: nil
        )
    }

    /// The regression guard for "the first channel back from settings never loads".
    ///
    /// `KSPlayerLayer` only rebuilds its decoder when the URL it is handed differs from the one it
    /// already holds, so a `stop()` that leaves the released channel's URL in place makes that
    /// channel permanently unplayable until some other channel displaces it. Releasing the stream
    /// therefore has to release the URL too.
    func testStopReleasesTheLayersHoldOnTheChannelsURL() {
        let only = channel("only")
        let receiver = Receiver()
        defer { receiver.stop() }

        receiver.tune(to: only)
        XCTAssertEqual(receiver.playerLayer.url, only.stream, "tuning should point the layer at the channel")

        receiver.stop()
        XCTAssertNotEqual(
            receiver.playerLayer.url,
            only.stream,
            "stop() must move the layer off the channel, or re-tuning it cannot reload"
        )
    }

    func testRetuningTheSameChannelAfterStopPointsAtItAgain() {
        let only = channel("only")
        let receiver = Receiver()
        defer { receiver.stop() }

        receiver.tune(to: only)
        receiver.stop()
        receiver.tune(to: only)

        XCTAssertEqual(receiver.playerLayer.url, only.stream)
    }

    /// `tune(to:)`'s identity guard is what makes turning up and back down onto the channel that
    /// never stopped playing a true no-op, so it must survive the stop/park handling around it.
    func testTuningToTheChannelAlreadyPlayingIsANoOp() {
        let a = channel("a")
        let b = channel("b")
        let receiver = Receiver()
        defer { receiver.stop() }

        receiver.tune(to: a)
        receiver.tune(to: b)
        receiver.tune(to: b)

        XCTAssertEqual(receiver.playerLayer.url, b.stream)
    }
}
