import SwiftUI

/// Text entry for the feed URL and the feed's display name, hosted in a `fullScreenCover`.
///
/// The cover is what makes "the system keyboard owns the remote while typing" a structural fact
/// rather than an assumption: while it is up the shell's move handler is not in the presented
/// hierarchy at all, and when it comes down focus returns to the settings row. Its contents are a
/// single row, so no vertical movement is needed here either.
struct TextFieldEditorCover: View {
    let title: String
    let onCommit: (String) -> Void

    @State private var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldIsFocused: Bool

    init(title: String, initial: String, onCommit: @escaping (String) -> Void) {
        self.title = title
        self.onCommit = onCommit
        self._text = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 48) {
            Text(title.uppercased())
                .font(.system(size: 36, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))

            // No sibling Buttons in this focus scope: a Button next to the field is a known
            // tvOS focus-engine trap, where a layout change from typing can hand focus to the
            // neighbor mid-edit. Committing/cancelling go through the keyboard's own return and
            // the Menu button instead, so the field is the only focusable thing here.
            TextField(title, text: $text)
                .font(.system(size: 30, design: .monospaced))
                .frame(width: 900)
                .focused($fieldIsFocused)
                .onSubmit {
                    onCommit(text)
                    dismiss()
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .defaultFocus($fieldIsFocused, true)
        .onExitCommand { dismiss() }
    }
}
