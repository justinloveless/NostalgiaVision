import SwiftUI

/// Where the knob is pointing while the picture has not caught up yet.
///
/// Rendered only when `TVSet.preview` is non-nil, so this view never has to express "nothing
/// pending" — its mere presence *is* the pending state. Stateless and not focusable: it must never
/// compete for the move commands that are driving it.
struct PreviewBar: View {
    let target: DialPosition

    var body: some View {
        HStack(spacing: 20) {
            switch target {
            case let .channel(tuned):
                Text(tuned.number.description)
                    .font(.system(size: 40, weight: .heavy, design: .monospaced))
                Text(tuned.channel.name.description.uppercased())
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
            case .settings:
                Text("SET-UP")
                    .font(.system(size: 28, weight: .heavy, design: .monospaced))
                    .tracking(8)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black, radius: 12)
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
        .background(Color.black.opacity(0.65))
        .padding(.top, 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch target {
        case let .channel(tuned):
            return "Previewing channel \(tuned.number.description), \(tuned.channel.name.description)"
        case .settings:
            return "Previewing set-up"
        }
    }
}
