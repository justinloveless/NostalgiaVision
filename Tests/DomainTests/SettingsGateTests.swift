import XCTest
@testable import NostalgiaVision

final class SettingsGateTests: XCTestCase {

    private struct StubPIN: PINOracle {
        let pin: PIN?
        var configuredLength: Int? { pin?.length }
        func accepts(_ candidate: PIN) -> Bool { pin == candidate }
    }

    private let now = Date(timeIntervalSinceReferenceDate: 0)

    private func digits(_ text: String) -> [Digit] {
        text.compactMap(Digit.init)
    }

    private func pin(_ text: String) -> PIN {
        PIN(digits: digits(text))!
    }

    private func settings(_ url: String, name: String = "Tunarr") -> FeedSettings {
        FeedSettings(feedURL: FeedURL(url)!, displayName: name)
    }

    private func type(_ text: String, into gate: inout SettingsGate, at instant: Date? = nil) {
        for digit in digits(text) {
            gate.apply(.typed(digit), now: instant ?? now)
        }
    }

    private func draft(of gate: SettingsGate) -> SettingsDraft? {
        if case let .editing(draft) = gate.screen { return draft }
        return nil
    }

    private func challenge(of gate: SettingsGate) -> PINChallenge? {
        if case let .locked(challenge) = gate.screen { return challenge }
        return nil
    }

    func testNoPINConfiguredOpensStraightIntoEditing() {
        let gate = SettingsGate(pin: StubPIN(pin: nil), current: settings("https://tunarr.local/a.m3u"), now: now)

        XCTAssertNotNil(draft(of: gate))
        XCTAssertEqual(draft(of: gate)?.feedURLText, "https://tunarr.local/a.m3u")
    }

    func testConfiguredPINStartsLockedWithNoDraftToRender() {
        let gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, now: now)

