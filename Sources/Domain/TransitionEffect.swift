import Foundation

/// What appears on screen while a channel is tuning in (`Reception.acquiring`). A `NoSignal`
/// failure ignores this and always shows static — that's a real dropped signal, not the
/// viewer's transition preference.
enum TransitionEffect: String, CaseIterable, Equatable, Codable, Sendable {
    case staticSnow
    case blackSpinner
    case colorBars
    case blank

    static let standard = TransitionEffect.staticSnow

    var title: String {
        switch self {
        case .staticSnow: return "SNOW"
        case .blackSpinner: return "SPINNER"
        case .colorBars: return "COLOR BARS"
        case .blank: return "BLANK"
        }
    }

    /// Cycles forward, wrapping — same shape as every other settings-row detent.
    func stepped() -> TransitionEffect {
        let ladder = Self.allCases
        guard let index = ladder.firstIndex(of: self), index + 1 < ladder.count else {
            return ladder[0]
        }
        return ladder[index + 1]
    }
}
