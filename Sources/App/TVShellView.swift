import SwiftUI

/// The root view. Renders whatever `TVSet.screen` says and forwards remote input to `TVSet`.
/// That is the whole app.
struct TVShellView: View {
    let tv: TVSet

    @FocusState private var shellHasFocus: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch tv.screen {
            case let .channel(tuned, reception):
                // PlayerSurface refuses focus, so nothing here competes for move commands. The
                // focus target is the channel screen itself, not the root: a focusable root spans
                // the whole window, so on settings the focus engine would never descend into the
                // control row and every control would look selected at once.
                ChannelScreen(
                    playerLayer: tv.playerLayer,
                    tuned: tuned,
                    reception: reception,
                    feedName: tv.feedName,
                    effects: tv.pictureEffects,
                    transitionEffect: tv.transitionEffect,
                    noiseVolume: tv.noiseVolume
                )
                    .focusable(true)
                    .focused($shellHasFocus)

            case let .settings(screen, trouble):
                // Horizontally navigable by construction; leaves up/down to the dial.
                SettingsScreenView(screen: screen, trouble: trouble) { event in tv.settings(event) }
            }
        }
        // A sibling of the screen, not part of it: the bar names where the knob is pointing, which
        // is by definition not what either branch above is rendering.
        .overlay(alignment: .top) {
            if let target = tv.preview {
                PreviewBar(target: target)
            }
        }
        .onMoveCommand { direction in
            // Vertical only. Horizontal is deliberately unhandled so focusable descendants get it.
            guard let turn = TuneDirection(direction) else { return }
            tv.turn(turn)
        }
        // Installed only on settings: on a channel the system must keep Menu so it can exit to the
        // Home screen, which is what a TV set does when you turn it off.
        .onExitCommand(perform: isShowingSettings ? { tv.pressedMenu() } : nil)
        .onChange(of: scenePhase) { _, phase in
            // If the shell ever loses focus the remote goes dead, so re-assert it on re-entry.
            if phase == .active { shellHasFocus = true }
        }
        .onChange(of: isShowingSettings) { _, showingSettings in
            // Coming back from settings the channel screen is newly focusable; claim it at once so
            // the remote is never dead.
            if !showingSettings { shellHasFocus = true }
        }
    }

    private var isShowingSettings: Bool {
        if case .settings = tv.screen { return true }
        return false
    }
}

/// The only place in the codebase where `MoveCommandDirection` appears.
extension TuneDirection {
    /// `nil` for `.left`/`.right`: horizontal movement is never the dial's business.
    init?(_ command: MoveCommandDirection) {
        switch command {
        case .up: self = .up
        case .down: self = .down
        default: return nil
        }
    }
}
