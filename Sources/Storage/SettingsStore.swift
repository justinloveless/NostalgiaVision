import Foundation

struct FeedSettings: Equatable, Codable, Sendable {
    var feedURL: FeedURL
    /// Shown on the settings slot and as the corner watermark. Free text; may be empty.
    var displayName: String
}

/// Everything the app persists outside the Keychain, as one value.
struct PersistedState: Equatable {
    var settings: FeedSettings?
    var lastTuned: ChannelID?
    /// Deliberately NOT nested in `FeedSettings`: it must have a legal value before any feed is
    /// configured, and it must survive the viewer clearing or replacing the feed URL.
    var tuneDelay: TuneDelay = .standard
    /// CRT post-processing knobs. Same lifetime rules as `tuneDelay`: legal before any feed is
    /// configured, survives feed replacement, and is never part of the committable draft.
    var pictureEffects: PictureEffects = .off
    /// Loudness of the tuning-in noise bed. Unlike the seven CRT knobs, absent does NOT mean off:
    /// the standard analog behaviour is audible, so silence has to be something the viewer chose
    /// rather than something an upgrade decided for them.
    var noiseVolume: EffectAmount = .medium
    /// Same absent-means-standard rule as `noiseVolume`: snow is what an install that never saw
    /// this setting already shows while a channel tunes in.
    var transitionEffect: TransitionEffect = .standard
}

/// The only file in the app containing a `UserDefaults` key string.
///
/// Read `persisted` at launch; assign to it to save. The setter writes each field only when it
/// actually changed, so "save on every knob click" is harmless and every save path is idempotent.
@MainActor
final class SettingsStore {
    private enum Key {
        static let feedURL = "nostalgiavision.feed.url"
        static let feedName = "nostalgiavision.feed.name"
        static let lastTuned = "nostalgiavision.lastTunedChannelID"
        static let tuneDelay = "nostalgiavision.tune.delayMilliseconds"
        static let vignette = "nostalgiavision.fx.vignette"
        static let scanLines = "nostalgiavision.fx.scanLines"
        static let curvature = "nostalgiavision.fx.curvature"
        static let chromaticAberration = "nostalgiavision.fx.chromaticAberration"
        static let glowBloom = "nostalgiavision.fx.glowBloom"
        static let signalNoise = "nostalgiavision.fx.signalNoise"
        static let bevel = "nostalgiavision.fx.bevel"
        static let noiseVolume = "nostalgiavision.noise.volume"
        static let transitionEffect = "nostalgiavision.transition.effect"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var persisted: PersistedState {
        get {
            let settings = (defaults.string(forKey: Key.feedURL)).flatMap(FeedURL.init).map {
                FeedSettings(feedURL: $0, displayName: defaults.string(forKey: Key.feedName) ?? "")
            }
            let lastTuned = defaults.string(forKey: Key.lastTuned).map(ChannelID.init(rawValue:))
            // `integer(forKey:)` returns 0 for an absent key, which is out of range, so "never
            // configured" and "corrupt" take the same fallback path.
            let tuneDelay = TuneDelay(milliseconds: defaults.integer(forKey: Key.tuneDelay)) ?? .standard
            let pictureEffects = PictureEffects(
                vignette: effect(forKey: Key.vignette),
                scanLines: effect(forKey: Key.scanLines),
                curvature: effect(forKey: Key.curvature),
                chromaticAberration: effect(forKey: Key.chromaticAberration),
                glowBloom: effect(forKey: Key.glowBloom),
                signalNoise: effect(forKey: Key.signalNoise),
                bevel: effect(forKey: Key.bevel)
            )
            let noiseVolume = amount(forKey: Key.noiseVolume) ?? .medium
            let transitionEffect = defaults.string(forKey: Key.transitionEffect)
                .flatMap(TransitionEffect.init(rawValue:)) ?? .standard
            return PersistedState(
                settings: settings,
                lastTuned: lastTuned,
                tuneDelay: tuneDelay,
                pictureEffects: pictureEffects,
                noiseVolume: noiseVolume,
                transitionEffect: transitionEffect
            )
        }
        set {
            let current = persisted
            guard current != newValue else { return }
            if current.settings?.feedURL != newValue.settings?.feedURL {
                defaults.set(newValue.settings?.feedURL.text, forKey: Key.feedURL)
            }
            if current.settings?.displayName != newValue.settings?.displayName {
                defaults.set(newValue.settings?.displayName, forKey: Key.feedName)
            }
            if current.lastTuned != newValue.lastTuned {
                defaults.set(newValue.lastTuned?.rawValue, forKey: Key.lastTuned)
            }
            if current.tuneDelay != newValue.tuneDelay {
                defaults.set(newValue.tuneDelay.milliseconds, forKey: Key.tuneDelay)
            }
            write(newValue.pictureEffects.vignette, forKey: Key.vignette, was: current.pictureEffects.vignette)
            write(newValue.pictureEffects.scanLines, forKey: Key.scanLines, was: current.pictureEffects.scanLines)
            write(newValue.pictureEffects.curvature, forKey: Key.curvature, was: current.pictureEffects.curvature)
            write(
                newValue.pictureEffects.chromaticAberration,
                forKey: Key.chromaticAberration,
                was: current.pictureEffects.chromaticAberration
            )
            write(newValue.pictureEffects.glowBloom, forKey: Key.glowBloom, was: current.pictureEffects.glowBloom)
            write(newValue.pictureEffects.signalNoise, forKey: Key.signalNoise, was: current.pictureEffects.signalNoise)
            write(newValue.pictureEffects.bevel, forKey: Key.bevel, was: current.pictureEffects.bevel)
            if current.noiseVolume != newValue.noiseVolume {
                defaults.set(newValue.noiseVolume.value, forKey: Key.noiseVolume)
            }
            if current.transitionEffect != newValue.transitionEffect {
                defaults.set(newValue.transitionEffect.rawValue, forKey: Key.transitionEffect)
            }
        }
    }

    /// `nil` for an absent or corrupt key, so each caller states its own fallback. The presence
    /// check is load-bearing: `double(forKey:)` answers `0` for a key that was never written and
    /// `0` is itself a legal amount, so without it a fresh install reads as deliberately silenced
    /// rather than unconfigured.
    private func amount(forKey key: String) -> EffectAmount? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return EffectAmount(value: defaults.double(forKey: key))
    }

    /// Absent or corrupt keys mean off — upgrading an install that never saw FX writes nothing.
    private func effect(forKey key: String) -> PictureEffect {
        PictureEffect(amount: amount(forKey: key) ?? .off)
    }

    private func write(_ effect: PictureEffect, forKey key: String, was prior: PictureEffect) {
        guard effect != prior else { return }
        defaults.set(effect.amount.value, forKey: key)
    }
}
