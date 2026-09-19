import XCTest
@testable import NostalgiaVision

final class PictureEffectsTests: XCTestCase {

    func testOffIsDisabledAndCaptionsAsOff() {
        XCTAssertFalse(EffectAmount.off.isEnabled)
        XCTAssertEqual(EffectAmount.off.caption, "OFF")
        XCTAssertEqual(PictureEffect.off.caption, "OFF")
    }

    func testBoundsThemselvesAreAccepted() {
        XCTAssertEqual(EffectAmount(value: 0)?.value, 0)
        XCTAssertEqual(EffectAmount(value: 1)?.value, 1)
    }

    func testValuesOutsideTheBoundsAreUnrepresentable() {
        XCTAssertNil(EffectAmount(value: -0.01))
        XCTAssertNil(EffectAmount(value: 1.01))
    }

    func testDetentsAreNonEmptyAscendingAndInRange() {
        let detents = EffectAmount.detents

        XCTAssertFalse(detents.isEmpty)
        XCTAssertEqual(detents, detents.sorted { $0.value < $1.value })
        XCTAssertEqual(Set(detents.map(\.value)).count, detents.count, "no duplicate detents")
        XCTAssertEqual(detents.first, .off)
        XCTAssertEqual(detents.last, .full)
    }

    func testSteppingAdvancesOneDetentIncludingOff() {
        XCTAssertEqual(EffectAmount.off.stepped(), .mild)
        XCTAssertEqual(EffectAmount.mild.stepped(), .medium)
        XCTAssertEqual(EffectAmount.full.stepped(), .off)
    }

    func testSteppingEveryDetentWalksTheWholeLadderExactlyOnce() {
        var amount = EffectAmount.detents[0]
        var seen = [amount]
        for _ in 1..<EffectAmount.detents.count {
            amount = amount.stepped()
            seen.append(amount)
        }

        XCTAssertEqual(seen, EffectAmount.detents)
        XCTAssertEqual(amount.stepped(), .off)
    }

    func testSteppingAnOffLadderValueLandsOnTheNextDetentAbove() {
        let offLadder = EffectAmount(value: 0.3)!

        XCTAssertFalse(EffectAmount.detents.contains(offLadder))
        XCTAssertEqual(offLadder.stepped(), .medium)
    }

    func testCaptionReadsAsPercentWhenEnabled() {
        XCTAssertEqual(EffectAmount.mild.caption, "25%")
        XCTAssertEqual(EffectAmount.medium.caption, "50%")
        XCTAssertEqual(EffectAmount.full.caption, "100%")
    }

    func testEveryDetentHasADistinctCaption() {
        let captions = EffectAmount.detents.map(\.caption)

        XCTAssertEqual(Set(captions).count, captions.count, "\(captions)")
    }

    func testPictureEffectSteppingWrapsThroughOff() {
        var effect = PictureEffect.off

        effect = effect.stepped()
        XCTAssertTrue(effect.isEnabled)
        XCTAssertEqual(effect.amount, .mild)

        for _ in 0..<4 { effect = effect.stepped() }
        XCTAssertEqual(effect, .off)
    }

    func testSteppingOneKindLeavesTheOthersAlone() {
        let before = PictureEffects.off

        let after = before.stepping(.scanLines)

        XCTAssertEqual(after.scanLines.amount, .mild)
        XCTAssertEqual(after.vignette, .off)
        XCTAssertEqual(after.curvature, .off)
        XCTAssertEqual(after.chromaticAberration, .off)
        XCTAssertEqual(after.glowBloom, .off)
        XCTAssertEqual(after.signalNoise, .off)
        XCTAssertTrue(after.isActive)
        XCTAssertFalse(before.isActive)
    }

    func testSubscriptReadsAndWritesEveryKind() {
        var effects = PictureEffects.off

        for kind in PictureEffectKind.allCases {
            effects[kind] = PictureEffect(amount: .strong)
            XCTAssertEqual(effects[kind].amount, .strong)
            effects[kind] = .off
        }

        XCTAssertFalse(effects.isActive)
    }

    func testAllSixKindsAreExposed() {
        XCTAssertEqual(
            PictureEffectKind.allCases.map(\.rawValue),
            ["vignette", "scanLines", "curvature", "chromaticAberration", "glowBloom", "signalNoise"]
        )
    }

    func testRoundTripsThroughCoding() throws {
        let original = PictureEffects(
            vignette: PictureEffect(amount: .mild),
            scanLines: PictureEffect(amount: .medium),
            curvature: PictureEffect(amount: .strong),
            chromaticAberration: .off,
            glowBloom: PictureEffect(amount: .full),
            signalNoise: PictureEffect(amount: .mild)
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PictureEffects.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }
}
