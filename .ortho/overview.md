# ORT-301: Noise effect jitter and grain size

## Task
Two rounds on the "NOISE" CRT picture-FX knob (`signalNoise`):
1. It made the whole video jump around drastically — separate the visual grain from the
   positional jitter it also drives, and tone the jitter down significantly.
2. Follow-up: shrink the visual grain/static "pixels" themselves, down to (but not below) the size
   of a 420-line broadcast picture's pixels — for both the `signalNoise` grain and the separate
   no-signal "snow" static screen.

## State: done, ready for review

## Round 1 — jitter root cause and fix
`PictureEffectsStage.jitterOffset` (`Sources/UI/PictureEffectsStage.swift`) had two compounding
bugs:
- **Modulo bias.** `Int64(bitPattern: s) % 1001` is a signed remainder. For roughly half of all
  random 64-bit seeds the dividend is negative, and Swift's `%` returns a negative result for a
  negative dividend, so each axis actually landed in `[-1.5, 0.5]` (mean ≈ -0.5), not the intended
  `[-0.5, 0.5]`. The picture wasn't randomly wobbling, it was being constantly pulled toward one
  corner. Confirmed by simulating 200k draws of the exact formula: measured range `[-1.5, 0.5]`,
  mean `-0.50`.
- **Same seed and cadence as the grain overlay.** Both re-rolled on the same 24fps `TimelineView`
  clock, at up to ±4pt/axis.

Fix: unsigned bit-shift extraction (`(s >> 33) & 0xFFFF`) instead of the biased signed modulo;
jitter now derives from its own seed, quantized to a new `jitterUpdatesPerSecond = 6.0` constant
(holds position ~166ms instead of ~42ms); amplitude cut from `2.0 + 6.0 * amount.value` (max
±4pt/axis) to `0.5 + 1.5 * amount.value` (max ±1pt/axis). `signalNoise` stays one knob — this
decouples two *internal* behaviors, it doesn't add a second user-facing control.

Verified by replaying the exact production formula, before/after, over 5 simulated seconds at full
strength (`swift /tmp/jitter-repro/verify.swift`, throwaway, not in the repo): mean offset
magnitude 7.98pt (biased ~(-3.9,-4.4)) → 0.72pt (centered ~(0.04,-0.01)); position changed on
119/120 sampled frames → 29/120.

## Round 2 — grain/static pixel size
Both `SignalNoiseOverlay` (`PictureEffectsStage.swift`) and `SnowView` (`SnowView.swift`, the
separate no-signal channel screen) drew a coarse grid (64×36 and 96×54 respectively) as one Core
Graphics `fill` per cell. Bumping the grid to 420 lines to get pixel-sized speckle would mean
~747×420 ≈ 313k cells/frame — at that count, per-cell `canvas.fill` calls would blow the frame
budget (SnowView redraws every cell every frame with no sparsity, at 12fps).

Added `Sources/UI/AnalogNoiseTexture.swift`: a shared `analogNoiseLines = 420` constant, an
`analogNoiseColumns(aspect:)` helper (keeps cells square for any canvas aspect ratio), and
`imageFromPremultipliedRGBA` (turns a raw byte buffer into one `CGImage`). Both views now write
random bytes directly into a pixel buffer (no Core Graphics call per cell), build one `CGImage`,
and blit it once with `.interpolation(.none)` so the upscale stays hard-edged instead of blurring
cells together. `signalNoise`'s sparse-lighting behavior (only ~1/8 of cells lit, so the picture
stays readable) and `SnowView`'s brightness-scaled-by-`volume` behavior are unchanged — same
formulas, just density-correct at the new resolution.

One real bug surfaced mid-implementation: nesting the new Canvas closure directly inside
`TimelineView`'s trailing closure made the Swift type-checker fail with "generic parameter
'Content' could not be inferred" — a known compiler limitation with heavily-bodied closures nested
inside another `ViewBuilder` closure. Fixed by extracting `SnowView`'s Canvas into a private
`frame(at:) -> some View` method (mirroring `PictureEffectsStage.stage(...)`, which already used
this pattern for the same reason), so the type-checker checks each closure independently.

