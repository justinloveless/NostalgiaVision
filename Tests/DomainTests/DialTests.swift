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

    func testFreshDialIsSettledWithNothingToPreview() {
        let channels = ["a", "b"].map(channel)
        let dial = Dial(cycle: TuningCycle(channels: channels), resuming: channels[1].id)

        XCTAssertTrue(dial.isSettled)
        XCTAssertNil(dial.preview)
        XCTAssertEqual(dial.live, dial.position)
    }

    func testTurningMovesTheKnobButLeavesThePictureWhereItWas() {
        let a = channel("a"), b = channel("b"), c = channel("c")
        var dial = Dial(cycle: TuningCycle(channels: [a, b, c]), resuming: nil)

        dial.turn(.up)
        dial.turn(.up)

        XCTAssertEqual(dial.position.channelID, c.id)
        XCTAssertEqual(dial.live.channelID, a.id, "the picture must not move until it settles")
        XCTAssertFalse(dial.isSettled)
        XCTAssertEqual(dial.preview?.channelID, c.id)
        XCTAssertEqual(dial.preview?.tuned?.number.description, "3")
    }

    func testPreviewIsNilExactlyWhenSettled() {
        let channels = ["a", "b"].map(channel)
        var dial = Dial(cycle: TuningCycle(channels: channels), resuming: nil)

        XCTAssertNil(dial.preview)
        dial.turn(.up)
        XCTAssertNotNil(dial.preview)
        dial.settle()
        XCTAssertNil(dial.preview)
        dial.turn(.down)
        XCTAssertNotNil(dial.preview)
        dial.turn(.up)
        XCTAssertNil(dial.preview, "returning the knob to the live slot settles it by arithmetic")
    }

    func testSettleBringsThePictureToTheKnobAndIsIdempotent() {
        let channels = ["a", "b", "c"].map(channel)
        var dial = Dial(cycle: TuningCycle(channels: channels), resuming: nil)

        dial.turn(.up)
        dial.settle()
        let once = dial
        dial.settle()

        XCTAssertEqual(dial, once)
        XCTAssertEqual(dial.live.channelID, channels[1].id)
        XCTAssertTrue(dial.isSettled)
    }

    func testPreviewingSettingsFromAChannelKeepsTheChannelAiring() {
        let channels = ["a", "b"].map(channel)
        var dial = Dial(cycle: TuningCycle(channels: channels), resuming: channels[1].id)

        dial.turn(.up)

        XCTAssertEqual(dial.preview, .settings)
        XCTAssertEqual(dial.live.channelID, channels[1].id)

        dial.settle()

        XCTAssertEqual(dial.live, .settings)
        XCTAssertNil(dial.preview)
    }

    func testResumeAndTuneToSettingsMoveOnlyTheKnob() {
        let channels = ["a", "b", "c"].map(channel)
        var dial = Dial(cycle: TuningCycle(channels: channels), resuming: channels[0].id)

        dial.tuneToSettings()
        XCTAssertEqual(dial.position, .settings)
        XCTAssertEqual(dial.live.channelID, channels[0].id)

        dial.settle()
        dial.resume(channels[2].id)
        XCTAssertEqual(dial.position.channelID, channels[2].id)
        XCTAssertEqual(dial.live, .settings)
    }

    func testDeadAirCanNeverPreviewAnything() {
        var dial = Dial(cycle: .deadAir, resuming: nil)

        for _ in 0..<10 { dial.turn(.up) }
        XCTAssertNil(dial.preview)
        XCTAssertTrue(dial.isSettled)

        dial.tuneToSettings()
        XCTAssertNil(dial.preview)
    }

    func testRelineupRemapsBothCursorsIndependently() {
        let a = channel("a"), b = channel("b"), c = channel("c")
        var dial = Dial(cycle: TuningCycle(channels: [a, b, c]), resuming: a.id)

        dial.turn(.up)
        dial.turn(.up)
        XCTAssertEqual(dial.live.channelID, a.id)
        XCTAssertEqual(dial.position.channelID, c.id)

        dial.relineup(to: TuningCycle(channels: [c, b, a]))

        XCTAssertEqual(dial.live.channelID, a.id, "the airing channel follows its own id")
        XCTAssertEqual(dial.live.tuned?.number.description, "3")
        XCTAssertEqual(dial.position.channelID, c.id, "the pending preview follows its own id")
        XCTAssertEqual(dial.position.tuned?.number.description, "1")
        XCTAssertFalse(dial.isSettled)
    }

    func testRelineupParksOnlyTheCursorWhoseChannelDisappeared() {
        let a = channel("a"), b = channel("b"), c = channel("c")
        var dial = Dial(cycle: TuningCycle(channels: [a, b, c]), resuming: a.id)

        dial.turn(.up)
        dial.turn(.up)

        dial.relineup(to: TuningCycle(channels: [a, b]))

        XCTAssertEqual(dial.live.channelID, a.id, "the airing channel survives untouched")
        XCTAssertEqual(dial.position, .settings, "the vanished preview target parks on settings")
        XCTAssertFalse(dial.isSettled)
    }

    func testRelineupCollapsesToSettledWhenBothCursorsAreGone() {
        let a = channel("a"), b = channel("b"), c = channel("c")
        var dial = Dial(cycle: TuningCycle(channels: [a, b, c]), resuming: b.id)

        dial.turn(.up)
        XCTAssertEqual(dial.preview?.channelID, c.id)

        dial.relineup(to: TuningCycle(channels: [a]))

        XCTAssertEqual(dial.live, .settings)
        XCTAssertEqual(dial.position, .settings)
        XCTAssertTrue(dial.isSettled)
        XCTAssertNil(dial.preview)
    }

    func testRelineupIsIdempotentWithAPreviewPending() {
        let channels = ["a", "b", "c"].map(channel)
        let cycle = TuningCycle(channels: channels)
        var dial = Dial(cycle: cycle, resuming: channels[0].id)
        dial.turn(.up)

        dial.relineup(to: cycle)
        let once = dial
        dial.relineup(to: cycle)

        XCTAssertEqual(dial, once)
        XCTAssertEqual(dial.live.channelID, channels[0].id)
        XCTAssertEqual(dial.position.channelID, channels[1].id)
    }

    func testDuplicateSlotsStillPreviewAsADistinctPosition() {
        let stream = URL(string: "https://tunarr.local/stream/dup.m3u8")!
        let duplicate = Channel(
            id: ChannelID(tag: "dup", stream: stream),
            name: ChannelName("Dup")!,
            stream: stream,
            logo: nil,
            group: nil
        )
        var dial = Dial(cycle: TuningCycle(channels: [duplicate, duplicate]), resuming: nil)

        dial.turn(.up)

        XCTAssertFalse(dial.isSettled, "a preview is by slot, not by channel identity")
        XCTAssertEqual(dial.preview?.tuned?.number.description, "2")
        XCTAssertEqual(dial.live.tuned?.number.description, "1")
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
