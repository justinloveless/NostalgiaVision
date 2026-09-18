import SwiftUI

@main
@MainActor
struct NostalgiaVisionApp: App {
    /// Composition root. The only place concrete implementations are named.
    @State private var tv = TVSet(store: SettingsStore(), feed: TunarrFeed(), receiver: Receiver())

    var body: some Scene {
        WindowGroup {
            TVShellView(tv: tv)
                .task { await tv.powerOn() }
                .preferredColorScheme(.dark)
                .persistentSystemOverlays(.hidden)
        }
    }
}
