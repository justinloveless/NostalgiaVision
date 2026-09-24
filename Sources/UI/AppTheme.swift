import SwiftUI

/// The app's brand palette, sourced from the TV logo artwork's swatch. `night` is the one that
/// recurs as a generic dark backdrop across the app; the rest exist for chrome that wants to
/// match the mark.
enum AppTheme {
    static let amberBody = Color(red: 0.769, green: 0.471, blue: 0.227)
    static let charcoalAccent = Color(red: 0.110, green: 0.122, blue: 0.149)
    static let cream = Color(red: 0.961, green: 0.941, blue: 0.902)
    static let amberDeep = Color(red: 0.659, green: 0.384, blue: 0.180)
    static let paper = Color(red: 0.980, green: 0.969, blue: 0.949)
    static let night = Color(red: 0.055, green: 0.063, blue: 0.078)
}
