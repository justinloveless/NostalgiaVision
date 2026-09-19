import SwiftUI

/// Composites the six CRT post-processing knobs over the picture.
///
/// Implemented as overlays and a light positional jitter rather than a GPU capture of the player:
/// `KSPlayer`'s UIKit surface does not reliably flatten into a SwiftUI `drawingGroup`, so sampling
/// shaders would silently no-op. Overlays still read as analog TV and stay cheap on the Apple TV.
struct PictureEffectsStage<Content: View>: View {
    let effects: PictureEffects
    @ViewBuilder let content: () -> Content

    var body: some View {
        if effects.signalNoise.isEnabled {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                let seed = UInt64(bitPattern: Int64(timeline.date.timeIntervalSinceReferenceDate * 1000))
                stage(seed: seed)
            }
        } else {
            stage(seed: 0)
        }
    }

    private func stage(seed: UInt64) -> some View {
        let jitter = Self.jitterOffset(amount: effects.signalNoise.amount, seed: seed)

        return ZStack {
            content()
                .offset(jitter)
                .scaleEffect(effects.curvature.isEnabled ? 1.0 + 0.02 * effects.curvature.amount.value : 1)

            if effects.chromaticAberration.isEnabled {
                ChromaticAberrationOverlay(amount: effects.chromaticAberration.amount)
            }

            if effects.scanLines.isEnabled {
                ScanLinesOverlay(amount: effects.scanLines.amount)
            }

            if effects.signalNoise.isEnabled {
                SignalNoiseOverlay(amount: effects.signalNoise.amount, seed: seed)
            }

            if effects.glowBloom.isEnabled {
                GlowBloomOverlay(amount: effects.glowBloom.amount)
            }

            if effects.vignette.isEnabled {
                VignetteOverlay(amount: effects.vignette.amount)
            }

            if effects.curvature.isEnabled {
                CurvatureMaskOverlay(amount: effects.curvature.amount)
            }
        }
    }

    /// A few pixels of unstable framing — the aerial is slightly bent.
    private static func jitterOffset(amount: EffectAmount, seed: UInt64) -> CGSize {
        guard amount.isEnabled else { return .zero }
        var s = seed | 1
        s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let x = Double(Int64(bitPattern: s) % 1001) / 1000.0 - 0.5
        s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let y = Double(Int64(bitPattern: s) % 1001) / 1000.0 - 0.5
        let pixels = 2.0 + 6.0 * amount.value
        return CGSize(width: x * pixels, height: y * pixels)
    }
}

// MARK: - Overlays

private struct VignetteOverlay: View {
    let amount: EffectAmount

