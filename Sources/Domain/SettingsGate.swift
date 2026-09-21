import Foundation

/// A yes/no oracle over the configured PIN, so the gate never holds a comparable PIN of its own.
/// `PINKeychain` is the production conformance; tests supply a literal one.
protocol PINOracle {
    /// `nil` when no PIN is configured, in which case the gate opens straight into `.editing` —
    /// first run and "the viewer cleared the PIN" are the same code path, not two.
    var configuredLength: Int? { get }
    func accepts(_ candidate: PIN) -> Bool
}

/// What the settings slot is showing right now.
///
/// This enum is the entire access-control mechanism. There is no `isUnlocked` anywhere in the
/// codebase, because the editable draft does not *exist* in the locked case — a view cannot render
/// a field it has no data for, and cannot forget a check it was never offered.
enum SettingsScreen: Equatable {
    case locked(PINChallenge)
    case editing(SettingsDraft)
}

extension SettingsScreen {
    /// True while up/down should still tune the dial away from settings — the `.locked` screen's
    /// safety net for a viewer who may not have the PIN. Once `.editing`, the dial is held: up/down
    /// belongs to settings navigation instead, until the viewer explicitly leaves (see
    /// `TVSet.leaveSettings()`).
    var dialAcceptsInput: Bool {
        switch self {
        case .locked: return true
        case .editing: return false
        }
    }
}

/// The locked half. Holds only what the keypad needs.
struct PINChallenge: Equatable {
    /// Never longer than the configured PIN length; the state machine submits and clears on the
    /// last digit.
    private(set) var typed: [Digit] = []
    private(set) var expectedLength: Int
    /// Drives a one-shot shake; cleared on the next digit.
    private(set) var lastAttemptFailed = false
    private(set) var failures = 0
    /// While non-nil and in the future, digits are ignored. In-memory only: a power cycle clears
    /// it, an accepted bypass for a shared living-room device.
    private(set) var cooldownEnds: Date?

    init(expectedLength: Int, failures: Int = 0, cooldownEnds: Date? = nil) {
        self.expectedLength = expectedLength
        self.failures = failures
        self.cooldownEnds = cooldownEnds
    }

    func isCoolingDown(at now: Date) -> Bool {
        guard let cooldownEnds else { return false }
        return cooldownEnds > now
    }

    fileprivate mutating func append(_ digit: Digit) {
        lastAttemptFailed = false
        typed.append(digit)
    }

    fileprivate mutating func backspace() {
        lastAttemptFailed = false
        if !typed.isEmpty { typed.removeLast() }
    }

    fileprivate mutating func rejected(at now: Date) {
        typed = []
        failures += 1
        lastAttemptFailed = true
        let cooldown = SettingsGate.cooldown(afterFailures: failures)
        cooldownEnds = cooldown > 0 ? now.addingTimeInterval(cooldown) : nil
    }

    /// Keeps the failure history but forgets the half-typed digits, so tuning away and back does
    /// not hand an attacker a free reset of the cooldown.
    fileprivate mutating func abandoned() {
        typed = []
        lastAttemptFailed = false
    }
}

/// The unlocked half. Holds the three editable fields and knows whether they are committable.
/// Validation is a pure property of the draft, not scattered `if` statements in the view.
struct SettingsDraft: Equatable {
    var feedURLText: String
    var feedName: String
    var pinEdit: PINEdit
    /// Not part of `FeedSettings` and never part of `validated`: stepping it persists immediately,
    /// exactly like clearing the PIN, so there is nothing to commit.
    var tuneDelay: TuneDelay
    /// CRT post-processing knobs. Same rules as `tuneDelay`: stepped and persisted at once.
    var pictureEffects: PictureEffects
    /// Loudness of the tuning-in noise bed. Same rules as `tuneDelay`: stepped and persisted at
    /// once, never part of `validated`.
    var noiseVolume: EffectAmount
    /// What the screen shows while a channel tunes in. Same rules as `tuneDelay`: stepped and
    /// persisted at once, never part of `validated`.
    var transitionEffect: TransitionEffect

