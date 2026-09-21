import SwiftUI

/// The setup channel's on-screen-display palette. Broadcast cyan rather than amber so the two
/// warning colours keep the warm end of the spectrum to themselves: red still means "this
/// value will not validate" and orange still means "the feed is in trouble".
enum SetupPalette {
    static let accent = Color(red: 0.62, green: 0.94, blue: 1.0)
    /// The same hue at reading contrast against the near-white card tvOS floods a focused control
    /// with. `accent` on that card is very nearly invisible.
    static let focusedAccent = Color(red: 0.03, green: 0.28, blue: 0.40)
    static let label = Color.white.opacity(0.62)
    static let dim = Color.white.opacity(0.28)
}

/// The one slot in the cycle that is not a channel.
///
/// Two layouts, because the dial is held in one state and not the other (`TVSet.dialAcceptsInput`,
/// derived from `SettingsScreen.dialAcceptsInput`). Locked, up/down still tunes, so nothing on that
/// screen may consume vertical movement: the keypad stays a single horizontal strip and a viewer
/// who does not have the PIN can always turn away. That constraint is load-bearing and permanent.
/// Unlocked, the dial is held, so vertical belongs to the menu instead and the way back to a
/// channel has to be on screen: the EXIT TO TV row. Drop that row and the viewer is stranded on
/// everything but tvOS's Menu button.
struct SettingsScreenView: View {
    let screen: SettingsScreen
    let trouble: FeedTrouble?
    let send: (SettingsGate.Event) -> Void
    let onExit: () -> Void

    @State private var editingField: EditableField?
    @State private var panel: Panel = .root

    /// Which face of the unlocked menu is showing. One value rather than a flag per sub-menu, so
    /// "in the PIN pad *and* in the effects list" is not a state the view can get into.
    private enum Panel: Equatable {
        case root
        case pinEntry([Digit])
        case effects
        case transition
    }

    enum EditableField: String, Identifiable {
        case feedURL = "Feed URL"
        case name = "Name"

        var id: String { rawValue }
    }