        XCTAssertNil(draft(of: gate))
        XCTAssertEqual(challenge(of: gate)?.expectedLength, 4)
        XCTAssertEqual(challenge(of: gate)?.typed.count, 0)
    }

    func testCorrectPINUnlocksIntoEditing() {
        var gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: settings("https://tunarr.local/a.m3u"), now: now)

        type("4821", into: &gate)

        XCTAssertEqual(draft(of: gate)?.feedURLText, "https://tunarr.local/a.m3u")
    }

    func testPartialEntryStaysLockedAndCountsDigits() {
        var gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, now: now)

        type("48", into: &gate)

        XCTAssertEqual(challenge(of: gate)?.typed.count, 2)
        XCTAssertEqual(challenge(of: gate)?.failures, 0)
    }

    func testWrongPINStaysLockedAndClearsTheEntry() {
        var gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, now: now)

        type("1234", into: &gate)

        XCTAssertNil(draft(of: gate))
        XCTAssertEqual(challenge(of: gate)?.typed.count, 0)
        XCTAssertEqual(challenge(of: gate)?.failures, 1)
        XCTAssertEqual(challenge(of: gate)?.lastAttemptFailed, true)
    }

    func testBackspaceRemovesTheLastDigit() {
        var gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, now: now)

        type("48", into: &gate)
        gate.apply(.backspace, now: now)

        XCTAssertEqual(challenge(of: gate)?.typed.count, 1)
    }

    func testRepeatedFailuresStartACooldownThatIgnoresDigits() {
        var gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, now: now)

        type("1111", into: &gate)
        type("1111", into: &gate)
        type("1111", into: &gate)

        XCTAssertEqual(challenge(of: gate)?.failures, 3)
        XCTAssertEqual(challenge(of: gate)?.isCoolingDown(at: now), true)

        type("4821", into: &gate)
        XCTAssertNil(draft(of: gate), "the correct PIN must be ignored while cooling down")

        type("4821", into: &gate, at: now.addingTimeInterval(31))
        XCTAssertNotNil(draft(of: gate), "the cooldown must expire on its own")
    }

    func testLeavingSettingsIsAlwaysAcceptedWhileLocked() {
        var gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, now: now)
        type("48", into: &gate)

        let effects = gate.apply(.leftSettings, now: now)

        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(challenge(of: gate)?.typed.count, 0, "half-typed digits are forgotten")
        XCTAssertNil(draft(of: gate), "leaving never unlocks")
    }

    func testLeavingSettingsIsAlwaysAcceptedWhileEditingAndRelocks() {
        var gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: settings("https://tunarr.local/a.m3u"), now: now)
        type("4821", into: &gate)
        XCTAssertNotNil(draft(of: gate))

        gate.apply(.leftSettings, now: now)

        XCTAssertNil(draft(of: gate))
        XCTAssertEqual(challenge(of: gate)?.expectedLength, 4)
    }

    func testLeavingSettingsWithNoPINStaysEditableForNextTime() {
        var gate = SettingsGate(pin: StubPIN(pin: nil), current: settings("https://tunarr.local/a.m3u"), now: now)

        gate.apply(.leftSettings, now: now)

        XCTAssertNotNil(draft(of: gate))
    }

    func testCommittingANewURLPersistsAndRefetches() {
        var gate = SettingsGate(pin: StubPIN(pin: nil), current: settings("https://tunarr.local/a.m3u"), now: now)
        var updated = draft(of: gate)!
        updated.feedURLText = "https://tunarr.local/b.m3u"
        gate.apply(.draftChanged(updated), now: now)

        let effects = gate.apply(.commitRequested, now: now)

        XCTAssertEqual(effects, [
            .persist(settings("https://tunarr.local/b.m3u")),
            .refetchFeed(FeedURL("https://tunarr.local/b.m3u")!)
        ])
    }

    func testCommittingOnlyANameChangePersistsWithoutRefetching() {
        var gate = SettingsGate(pin: StubPIN(pin: nil), current: settings("https://tunarr.local/a.m3u"), now: now)
        var updated = draft(of: gate)!
        updated.feedName = "Den"
        gate.apply(.draftChanged(updated), now: now)

        let effects = gate.apply(.commitRequested, now: now)

        XCTAssertEqual(effects, [.persist(settings("https://tunarr.local/a.m3u", name: "Den"))])
    }

    func testCommittingAnUnchangedDraftWritesNothing() {
        var gate = SettingsGate(pin: StubPIN(pin: nil), current: settings("https://tunarr.local/a.m3u"), now: now)

        XCTAssertTrue(gate.apply(.commitRequested, now: now).isEmpty)
    }

    func testCommittingAnInvalidURLWritesNothing() {
        var gate = SettingsGate(pin: StubPIN(pin: nil), current: nil, now: now)
        var updated = draft(of: gate)!
        updated.feedURLText = "not a url"
        gate.apply(.draftChanged(updated), now: now)

        XCTAssertTrue(gate.apply(.commitRequested, now: now).isEmpty)
        XCTAssertNil(draft(of: gate)?.validated)
    }

    func testClearingThePINPersistsNilAndDoesNotSelfLock() {
        var gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, now: now)
        type("4821", into: &gate)

        let effects = gate.apply(.pinEdited(.cleared), now: now)

        XCTAssertEqual(effects, [.persistPIN(nil)])
        XCTAssertNotNil(draft(of: gate))
    }

    func testSettingAValidPINPersistsItAndAShortOneDoesNot() {
        var gate = SettingsGate(pin: StubPIN(pin: nil), current: nil, now: now)

        XCTAssertEqual(gate.apply(.pinEdited(.set(digits("123456"))), now: now), [.persistPIN(pin("123456"))])
        XCTAssertTrue(gate.apply(.pinEdited(.set(digits("12"))), now: now).isEmpty)
    }

    func testEnteringSettingsIsIdempotentAndNeverResetsADraft() {
        var gate = SettingsGate(pin: StubPIN(pin: nil), current: settings("https://tunarr.local/a.m3u"), now: now)
        var updated = draft(of: gate)!
        updated.feedName = "Den"
        gate.apply(.draftChanged(updated), now: now)

        gate.apply(.enteredSettings, now: now)
        gate.apply(.enteredSettings, now: now)

        XCTAssertEqual(draft(of: gate)?.feedName, "Den")
    }

    func testSteppingTheTuneDelayUpdatesTheDraftAndPersistsAtOnce() {
        var gate = SettingsGate(
            pin: StubPIN(pin: nil),
            current: settings("https://tunarr.local/a.m3u"),
            delay: .standard,
            now: now
        )
        XCTAssertEqual(draft(of: gate)?.tuneDelay, .standard)

        let effects = gate.apply(.delayStepped, now: now)

        XCTAssertEqual(effects, [.persistDelay(TuneDelay.standard.stepped())])
        XCTAssertEqual(draft(of: gate)?.tuneDelay, TuneDelay.standard.stepped())
    }

    func testSteppingTheTuneDelayNeverTouchesTheCommittableSettings() {
        var gate = SettingsGate(
            pin: StubPIN(pin: nil),
            current: settings("https://tunarr.local/a.m3u"),
            delay: .standard,
            now: now
        )

        gate.apply(.delayStepped, now: now)

        XCTAssertEqual(draft(of: gate)?.validated, settings("https://tunarr.local/a.m3u"))
        XCTAssertTrue(gate.apply(.commitRequested, now: now).isEmpty, "the delay is not feed settings")
    }

    func testSteppingTheTuneDelayWhileLockedIsANoOp() {
        var gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, delay: .standard, now: now)

        XCTAssertTrue(gate.apply(.delayStepped, now: now).isEmpty)
        XCTAssertNil(draft(of: gate), "a locked screen has no draft to step")
        XCTAssertEqual(challenge(of: gate)?.expectedLength, 4)
    }

    func testLeavingSettingsReseedsTheDraftWithTheSteppedDelay() {
        var gate = SettingsGate(
            pin: StubPIN(pin: nil),
            current: settings("https://tunarr.local/a.m3u"),
            delay: .standard,
            now: now
        )
        gate.apply(.delayStepped, now: now)
        let stepped = TuneDelay.standard.stepped()

        gate.apply(.leftSettings, now: now)

        XCTAssertEqual(draft(of: gate)?.tuneDelay, stepped, "the rebuilt draft must not show a stale delay")
    }

    func testUnlockingAfterSteppingShowsTheSteppedDelay() {
        var gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, delay: .standard, now: now)
        type("4821", into: &gate)
        gate.apply(.delayStepped, now: now)
        let stepped = TuneDelay.standard.stepped()

        gate.apply(.leftSettings, now: now)
        XCTAssertNil(draft(of: gate), "a PIN is configured, so leaving re-locks")
        type("4821", into: &gate)

        XCTAssertEqual(draft(of: gate)?.tuneDelay, stepped)
    }

    func testTheDelayDefaultsToStandardWhenTheCallerDoesNotSupplyOne() {
        let gate = SettingsGate(pin: StubPIN(pin: nil), current: nil, now: now)

        XCTAssertEqual(draft(of: gate)?.tuneDelay, .standard)
    }

    func testPictureEffectsDefaultToAllOff() {
        let gate = SettingsGate(pin: StubPIN(pin: nil), current: nil, now: now)

        XCTAssertEqual(draft(of: gate)?.pictureEffects, .off)
    }

    func testSteppingAPictureEffectUpdatesTheDraftAndPersistsAtOnce() {
        var gate = SettingsGate(
            pin: StubPIN(pin: nil),
            current: settings("https://tunarr.local/a.m3u"),
            effects: .off,
            now: now
        )

        let effects = gate.apply(.effectStepped(.vignette), now: now)

        let expected = PictureEffects.off.stepping(.vignette)
        XCTAssertEqual(effects, [.persistEffects(expected)])
        XCTAssertEqual(draft(of: gate)?.pictureEffects, expected)
    }

    func testSteppingAPictureEffectNeverTouchesTheCommittableSettings() {
        var gate = SettingsGate(
            pin: StubPIN(pin: nil),
            current: settings("https://tunarr.local/a.m3u"),
            effects: .off,
            now: now
        )

        gate.apply(.effectStepped(.scanLines), now: now)

        XCTAssertEqual(draft(of: gate)?.validated, settings("https://tunarr.local/a.m3u"))
        XCTAssertTrue(gate.apply(.commitRequested, now: now).isEmpty, "picture FX are not feed settings")
    }

    func testSteppingAPictureEffectWhileLockedIsANoOp() {
        var gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, effects: .off, now: now)

        XCTAssertTrue(gate.apply(.effectStepped(.glowBloom), now: now).isEmpty)
        XCTAssertNil(draft(of: gate))
    }

    func testLeavingSettingsReseedsTheDraftWithSteppedEffects() {
        var gate = SettingsGate(
            pin: StubPIN(pin: nil),
            current: settings("https://tunarr.local/a.m3u"),
            effects: .off,
            now: now
        )
        gate.apply(.effectStepped(.curvature), now: now)
        let stepped = PictureEffects.off.stepping(.curvature)

        gate.apply(.leftSettings, now: now)

        XCTAssertEqual(draft(of: gate)?.pictureEffects, stepped)
    }

    func testUnlockingAfterSteppingEffectsShowsTheSteppedValue() {
        var gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, effects: .off, now: now)
        type("4821", into: &gate)
        gate.apply(.effectStepped(.signalNoise), now: now)
        let stepped = PictureEffects.off.stepping(.signalNoise)

        gate.apply(.leftSettings, now: now)
        type("4821", into: &gate)

        XCTAssertEqual(draft(of: gate)?.pictureEffects, stepped)
    }

    func testTheNoiseVolumeAndTransitionDefaultToTheirStandardsWhenTheCallerSuppliesNeither() {
        let gate = SettingsGate(pin: StubPIN(pin: nil), current: nil, now: now)

        XCTAssertEqual(draft(of: gate)?.noiseVolume, .medium)
        XCTAssertEqual(draft(of: gate)?.transitionEffect, .standard)
    }

    func testSteppingTheNoiseVolumeUpdatesTheDraftAndPersistsAtOnce() {
        var gate = SettingsGate(
            pin: StubPIN(pin: nil),
            current: settings("https://tunarr.local/a.m3u"),
            noiseVolume: .medium,
            now: now
        )

        let effects = gate.apply(.noiseVolumeStepped, now: now)

        XCTAssertEqual(effects, [.persistNoiseVolume(EffectAmount.medium.stepped())])
        XCTAssertEqual(draft(of: gate)?.noiseVolume, EffectAmount.medium.stepped())
    }

    func testSteppingTheNoiseVolumeNeverTouchesTheCommittableSettings() {
        var gate = SettingsGate(
            pin: StubPIN(pin: nil),
            current: settings("https://tunarr.local/a.m3u"),
            noiseVolume: .medium,
            now: now
        )

        gate.apply(.noiseVolumeStepped, now: now)

        XCTAssertEqual(draft(of: gate)?.validated, settings("https://tunarr.local/a.m3u"))
        XCTAssertTrue(gate.apply(.commitRequested, now: now).isEmpty, "the noise volume is not feed settings")
    }

    func testSteppingTheNoiseVolumeWhileLockedIsANoOp() {
        var gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, noiseVolume: .medium, now: now)

        XCTAssertTrue(gate.apply(.noiseVolumeStepped, now: now).isEmpty)
        XCTAssertNil(draft(of: gate))
    }

    func testLeavingSettingsReseedsTheDraftWithTheSteppedNoiseVolume() {
        var gate = SettingsGate(
            pin: StubPIN(pin: nil),
            current: settings("https://tunarr.local/a.m3u"),
            noiseVolume: .medium,
            now: now
        )
        gate.apply(.noiseVolumeStepped, now: now)
        let stepped = EffectAmount.medium.stepped()

        gate.apply(.leftSettings, now: now)

        XCTAssertEqual(draft(of: gate)?.noiseVolume, stepped)
    }

    func testUnlockingAfterSteppingTheNoiseVolumeShowsTheSteppedValue() {
        var gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, noiseVolume: .medium, now: now)
        type("4821", into: &gate)
        gate.apply(.noiseVolumeStepped, now: now)
        let stepped = EffectAmount.medium.stepped()

        gate.apply(.leftSettings, now: now)
        type("4821", into: &gate)

        XCTAssertEqual(draft(of: gate)?.noiseVolume, stepped)
    }

    func testSteppingTheTransitionEffectUpdatesTheDraftAndPersistsAtOnce() {
        var gate = SettingsGate(
            pin: StubPIN(pin: nil),
            current: settings("https://tunarr.local/a.m3u"),
            transitionEffect: .standard,
            now: now
        )

        let effects = gate.apply(.transitionEffectStepped, now: now)

        XCTAssertEqual(effects, [.persistTransitionEffect(TransitionEffect.standard.stepped())])
        XCTAssertEqual(draft(of: gate)?.transitionEffect, TransitionEffect.standard.stepped())
    }

    func testSteppingTheTransitionEffectNeverTouchesTheCommittableSettings() {
        var gate = SettingsGate(
            pin: StubPIN(pin: nil),
            current: settings("https://tunarr.local/a.m3u"),
            transitionEffect: .standard,
            now: now
        )

        gate.apply(.transitionEffectStepped, now: now)

        XCTAssertEqual(draft(of: gate)?.validated, settings("https://tunarr.local/a.m3u"))
        XCTAssertTrue(gate.apply(.commitRequested, now: now).isEmpty, "the transition is not feed settings")
    }

    func testSteppingTheTransitionEffectWhileLockedIsANoOp() {
        var gate = SettingsGate(
            pin: StubPIN(pin: pin("4821")),
            current: nil,
            transitionEffect: .standard,
            now: now
        )

        XCTAssertTrue(gate.apply(.transitionEffectStepped, now: now).isEmpty)
        XCTAssertNil(draft(of: gate))
    }

    func testLeavingSettingsReseedsTheDraftWithTheSteppedTransitionEffect() {
        var gate = SettingsGate(
            pin: StubPIN(pin: nil),
            current: settings("https://tunarr.local/a.m3u"),
            transitionEffect: .standard,
            now: now
        )
        gate.apply(.transitionEffectStepped, now: now)
        let stepped = TransitionEffect.standard.stepped()

        gate.apply(.leftSettings, now: now)

        XCTAssertEqual(draft(of: gate)?.transitionEffect, stepped)
    }

    func testUnlockingAfterSteppingTheTransitionEffectShowsTheSteppedValue() {
        var gate = SettingsGate(
            pin: StubPIN(pin: pin("4821")),
            current: nil,
            transitionEffect: .standard,
            now: now
        )
        type("4821", into: &gate)
        gate.apply(.transitionEffectStepped, now: now)
        let stepped = TransitionEffect.standard.stepped()

        gate.apply(.leftSettings, now: now)
        type("4821", into: &gate)

        XCTAssertEqual(draft(of: gate)?.transitionEffect, stepped)
    }

    func testLockedScreenIgnoresDraftAndCommitEvents() {
        var gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, now: now)
        var forged = SettingsDraft(from: nil)
        forged.feedURLText = "https://evil.local/x.m3u"

        XCTAssertTrue(gate.apply(.draftChanged(forged), now: now).isEmpty)
        XCTAssertTrue(gate.apply(.commitRequested, now: now).isEmpty)
        XCTAssertNil(draft(of: gate))
    }
}
