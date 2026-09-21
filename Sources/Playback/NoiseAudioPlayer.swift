import AVFoundation

/// Peak sample amplitude of the hiss, well under full scale. At 1.0 the top of the `EffectAmount`
/// ladder is louder than anything else the set can play, which would leave most of the volume
/// control unusable.
private let noisePeakAmplitude = 0.25

/// Length of the looped buffer: long enough that the repeat does not read as a rhythm, short
/// enough that the samples cost a few hundred kilobytes rather than megabytes.
private let noiseLoopSeconds = 2.0

/// The audio track of `SnowView` — white noise synthesised from the same generator that draws the
/// picture's static, so the hiss costs no bundled asset and no decode.
///
/// Every failure path is silent. There is no error alert anywhere in the app (see `Reception`), and
/// this runs in places with no audio hardware at all: the test runner, a simulator. A set that
/// cannot hiss must still show its picture.
@MainActor
final class NoiseAudioPlayer {
    /// Fixed mono 44.1 kHz rather than the hardware's own format: `mainMixerNode` reports a zero
    /// sample rate when there is no audio route, and the mixer resamples to whatever the device
    /// actually wants regardless.
    private static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    /// Idempotent through the engine's own state rather than a flag of ours. `player.engine` is
    /// non-nil only once the node is attached, and `engine.isRunning` is the authoritative answer
    /// to "already playing".
    ///
    /// The asymmetry that shapes this: `engine.stop()` leaves the graph attached while
    /// `player.stop()` discards whatever was scheduled. So attach-and-connect happens at most once
    /// for the object's life, and only a start that actually starts the engine schedules a buffer.
    func start(volume: Double) {
        setVolume(volume)

        if player.engine == nil {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: Self.format)
        }

        guard !engine.isRunning else { return }
        configureSession()
        guard let buffer = Self.makeNoiseBuffer(format: Self.format, seconds: noiseLoopSeconds) else { return }

        try? engine.start()
        guard engine.isRunning else { return }

        // The engine also stops itself on a hardware configuration change, and that leaves the old
        // buffer scheduled. Clearing the queue keeps a restart from stacking a second endless loop
        // behind a loop that never ends.
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        player.play()
    }

    /// `AVAudioPlayerNode.volume` is documented as 0...1 but its `Float` type enforces nothing, so
    /// this clamp is the boundary.
    func setVolume(_ volume: Double) {
        player.volume = Float(min(max(volume, 0), 1))
    }

    func stop() {
        player.stop()
        engine.stop()
    }

    /// `.playback` with `.mixWithOthers` so this never fights the session KSPlayer configures for
    /// the stream. The hiss and the picture's audio are meant to coexist, and whichever of the two
    /// configures its session last must not silence the other.
    private func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
    }

    /// Kept free of the engine so the sample maths can be tested where no audio hardware exists.
    nonisolated static func makeNoiseBuffer(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount((format.sampleRate * seconds).rounded())
        // `AVAudioPCMBuffer` traps on a zero `frameCapacity` rather than failing its initializer,
        // so a non-positive request has to be turned away before it ever reaches the framework.
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames

        let frameStride = buffer.stride
        var seed: UInt64 = 1
        for channel in 0..<Int(format.channelCount) {
            let samples = channels[channel]
            for frame in 0..<Int(frames) {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                // `>>` on a UInt64 is a logical shift, so this lands evenly in [0, 1). Taking a
                // signed modulo of the raw seed instead would fold negative seeds to one side and
                // leave a DC offset on the whole buffer rather than noise centred on silence.
                let unit = Double((seed >> 33) & 0xFFFF) / 65535.0
                samples[frame * frameStride] = Float((unit * 2 - 1) * noisePeakAmplitude)
            }
        }
        return buffer
    }
}
