import Foundation

/// What the picture is doing. The view renders exactly one of these; there is no error alert
/// anywhere in the app.
enum Reception: Equatable, Sendable {
    /// Tuning in: snow, plus the channel number. Held for at least `minimumSnow` even when the
    /// stream is instantly ready, so every channel change feels like a knob and not a page load.
    case acquiring
    case picture
    case noSignal(NoSignal)

    static let minimumSnow: Duration = .milliseconds(450)
}

/// An analog failure. Rendered as a snow field with a "NO SIGNAL" caption and the channel number —
/// never a dialog, never a stack trace, never a retry button.
///
/// Only stream-level causes exist: a feed-level failure yields `TuningCycle.deadAir`, which parks
/// the dial on the settings slot, where trouble is reported as a one-line strip instead.
struct NoSignal: Equatable, Sendable {
    enum Cause: Equatable, Sendable {
        /// The item will not load or play.
        case streamFailed
        /// Buffering past patience.
        case stalled
    }

    let cause: Cause
    /// 1-based.
    let attempt: Int
    /// A real TV never stops trying, and neither do we while this channel is selected. Cleared the
    /// moment the dial moves.
    let nextRetry: Date?
}

/// Pure timing policy. Owns no timers — the receiver schedules against these values.
enum RetryPolicy {
    /// One fixed interval. A set with a bent aerial retries at the same rate forever.
    static let interval: Duration = .seconds(5)
    /// How long a stream may sit un-started before it counts as a stall rather than a slow tune-in.
    static let stallPatience: Duration = .seconds(12)
}

/// How long the knob must sit still before the picture actually changes. Channel-surfing debounce:
/// the preview bar names the new channel instantly; the stream starts when the knob stops. Without
/// this, spinning through 40 channels opens 40 HLS sessions.
///
/// Persisted and user-editable from Settings; replaces the hardcoded `TuneSettle.interval`.
///
/// Constructible only through the failable millisecond initializer (the persistence boundary) or
/// `stepped()`, so every `TuneDelay` in memory is already known-valid; nothing downstream re-checks
/// the range.
struct TuneDelay: Equatable, Codable, Sendable {
    static let allowedMilliseconds: ClosedRange<Int> = 150...2000
    /// Matches the previously hardcoded `TuneSettle.interval` exactly — upgrading changes nothing
    /// for a viewer who never opens the new setting.
    static let standard = TuneDelay(milliseconds: 300)!
    static let step = 150
    /// Ascending, all in range, non-empty. What the settings control cycles through.
    static let detents: [TuneDelay] = stride(
        from: allowedMilliseconds.lowerBound,
        through: allowedMilliseconds.upperBound,
        by: step
    ).compactMap(TuneDelay.init(milliseconds:))

    let milliseconds: Int

    /// `nil` outside `allowedMilliseconds` — including the `0` that `UserDefaults.integer(forKey:)`
    /// returns for an absent key, so "never configured" and "corrupt" take the same fallback path.
    init?(milliseconds: Int) {
        guard Self.allowedMilliseconds.contains(milliseconds) else { return nil }
        self.milliseconds = milliseconds
    }

    var duration: Duration { .milliseconds(milliseconds) }

    /// The next detent, wrapping at the top. Tolerant of a persisted value that is no longer itself
    /// a detent: it lands on the first detent strictly above it.
    func stepped() -> TuneDelay {
        Self.detents.first { $0.milliseconds > milliseconds } ?? Self.detents[0]
    }

    /// "0.3 SEC", "1.2 SEC" — the one place a delay becomes text.
    var caption: String { String(format: "%.1f SEC", Double(milliseconds) / 1000) }
}

extension Duration {
    /// The one place `Duration` is flattened for APIs that still take seconds.
    var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
