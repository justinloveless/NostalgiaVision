import AVFoundation
import Foundation
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
        self.gate = SettingsGate(pin: keychain, current: persisted.settings, now: .now)
        self.trouble = persisted.settings == nil ? .notConfigured : nil
    }

    /// The single value the root view renders. Derived on every access.
    var screen: Screen {
        switch dial.position {
        case let .channel(tuned):
            return .channel(tuned, receiver.reception)
        case .settings:
            return .settings(gate.screen, trouble: trouble)
        }
    }

    /// Handed straight to `PlayerSurface`; the view never touches `Receiver` otherwise.
    var player: AVPlayer { receiver.player }

    /// The display name the viewer gave the feed, shown as a corner watermark.
    var feedName: String { store.persisted.settings?.displayName ?? "" }

    /// Idempotent. Restores persisted settings and refreshes the lineup. Safe to call again on
    /// scene re-activation: a second call performs no fetch and no re-tune.
    func powerOn() async {
        guard !poweredOn else { return }
        poweredOn = true

        guard let settings = store.persisted.settings else {
            dial.tuneToSettings()
            trouble = .notConfigured
            receiver.stop()
            return
        }
        startRefresh(from: settings.feedURL)
    }

    /// Moves the dial immediately and schedules the actual tune after `TuneSettle.interval`.
    /// Cancels any pending settle, so fast surfing starts exactly one stream.
    func turn(_ direction: TuneDirection) {
        hasResumed = true
        let wasOnSettings = dial.position == .settings
        dial.turn(direction)
        let isOnSettings = dial.position == .settings

        if wasOnSettings && !isOnSettings {
            settings(.leftSettings)
        } else if isOnSettings && !wasOnSettings {
            settings(.enteredSettings)
        }

        if !isOnSettings { receiver.beginAcquiring() }
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
            case let .refetchFeed(url):
                startRefresh(from: url)
            }
        }
    }

    /// Menu button. Only installed while settings is on screen, so on a channel the system handles
    /// it and exits to the Home screen — which is the correct behaviour for a TV set.
    func pressedMenu() {
        guard dial.position == .settings else { return }
        settings(.leftSettings)
        dial.resume(store.persisted.lastTuned)
        if dial.position != .settings {
            receiver.beginAcquiring()
            scheduleSettle()
        }
    }

    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: TuneSettle.interval)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in self?.settle() }
        }
    }

    private func settle() {
        switch dial.position {
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
