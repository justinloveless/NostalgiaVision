import SwiftUI

extension PictureEffects {
    /// The setup screen's own fixed CRT dressing — not a user setting, never persisted, and
    /// independent of the viewer's own `PictureEffects` (which default fully off). Setup is the
    /// app's own channel, so it always airs in the retro look regardless of what the viewer has
    /// configured for their picture.
    ///
    /// `chromaticAberration` and `signalNoise` are off: the settings screen is mostly small
    /// monospaced text, and both of those knobs cost either fringing at content edges or a
    /// permanently-running 24fps redraw loop (`PictureEffectsStage` switches to a `TimelineView`
    /// whenever `signalNoise` is enabled) — not worth paying on a static menu.
    static let setupChannel = PictureEffects(
        vignette: PictureEffect(amount: .mild),
        scanLines: PictureEffect(amount: .mild),
        curvature: PictureEffect(amount: .mild),
        chromaticAberration: .off,
        glowBloom: PictureEffect(amount: .mild),
        signalNoise: .off,
        bevel: PictureEffect(amount: .mild)
    )
}

/// A deep, slightly blue-black backdrop for the setup screen — reads as a CRT that's on but
/// showing its own test-card content, rather than a hole in the UI. Deliberately not `SnowView`:
/// that view starts a coupled audio hiss on appear (`NoiseAudioPlayer`), which is right for a
/// channel that's tuning in and wrong for a menu the viewer is meant to sit and read.
struct SetupBackdrop: View {
    var body: some View {
        RadialGradient(
            colors: [AppTheme.night, Color.black],
            center: .center,
            startRadius: 0,
            endRadius: 1200
        )
        .ignoresSafeArea()
    }
}
