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
/// Three layouts, because the dial is held in exactly one of the three (`TVSet`'s gate, derived from
/// `SettingsScreen.dialAcceptsInput`). Locked and landing both show a single, low-stakes control — a
/// keypad, a button — and leave up/down free to tune away, so dialing onto the settings slot never
/// captures the remote by surprise, with or without a PIN configured. Only pressing EDIT SETTINGS (or
/// typing a correct PIN, which skips landing entirely) commits to `.editing`, which holds the dial for
/// its own vertical menu. BACK at the root of that menu sends `.backRequested`, handing the dial back
/// without leaving the settings slot; tvOS's Menu button still leaves the slot entirely from any of
/// the three, exactly as it always has.
struct SettingsScreenView: View {
    let screen: SettingsScreen
    let trouble: FeedTrouble?
    let send: (SettingsGate.Event) -> Void

    @State private var editingField: EditableField?
    @State private var panel: Panel = .root
    @State private var previewBackground: PreviewBackground = .colorBars

    /// Which face of the unlocked menu is showing. One value rather than a flag per sub-menu, so
    /// "in the PIN pad *and* in the effects list" is not a state the view can get into.
    private enum Panel: Equatable {
        case root
        case pinEntry([Digit])
        case effects
        case transition
    }

    /// What the effects preview is painted over. Local `@State` rather than part of `SettingsDraft`,
    /// because like `panel` it is ephemeral state about how the preview is being inspected, not a
    /// setting the viewer owns.
    private enum PreviewBackground: CaseIterable, Equatable {
        case colorBars
        /// The screen-blend effects need headroom to read as adding light, and `ColorBarsView`'s
        /// fully-saturated broadcast-bright bars leave none — GLOW especially, and NOISE, barely
        /// show against them.
        case dark

        var title: String {
            switch self {
            case .colorBars: return "BARS"
            case .dark: return "DARK"
            }
        }

        func stepped() -> PreviewBackground {
            let ladder = Self.allCases
            guard let index = ladder.firstIndex(of: self), index + 1 < ladder.count else {
                return ladder[0]
            }
            return ladder[index + 1]
        }
    }

    enum EditableField: String, Identifiable {
        case feedURL = "Feed URL"
        case name = "Name"

        var id: String { rawValue }
    }

    var body: some View {
        PictureEffectsStage(effects: outerEffects) {
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
            if !editing {
                panel = .root
                previewBackground = .colorBars
            }
        }
    }

    private var isEditing: Bool {
        if case .editing = screen { return true }
        return false
    }

    /// Suspended on the FX panel so the whole-screen dressing does not paint over the swatch the
    /// viewer is using to judge their own effects. The layout inset below stays keyed to the fixed
    /// `.setupChannel` bevel on purpose, so entering and leaving this panel only stops the overlays
    /// from drawing and never reflows the menu or moves focus.
    private var outerEffects: PictureEffects {
        panel == .effects ? .off : .setupChannel
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

        case .landing:
            // A single deliberate act, so landing on the settings slot mid-surf never captures the
            // remote on its own — the viewer has to ask for the menu before up/down stops tuning.
            Button(action: { send(.enterEditing) }) {
                LandingButtonLabel(title: "EDIT SETTINGS")
            }

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

                row(title: "BACK", value: "SET-UP", isValid: true) { send(.backRequested) }
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
                EffectsPreviewMonitor(effects: draft.pictureEffects, background: previewBackground)
                    .padding(.bottom, 14)

                row(title: "BACKDROP", value: previewBackground.title, isValid: true) {
                    previewBackground = previewBackground.stepped()
                }

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

    /// The landing screen's one control. Larger and centred rather than a `RowLabel`, since there is
    /// nothing beside it to align a value column against.
    private struct LandingButtonLabel: View {
        let title: String

        @Environment(\.isFocused) private var isFocused

        var body: some View {
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .foregroundStyle(isFocused ? Color.black.opacity(0.85) : .white)
                .padding(.vertical, 22)
                .padding(.horizontal, 56)
        }
    }

    /// A live swatch of the viewer's own `PictureEffects`, inside a screen that is otherwise rendering
    /// the fixed `.setupChannel` preset. The bars backdrop is `ColorBarsView` rather than `SnowView`,
    /// which starts a coupled audio hiss on appear — the same call `SetupBackdrop` makes, for the
    /// same reason.
    ///
    /// The clip is not cosmetic. Every overlay in `PictureEffectsStage` ignores the safe area, so
    /// without it an extreme vignette or bevel paints across the whole menu instead of the swatch.
    ///
    /// Rendered at the channel's own 1920x1080 and scaled down, not handed the swatch's own small
    /// frame directly: every overlay's math (bevel thickness, vignette/glow radii) is tuned in
    /// absolute points for a full screen, so a 360pt-wide stage would show a maxed-out bevel
    /// swallowing the whole swatch and a vignette reading far weaker than it will on the real channel.
    private struct EffectsPreviewMonitor: View {
        let effects: PictureEffects
        let background: PreviewBackground

        private static let channelSize = CGSize(width: 1920, height: 1080)
        private static let displayWidth: CGFloat = 360
        private static var scale: CGFloat { displayWidth / channelSize.width }

        @ViewBuilder
        private var content: some View {
            switch background {
            case .colorBars: ColorBarsView()
            case .dark: AppTheme.night.ignoresSafeArea()
            }
        }

        var body: some View {
            PictureEffectsStage(effects: effects) {
                content
            }
            .frame(width: Self.channelSize.width, height: Self.channelSize.height)
            .scaleEffect(Self.scale)
            .frame(width: Self.displayWidth, height: Self.channelSize.height * Self.scale)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(SetupPalette.dim, lineWidth: 1)
            )
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
