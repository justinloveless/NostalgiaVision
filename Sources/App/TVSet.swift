import Foundation
import KSPlayer
import Observation

/// The render contract. The root view is a `switch` over this and nothing else.
enum Screen: Equatable {
    case channel(TunedChannel, Reception)
    /// `trouble` is the one-line strip at the bottom of settings ("NO SIGNAL FROM SERVER",
    /// "3 ENTRIES SKIPPED"). It is the only place a feed problem is ever described in words.
    case settings(SettingsScreen, trouble: FeedTrouble?)
}

/// Everything the app knows, on the main actor, in one object.
///
/// Nothing is mirrored: `Reception` is read through to `Receiver`, the channel number is derived
/// from `Dial`, and persisted values are read at launch and written through. There is no second
/// copy of any fact.
///
/// Single-writer discipline: `TVSet` is the only thing that assigns `dial` and `gate`; `Receiver`
/// is the only thing that assigns `reception`.
@MainActor @Observable
final class TVSet {
    private let store: SettingsStore
    private let feed: any ChannelFeed
    private let keychain: PINKeychain
    private let receiver: Receiver

    private var dial: Dial
    private var gate: SettingsGate
    private var trouble: FeedTrouble?

    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var poweredOn = false
    /// The launch lineup arrives after the dial already exists, so the resume happens once, when
    /// there is finally something to resume onto — and never after the viewer has touched the knob.
    @ObservationIgnored private var hasResumed = false

    init(
        store: SettingsStore,
        feed: any ChannelFeed,
        keychain: PINKeychain = PINKeychain(),
        receiver: Receiver
    ) {
        self.store = store
        self.feed = feed
        self.keychain = keychain
        self.receiver = receiver

        let persisted = store.persisted
        self.dial = Dial(cycle: .deadAir, resuming: persisted.lastTuned)
        self.gate = SettingsGate(
            pin: keychain,
            current: persisted.settings,
            delay: persisted.tuneDelay,
            effects: persisted.pictureEffects,
            noiseVolume: persisted.noiseVolume,
            transitionEffect: persisted.transitionEffect,
            now: .now
        )
        self.trouble = persisted.settings == nil ? .notConfigured : nil
    }

    /// The single value the root view renders. Derived on every access, from what is *airing* —
    /// the knob may already be pointing somewhere else, which is what `preview` is for.
    var screen: Screen {
        switch dial.live {
        case let .channel(tuned):
            return .channel(tuned, receiver.reception)
        case .settings:
            return .settings(gate.screen, trouble: trouble)
        }
    }

    /// What the preview bar names, `nil` when nothing is pending. Derived; never assigned.
    var preview: DialPosition? { dial.preview }

    /// Handed straight to `PlayerSurface`; the view never touches `Receiver` otherwise.
    var playerLayer: KSPlayerLayer { receiver.playerLayer }

    /// The display name the viewer gave the feed, shown as a corner watermark.
    var feedName: String { store.persisted.settings?.displayName ?? "" }

    /// CRT post-processing knobs applied over the picture. Read through from the store so a
    /// settings click updates the live channel the moment the viewer tunes back.
    var pictureEffects: PictureEffects { store.persisted.pictureEffects }

    /// How loud the tuning-in noise bed plays. Read through from the store, like `pictureEffects`.
    var noiseVolume: EffectAmount { store.persisted.noiseVolume }

    /// What the screen shows while a channel tunes in. Read through from the store, like
    /// `pictureEffects`.
    var transitionEffect: TransitionEffect { store.persisted.transitionEffect }

    /// Idempotent. Restores persisted settings and refreshes the lineup. Safe to call again on
    /// scene re-activation: a second call performs no fetch and no re-tune.
    func powerOn() async {
        guard !poweredOn else { return }
        poweredOn = true

        guard let settings = store.persisted.settings else {
            dial.tuneToSettings()
            trouble = .notConfigured
            settle()
            return
        }
        startRefresh(from: settings.feedURL)
    }

    /// Whether `turn(_:)` may move the dial right now. Derived from `screen` — the same value the
    /// root view renders — so what's on screen and what up/down does can never disagree. `true`
    /// everywhere except an unlocked settings screen, which has taken over up/down for its own
    /// navigation.
    private var dialAcceptsInput: Bool {
        guard case let .settings(settingsScreen, _) = screen else { return true }
        return settingsScreen.dialAcceptsInput
    }