    var body: some View {
        PictureEffectsStage(effects: .setupChannel) {
            VStack(spacing: 24) {
                Text(heading)
                    .font(.system(size: 38, weight: .heavy, design: .monospaced))
                    .foregroundStyle(SetupPalette.accent.opacity(0.75))
                    .tracking(10)

                menu

                Text(troubleCaption)
                    .font(.system(size: 22, weight: .regular, design: .monospaced))
                    .foregroundStyle(trouble == nil ? SetupPalette.dim : Color.orange)
                    .frame(height: 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(cabinetInsets(bevel: PictureEffects.setupChannel.bevel))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(SetupBackdrop())
        }
        .fullScreenCover(item: $editingField) { field in
            TextFieldEditorCover(title: field.rawValue, initial: initialText(for: field)) { text in
                commit(text, to: field)
            }
        }
        .onChange(of: isEditing) { _, editing in
            // Leaving the unlocked draft (re-lock, or dial away) must collapse any sub-panel so a
            // later unlock does not open straight into one of them.
            if !editing { panel = .root }
        }
    }

    private var isEditing: Bool {
        if case .editing = screen { return true }
        return false
    }

    private var heading: String {
        switch panel {
        case .root, .pinEntry: return "SET-UP"
        case .effects: return "PICTURE FX"
        case .transition: return "TRANSITION"
        }
    }

    @ViewBuilder
    private var menu: some View {
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
            // Capped rather than full-bleed: across 1920pt a row's title and its value end up at
            // opposite edges of the screen with nothing between them to read across. The locked
            // keypad above is deliberately left uncapped — it is one strip of eleven controls and
            // squeezing it wraps the labels.
            editingMenu(draft)
                .frame(maxWidth: 1100)
        }
    }

    @ViewBuilder
    private func editingMenu(_ draft: SettingsDraft) -> some View {
        switch panel {
        case .root:
            VStack(spacing: 6) {
                row(
                    title: "FEED URL",
                    value: draft.feedURLText.isEmpty ? "NOT SET" : draft.feedURLText,
                    isValid: draft.validated != nil || draft.feedURLText.isEmpty
                ) { editingField = .feedURL }

                row(
                    title: "NAME",
                    value: draft.feedName.isEmpty ? "NOT SET" : draft.feedName,
                    isValid: true
                ) { editingField = .name }

                row(title: "PIN", value: pinCaption(draft.pinEdit), isValid: true) {
                    panel = .pinEntry([])
                }

                row(title: "CLEAR PIN", value: "NO LOCK", isValid: true) {
                    send(.pinEdited(.cleared))
                }

                // Steps the detent ladder and persists on the spot, like CLEAR PIN — there is
                // nothing to type, so no editor cover and no commit.
                row(title: "TUNE DELAY", value: draft.tuneDelay.caption, isValid: true) {
                    send(.delayStepped)
                }

                row(
                    title: "PICTURE FX",
                    value: draft.pictureEffects.isActive ? "ON" : "OFF",
                    isValid: true
                ) { panel = .effects }

                row(title: "TRANSITION", value: draft.transitionEffect.title, isValid: true) {
                    panel = .transition
                }

                Rectangle()
                    .fill(SetupPalette.dim)
                    .frame(height: 1)
                    .padding(.top, 18)
                    .padding(.horizontal, 28)

                row(title: "EXIT TO TV", value: "CHANNEL", isValid: true) { onExit() }
            }

        case let .pinEntry(entry):
            PINEntryPad(
                entry: entry,
                onDigit: { digit in
                    guard entry.count < PIN.allowedLength.upperBound else { return }
                    panel = .pinEntry(entry + [digit])
                },
                onBackspace: { panel = .pinEntry(Array(entry.dropLast())) },
                onSave: {
                    send(.pinEdited(.set(entry)))
                    panel = .root
                },
                onBack: { panel = .root }
            )

        case .effects:
            VStack(spacing: 6) {
                ForEach(PictureEffectKind.allCases, id: \.self) { kind in
                    row(title: kind.title, value: draft.pictureEffects[kind].caption, isValid: true) {
                        send(.effectStepped(kind))
                    }
                }

                row(title: "BACK", value: "SET-UP", isValid: true) { panel = .root }
            }

        case .transition:
            VStack(spacing: 6) {
                row(title: "NOISE VOL", value: draft.noiseVolume.caption, isValid: true) {
                    send(.noiseVolumeStepped)
                }

                row(title: "TRANSITION", value: draft.transitionEffect.title, isValid: true) {
                    send(.transitionEffectStepped)
                }

                row(title: "BACK", value: "SET-UP", isValid: true) { panel = .root }
            }
        }
    }

    private func row(title: String, value: String, isValid: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RowLabel(title: title, value: value, isValid: isValid)
        }
    }

    /// Title before value, always: XCUITest matches these buttons on the composed accessibility
    /// label ("FEED URL, …"), which is built from the subviews in tree order.
    ///
    /// A view of its own only so it can read `isFocused`. tvOS floods the focused control with a
    /// near-white card and inverts the text itself only for plain-title buttons; a custom label
    /// like this one keeps whatever colours it was handed, which would wash out the single row the
    /// viewer is actually reading.
    private struct RowLabel: View {
        let title: String
        let value: String
        let isValid: Bool

        @Environment(\.isFocused) private var isFocused

        var body: some View {
            HStack(spacing: 32) {
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(isFocused ? Color.black.opacity(0.85) : .white)

                Spacer()

                Text(value)
                    .font(.system(size: 26, weight: .regular, design: .monospaced))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        }

        private var valueColor: Color {
            guard isValid else { return .red }
            return isFocused ? SetupPalette.focusedAccent : SetupPalette.accent
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
