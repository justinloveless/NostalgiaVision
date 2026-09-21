import CoreGraphics
import Foundation

/// Vertical line count shared by every drawn-static effect (signal-noise grain, no-signal snow).
/// Their "pixels" should read at the chunkiness of an actual 420-line broadcast picture no matter
/// the screen's real resolution — finer than this and the noise starts looking like modern,
/// digitally-clean grain instead of an analog signal.
let analogNoiseLines = 420

/// Column count for an `analogNoiseLines`-tall grid that fills a canvas of the given
/// width-over-height `aspect` without squishing cells into rectangles.
func analogNoiseColumns(aspect: CGFloat) -> Int {
    max(1, Int((CGFloat(analogNoiseLines) * aspect).rounded()))
}

/// Turns a buffer of premultiplied RGBA bytes into a `CGImage` sized `columns` x `rows`.
///
/// Callers write one grid of static by filling this buffer directly rather than issuing a Core
/// Graphics fill per cell: at `analogNoiseLines` resolution a canvas has 100k+ cells, and one fill
/// call each drops well below frame rate. Writing bytes and blitting a single scaled image stays
/// cheap on the Apple TV at any grid size.
func imageFromPremultipliedRGBA(_ pixels: [UInt8], columns: Int, rows: Int) -> CGImage? {
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(
        width: columns,
        height: rows,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: columns * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}
