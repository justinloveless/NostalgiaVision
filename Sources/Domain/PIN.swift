import Foundation

/// One decimal digit. A "PIN" made of letters is unrepresentable.
struct Digit: Hashable, Sendable {
    let value: UInt8

    init?(_ character: Character) {
        guard let digit = character.wholeNumberValue, (0...9).contains(digit) else { return nil }
        self.value = UInt8(digit)
    }

    init?(_ value: Int) {
        guard (0...9).contains(value) else { return nil }
        self.value = UInt8(value)
    }
}

/// A validated PIN: 4–6 digits.
///
/// Intentionally not `Codable`, not `CustomStringConvertible`, not `CustomDebugStringConvertible`:
/// it must be impossible to accidentally serialise a PIN into a plist, a log line, or a crash
/// report. `PINKeychain` is the one file allowed to turn `digits` back into characters.
struct PIN: Equatable, Sendable {
    static let allowedLength: ClosedRange<Int> = 4...6

    let digits: [Digit]

    init?(digits: [Digit]) {
        guard Self.allowedLength.contains(digits.count) else { return nil }
        self.digits = digits
    }

    var length: Int { digits.count }
}
