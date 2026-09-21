# ORT-302: White noise whenever snow plays

## Task
Sync the white-noise audio with the snow visual (`SnowView`) instead of it being a separate,
unsynced thing. Add a settings knob for the noise's volume/mute, and a settings picker for what
shows during a channel transition: static snow (default), a black screen with a spinner, SMPTE
colour bars, or nothing.

## State: done, merged to local `main`, not pushed to GitHub

Blocker ORT-301 (Noise effect) was already done, but turned out to only add the *visual* grain
overlay on the live picture — there was no audio white noise anywhere in the codebase yet. This
task built it from scratch.

## What shipped

- **`TransitionEffect`** (`Sources/Domain/TransitionEffect.swift`) — new enum: `staticSnow`
  (default), `blackSpinner`, `colorBars`, `blank`. Governs `Reception.acquiring` only — a real
  `NoSignal` always shows static regardless of the setting, since that's a dropped stream, not a
  transition the viewer chose.
- **Noise volume** reuses the existing `EffectAmount` type (0...1 detent ladder, `.off` = mute) —
  no new type needed.
- **`NoiseAudioPlayer`** (`Sources/Playback/NoiseAudioPlayer.swift`) — synthesizes a looping
  white-noise buffer via `AVAudioEngine`/`AVAudioPlayerNode`, same seeded-LCG approach as the
  picture's own static. No bundled asset. All failure paths are silent (no audio hardware in the
  test runner/simulator must not crash the app).
- **`SnowView`** now owns the audio track directly: `onAppear` starts it, `onDisappear` stops it.
  This is deliberate — `SnowView` is only ever mounted/unmounted by its caller, so those lifecycle
  hooks already mean exactly "snow is on screen," with nothing to drift out of sync.
- **`ChannelScreen`** renders one of the four transition looks (`BlackSpinnerView`/`ColorBarsView`
  added in `Sources/UI/TransitionViews.swift`) based on a new `effectiveTransition` computed
  property.
- **Settings UI**: one new top-level "TRANSITION" field opens a nested sub-row (same pattern as
  "PICTURE FX") with "NOISE VOL" and "TRANSITION" fields.
- Persistence/gate: both settings follow the existing `tuneDelay`/`pictureEffects` convention —
  stepped and persisted immediately, never part of the committable draft, defaulting to the
  already-existing behavior (audible snow) so upgrading changes nothing.

## Verification

- Found and fixed one real bug during review: `NoiseAudioPlayer.makeNoiseBuffer` didn't actually
  guard against a zero-frame request despite its own test's doc comment claiming it did —
  `AVAudioPCMBuffer(pcmFormat:frameCapacity: 0)` traps. Added the missing `frames > 0` guard.
- Full suite green: `xcodebuild test` on the Apple TV 4K simulator — **121 tests, 0 failures**
  (after the fix; 1 failure before it, exactly the bug above).
- **Second bug, caught only by building in the user's actual checkout** (`/Users/justin.loveless
  /Code/NostalgiaVision`), not the throwaway worktree: `xcodegen` bakes an explicit file list into
  the checked-in, gitignored `.xcodeproj`. Merging in the 5 new Swift files (via `git merge --ff-
  only`, which doesn't touch `project.yml`) left that checkout's `.xcodeproj` with zero references
  to any of them, so Xcode couldn't resolve `TransitionEffect`, `NoiseAudioPlayer`, etc. — a real
  build failure, reported by the user. The existing `post-merge`/`post-checkout` git hooks only
  regenerated the project when `project.yml` itself changed, which this merge didn't do, so they
  silently didn't fire.
  - Fixed the immediate problem: ran `xcodegen generate` in that checkout. Confirmed with a clean
    `xcodebuild build` (**BUILD SUCCEEDED**) and `xcodebuild test` (**121 tests, 0 failures**).
  - Fixed the recurring cause: broadened `.githooks/regenerate-if-project-changed.sh` (renamed
    from `regenerate-if-project-yml-changed.sh`) to also regenerate on any added/removed file
    under `Sources`/`Tests`/`UITemp`, not just a `project.yml` edit. Verified against the exact
    commit range that broke the build (correctly triggers) and a same-commit no-op range
    (correctly stays quiet). Committed directly to `main` at the user's checkout (`8e47ecc`) since
    it was blocking them right now.

## Commits (on `main`, local only)

1. Domain layer: `TransitionEffect`, `EffectAmount` reuse, `SettingsGate`/`SettingsStore` wiring.
2. `NoiseAudioPlayer` + `SnowView`'s onAppear/onDisappear audio lifecycle.
3. `ChannelScreen`/`TransitionViews`/`SettingsScreenView`/`TVSet`/`TVShellView` wiring.
4. Tests for all of the above.
5. `8e47ecc` — broadened the xcodegen-regenerate git hook to cover added/removed source files.

## Open items / assumptions

- **Not pushed to `origin/main`.** Local `main` (at `/Users/justin.loveless/Code/NostalgiaVision`,
  the user's own checkout) is now 8 commits ahead of `origin/main` — the 7 pre-existing
  ORT-299/300/301 commits that were apparently never pushed, plus this work. Push was not
  requested; ask before doing it, since it's a bigger, more visible action than what was asked
  for, and it would carry forward commits from other tasks this session has no context on.
- `AVAudioSession` category is set to `.playback` + `.mixWithOthers` best-effort, to avoid fighting
  whatever KSPlayer configures for the video stream's own audio. Not verified on a real device —
  only the pure buffer-generation logic is unit-tested; actual engine start/stop needs real audio
  hardware and wasn't exercised by the test target.
- No interactive UI verification (no way to drive the tvOS simulator's UI in this environment).
  Recommend running it locally in Xcode to confirm the transition picker and audio actually behave
  as expected on-screen.
