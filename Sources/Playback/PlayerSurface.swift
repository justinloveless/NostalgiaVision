import KSPlayer
import SwiftUI

/// A bare host for `KSPlayerLayer`'s rendering view. No controls, no gesture recognizers, no focus.
///
/// `KSPlayerLayer` reparents its own view into whatever superview it already has whenever the
/// underlying decoder is swapped (AirPlay, an engine fallback): it inserts the new view below the
/// old one, then removes the old one. So this only ever needs to host the view once — the same
/// "one player, reused, no black flash between channels" contract `Receiver` keeps, just enforced
/// one layer down.
///
/// `canBecomeFocused` is false and interaction is disabled, so the tvOS focus engine never
/// considers this view. That is what guarantees the root shell keeps focus while a channel plays
/// and therefore receives every move command — the routing rule is enforced by the view hierarchy,
/// not by a runtime guard.
struct PlayerSurface: UIViewRepresentable {
    let playerLayer: KSPlayerLayer

    func makeUIView(context: Context) -> PlayerHostView {
        let host = PlayerHostView()
        host.backgroundColor = .black
        host.isUserInteractionEnabled = false
        if let view = playerLayer.player.view {
            view.isUserInteractionEnabled = false
            view.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: host.topAnchor),
                view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            ])
        }
        return host
    }

    /// `KSPlayerLayer` manages its own view's presence in `host` from here on; there is nothing
    /// left for SwiftUI to reconcile on updates.
    func updateUIView(_ host: PlayerHostView, context: Context) {}
}

final class PlayerHostView: UIView {
    override var canBecomeFocused: Bool { false }
}
