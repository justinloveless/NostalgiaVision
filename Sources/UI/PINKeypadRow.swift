import SwiftUI

/// A single horizontal strip: dots, 0–9, backspace, and whatever extra controls the caller needs.
///
/// Our own keypad rather than `SecureField` for two reasons: the tvOS system keyboard for a secure
/// field is a full alphanumeric presentation, which is the wrong affordance for four digits; and
/// this keeps `[Digit]` at the boundary instead of a `String` that would have to be re-validated.
/// It also keeps the locked screen free of any system presentation, so vertical movement still
/// belongs to the dial while the PIN is being entered.
struct PINKeypadRow: View {
    struct Control: Identifiable {
        let title: String
        let isEnabled: Bool
        let action: () -> Void

        var id: String { title }
    }

    let caption: String
    let filled: Int
    let expectedLength: Int?
    let shake: Bool
    let onDigit: (Digit) -> Void
    let onBackspace: () -> Void
    var controls: [Control] = []

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 16) {
                Text(caption)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                dots
            }

            HStack(spacing: 20) {
                ForEach(0...9, id: \.self) { value in
                    Button(String(value)) {
                        if let digit = Digit(value) { onDigit(digit) }
                    }
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                }

                Button("DEL", action: onBackspace)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))

                ForEach(controls) { control in
                    Button(control.title, action: control.action)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .disabled(!control.isEnabled)
                }
            }
        }
        .offset(x: shake ? 18 : 0)
        .animation(.default.speed(4), value: shake)
    }

    private var dots: some View {
        HStack(spacing: 18) {
            ForEach(0..<max(filled, expectedLength ?? filled), id: \.self) { index in
                Circle()
                    .fill(index < filled ? Color.white : Color.white.opacity(0.2))
                    .frame(width: 22, height: 22)
            }
            if expectedLength == nil && filled == 0 {
                Circle()
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 2)
                    .frame(width: 22, height: 22)
            }
        }
        .frame(height: 24)
    }
}
