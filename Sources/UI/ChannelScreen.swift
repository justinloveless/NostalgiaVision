import KSPlayer
import SwiftUI

/// The picture, whatever it is doing. Nothing here is focusable, so the shell keeps focus and every
/// move command reaches the dial.
struct ChannelScreen: View {
    let playerLayer: KSPlayerLayer
    let tuned: TunedChannel
    let reception: Reception
    let feedName: String
    let effects: PictureEffects
    let transitionEffect: TransitionEffect
    let noiseVolume: EffectAmount

    @State private var showsChannelBug = true

    var body: some View {
        PictureEffectsStage(effects: effects) {
            ZStack {
                Color.black.ignoresSafeArea()

                PlayerSurface(playerLayer: playerLayer)
                    .ignoresSafeArea()

                transitionOverlay

                if case let .noSignal(signal) = reception {
                    caption(for: signal)
                }

                // The number stays up for as long as there is no picture — a set with snow on it has
                // nothing else to show — and otherwise flashes for a few seconds after a change.
                if showsChannelBug || reception != .picture {
                    channelBug
                }
            }
        }
        .task(id: tuned.channel.id) {
            showsChannelBug = true
            try? await Task.sleep(for: .seconds(3))
            showsChannelBug = false
        }
    }

    /// A `NoSignal` is a real dropped signal, not a transition the viewer asked for, so it shows
    /// static whatever the setting says. The rule lives here alone so no branch below has to ask
    /// what the reception is.
    private var effectiveTransition: TransitionEffect {
        reception == .acquiring ? transitionEffect : .staticSnow
    }

    @ViewBuilder
    private var transitionOverlay: some View {
        if reception != .picture {
            // No `default:`: a fifth look must fail to compile here rather than quietly render
            // nothing over the black.
            switch effectiveTransition {
            case .staticSnow: SnowView(noiseVolume: noiseVolume)
            case .blackSpinner: BlackSpinnerView()
            case .colorBars: ColorBarsView()
            case .blank: EmptyView()
            }
        }
    }

    private var channelBug: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(tuned.number.description)
                .font(.system(size: 96, weight: .heavy, design: .monospaced))
            Text(tuned.channel.name.description.uppercased())
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
            if !feedName.isEmpty {
                Text(feedName.uppercased())
                    .font(.system(size: 20, weight: .regular, design: .monospaced))
                    .opacity(0.6)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black, radius: 12)
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Channel \(tuned.number.description), \(tuned.channel.name.description)")
    }

    private func caption(for signal: NoSignal) -> some View {
        VStack(spacing: 16) {
            Text("NO SIGNAL")
                .font(.system(size: 72, weight: .heavy, design: .monospaced))
            Text(signal.cause == .stalled ? "WEAK RECEPTION" : "CHECK THE AERIAL")
                .font(.system(size: 28, weight: .regular, design: .monospaced))
                .opacity(0.7)
            Text("RETUNING…")
                .font(.system(size: 22, weight: .regular, design: .monospaced))
                .opacity(0.5)
        }
        .foregroundStyle(.white)
        .padding(48)
        .background(Color.black.opacity(0.55))
    }
}