## Verification
- `xcodebuild build` for the tvOS simulator: **build succeeded**, both rounds.
- `xcodebuild test -only-testing:NostalgiaVisionTests`: **99 tests, 0 failures**, after every
  change.
- Performance: benchmarked the exact new pixel-buffer builder standalone (`-O`, same seed/loop
  logic, 240 simulated frames at 747×420) — 0.317ms/frame average, ~0.8% of a 24fps frame budget on
  this Mac. Apple TV hardware is slower per-core, but this replaced an approach (300k+ Core
  Graphics fill calls/frame) that would have been categorically worse, not just slower.
- Visual: rendered the actual production byte-buffer-to-`CGImage` pipeline headlessly (raw
  CoreGraphics, not SwiftUI) at both the old 64×36 grid and the new 420-line grid, composited onto
  a full 1920×1080 backdrop, and inspected the PNGs directly — old grid shows clearly discrete
  ~30px blocks, new grid shows fine ~2.5px speckle with no visible blur from the upscale.

## Round 3 — unrelated build failure in Xcode GUI
User reported the build failing in Xcode with 7 issues, the first being "Missing package product
'KSPlayer'" and the other six being `Cannot find 'analogNoiseLines'/'analogNoiseColumns'/
'imageFromPremultipliedRGBA' in scope` in `PictureEffectsStage`/`SnowView`. Not a code bug: those
six are the cascading symptom of the first — when a package dependency fails to resolve, Xcode
can't build the module and reports every cross-file symbol as unresolved, including ones that are
fine. Reproduced independently: two full clean builds from a wiped `DerivedData` via command-line
`xcodebuild` both succeeded with zero errors, so the Swift sources were never broken.

Root cause: `project.yml` pinned `KSPlayer` to `branch: main`, a floating reference that
re-resolves over the network on every Xcode open/build. User tried Reset Package Caches + Resolve
Package Versions in Xcode and the GUI build still failed — a network/resolution hiccup specific to
that floating pin, not to the code.

Fix: pinned `KSPlayer` to the exact `revision` that `main` already resolved to
(`75e590e770f7f01d088ced2546deed9817b660ae`, confirmed still `main`'s current tip via
`git ls-remote` at pin time, and the exact commit this codebase had already built against). A
revision pin is immutable and needs no re-resolution against a moving target, which removes the
failure mode entirely, and picking the commit already proven to compile means zero API-drift risk
— unlike jumping to the latest tagged release (`2.3.4`), which could be arbitrarily far from `main`
and require unrelated source changes.

Verified: wiped `DerivedData` and the generated `.xcodeproj` again, ran `xcodegen generate`, then a
clean `xcodebuild build` — package resolution logged `Fetching ... (cached)` / `Resolved source
packages` with no errors, build succeeded, and the checked-in-by-Xcode `Package.resolved` now shows
a fixed `revision` with no `branch` key. Full `NostalgiaVisionTests` run: 99/99 still passing.

## Key decisions
- Kept `signalNoise` a single user-facing knob throughout — both asks were about internal
  coupling/intensity/resolution, not about exposing new controls.
- `analogNoiseLines` is a shared top-level constant (not per-view) because the same "chunkiness of
  a 420-line picture" is the right authenticity target for anything drawn as analog static in this
  app, and the ask named both `signalNoise` and, implicitly, the "snow" static as a matched pair.
- Pinned KSPlayer to a `revision`, not a `version`/`exactVersion` tag — the goal was removing the
  floating-reference fragility with zero behavior change, not adopting a different upstream release
  (that's a separate decision the user didn't ask for here).

## Dependencies
- Blocked by ORT-300 (bevel) — done, unaffected by either round of this change.
- Blocks ORT-302 (white noise volume when snow plays) — `SnowView.swift` is a separate
  implementation from the `signalNoise` picture effect; ORT-302 can proceed independently of
  everything done here.

## Open items
- None for this task.
