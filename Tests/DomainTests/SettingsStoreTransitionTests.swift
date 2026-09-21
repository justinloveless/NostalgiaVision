import XCTest
@testable import NostalgiaVision

@MainActor
final class SettingsStoreTransitionTests: XCTestCase {

    private func store() -> (SettingsStore, UserDefaults) {
        let suiteName = "nostalgiavision.tests.transition.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (SettingsStore(defaults: defaults), defaults)
    }

    func testMissingKeysMeanAudibleSnowRatherThanSilence() {
        let (store, _) = store()

        XCTAssertEqual(store.persisted.noiseVolume, .medium)
        XCTAssertEqual(store.persisted.transitionEffect, .standard)
    }

    func testWritingAndReadingRoundTripsBothFields() {
        let (store, _) = store()
        var state = store.persisted
        state.noiseVolume = .full
        state.transitionEffect = .colorBars

        store.persisted = state

        XCTAssertEqual(store.persisted.noiseVolume, .full)
        XCTAssertEqual(store.persisted.transitionEffect, .colorBars)
    }

    func testADeliberateMuteSurvivesInsteadOfReadingAsUnconfigured() {
        let (store, _) = store()
        var state = store.persisted
        state.noiseVolume = .off

        store.persisted = state

        XCTAssertEqual(store.persisted.noiseVolume, .off)
    }

    func testACorruptNoiseVolumeFallsBackWithoutDisturbingTheTransition() {
        let (store, defaults) = store()
        var state = store.persisted
        state.noiseVolume = .mild
        state.transitionEffect = .blackSpinner
        store.persisted = state

        defaults.set(2.5, forKey: "nostalgiavision.noise.volume")

        XCTAssertEqual(store.persisted.noiseVolume, .medium)
        XCTAssertEqual(store.persisted.transitionEffect, .blackSpinner)
    }

    func testAnUnknownTransitionEffectFallsBackToTheStandard() {
        let (store, defaults) = store()

        defaults.set("kaleidoscope", forKey: "nostalgiavision.transition.effect")

        XCTAssertEqual(store.persisted.transitionEffect, .standard)
    }

    func testIdempotentWriteDoesNotChangeStoredValues() {
        let (store, defaults) = store()
        var state = store.persisted
        state.noiseVolume = .strong
        state.transitionEffect = .blank
        store.persisted = state

        let volumeBefore = defaults.object(forKey: "nostalgiavision.noise.volume") as? Double
        let transitionBefore = defaults.object(forKey: "nostalgiavision.transition.effect") as? String
        store.persisted = store.persisted

        XCTAssertEqual(defaults.object(forKey: "nostalgiavision.noise.volume") as? Double, volumeBefore)
        XCTAssertEqual(
            defaults.object(forKey: "nostalgiavision.transition.effect") as? String,
            transitionBefore
        )
        XCTAssertEqual(volumeBefore, 0.75)
        XCTAssertEqual(transitionBefore, "blank")
    }
}
