import XCTest
@testable import NostalgiaVision

final class DialTests: XCTestCase {

    private func channel(_ name: String) -> Channel {
        let stream = URL(string: "https://tunarr.local/stream/\(name).m3u8")!
        return Channel(
            id: ChannelID(tag: name, stream: stream),
            name: ChannelName(name)!,
            stream: stream,
            logo: nil,
            group: nil
        )
    }

    func testKnobWrapsThroughSettingsGoingUp() {
        let a = channel("a"), b = channel("b"), c = channel("c")
        var dial = Dial(cycle: TuningCycle(channels: [a, b, c]), resuming: nil)

        XCTAssertEqual(dial.position.channelID, a.id)
        dial.turn(.up)
        XCTAssertEqual(dial.position.channelID, b.id)
        dial.turn(.up)
        XCTAssertEqual(dial.position.channelID, c.id)
        dial.turn(.up)
        XCTAssertEqual(dial.position, .settings)
        dial.turn(.up)
        XCTAssertEqual(dial.position.channelID, a.id)
    }

    func testKnobWrapsThroughSettingsGoingDown() {
        let a = channel("a"), b = channel("b"), c = channel("c")
        var dial = Dial(cycle: TuningCycle(channels: [a, b, c]), resuming: nil)

        dial.turn(.down)
        XCTAssertEqual(dial.position, .settings)
        dial.turn(.down)
        XCTAssertEqual(dial.position.channelID, c.id)
        dial.turn(.down)
        XCTAssertEqual(dial.position.channelID, b.id)
    }

    func testChannelNumbersAreOneBasedFeedOrder() {
        let channels = ["a", "b", "c"].map(channel)
        var dial = Dial(cycle: TuningCycle(channels: channels), resuming: nil)

        XCTAssertEqual(dial.position.tuned?.number.description, "1")
        dial.turn(.up)
        XCTAssertEqual(dial.position.tuned?.number.description, "2")
        dial.turn(.up)
        XCTAssertEqual(dial.position.tuned?.number.description, "3")
    }

    func testDeadAirCycleIsAlwaysSettings() {
        var dial = Dial(cycle: .deadAir, resuming: nil)

        XCTAssertEqual(dial.position, .settings)
        dial.turn(.up)
        XCTAssertEqual(dial.position, .settings)
        dial.turn(.down)
        XCTAssertEqual(dial.position, .settings)
        for _ in 0..<50 { dial.turn(.up) }
        XCTAssertEqual(dial.position, .settings)
    }

    func testDeadAirIgnoresAResumeTargetItDoesNotHave() {
        let dial = Dial(cycle: .deadAir, resuming: channel("a").id)
        XCTAssertEqual(dial.position, .settings)
    }

    func testResumingRestoresTheWatchedChannel() {
        let channels = ["a", "b", "c"].map(channel)
        let dial = Dial(cycle: TuningCycle(channels: channels), resuming: channels[2].id)
        XCTAssertEqual(dial.position.channelID, channels[2].id)
    }

    func testRelineupKeepsTheViewerOnTheSameChannelAtANewSlot() {
        let a = channel("a"), b = channel("b"), c = channel("c")
        var dial = Dial(cycle: TuningCycle(channels: [a, b, c]), resuming: c.id)

        dial.relineup(to: TuningCycle(channels: [c, a, b]))

        XCTAssertEqual(dial.position.channelID, c.id)
        XCTAssertEqual(dial.position.tuned?.number.description, "1")
    }

    func testRelineupParksOnSettingsWhenTheChannelIsGone() {
        let a = channel("a"), b = channel("b")
        var dial = Dial(cycle: TuningCycle(channels: [a, b]), resuming: b.id)

        dial.relineup(to: TuningCycle(channels: [a]))

        XCTAssertEqual(dial.position, .settings)
    }

    func testRelineupIsIdempotent() {
        let channels = ["a", "b", "c"].map(channel)
        let cycle = TuningCycle(channels: channels)
        var dial = Dial(cycle: cycle, resuming: channels[1].id)

        dial.relineup(to: cycle)
        let once = dial
        dial.relineup(to: cycle)

        XCTAssertEqual(dial, once)
        XCTAssertEqual(dial.position.channelID, channels[1].id)
    }

    func testTuneToSettingsAndBack() {
        let channels = ["a", "b", "c"].map(channel)
        var dial = Dial(cycle: TuningCycle(channels: channels), resuming: channels[1].id)

        dial.tuneToSettings()
        XCTAssertEqual(dial.position, .settings)

        dial.resume(channels[1].id)
        XCTAssertEqual(dial.position.channelID, channels[1].id)
    }

    func testResumeFallsBackToChannelOneWhenNothingIsRemembered() {
        let channels = ["a", "b"].map(channel)
        var dial = Dial(cycle: TuningCycle(channels: channels), resuming: nil)

        dial.tuneToSettings()
        dial.resume(nil)

        XCTAssertEqual(dial.position.channelID, channels[0].id)
    }

    func testDuplicateIdentifiersRemainSeparateSlots() {
        let stream = URL(string: "https://tunarr.local/stream/dup.m3u8")!
        let duplicate = Channel(
            id: ChannelID(tag: "dup", stream: stream),
            name: ChannelName("Dup")!,
            stream: stream,
            logo: nil,
            group: nil
        )
        var dial = Dial(cycle: TuningCycle(channels: [duplicate, duplicate]), resuming: nil)

        XCTAssertEqual(dial.position.tuned?.number.description, "1")
        dial.turn(.up)
        XCTAssertEqual(dial.position.tuned?.number.description, "2")
        dial.turn(.up)
        XCTAssertEqual(dial.position, .settings)
    }
}
