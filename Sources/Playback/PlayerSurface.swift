import AVFoundation
import SwiftUI

/// A bare `AVPlayerLayer` in a `UIView`. No controls, no gesture recognizers, no focus.
///
/// `canBecomeFocused` is false and interaction is disabled, so the tvOS focus engine never
/// considers this view. That is what guarantees the root shell keeps focus while a channel plays
/// and therefore receives every move command — the routing rule is enforced by the view hierarchy,
/// not by a runtime guard.
struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    /// Rebinding the same player is a no-op; the layer is never torn down on channel change, which
    /// is what avoids a black flash between channels.
    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    override var canBecomeFocused: Bool { false }

    /// `.resizeAspect` — pillarbox 4:3 content rather than crop it. A CRT never cropped.
    var playerLayer: AVPlayerLayer {
        // Safe by construction: `layerClass` above fixes the layer type for every instance.
        layer as! AVPlayerLayer
    }
}
