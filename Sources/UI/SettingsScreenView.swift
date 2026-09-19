import SwiftUI

/// The one slot in the cycle that is not a channel.
///
/// Everything interactive lives in a single horizontal row. That is the load-bearing layout
/// decision of the whole app: no control here consumes vertical movement, so up/down always reach
/// the shell's dial handler and the viewer can tune away — including away from a *locked* screen.
/// A vertical `Form` would eat the only gesture that leaves this screen.
struct SettingsScreenView: View {
    let screen: SettingsScreen
    let trouble: FeedTrouble?
    let send: (SettingsGate.Event) -> Void

    @State private var editingField: EditableField?
    @State private var pinEntry: [Digit]?
    /// Nested CRT-effects row. Same idea as the PIN entry sub-row: one horizontal strip, no
    /// vertical focus traps, BACK returns to the main settings fields.
    @State private var editingEffects = false

    enum EditableField: String, Identifiable {
        case feedURL = "Feed URL"
        case name = "Name"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 72) {
            Text(editingEffects ? "PICTURE FX" : "SET-UP")
                .font(.system(size: 44, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(12)

            row

            Text(troubleCaption)
                .font(.system(size: 24, weight: .regular, design: .monospaced))
                .foregroundStyle(trouble == nil ? .white.opacity(0.3) : .orange)
                .frame(height: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .fullScreenCover(item: $editingField) { field in
            TextFieldEditorCover(title: field.rawValue, initial: initialText(for: field)) { text in
                commit(text, to: field)
            }
        }
        .onChange(of: isEditing) { _, editing in
            // Leaving the unlocked draft (re-lock, or dial away) must collapse the FX sub-row so a
            // later unlock does not open straight into effects.
            if !editing { editingEffects = false }
        }
    }

    private var isEditing: Bool {
        if case .editing = screen { return true }
        return false
    }

    @ViewBuilder
    private var row: some View {
        switch screen {
        case let .locked(challenge):
            // There is no draft to render here. Not "disabled" — absent.
            PINKeypadRow(
                caption: challenge.isCoolingDown(at: .now) ? "LOCKED OUT — WAIT" : "ENTER PIN",
                filled: challenge.typed.count,
                expectedLength: challenge.expectedLength,
                shake: challenge.lastAttemptFailed,
                onDigit: { send(.typed($0)) },
                onBackspace: { send(.backspace) }
            )

        case let .editing(draft):
            if let entry = pinEntry {
                PINKeypadRow(
                    caption: "NEW PIN — \(PIN.allowedLength.lowerBound) TO \(PIN.allowedLength.upperBound) DIGITS",
                    filled: entry.count,
                    expectedLength: nil,
                    shake: false,
                    onDigit: { digit in
                        guard entry.count < PIN.allowedLength.upperBound else { return }
                        pinEntry = entry + [digit]
                    },
                    onBackspace: { pinEntry = entry.isEmpty ? entry : Array(entry.dropLast()) },
                    controls: [
                        PINKeypadRow.Control(title: "SAVE", isEnabled: PIN(digits: entry) != nil) {
                            send(.pinEdited(.set(entry)))
                            pinEntry = nil
                        },
                        PINKeypadRow.Control(title: "BACK", isEnabled: true) { pinEntry = nil }
                    ]
                )
            } else if editingEffects {
                HStack(spacing: 36) {
                    ForEach(PictureEffectKind.allCases, id: \.self) { kind in
                        field(title: kind.title, value: draft.pictureEffects[kind].caption, isValid: true) {
                            send(.effectStepped(kind))
                        }
                    }

                    field(title: "BACK", value: "SET-UP", isValid: true) {
                        editingEffects = false
                    }
                }
            } else {
                HStack(spacing: 60) {
                    field(
                        title: "FEED URL",
                        value: draft.feedURLText.isEmpty ? "NOT SET" : draft.feedURLText,
                        isValid: draft.validated != nil || draft.feedURLText.isEmpty
                    ) { editingField = .feedURL }

                    field(
                        title: "NAME",
                        value: draft.feedName.isEmpty ? "NOT SET" : draft.feedName,
                        isValid: true
                    ) { editingField = .name }

                    field(title: "PIN", value: pinCaption(draft.pinEdit), isValid: true) {
                        pinEntry = []
                    }

                    field(title: "CLEAR PIN", value: "NO LOCK", isValid: true) {
                        send(.pinEdited(.cleared))
                    }

                    // Steps the detent ladder and persists on the spot, like CLEAR PIN — there is
                    // nothing to type, so no editor cover and no commit.
                    field(title: "TUNE DELAY", value: draft.tuneDelay.caption, isValid: true) {
                        send(.delayStepped)
                    }

                    field(
                        title: "PICTURE FX",
                        value: draft.pictureEffects.isActive ? "ON" : "OFF",
                        isValid: true
                    ) {
                        editingEffects = true
                    }
                }
            }
        }
    }

    private func field(title: String, value: String, isValid: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Text(value)
                    .font(.system(size: 28, weight: .regular, design: .monospaced))
                    .foregroundStyle(isValid ? .white : .red)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520)
            }
            .padding(24)
        }
    }

    private func pinCaption(_ edit: PINEdit) -> String {
        switch edit {
        case .unchanged: return "SET / CHANGE"
        case .cleared: return "CLEARED"
        case .set: return "SAVED"
        }
    }

    private var troubleCaption: String {
        switch trouble {
        case nil: return ""
        case .notConfigured: return "NO AERIAL — ENTER A FEED URL"
        case .unreachable: return "NO SIGNAL FROM SERVER"
        case .rejected: return "SERVER REFUSED THE CONNECTION"
        case .notAPlaylist: return "THAT URL IS NOT A PLAYLIST"
        case .empty: return "PLAYLIST HAS NO CHANNELS"
        case let .skippedEntries(count): return "\(count) ENTRIES SKIPPED"
        }
    }

    private func initialText(for field: EditableField) -> String {
        guard case let .editing(draft) = screen else { return "" }
        switch field {
        case .feedURL: return draft.feedURLText
        case .name: return draft.feedName
        }
    }

    private func commit(_ text: String, to field: EditableField) {
        guard case let .editing(draft) = screen else { return }
        var updated = draft
        switch field {
        case .feedURL: updated.feedURLText = text
        case .name: updated.feedName = text
        }
        send(.draftChanged(updated))
        send(.commitRequested)
    }
}
