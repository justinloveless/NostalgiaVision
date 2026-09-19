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
            return PersistedState(settings: settings, lastTuned: lastTuned, tuneDelay: tuneDelay)
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
        }
    }
}
