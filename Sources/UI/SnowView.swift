import SwiftUI

/// Analog static: a coarse grid of random grey cells, redrawn a dozen times a second. Drawn rather
/// than played back so it costs no asset and never loops visibly.
struct SnowView: View {
    private static let columns = 96
    private static let rows = 54
    /// Peak cell brightness — the volume of the white-noise snow. Held at 20% so the static
    /// stays present without blasting the screen between channels.
    static let volume = 0.2

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { context in
            Canvas(opaque: true, rendersAsynchronously: true) { canvas, size in
                // A cheap LCG reseeded per frame: deterministic within a frame, different between
                // frames, and no allocation.
                var seed = UInt64(bitPattern: Int64(context.date.timeIntervalSinceReferenceDate * 1000)) | 1
                let cellWidth = size.width / CGFloat(Self.columns)
                let cellHeight = size.height / CGFloat(Self.rows)

                for row in 0..<Self.rows {
                    for column in 0..<Self.columns {
                        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                        let level = Double((seed >> 33) & 0xFF) / 255.0
                        let rect = CGRect(
                            x: CGFloat(column) * cellWidth,
                            y: CGFloat(row) * cellHeight,
                            width: cellWidth + 1,
                            height: cellHeight + 1
                        )
                        canvas.fill(Path(rect), with: .color(Color(white: level * Self.volume)))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
