import SwiftUI

/// Analog static: a 420-line grid of random grey cells, redrawn a dozen times a second. Drawn
/// rather than played back so it costs no asset and never loops visibly.
struct SnowView: View {
    /// Peak cell brightness — the volume of the white-noise snow. Held at 20% so the static
    /// stays present without blasting the screen between channels.
    static let volume = 0.2

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { context in
            frame(at: context.date)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func frame(at date: Date) -> some View {
        Canvas(opaque: true, rendersAsynchronously: true) { canvas, size in
            guard size.width > 0, size.height > 0 else { return }
            let rows = analogNoiseLines
            let columns = analogNoiseColumns(aspect: size.width / size.height)

            // A cheap LCG reseeded per frame: deterministic within a frame, different between
            // frames, and no allocation beyond the pixel buffer itself.
            var seed = UInt64(bitPattern: Int64(date.timeIntervalSinceReferenceDate * 1000)) | 1
            var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
            for i in 0..<(columns * rows) {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let level = UInt8(clamping: Int((Double((seed >> 33) & 0xFF) * Self.volume).rounded()))
                let base = i * 4
                pixels[base] = level
                pixels[base + 1] = level
                pixels[base + 2] = level
                pixels[base + 3] = 255
            }

            guard let image = imageFromPremultipliedRGBA(pixels, columns: columns, rows: rows) else { return }
            let swiftUIImage = Image(decorative: image, scale: 1, orientation: .up).interpolation(.none)
            canvas.draw(swiftUIImage, in: CGRect(origin: .zero, size: size))
        }
    }
}
