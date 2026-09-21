import Foundation

/// Discrete strength for one knob — a CRT effect or an audio level. `0` is off; every detent above
/// that is on at that strength.
///
/// Constructible only through the failable initializer (the persistence boundary) or `stepped()`,
/// so every amount in memory is already known-valid.
struct EffectAmount: Equatable, Codable, Sendable {
    static let allowed: ClosedRange<Double> = 0...1
    static let step = 0.25
    /// Ascending, including off. What each effect field cycles through.
    static let detents: [EffectAmount] = [0, 0.25, 0.5, 0.75, 1].map { EffectAmount(unchecked: $0) }

    let value: Double

    /// `nil` outside `allowed` — corrupt persistence falls back at the store boundary.
    init?(value: Double) {
        guard Self.allowed.contains(value) else { return nil }
        self.value = value
    }

    private init(unchecked value: Double) {
        self.value = value
    }

    static let off = EffectAmount(unchecked: 0)
    static let mild = EffectAmount(unchecked: 0.25)
    static let medium = EffectAmount(unchecked: 0.5)
    static let strong = EffectAmount(unchecked: 0.75)
    static let full = EffectAmount(unchecked: 1)

    var isEnabled: Bool { value > 0 }

    /// The next detent, wrapping from full back to off. Tolerant of an off-ladder value: lands on
    /// the first detent strictly above it, or off when nothing is above.
    func stepped() -> EffectAmount {
        Self.detents.first { $0.value > value + 0.000_1 } ?? .off
    }

    /// "OFF", "25%", "50%", "75%", "100%".
    var caption: String {
        guard isEnabled else { return "OFF" }
        return "\(Int((value * 100).rounded()))%"
    }
}

/// Which CRT effect the settings row is stepping. Raw values are the persistence key suffixes and
/// the on-screen titles.
enum PictureEffectKind: String, CaseIterable, Equatable, Sendable {
    case vignette
    case scanLines
    case curvature
    case chromaticAberration
    case glowBloom
    case signalNoise
    case bevel

    var title: String {
        switch self {
        case .vignette: return "VIGNETTE"
        case .scanLines: return "SCANLINES"
        case .curvature: return "CURVE"
        case .chromaticAberration: return "CHROMA"
        case .glowBloom: return "GLOW"
        case .signalNoise: return "NOISE"
        case .bevel: return "BEVEL"
        }
    }
}

/// One toggleable CRT effect with a single adjustable strength. Stepping advances OFF → 25% → …
/// → 100% → OFF, so enable/disable and intensity share one control — matching the tune-delay
/// detent pattern and the horizontal settings row.
struct PictureEffect: Equatable, Codable, Sendable {
    var amount: EffectAmount

    static let off = PictureEffect(amount: .off)

    var isEnabled: Bool { amount.isEnabled }

    var caption: String { amount.caption }

    func stepped() -> PictureEffect {
        PictureEffect(amount: amount.stepped())
    }
}

/// The seven CRT post-processing knobs. Defaults are all off so upgrading changes nothing for a
/// viewer who never opens the new settings.
struct PictureEffects: Equatable, Codable, Sendable {
    var vignette: PictureEffect
    var scanLines: PictureEffect
    var curvature: PictureEffect
    var chromaticAberration: PictureEffect
    var glowBloom: PictureEffect
    var signalNoise: PictureEffect
    var bevel: PictureEffect

    static let off = PictureEffects(
        vignette: .off,
        scanLines: .off,
        curvature: .off,
        chromaticAberration: .off,
        glowBloom: .off,
        signalNoise: .off,
        bevel: .off
    )

    subscript(_ kind: PictureEffectKind) -> PictureEffect {
        get {
            switch kind {
            case .vignette: return vignette
            case .scanLines: return scanLines
            case .curvature: return curvature
            case .chromaticAberration: return chromaticAberration
            case .glowBloom: return glowBloom
            case .signalNoise: return signalNoise
            case .bevel: return bevel
            }
        }
        set {
            switch kind {
            case .vignette: vignette = newValue
            case .scanLines: scanLines = newValue
            case .curvature: curvature = newValue
            case .chromaticAberration: chromaticAberration = newValue
            case .glowBloom: glowBloom = newValue
            case .signalNoise: signalNoise = newValue
            case .bevel: bevel = newValue
            }
        }
    }

    /// Advances one effect one detent. Pure; the gate persists the returned value.
    func stepping(_ kind: PictureEffectKind) -> PictureEffects {
        var next = self
        next[kind] = self[kind].stepped()
        return next
    }

    /// True when any effect will change what is drawn over the picture.
    var isActive: Bool {
        PictureEffectKind.allCases.contains { self[$0].isEnabled }
    }
}
