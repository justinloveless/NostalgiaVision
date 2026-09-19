import XCTest
@testable import NostalgiaVision

@MainActor
final class SettingsStorePictureEffectsTests: XCTestCase {

    private func store() -> (SettingsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "nostalgiavision.tests.fx.\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: defaults.suiteName!)
        return (SettingsStore(defaults: defaults), defaults)
    }

    func testMissingKeysMeanAllEffectsAreOff() {
        let (store, _) = store()

        XCTAssertEqual(store.persisted.pictureEffects, .off)
    }

    func testWritingAndReadingRoundTripsEveryKnob() {
        let (store, _) = store()
        var state = store.persisted
        state.pictureEffects = PictureEffects(
            vignette: PictureEffect(amount: .mild),
            scanLines: PictureEffect(amount: .medium),
            curvature: PictureEffect(amount: .strong),
            chromaticAberration: PictureEffect(amount: .full),
            glowBloom: PictureEffect(amount: .mild),
            signalNoise: PictureEffect(amount: .medium)
        )

        store.persisted = state

        XCTAssertEqual(store.persisted.pictureEffects, state.pictureEffects)
    }

    func testCorruptValuesFallBackToOffForThatKnobOnly() {
        let (store, defaults) = store()
        var state = store.persisted
        state.pictureEffects.vignette = PictureEffect(amount: .full)
        state.pictureEffects.scanLines = PictureEffect(amount: .medium)
        store.persisted = state

        defaults.set(2.5, forKey: "nostalgiavision.fx.vignette")

        XCTAssertEqual(store.persisted.pictureEffects.vignette, .off)
        XCTAssertEqual(store.persisted.pictureEffects.scanLines.amount, .medium)
    }

    func testIdempotentWriteDoesNotChangeStoredValues() {
        let (store, defaults) = store()
        var state = store.persisted
        state.pictureEffects.glowBloom = PictureEffect(amount: .strong)
        store.persisted = state

        let before = defaults.object(forKey: "nostalgiavision.fx.glowBloom") as? Double
        store.persisted = store.persisted
        let after = defaults.object(forKey: "nostalgiavision.fx.glowBloom") as? Double

        XCTAssertEqual(before, after)
        XCTAssertEqual(before, 0.75)
    }
}
