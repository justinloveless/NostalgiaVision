import AVFoundation
import Foundation
import Observation

/// Owns the app's single `AVPlayer` for its whole life and translates AVFoundation state into
/// `Reception`.
///
/// One player, reused: channel changes replace the `AVPlayerItem` rather than rebuilding the render
/// surface. Rebuilding produces a black frame and a focus-hierarchy change on every channel, which
/// is precisely the un-analog feeling we are avoiding.
@MainActor @Observable
final class Receiver {
    let player: AVPlayer

    /// The single source of truth for picture state. `TVSet.screen` reads it; nothing copies it.
    private(set) var reception: Reception = .acquiring

    @ObservationIgnored private var channel: Channel?
    @ObservationIgnored private var itemStatus: NSKeyValueObservation?
    @ObservationIgnored private var timeControl: NSKeyValueObservation?
    @ObservationIgnored private var failureObserver: NSObjectProtocol?
    @ObservationIgnored private var stallObserver: NSObjectProtocol?
    @ObservationIgnored private var snowStartedAt = Date.distantPast
    @ObservationIgnored private var pictureTask: Task<Void, Never>?
    @ObservationIgnored private var stallTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var attempt = 0

    init() {
        player = AVPlayer()
        player.allowsExternalPlayback = false
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false

        // Without this an Apple TV has no reason to route audio out at all; it is not implied by
        // merely holding an `AVPlayer`.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        // Observed on the player, not on the item, so it survives every channel change and never
        // needs re-registering.
        timeControl = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.resolveReception() }
        }
    }

    /// Starts the snow the instant the knob turns, before the stream for the new channel is even
    /// requested. `TVSet` debounces the actual `tune(to:)` by `TuneSettle.interval`.
    func beginAcquiring() {
        cancelTimers()
        snowStartedAt = .now
        reception = .acquiring
    }

    /// Attaches `channel`'s stream to the single long-lived `AVPlayer`.
    ///
    /// **Removes the previous `AVPlayerItem`'s KVO observer and notification registration before
    /// attaching the new item's**, so observers cannot accumulate across channel changes.
    ///
    /// Idempotent: tuning to the channel already playing does not touch the player, so a duplicate
    /// remote event, a lineup refresh that resolves to the same channel, or a scene re-activation
    /// cannot restart a stream mid-scene.
    func tune(to channel: Channel) {
        if self.channel == channel, player.currentItem != nil {
            resolveReception()
            return
        }
        detachItem()
        self.channel = channel
        attempt = 1
        attachItem()
    }

    /// Releases the current item and leaves the surface black. Called when the dial lands on
    /// `.settings`: an analog set has no picture-in-picture.
    func stop() {
        detachItem()
        channel = nil
        attempt = 0
        reception = .acquiring
    }

    /// Re-attempts the current channel from scratch.
    func retry() {
        guard channel != nil else { return }
        detachItem()
        attempt += 1
        snowStartedAt = .now
        reception = .acquiring
        attachItem()
    }

    private func attachItem() {
        guard let channel else { return }
        let item = AVPlayerItem(url: channel.stream)

        itemStatus = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in
                if status == .failed {
                    self?.lostSignal(.streamFailed)
                } else {
                    self?.resolveReception()
                }
            }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.lostSignal(.streamFailed) }
        }

        // The authoritative "the buffer ran dry mid-playback" signal from AVFoundation itself.
        // `timeControlStatus` and `currentTime()` both keep reporting steady progress through a
        // real stall — with `automaticallyWaitsToMinimizeStalling` off, AVPlayer just runs its
        // clock forward optimistically rather than pausing to reflect reality — so a stall (a
        // dead segment, a discontinuity between programs the decoder chokes on) can otherwise
        // freeze the surface on whatever frame it last decoded with nothing to notice. Registered
        // for the item's whole life, not just the tune-in window.
        stallObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.lostSignal(.stalled) }
        }

        player.replaceCurrentItem(with: item)
        player.play()

        stallTask = Task { [weak self] in
            try? await Task.sleep(for: RetryPolicy.stallPatience)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.player.timeControlStatus != .playing else { return }
                self.lostSignal(.stalled)
            }
        }
    }

    private func detachItem() {
        cancelTimers()
        itemStatus?.invalidate()
        itemStatus = nil
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
            self.failureObserver = nil
        }
        if let stallObserver {
            NotificationCenter.default.removeObserver(stallObserver)
            self.stallObserver = nil
        }
        player.replaceCurrentItem(with: nil)
    }

    private func cancelTimers() {
        pictureTask?.cancel()
        pictureTask = nil
        stallTask?.cancel()
        stallTask = nil
        retryTask?.cancel()
        retryTask = nil
    }

    private func resolveReception() {
        guard channel != nil, let item = player.currentItem else { return }
        if item.status == .failed {
            lostSignal(.streamFailed)
            return
        }
        guard player.timeControlStatus == .playing else { return }
        showPictureAfterSnow()
    }

    private func showPictureAfterSnow() {
        guard pictureTask == nil else { return }
        let remaining = Reception.minimumSnow.seconds - Date.now.timeIntervalSince(snowStartedAt)
        guard remaining > 0 else {
            reception = .picture
            stallTask?.cancel()
            stallTask = nil
            return
        }
        pictureTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.pictureTask = nil
                guard self.player.timeControlStatus == .playing else { return }
                self.stallTask?.cancel()
                self.stallTask = nil
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
