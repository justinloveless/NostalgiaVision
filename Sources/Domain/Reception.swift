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

/// Channel-surfing debounce. The number on screen changes instantly; the stream starts when the
/// knob stops. Without this, spinning through 40 channels opens 40 HLS sessions.
enum TuneSettle {
    static let interval: Duration = .milliseconds(300)
}

extension Duration {
    /// The one place `Duration` is flattened for APIs that still take seconds.
    var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
