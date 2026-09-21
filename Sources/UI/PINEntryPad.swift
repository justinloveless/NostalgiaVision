import SwiftUI

/// The keypad for choosing a *new* PIN, on the unlocked setup menu.
///
/// Deliberately a second view rather than an orientation flag on `PINKeypadRow`. That view serves
/// the locked screen, where vertical movement has to reach the dial so a viewer who does not know
/// the PIN can always tune away; it can never be allowed to grow a second row, and a flag is an
/// invitation to pass the wrong one and silently seal that exit. Here the draft already owns
/// up/down (`SettingsScreen.dialAcceptsInput`), so a grid is both legal and a much shorter trip
/// across a remote than eleven controls strung out in a line.
///
/// The length rule lives here twice over — the caption and whether SAVE is live are both read off
/// `PIN.allowedLength`, so neither can drift from what `PIN.init` will actually accept.
struct PINEntryPad: View {
    let entry: [Digit]
    let onDigit: (Digit) -> Void
    let onBackspace: () -> Void
    let onSave: () -> Void
    let onBack: () -> Void

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: 3)

    private var isSaveEnabled: Bool { PIN(digits: entry) != nil }

    private var caption: String {
        "NEW PIN — \(PIN.allowedLength.lowerBound) TO \(PIN.allowedLength.upperBound) DIGITS"
    }

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 16) {
                Text(caption)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SetupPalette.accent)
                dots
            }

            LazyVGrid(columns: Self.columns, spacing: 12) {
                ForEach(1...9, id: \.self) { value in
                    digit(value)
                }

                Button("DEL", action: onBackspace)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(SetupPalette.label)

                digit(0)

                Button("SAVE", action: onSave)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .disabled(!isSaveEnabled)
            }

            Button("BACK", action: onBack)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(SetupPalette.label)
        }
        .frame(maxWidth: 560)
    }

    private func digit(_ value: Int) -> some View {
        Button(String(value)) {
            if let digit = Digit(value) { onDigit(digit) }
        }
        .font(.system(size: 34, weight: .bold, design: .monospaced))
        .foregroundStyle(.white)
    }

    private var dots: some View {
        HStack(spacing: 18) {
            ForEach(0..<entry.count, id: \.self) { _ in
                Circle()
                    .fill(SetupPalette.accent)
                    .frame(width: 22, height: 22)
            }
            if entry.isEmpty {
                Circle()
                    .strokeBorder(SetupPalette.dim, lineWidth: 2)
                    .frame(width: 22, height: 22)
            }
        }
        .frame(height: 24)
    }
}
