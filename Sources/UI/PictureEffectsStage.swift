import SwiftUI

/// How often the positional jitter re-rolls, independent of the grain overlay's own redraw rate —
/// the picture should read as being on an unstable antenna, not as vibrating.
private let jitterUpdatesPerSecond = 6.0

/// Composites the seven CRT post-processing knobs over the picture.
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
                let time = timeline.date.timeIntervalSinceReferenceDate
                let noiseSeed = UInt64(bitPattern: Int64(time * 1000))
                let jitterTime = (time * jitterUpdatesPerSecond).rounded(.down) / jitterUpdatesPerSecond
                let jitterSeed = UInt64(bitPattern: Int64(jitterTime * 1000))
                stage(noiseSeed: noiseSeed, jitterSeed: jitterSeed)
            }
        } else {
            stage(noiseSeed: 0, jitterSeed: 0)
        }
    }

    private func stage(noiseSeed: UInt64, jitterSeed: UInt64) -> some View {
        let jitter = Self.jitterOffset(amount: effects.signalNoise.amount, seed: jitterSeed)

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
                SignalNoiseOverlay(amount: effects.signalNoise.amount, seed: noiseSeed)
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

            if effects.bevel.isEnabled {
                BevelOverlay(amount: effects.bevel.amount, curvatureAmount: effects.curvature.amount)
            }
        }
    }

    /// A whisper of unstable framing — the aerial is slightly bent. Kept subtle: this used to
    /// swing up to ±4pt on both axes every single frame, which read as the whole picture
    /// vibrating rather than a loose antenna.
    private static func jitterOffset(amount: EffectAmount, seed: UInt64) -> CGSize {
        guard amount.isEnabled else { return .zero }
        var s = seed | 1
        // `>>` on a UInt64 is a logical shift, so this lands evenly in [0, 1) unlike the signed
        // `% 1001` this replaced, which folded negative seeds into [-1.5, -0.5) and skewed every
        // axis toward one corner instead of centering on zero.
        s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let x = Double((s >> 33) & 0xFFFF) / 65535.0 - 0.5
        s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let y = Double((s >> 33) & 0xFFFF) / 65535.0 - 0.5
        let pixels = 0.5 + 1.5 * amount.value
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
        return cushionPath(in: rect, corner: corner, bow: bow)
    }
}

/// A closed cushion shape: each edge is a quadratic curve bowed toward the centre at its
/// midpoint, and each corner is a quadratic curve through the true rect corner (rounds it with
/// no arc-angle bookkeeping). `bow` is the inward pull of an edge's midpoint; `corner` is how
/// far the rounding reaches along each edge.
private func cushionPath(in rect: CGRect, corner: CGFloat, bow: CGFloat) -> Path {
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

/// An opaque cabinet painted over the outer band of the canvas with a cushion-shaped hole the
/// picture shows through. Nothing is warped or resized; the set is simply in front of the tube.
private struct BevelOverlay: View {
    let amount: EffectAmount
    /// The hole reuses the curvature knob's own cushion geometry, so the two never compose into a
    /// straight cabinet edge crossing a bowed tube edge.
    let curvatureAmount: EffectAmount

    var body: some View {
        Canvas { canvas, size in
            let thickness = 16 + 104 * CGFloat(amount.value)
            let topInset = thickness * 0.8
            let bottomInset = thickness * 1.25
            let cutoutRect = CGRect(
                x: thickness,
                y: topInset,
                width: size.width - thickness * 2,
                height: size.height - topInset - bottomInset
            )
            let curve = curvatureAmount.value
            let cutout = cushionPath(
                in: cutoutRect,
                corner: min(cutoutRect.width, cutoutRect.height) * (0.1 + 0.05 * curve),
                bow: min(cutoutRect.width, cutoutRect.height) * (0.012 + 0.035 * curve)
            )

            var cabinet = Path(CGRect(origin: .zero, size: size))
            cabinet.addPath(cutout)
            canvas.fill(
                cabinet,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.44, green: 0.31, blue: 0.20),
                        Color(red: 0.27, green: 0.18, blue: 0.11),
                        Color(red: 0.36, green: 0.25, blue: 0.16)
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                ),
                style: FillStyle(eoFill: true)
            )

            canvas.drawLayer { layer in
                layer.clip(to: cabinet, style: FillStyle(eoFill: true))
                layer.stroke(
                    cutout,
                    with: .color(.black.opacity(0.55)),
                    lineWidth: 6 + 10 * amount.value
                )
            }

            // Everything below is sized off the apron rather than in absolute points, so the
            // grille and knobs stay in proportion as the cabinet thickens.
            canvas.drawLayer { layer in
                layer.clip(to: cabinet, style: FillStyle(eoFill: true))
                let apronMidY = (cutoutRect.maxY + size.height) / 2
                let spacing = bottomInset * 0.16
                let dot = spacing * 0.3
                let rows = 4
                let originY = apronMidY - spacing * CGFloat(rows - 1) / 2
                for row in 0..<rows {
                    for column in 0..<26 {
                        let x = cutoutRect.minX + spacing * (2 + CGFloat(column))
                        let y = originY + spacing * CGFloat(row)
                        layer.fill(
                            Path(ellipseIn: CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2)),
                            with: .color(.black.opacity(0.55 * amount.value))
                        )
                    }
                }

                let radius = bottomInset * 0.26
                for index in 0..<2 {
                    let centerX = cutoutRect.maxX - radius * (1.4 + 3.0 * CGFloat(index))
                    let dial = Path(ellipseIn: CGRect(
                        x: centerX - radius,
                        y: apronMidY - radius,
                        width: radius * 2,
                        height: radius * 2
                    ))
                    layer.fill(
                        dial,
                        with: .radialGradient(
                            Gradient(colors: [
                                Color(red: 0.78, green: 0.64, blue: 0.45).opacity(0.95 * amount.value),
                                Color(red: 0.42, green: 0.31, blue: 0.20).opacity(0.95 * amount.value)
                            ]),
                            center: CGPoint(x: centerX - radius * 0.3, y: apronMidY - radius * 0.3),
                            startRadius: 0,
                            endRadius: radius * 1.6
                        )
                    )
                    layer.stroke(
                        dial,
                        with: .color(.black.opacity(0.5 * amount.value)),
                        lineWidth: max(1, radius * 0.16)
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
