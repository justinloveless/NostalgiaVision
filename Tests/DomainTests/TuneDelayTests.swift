import XCTest
@testable import NostalgiaVision

final class TuneDelayTests: XCTestCase {

    func testStandardMatchesTheOldHardcodedInterval() {
        XCTAssertEqual(TuneDelay.standard.milliseconds, 300)
        XCTAssertEqual(TuneDelay.standard.duration, .milliseconds(300))
    }

    func testTheBoundsThemselvesAreAccepted() {
        XCTAssertEqual(TuneDelay(milliseconds: TuneDelay.allowedMilliseconds.lowerBound)?.milliseconds, 150)
        XCTAssertEqual(TuneDelay(milliseconds: TuneDelay.allowedMilliseconds.upperBound)?.milliseconds, 2000)
    }

    func testValuesOutsideTheBoundsAreUnrepresentable() {
        XCTAssertNil(TuneDelay(milliseconds: TuneDelay.allowedMilliseconds.lowerBound - 1))
        XCTAssertNil(TuneDelay(milliseconds: TuneDelay.allowedMilliseconds.upperBound + 1))
        XCTAssertNil(TuneDelay(milliseconds: -1))
    }

    func testAnAbsentUserDefaultsKeyFallsBackRatherThanMeaningZero() {
        // `UserDefaults.integer(forKey:)` returns 0 for a key that was never written.
        XCTAssertNil(TuneDelay(milliseconds: 0))
    }

    func testDetentsAreNonEmptyAscendingAndInRange() {
        let detents = TuneDelay.detents

        XCTAssertFalse(detents.isEmpty)
        XCTAssertEqual(detents, detents.sorted { $0.milliseconds < $1.milliseconds })
        XCTAssertEqual(Set(detents.map(\.milliseconds)).count, detents.count, "no duplicate detents")
        for detent in detents {
            XCTAssertTrue(TuneDelay.allowedMilliseconds.contains(detent.milliseconds))
        }
    }

    func testTheStandardDelayIsItselfADetent() {
        XCTAssertTrue(TuneDelay.detents.contains(.standard))
    }

    func testSteppingAdvancesOneDetent() {
        XCTAssertEqual(TuneDelay.detents[0].stepped(), TuneDelay.detents[1])
        XCTAssertEqual(TuneDelay.standard.stepped().milliseconds, 300 + TuneDelay.step)
    }

    func testSteppingWrapsAtTheTopOfTheLadder() {
        XCTAssertEqual(TuneDelay.detents.last?.stepped(), TuneDelay.detents.first)
    }

    func testSteppingEveryDetentWalksTheWholeLadderExactlyOnce() {
        var delay = TuneDelay.detents[0]
        var seen = [delay]
        for _ in 1..<TuneDelay.detents.count {
            delay = delay.stepped()
            seen.append(delay)
        }

        XCTAssertEqual(seen, TuneDelay.detents)
        XCTAssertEqual(delay.stepped(), TuneDelay.detents[0])
    }

    func testSteppingAValueThatIsNoLongerADetentLandsOnTheNextOneAbove() {
        let offLadder = TuneDelay(milliseconds: 310)!

        XCTAssertFalse(TuneDelay.detents.contains(offLadder))
        XCTAssertEqual(offLadder.stepped().milliseconds, 450)
    }

    func testSteppingAnOffLadderValueAboveTheTopDetentWraps() {
        let aboveTop = TuneDelay(milliseconds: TuneDelay.allowedMilliseconds.upperBound)!

        guard let top = TuneDelay.detents.last else { return XCTFail("detents must not be empty") }
        XCTAssertGreaterThanOrEqual(aboveTop.milliseconds, top.milliseconds)
        XCTAssertEqual(aboveTop.stepped(), TuneDelay.detents[0])
    }

    func testCaptionReadsAsSeconds() {
        XCTAssertEqual(TuneDelay.standard.caption, "0.3 SEC")
        XCTAssertEqual(TuneDelay(milliseconds: 1200)?.caption, "1.2 SEC")
        XCTAssertEqual(TuneDelay(milliseconds: 150)?.caption, "0.1 SEC")
    }

    /// The caption is rounded to a tenth, so two detents sharing one would make the settings field
    /// look stuck when it stepped.
    func testEveryDetentHasADistinctCaption() {
        let captions = TuneDelay.detents.map(\.caption)

        XCTAssertEqual(Set(captions).count, captions.count, "\(captions)")
    }

    func testRoundTripsThroughCoding() throws {
        let encoded = try JSONEncoder().encode(TuneDelay(milliseconds: 1050)!)
        let decoded = try JSONDecoder().decode(TuneDelay.self, from: encoded)

        XCTAssertEqual(decoded.milliseconds, 1050)
    }
}