    var body: some View {
        RadialGradient(
            colors: [
                .clear,
                .black.opacity(0.15 * amount.value),
                .black.opacity(0.55 * amount.value + 0.15 * amount.value),
                .black.opacity(0.85 * amount.value)
            ],
            center: .center,
            startRadius: 80,
            endRadius: 900
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ScanLinesOverlay: View {
    let amount: EffectAmount

    var body: some View {
        Canvas { canvas, size in
            let spacing = max(2.0, 4.0 - amount.value * 1.5)
            let lineOpacity = 0.12 + 0.28 * amount.value
            var y: CGFloat = 0
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                canvas.stroke(path, with: .color(.black.opacity(lineOpacity)), lineWidth: 1)
                y += spacing
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .blendMode(.multiply)
    }
}

/// RGB fringe at the tube edges — sells chromatic aberration without sampling the player texture.
private struct ChromaticAberrationOverlay: View {
    let amount: EffectAmount

    var body: some View {
        let strength = 0.18 * amount.value
        HStack(spacing: 0) {
            LinearGradient(
                colors: [.red.opacity(strength), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(maxWidth: 120 + 80 * amount.value)

            Spacer(minLength: 0)

            LinearGradient(
                colors: [.clear, .cyan.opacity(strength)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(maxWidth: 120 + 80 * amount.value)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .blendMode(.screen)
    }
}

/// Soft phosphor haze: a cool-white centre bloom plus a faint green tube glow at the rim.
private struct GlowBloomOverlay: View {
    let amount: EffectAmount

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color(red: 0.85, green: 0.95, blue: 1.0).opacity(0.18 * amount.value),
                    .clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    .clear,
                    Color(red: 0.45, green: 1.0, blue: 0.55).opacity(0.10 * amount.value),
                    Color(red: 0.45, green: 1.0, blue: 0.55).opacity(0.22 * amount.value)
                ],
                center: .center,
                startRadius: 380,
                endRadius: 980
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .blendMode(.screen)
    }
}

/// Sells a curved piece of glass rather than a rounded corner crop: the tube's boundary is a
/// pillow/cushion shape (edges bow inward at their midpoint, not just the corners), with a blurred
/// dark rim where the glass reads thickest and a specular sweep where it catches the light.
private struct CurvatureMaskOverlay: View {
    let amount: EffectAmount

    var body: some View {
        Canvas { canvas, size in
            let tube = Self.tubePath(in: size, amount: amount.value)

            var mask = Path(CGRect(origin: .zero, size: size))
            mask.addPath(tube)
            canvas.fill(
                mask,
                with: .color(.black.opacity(0.55 + 0.35 * amount.value)),
                style: FillStyle(eoFill: true)
            )

            // Rim compression: the glass looks thickest right at the curve, same as light grazing
            // the edge of an actual curved surface.
            canvas.drawLayer { layer in
                layer.clip(to: tube)
                layer.addFilter(.blur(radius: 8 + 14 * amount.value))
                layer.stroke(
                    tube,
                    with: .color(.black.opacity(0.35 * amount.value)),
                    lineWidth: 20 + 46 * amount.value
                )
            }

            // Specular sweep: a soft highlight arcing across the upper rim, the way light catches
            // curved glass.
            canvas.drawLayer { layer in
                layer.clip(to: tube)
                let bandHeight = size.height * (0.22 + 0.1 * amount.value)
                layer.fill(
                    Path(CGRect(x: 0, y: 0, width: size.width, height: bandHeight)),
                    with: .linearGradient(
                        Gradient(colors: [.white.opacity(0.16 * amount.value), .clear]),
                        startPoint: CGPoint(x: size.width / 2, y: 0),
                        endPoint: CGPoint(x: size.width / 2, y: bandHeight)
                    )
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A closed cushion shape: each edge is a quadratic curve bowed toward the centre at its
    /// midpoint, and each corner is a quadratic curve through the true rect corner (rounds it with
    /// no arc-angle bookkeeping). `bow` is the inward pull of an edge's midpoint; `corner` is how
    /// far the rounding reaches along each edge.
    private static func tubePath(in size: CGSize, amount: Double) -> Path {
        let insetX = 18 + 36 * amount
        let insetY = 14 + 28 * amount
        let rect = CGRect(
            x: insetX,
            y: insetY,
            width: size.width - insetX * 2,
            height: size.height - insetY * 2
        )
        let corner = min(rect.width, rect.height) * (0.1 + 0.05 * amount)
        let bow = min(rect.width, rect.height) * (0.012 + 0.035 * amount)

        let left = rect.minX, right = rect.maxX, top = rect.minY, bottom = rect.maxY
        let midX = rect.midX, midY = rect.midY

        var path = Path()
        path.move(to: CGPoint(x: left + corner, y: top))
        path.addQuadCurve(to: CGPoint(x: right - corner, y: top), control: CGPoint(x: midX, y: top + bow))
        path.addQuadCurve(to: CGPoint(x: right, y: top + corner), control: CGPoint(x: right, y: top))
        path.addQuadCurve(to: CGPoint(x: right, y: bottom - corner), control: CGPoint(x: right - bow, y: midY))
        path.addQuadCurve(to: CGPoint(x: right - corner, y: bottom), control: CGPoint(x: right, y: bottom))
        path.addQuadCurve(to: CGPoint(x: left + corner, y: bottom), control: CGPoint(x: midX, y: bottom - bow))
        path.addQuadCurve(to: CGPoint(x: left, y: bottom - corner), control: CGPoint(x: left, y: bottom))
        path.addQuadCurve(to: CGPoint(x: left, y: top + corner), control: CGPoint(x: left + bow, y: midY))
        path.addQuadCurve(to: CGPoint(x: left + corner, y: top), control: CGPoint(x: left, y: top))
        path.closeSubpath()
        return path
    }
}

private struct SignalNoiseOverlay: View {
    let amount: EffectAmount
    let seed: UInt64

    private static let columns = 64
    private static let rows = 36

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { canvas, size in
            var s = seed | 1
            let cellWidth = size.width / CGFloat(Self.columns)
            let cellHeight = size.height / CGFloat(Self.rows)
            let opacity = 0.04 + 0.14 * amount.value

            for row in 0..<Self.rows {
                for column in 0..<Self.columns {
                    s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    let level = Double((s >> 33) & 0xFF) / 255.0
                    // Sparse: only light a fraction of cells so the picture stays readable.
                    guard ((s >> 8) & 0x7) == 0 else { continue }
                    let rect = CGRect(
                        x: CGFloat(column) * cellWidth,
                        y: CGFloat(row) * cellHeight,
                        width: cellWidth + 1,
                        height: cellHeight + 1
                    )
                    canvas.fill(Path(rect), with: .color(Color(white: level, opacity: opacity)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .blendMode(.screen)
    }
}