    /// Moves the knob immediately and schedules the actual switch for once it sits still for the
    /// configured `TuneDelay`. Cancels any pending settle, so fast surfing starts exactly one
    /// stream. Nothing else happens here: the picture, the gate and the store are all the business
    /// of `settle()`.
    func turn(_ direction: TuneDirection) {
        hasResumed = true
        guard dialAcceptsInput else { return }
        dial.turn(direction)
        scheduleSettle()
    }

    /// Feeds the gate and performs the effects it returns.
    func settings(_ event: SettingsGate.Event) {
        for effect in gate.apply(event, now: .now) {
            switch effect {
            case let .persist(settings):
                var persisted = store.persisted
                persisted.settings = settings
                store.persisted = persisted
            case let .persistPIN(pin):
                keychain.save(pin)
            case let .persistDelay(delay):
                var persisted = store.persisted
                persisted.tuneDelay = delay
                store.persisted = persisted
            case let .persistEffects(effects):
                var persisted = store.persisted
                persisted.pictureEffects = effects
                store.persisted = persisted
            case let .persistNoiseVolume(volume):
                var persisted = store.persisted
                persisted.noiseVolume = volume
                store.persisted = persisted
            case let .persistTransitionEffect(transition):
                var persisted = store.persisted
                persisted.transitionEffect = transition
                store.persisted = persisted
            case let .refetchFeed(url):
                startRefresh(from: url)
            }
        }
    }

    /// The only way out of an unlocked settings screen: `dialAcceptsInput` holds the dial there, so
    /// up/down no longer carries the viewer away. tvOS's Menu button is the one caller today, and
    /// an in-UI exit affordance will be the second; both mean the same thing, so this reads as
    /// "leave" rather than "a particular button was pressed".
    ///
    /// The guard is on `dial.live`, not `dial.position`, because Menu is installed only while
    /// settings is airing — on a channel the system keeps it and exits to the Home screen, which is
    /// the correct behaviour for a TV set. With a preview already pending — the knob has moved off
    /// settings while settings is still what's airing — leaving commits that preview rather than
    /// jumping back to `lastTuned`.
    func leaveSettings() {
        guard dial.live == .settings else { return }
        if dial.preview == nil { dial.resume(store.persisted.lastTuned) }
        settle()
    }

    private func scheduleSettle() {
        settleTask?.cancel()
        // Captured at schedule time, not fire time: changing the delay never retimes a switch that
        // is already counting down.
        let delay = store.persisted.tuneDelay
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: delay.duration)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in self?.settle() }
        }
    }

    /// The single place the live position changes, and therefore the single place the gate's
    /// entered/left events fire, snow starts (inside `receiver.tune`), the tune happens, and
    /// `lastTuned` is persisted.
    ///
    /// Idempotent end to end: firing twice, or calling it with nothing pending, is a true no-op —
    /// `dial.settle()` rewrites the value already there and `receiver.tune(to:)` returns at its
    /// identity guard without so much as starting snow.
    private func settle() {
        settleTask?.cancel()
        settleTask = nil

        let wasOnSettings = dial.live == .settings
        dial.settle()
        let isOnSettings = dial.live == .settings

        if wasOnSettings && !isOnSettings {
            settings(.leftSettings)
        } else if isOnSettings && !wasOnSettings {
            settings(.enteredSettings)
        }

        switch dial.live {
        case let .channel(tuned):
            receiver.tune(to: tuned.channel)
            var persisted = store.persisted
            persisted.lastTuned = tuned.channel.id
            store.persisted = persisted
        case .settings:
            receiver.stop()
        }
    }

    /// Cancelling the previous task *is* the staleness check: a fetch for an old URL can never land
    /// after the viewer has typed a new one, so there is no generation counter to keep in sync.
    private func startRefresh(from url: FeedURL) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let feed = self?.feed else { return }
            let outcome = await feed.lineup(from: url)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in self?.apply(outcome) }
        }
    }

    private func apply(_ outcome: FeedOutcome) {
        trouble = outcome.trouble
        dial.relineup(to: outcome.cycle)
        if !hasResumed {
            hasResumed = true
            dial.resume(store.persisted.lastTuned)
        }
        settle()
    }
}
