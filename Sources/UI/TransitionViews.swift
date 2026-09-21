import SwiftUI

/// The quiet alternative to static between channels, for a viewer who finds the hiss and the
/// flicker abrasive: a dead screen with the spinner a set never had.
struct BlackSpinnerView: View {
    var body: some View {
        ZStack {
            Color.black

            ProgressView()
                .tint(.white)
                .scaleEffect(3)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// SMPTE colour bars, in broadcast left-to-right order.
///
/// Built from the colour list rather than a test-card image, like every other effect here: seven
/// flexible stripes divide any screen evenly, at any resolution, with nothing to ship.
struct ColorBarsView: View {
    /// `Color.magenta` is not on every SDK this builds against, so that bar is spelled out.
    private static let bars: [Color] = [
        .white,
        .yellow,
        .cyan,
        .green,
        Color(red: 1, green: 0, blue: 1),
        .red,
        .blue
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.bars, id: \.self) { bar in
                bar
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
