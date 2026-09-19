import Foundation
import KSPlayer
import Observation

/// Owns the app's single `KSPlayerLayer` for its whole life and translates its state into
/// `Reception`.
///
/// One player, reused: channel changes replace the URL rather than rebuilding the render surface.
/// Rebuilding produces a black frame and a focus-hierarchy change on every channel, which is
/// precisely the un-analog feeling we are avoiding.
///
/// Backed by `KSMEPlayer` (KSPlayer's own FFmpeg-based decoder), not AVPlayer: AVFoundation's HLS
/// decode can silently wedge on some IPTV streams — a frame decodes, then nothing ever does again,
/// with `timeControlStatus` and `currentTime()` both still claiming everything is fine, because
/// neither reflects real decode health once `automaticallyWaitsToMinimizeStalling` is off. KSPlayer
/// defaults to its own AVPlayer wrapper (`KSAVPlayer`) as primary and only falls back to
/// `KSMEPlayer` on an explicit error — exactly the signal AVFoundation never sent here — so that
/// default would have reproduced the same bug. `KSMEPlayer` is forced as primary below instead,
/// which also means its `.buffering`/`.bufferFinished` states come from its own demuxer's buffer
/// occupancy, not from an optimistic clock — a signal this class can actually trust.
@MainActor @Observable
final class Receiver: NSObject {
    let playerLayer: KSPlayerLayer

    /// The single source of truth for picture state. `TVSet.screen` reads it; nothing copies it.
    private(set) var reception: Reception = .acquiring

    @ObservationIgnored private var channel: Channel?
    @ObservationIgnored private var snowStartedAt = Date.distantPast
    @ObservationIgnored private var pictureTask: Task<Void, Never>?
    @ObservationIgnored private var stallTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var attempt = 0

    /// No channel is tuned yet at launch; `KSPlayerLayer` needs some URL to exist, but
    /// `isAutoPlay: false` means it is never asked to load it.
    private static let noChannelURL = URL(string: "about:blank")!

    override init() {
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = nil
        playerLayer = KSPlayerLayer(url: Self.noChannelURL, isAutoPlay: false, options: KSOptions())
        super.init()
        playerLayer.delegate = self
    }

    /// Points `playerLayer` at `channel`'s stream, starting the snow as it goes.
    ///
    /// Idempotent: tuning to the channel already playing does not touch the player AND does not
    /// start snow, so a duplicate remote event, a lineup refresh that resolves to the same channel,
    /// or a scene re-activation cannot restart a stream mid-scene. That second half is
    /// load-bearing for the delayed switch: turning up then back down settles onto the channel that
    /// never stopped playing, and nothing should happen at all. The old two-call protocol
    /// (`beginAcquiring()` now, `tune(to:)` later) could not express that — snow was committed to
    /// before the target was known, which also let a turn-away-and-back strand `reception` in
    /// `.acquiring` forever.
    func tune(to channel: Channel) {
        guard self.channel != channel else { return }
        cancelTimers()
        snowStartedAt = .now
        reception = .acquiring
        self.channel = channel
        attempt = 1
        playerLayer.set(url: channel.stream, options: KSOptions())
        playerLayer.play()
        scheduleStallCheck()
    }

    /// Releases the current stream and leaves the surface black. Called when the dial lands on
    /// `.settings`: an analog set has no picture-in-picture.
    func stop() {
        cancelTimers()
        channel = nil
        attempt = 0
        reception = .acquiring
        playerLayer.stop()
    }

    /// Re-attempts the current channel from scratch.
    func retry() {
        guard let channel else { return }
        cancelTimers()
        attempt += 1
        snowStartedAt = .now
        reception = .acquiring
        playerLayer.set(url: channel.stream, options: KSOptions())
        playerLayer.play()
        scheduleStallCheck()
    }

    private func handle(_ state: KSPlayerState) {
        guard channel != nil else { return }
        switch state {
        case .initialized, .preparing, .readyToPlay, .paused:
            break
        case .buffering:
            // Live TV rebuffers for a moment sometimes; give it `stallPatience` before calling it
            // dead air. Idempotent — a second `.buffering` while already waiting changes nothing.
            scheduleStallCheck()
        case .bufferFinished:
            stallTask?.cancel()
            stallTask = nil
            showPictureAfterSnow()
        case .playedToTheEnd:
            // A live channel should never run out of programme; treat it as a stall and retry.
            lostSignal(.stalled)
        case .error:
            lostSignal(.streamFailed)
        }
    }

    /// The one stall check, covering both "never got going" and "was fine, then stalled": armed on
    /// every `tune`/`retry` and every `.buffering`, disarmed the moment `.bufferFinished` proves the
    /// stream is actually flowing again.
    private func scheduleStallCheck() {
        guard stallTask == nil else { return }
        stallTask = Task { [weak self] in
            try? await Task.sleep(for: RetryPolicy.stallPatience)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.stallTask = nil
                self.lostSignal(.stalled)
            }
        }
    }

    private func cancelTimers() {
        pictureTask?.cancel()
        pictureTask = nil
        stallTask?.cancel()
        stallTask = nil
        retryTask?.cancel()
        retryTask = nil
    }

    private func showPictureAfterSnow() {
        guard pictureTask == nil else { return }
        let remaining = Reception.minimumSnow.seconds - Date.now.timeIntervalSince(snowStartedAt)
        guard remaining > 0 else {
            reception = .picture
            return
        }
        pictureTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.pictureTask = nil
                self.reception = .picture
            }
        }
    }

    private func lostSignal(_ cause: NoSignal.Cause) {
        guard channel != nil else { return }
        if case let .noSignal(existing) = reception, existing.cause == cause, retryTask != nil { return }
        cancelTimers()
        reception = .noSignal(
            NoSignal(cause: cause, attempt: max(attempt, 1), nextRetry: .now + RetryPolicy.interval.seconds)
        )
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: RetryPolicy.interval)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in self?.retry() }
        }
    }
}

extension Receiver: KSPlayerLayerDelegate {
    func player(layer _: KSPlayerLayer, state: KSPlayerState) {
        handle(state)
    }

    func player(layer _: KSPlayerLayer, currentTime _: TimeInterval, totalTime _: TimeInterval) {}

    func player(layer _: KSPlayerLayer, finish error: Error?) {
        if error != nil {
            lostSignal(.streamFailed)
        }
    }

    func player(layer _: KSPlayerLayer, bufferedCount _: Int, consumeTime _: TimeInterval) {}
}
