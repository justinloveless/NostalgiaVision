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

    /// Most fixtures want a gate already past `.landing`'s button, since editing behaviour is what
    /// they actually exercise. Tests about `.landing` or `.locked` themselves construct `SettingsGate`
    /// directly instead.
    private func editingGate(
        pin configuredPIN: PIN? = nil,
        current: FeedSettings? = nil,
        delay: TuneDelay = .standard,
        effects: PictureEffects = .off,
        noiseVolume: EffectAmount = .medium,
        transitionEffect: TransitionEffect = .standard
    ) -> SettingsGate {
        var gate = SettingsGate(
            pin: StubPIN(pin: configuredPIN),
            current: current,
            delay: delay,
            effects: effects,
            noiseVolume: noiseVolume,
            transitionEffect: transitionEffect,
            now: now
        )
        if configuredPIN == nil { gate.apply(.enterEditing, now: now) }
        return gate
    }

    private func draft(of gate: SettingsGate) -> SettingsDraft? {
        if case let .editing(draft) = gate.screen { return draft }
        return nil
    }

    private func landingDraft(of gate: SettingsGate) -> SettingsDraft? {
        if case let .landing(draft) = gate.screen { return draft }
        return nil
    }

    private func challenge(of gate: SettingsGate) -> PINChallenge? {
        if case let .locked(challenge) = gate.screen { return challenge }
        return nil
    }

    func testNoPINConfiguredOpensOntoLanding() {
        let gate = SettingsGate(pin: StubPIN(pin: nil), current: settings("https://tunarr.local/a.m3u"), now: now)

        XCTAssertNotNil(landingDraft(of: gate))
        XCTAssertEqual(landingDraft(of: gate)?.feedURLText, "https://tunarr.local/a.m3u")
        XCTAssertNil(draft(of: gate), "landing is not editing")
    }

    func testPressingEditSettingsOnLandingEntersEditingWithTheSameDraft() {
        var gate = SettingsGate(pin: StubPIN(pin: nil), current: settings("https://tunarr.local/a.m3u"), now: now)

        gate.apply(.enterEditing, now: now)

        XCTAssertEqual(draft(of: gate)?.feedURLText, "https://tunarr.local/a.m3u")
    }

    func testConfiguredPINStartsLockedWithNoDraftToRender() {
        let gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, now: now)

        XCTAssertNil(draft(of: gate))
        XCTAssertEqual(challenge(of: gate)?.expectedLength, 4)
        XCTAssertEqual(challenge(of: gate)?.typed.count, 0)
    }

    func testALockedScreenLeavesTheDialFreeToTuneAway() {
        let gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, now: now)

        XCTAssertTrue(gate.screen.dialAcceptsInput)
    }

    func testALandingScreenLeavesTheDialFreeToTuneAway() {
        let gate = SettingsGate(pin: StubPIN(pin: nil), current: nil, now: now)

        XCTAssertTrue(gate.screen.dialAcceptsInput)
    }

    func testAnEditingScreenHoldsTheDialForItsOwnNavigation() {
        let gate = editingGate()

        XCTAssertFalse(gate.screen.dialAcceptsInput)
    }

    func testCorrectPINUnlocksDirectlyIntoEditingSkippingLanding() {
        var gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: settings("https://tunarr.local/a.m3u"), now: now)

        type("4821", into: &gate)

        XCTAssertEqual(draft(of: gate)?.feedURLText, "https://tunarr.local/a.m3u")
        XCTAssertNil(landingDraft(of: gate), "a PIN takes the viewer straight into editing")
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

    func testLeavingSettingsWithNoPINReturnsToLandingRatherThanEditing() {
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"))
        XCTAssertNotNil(draft(of: gate))

        gate.apply(.leftSettings, now: now)

        XCTAssertNil(draft(of: gate), "leaving drops out of editing")
        XCTAssertNotNil(landingDraft(of: gate), "and lands on the button, not straight back into the menu")
    }

    func testBackRequestedFromEditingRootReturnsToLandingWithoutTouchingTheDial() {
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"))

        let effects = gate.apply(.backRequested, now: now)

        XCTAssertTrue(effects.isEmpty)
        XCTAssertNotNil(landingDraft(of: gate))
        XCTAssertTrue(gate.screen.dialAcceptsInput, "back at the root hands the dial back")
    }

    func testBackRequestedFromEditingRelocksWhenAPINIsConfigured() {
        var gate = SettingsGate(pin: StubPIN(pin: pin("4821")), current: settings("https://tunarr.local/a.m3u"), now: now)
        type("4821", into: &gate)

        gate.apply(.backRequested, now: now)

        XCTAssertNil(draft(of: gate))
        XCTAssertEqual(challenge(of: gate)?.expectedLength, 4)
    }

    func testBackRequestedIsIgnoredOutsideEditing() {
        var landing = SettingsGate(pin: StubPIN(pin: nil), current: nil, now: now)
        XCTAssertTrue(landing.apply(.backRequested, now: now).isEmpty)
        XCTAssertNotNil(landingDraft(of: landing))

        var locked = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, now: now)
        XCTAssertTrue(locked.apply(.backRequested, now: now).isEmpty)
        XCTAssertNotNil(challenge(of: locked))
    }

    func testEnterEditingIsIgnoredOutsideLanding() {
        var locked = SettingsGate(pin: StubPIN(pin: pin("4821")), current: nil, now: now)
        XCTAssertTrue(locked.apply(.enterEditing, now: now).isEmpty)
        XCTAssertNotNil(challenge(of: locked))

        var editing = editingGate()
        XCTAssertTrue(editing.apply(.enterEditing, now: now).isEmpty)
        XCTAssertNotNil(draft(of: editing))
    }

    func testCommittingANewURLPersistsAndRefetches() {
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"))
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
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"))
        var updated = draft(of: gate)!
        updated.feedName = "Den"
        gate.apply(.draftChanged(updated), now: now)

        let effects = gate.apply(.commitRequested, now: now)

        XCTAssertEqual(effects, [.persist(settings("https://tunarr.local/a.m3u", name: "Den"))])
    }

    func testCommittingAnUnchangedDraftWritesNothing() {
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"))

        XCTAssertTrue(gate.apply(.commitRequested, now: now).isEmpty)
    }

    func testCommittingAnInvalidURLWritesNothing() {
        var gate = editingGate()
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
        var gate = editingGate()

        XCTAssertEqual(gate.apply(.pinEdited(.set(digits("123456"))), now: now), [.persistPIN(pin("123456"))])
        XCTAssertTrue(gate.apply(.pinEdited(.set(digits("12"))), now: now).isEmpty)
    }

    func testEnteringSettingsIsIdempotentAndNeverResetsADraft() {
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"))
        var updated = draft(of: gate)!
        updated.feedName = "Den"
        gate.apply(.draftChanged(updated), now: now)

        gate.apply(.enteredSettings, now: now)
        gate.apply(.enteredSettings, now: now)

        XCTAssertEqual(draft(of: gate)?.feedName, "Den")
    }

    func testSteppingTheTuneDelayUpdatesTheDraftAndPersistsAtOnce() {
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"), delay: .standard)
        XCTAssertEqual(draft(of: gate)?.tuneDelay, .standard)

        let effects = gate.apply(.delayStepped, now: now)

        XCTAssertEqual(effects, [.persistDelay(TuneDelay.standard.stepped())])
        XCTAssertEqual(draft(of: gate)?.tuneDelay, TuneDelay.standard.stepped())
    }

    func testSteppingTheTuneDelayNeverTouchesTheCommittableSettings() {
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"), delay: .standard)

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

    func testSteppingTheTuneDelayWhileLandingIsANoOp() {
        var gate = SettingsGate(pin: StubPIN(pin: nil), current: nil, delay: .standard, now: now)

        XCTAssertTrue(gate.apply(.delayStepped, now: now).isEmpty)
        XCTAssertEqual(landingDraft(of: gate)?.tuneDelay, .standard, "landing has a draft, but it does not step")
    }

    func testLeavingSettingsReseedsTheDraftWithTheSteppedDelay() {
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"), delay: .standard)
        gate.apply(.delayStepped, now: now)
        let stepped = TuneDelay.standard.stepped()

        gate.apply(.leftSettings, now: now)

        XCTAssertEqual(landingDraft(of: gate)?.tuneDelay, stepped, "the rebuilt draft must not show a stale delay")
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

        XCTAssertEqual(landingDraft(of: gate)?.tuneDelay, .standard)
    }

    func testPictureEffectsDefaultToAllOff() {
        let gate = SettingsGate(pin: StubPIN(pin: nil), current: nil, now: now)

        XCTAssertEqual(landingDraft(of: gate)?.pictureEffects, .off)
    }

    func testSteppingAPictureEffectUpdatesTheDraftAndPersistsAtOnce() {
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"), effects: .off)

        let effects = gate.apply(.effectStepped(.vignette), now: now)

        let expected = PictureEffects.off.stepping(.vignette)
        XCTAssertEqual(effects, [.persistEffects(expected)])
        XCTAssertEqual(draft(of: gate)?.pictureEffects, expected)
    }

    func testSteppingAPictureEffectNeverTouchesTheCommittableSettings() {
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"), effects: .off)

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
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"), effects: .off)
        gate.apply(.effectStepped(.curvature), now: now)
        let stepped = PictureEffects.off.stepping(.curvature)

        gate.apply(.leftSettings, now: now)

        XCTAssertEqual(landingDraft(of: gate)?.pictureEffects, stepped)
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

        XCTAssertEqual(landingDraft(of: gate)?.noiseVolume, .medium)
        XCTAssertEqual(landingDraft(of: gate)?.transitionEffect, .standard)
    }

    func testSteppingTheNoiseVolumeUpdatesTheDraftAndPersistsAtOnce() {
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"), noiseVolume: .medium)

        let effects = gate.apply(.noiseVolumeStepped, now: now)

        XCTAssertEqual(effects, [.persistNoiseVolume(EffectAmount.medium.stepped())])
        XCTAssertEqual(draft(of: gate)?.noiseVolume, EffectAmount.medium.stepped())
    }

    func testSteppingTheNoiseVolumeNeverTouchesTheCommittableSettings() {
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"), noiseVolume: .medium)

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
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"), noiseVolume: .medium)
        gate.apply(.noiseVolumeStepped, now: now)
        let stepped = EffectAmount.medium.stepped()

        gate.apply(.leftSettings, now: now)

        XCTAssertEqual(landingDraft(of: gate)?.noiseVolume, stepped)
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
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"), transitionEffect: .standard)

        let effects = gate.apply(.transitionEffectStepped, now: now)

        XCTAssertEqual(effects, [.persistTransitionEffect(TransitionEffect.standard.stepped())])
        XCTAssertEqual(draft(of: gate)?.transitionEffect, TransitionEffect.standard.stepped())
    }

    func testSteppingTheTransitionEffectNeverTouchesTheCommittableSettings() {
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"), transitionEffect: .standard)

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
        var gate = editingGate(current: settings("https://tunarr.local/a.m3u"), transitionEffect: .standard)
        gate.apply(.transitionEffectStepped, now: now)
        let stepped = TransitionEffect.standard.stepped()

        gate.apply(.leftSettings, now: now)

        XCTAssertEqual(landingDraft(of: gate)?.transitionEffect, stepped)
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

    func testLandingScreenIgnoresDraftAndCommitEvents() {
        var gate = SettingsGate(pin: StubPIN(pin: nil), current: nil, now: now)
        var forged = SettingsDraft(from: nil)
        forged.feedURLText = "https://evil.local/x.m3u"

        XCTAssertTrue(gate.apply(.draftChanged(forged), now: now).isEmpty)
        XCTAssertTrue(gate.apply(.commitRequested, now: now).isEmpty)
        XCTAssertNil(draft(of: gate))
        XCTAssertNotEqual(landingDraft(of: gate)?.feedURLText, "https://evil.local/x.m3u")
    }
}