    init(
        from settings: FeedSettings?,
        delay: TuneDelay = .standard,
        effects: PictureEffects = .off,
        noiseVolume: EffectAmount = .medium,
        transitionEffect: TransitionEffect = .standard
    ) {
        self.feedURLText = settings?.feedURL.text ?? ""
        self.feedName = settings?.displayName ?? ""
        self.pinEdit = .unchanged
        self.tuneDelay = delay
        self.pictureEffects = effects
        self.noiseVolume = noiseVolume
        self.transitionEffect = transitionEffect
    }

    /// Non-nil exactly when the draft is safe to persist. The view renders the URL field in CRT red
    /// when this is nil; nothing else consults the URL text.
    var validated: FeedSettings? {
        guard let url = FeedURL(feedURLText) else { return nil }
        return FeedSettings(feedURL: url, displayName: feedName.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// A PIN change expressed as an intent rather than a value, so "no change" and "clear it" are
/// distinct states instead of both being an empty string.
enum PINEdit: Equatable {
    case unchanged
    case cleared
    case set([Digit])
}

/// Pure state machine for settings access.
///
/// Every transition is a total function of (current state, event, configured PIN, injected `now`).
/// No I/O, no ambient clock, no view dependencies. The gate never writes anything: it returns
/// `GateEffect`s and the shell performs them.
///
/// The asymmetry that matters: **the gate locks the fields, never the dial.** `.leftSettings` is
/// always accepted, from either state, so a locked settings screen can always be tuned away from.
struct SettingsGate {
    private let pin: any PINOracle
    private var current: FeedSettings?
    /// The gate's own copy of the persisted delay, so a draft rebuilt after re-locking or
    /// re-entering shows the stepped value rather than the one the gate was born with.
    private var currentDelay: TuneDelay
    /// Same lifetime as `currentDelay`: survives re-lock and re-entry without going stale.
    private var currentEffects: PictureEffects
    /// Same lifetime as `currentDelay`.
    private var currentNoiseVolume: EffectAmount
    /// Same lifetime as `currentDelay`.
    private var currentTransitionEffect: TransitionEffect

    private(set) var screen: SettingsScreen

    init(
        pin: any PINOracle,
        current: FeedSettings?,
        delay: TuneDelay = .standard,
        effects: PictureEffects = .off,
        noiseVolume: EffectAmount = .medium,
        transitionEffect: TransitionEffect = .standard,
        now: Date
    ) {
        self.pin = pin
        self.current = current
        self.currentDelay = delay
        self.currentEffects = effects
        self.currentNoiseVolume = noiseVolume
        self.currentTransitionEffect = transitionEffect
        if let length = pin.configuredLength {
            self.screen = .locked(PINChallenge(expectedLength: length))
        } else {
            self.screen = .editing(SettingsDraft(
                from: current,
                delay: delay,
                effects: effects,
                noiseVolume: noiseVolume,
                transitionEffect: transitionEffect
            ))
        }
    }

    enum Event: Equatable {
        /// The dial landed on the settings slot. Idempotent: re-entering while already entered
        /// changes nothing, so a duplicate remote event cannot reset a draft.
        case enteredSettings
        /// The dial turned away. Commits, then re-locks if a PIN is configured.
        case leftSettings
        case typed(Digit)
        case backspace
        case draftChanged(SettingsDraft)
        case pinEdited(PINEdit)
        /// The viewer clicked the tune-delay field: advance one detent and persist at once. Like
        /// clearing the PIN, this is not part of the committable draft.
        case delayStepped
        /// The viewer clicked one CRT effect field: advance that knob one detent and persist.
        case effectStepped(PictureEffectKind)
        /// The viewer clicked the noise-volume field: advance one detent and persist. `.off` is a
        /// detent on that ladder, so this is also how the noise bed gets muted.
        case noiseVolumeStepped
        /// The viewer clicked the transition field: advance to the next transition effect and
        /// persist. Also not part of the committable draft.
        case transitionEffectStepped
        /// The viewer finished editing a field.
        case commitRequested
    }

    /// Three wrong PINs in a row buys 30 seconds, six buys five minutes. Not in `RetryPolicy`,
    /// which is about the picture, not about access control.
    static func cooldown(afterFailures failures: Int) -> TimeInterval {
        switch failures {
        case ..<3: return 0
        case ..<6: return 30
        default: return 300
        }
    }

    @discardableResult
    mutating func apply(_ event: Event, now: Date) -> [GateEffect] {
        switch (screen, event) {
        case (_, .enteredSettings):
            return []

        case (.locked(var challenge), .leftSettings):
            challenge.abandoned()
            screen = .locked(challenge)
            return []

        case let (.editing(draft), .leftSettings):
            let effects = commit(draft)
            if let length = pin.configuredLength {
                screen = .locked(PINChallenge(expectedLength: length))
            } else {
                screen = .editing(SettingsDraft(
                    from: current,
                    delay: currentDelay,
                    effects: currentEffects,
                    noiseVolume: currentNoiseVolume,
                    transitionEffect: currentTransitionEffect
                ))
            }
            return effects

        case (.locked(var challenge), let .typed(digit)):
            guard !challenge.isCoolingDown(at: now) else { return [] }
            challenge.append(digit)
            guard challenge.typed.count >= challenge.expectedLength else {
                screen = .locked(challenge)
                return []
            }
            if let candidate = PIN(digits: challenge.typed), pin.accepts(candidate) {
                screen = .editing(SettingsDraft(
                    from: current,
                    delay: currentDelay,
                    effects: currentEffects,
                    noiseVolume: currentNoiseVolume,
                    transitionEffect: currentTransitionEffect
                ))
            } else {
                challenge.rejected(at: now)
                screen = .locked(challenge)
            }
            return []

        case (.locked(var challenge), .backspace):
            challenge.backspace()
            screen = .locked(challenge)
            return []

        case let (.editing, .draftChanged(draft)):
            screen = .editing(draft)
            return []

        case (.editing(var draft), let .pinEdited(edit)):
            draft.pinEdit = edit
            screen = .editing(draft)
            switch edit {
            case .unchanged:
                return []
            case .cleared:
                // Never self-lock mid-session; the next entry opens freely.
                return [.persistPIN(nil)]
            case let .set(digits):
                guard let newPIN = PIN(digits: digits) else { return [] }
                return [.persistPIN(newPIN)]
            }

        case (.editing(var draft), .delayStepped):
            draft.tuneDelay = draft.tuneDelay.stepped()
            currentDelay = draft.tuneDelay
            screen = .editing(draft)
            return [.persistDelay(draft.tuneDelay)]

        case (.editing(var draft), let .effectStepped(kind)):
            draft.pictureEffects = draft.pictureEffects.stepping(kind)
            currentEffects = draft.pictureEffects
            screen = .editing(draft)
            return [.persistEffects(draft.pictureEffects)]

        case (.editing(var draft), .noiseVolumeStepped):
            draft.noiseVolume = draft.noiseVolume.stepped()
            currentNoiseVolume = draft.noiseVolume
            screen = .editing(draft)
            return [.persistNoiseVolume(draft.noiseVolume)]

        case (.editing(var draft), .transitionEffectStepped):
            draft.transitionEffect = draft.transitionEffect.stepped()
            currentTransitionEffect = draft.transitionEffect
            screen = .editing(draft)
            return [.persistTransitionEffect(draft.transitionEffect)]

        case let (.editing(draft), .commitRequested):
            return commit(draft)

        case (.editing, .typed), (.editing, .backspace),
             (.locked, .draftChanged), (.locked, .pinEdited), (.locked, .commitRequested),
             (.locked, .delayStepped), (.locked, .effectStepped),
             (.locked, .noiseVolumeStepped), (.locked, .transitionEffectStepped):
            return []
        }
    }

    private mutating func commit(_ draft: SettingsDraft) -> [GateEffect] {
        guard let validated = draft.validated, validated != current else { return [] }
        let urlChanged = validated.feedURL != current?.feedURL
        current = validated
        return urlChanged ? [.persist(validated), .refetchFeed(validated.feedURL)] : [.persist(validated)]
    }
}

/// What the shell must do as a consequence of a gate transition. Each case is idempotent: applying
/// the same effect twice writes the same bytes and triggers at most one extra fetch.
enum GateEffect: Equatable {
    case persist(FeedSettings)
    /// `nil` clears the configured PIN.
    case persistPIN(PIN?)
    case persistDelay(TuneDelay)
    case persistEffects(PictureEffects)
    case persistNoiseVolume(EffectAmount)
    case persistTransitionEffect(TransitionEffect)
    case refetchFeed(FeedURL)
}
