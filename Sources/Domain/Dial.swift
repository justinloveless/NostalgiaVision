import Foundation

/// The channel order exactly as it appeared in the feed, plus the one settings slot.
///
/// Structural invariant: a cycle always has at least one slot, because the settings slot always
/// exists. There is consequently no "empty lineup" special case anywhere in the app — a feed that
/// is missing, unreachable, or empty produces `.deadAir`, a one-slot cycle whose only position is
/// `.settings`, and the ordinary wrap-around arithmetic keeps working untouched.
///
/// Duplicate `ChannelID`s are preserved, not coalesced: position is by slot, never by identity.
struct TuningCycle: Equatable, Sendable {
    private let channels: [Channel]

    /// - Parameter channels: feed order. Feed order *is* channel order; nothing re-sorts it.
    init(channels: [Channel]) {
        self.channels = channels
    }

    /// The cycle with no channels. Turning the knob on it is a no-op by arithmetic, not by check.
    static let deadAir = TuningCycle(channels: [])

    var channelCount: Int { channels.count }

    /// Total slots = `channelCount + 1`. Always >= 1. Deliberately not visible outside this file:
    /// no caller should ever index a cycle, which is why `DialPosition` carries no index.
    fileprivate var slotCount: Int { channels.count + 1 }

    fileprivate func channel(atSlot slot: Int) -> Channel? {
        channels.indices.contains(slot) ? channels[slot] : nil
    }

    /// Linear scan. Called once per feed refresh, never per frame or per knob turn.
    fileprivate func firstSlot(of id: ChannelID) -> Int? {
        channels.firstIndex { $0.id == id }
    }
}

/// Where the dial points. This is the *only* way to name a position, and it carries no index, so an
/// out-of-range position is not merely invalid — it is unrepresentable. Being on a channel and being
/// on settings are exclusive cases of one enum, so "channel index + isSettings flag" cannot be
/// expressed.
enum DialPosition: Equatable, Sendable {
    case channel(TunedChannel)
    case settings

    var tuned: TunedChannel? {
        switch self {
        case let .channel(tuned): return tuned
        case .settings: return nil
        }
    }

    var channelID: ChannelID? { tuned?.channel.id }
}

/// A channel plus the number painted in the corner of the screen.
///
/// The number is *derived* from the slot (1-based feed order) each time the position is read; it is
/// never stored on `Channel` and never persisted, so it cannot drift out of step with the feed.
struct TunedChannel: Equatable, Sendable {
    let channel: Channel
    let number: ChannelNumber
}

/// 1...channelCount. Constructible only by `Dial`, so no caller can invent channel 0 or 999.
struct ChannelNumber: Equatable, Sendable, CustomStringConvertible {
    private let value: Int

    fileprivate init(_ value: Int) {
        self.value = value
    }

    var description: String { String(value) }
}

/// Which way the knob turned. Mapped from `MoveCommandDirection` in exactly one place
/// (`TuneDirection.init(_:)` in TVShellView.swift) so SwiftUI types never reach the domain.
enum TuneDirection: Equatable, Sendable {
    case up, down
}

/// A cycle plus a cursor. The cursor is private and only `turn`/`relineup`/`resume`/`tuneToSettings`
/// move it, so every reachable state is valid by construction rather than by validation.
///
/// `up` advances to the next-higher channel number; from the last channel it lands on `.settings`,
/// and from `.settings` it lands on channel 1. `down` is the exact mirror. Both wrap forever.
struct Dial: Equatable, Sendable {
    private var cycle: TuningCycle
    /// 0..<cycle.slotCount. Slot `channelCount` is the settings slot — that placement is what puts
    /// settings "between the last channel and the first" for free.
    private var cursor: Int

    /// - Parameter resuming: the channel the viewer was last watching. Restores that slot when the
    ///   id is still present; otherwise starts on channel 1 (or `.settings` for `.deadAir`, where
    ///   slot 0 *is* the settings slot).
    init(cycle: TuningCycle, resuming: ChannelID?) {
        self.cycle = cycle
        self.cursor = resuming.flatMap { cycle.firstSlot(of: $0) } ?? 0
    }

    /// Derived from `(cycle, cursor)` on every read. No stored copy exists to fall out of date.
    var position: DialPosition {
        guard let channel = cycle.channel(atSlot: cursor) else { return .settings }
        return .channel(TunedChannel(channel: channel, number: ChannelNumber(cursor + 1)))
    }

    mutating func turn(_ direction: TuneDirection) {
        let slots = cycle.slotCount
        switch direction {
        case .up: cursor = (cursor + 1) % slots
        case .down: cursor = (cursor - 1 + slots) % slots
        }
    }

    /// Swaps in a refreshed lineup, keeping the viewer on the same channel when its `ChannelID`
    /// still exists, otherwise parking on `.settings` so a feed that changed out from under the
    /// viewer never silently drops them onto an unrelated channel.
    ///
    /// Idempotent: applying the same cycle twice is a no-op.
    mutating func relineup(to cycle: TuningCycle) {
        let watching = position.channelID
        self.cycle = cycle
        self.cursor = watching.flatMap { cycle.firstSlot(of: $0) } ?? cycle.channelCount
    }

    /// Returns to a known channel, falling back to channel 1 exactly as `init(resuming:)` does.
    /// Used at launch once the lineup arrives, and by the Menu button leaving settings.
    mutating func resume(_ id: ChannelID?) {
        cursor = id.flatMap { cycle.firstSlot(of: $0) } ?? 0
    }

    /// Jumps to the settings slot. Used on first launch with no feed URL configured.
    mutating func tuneToSettings() {
        cursor = cycle.channelCount
    }
}
