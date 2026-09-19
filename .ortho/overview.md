# ORT-300: Bevel — an old-TV cabinet frame around the picture

## Task
Add a seventh CRT picture-FX knob, "bevel": an opaque old-TV cabinet painted over the outer band
of the screen, with a transparent cutout in the middle so the actual picture reads as something
being watched *through* an old television rather than a rectangle with filters on it.

## State: done, ready for review

## What changed
- `Sources/Domain/PictureEffects.swift` — new `PictureEffectKind.bevel` case (title `"BEVEL"`), new
  `PictureEffects.bevel` field, wired into `.off` and the by-kind subscript. Steps OFF → 25% → 50%
  → 75% → 100% exactly like the other six knobs; the settings screen's `ForEach(allCases)` row
  picked it up with no UI changes needed.
- `Sources/Storage/SettingsStore.swift` — new `nostalgiavision.fx.bevel` UserDefaults key, read and
  written the same way as the other five FX keys.
- `Sources/UI/PictureEffectsStage.swift` — new `BevelOverlay`, rendered topmost (after
  `CurvatureMaskOverlay`) since the cabinet is the outermost physical object. It fills the full
  canvas minus a cushion-shaped cutout (`eoFill`) with a wood-cabinet gradient, darkens the cutout's
  inner lip, and fades in a speaker grille + two control knobs (sized off the frame's own apron, not
  absolute points) as the knob strength increases. `CurvatureMaskOverlay`'s cushion-path math was
  extracted into a shared `cushionPath(in:corner:bow:)` function (pure refactor, verified
  byte-identical renders before/after) so the bevel's cutout can reuse curvature's exact tube shape
  — passing `effects.curvature.amount` as `curvatureAmount` — so a bevel+curvature combo never shows
  a straight cabinet edge crossing a bowed tube edge.
- Tests updated for the new 7th kind (`PictureEffectsTests.swift`,
  `SettingsStorePictureEffectsTests.swift`), plus one dedicated round-trip test each for the domain
  stepping and the storage persistence.
- Fixed, in the same file we already had to touch: `SettingsStorePictureEffectsTests.swift` called
  the non-existent `UserDefaults.suiteName` instance property, which meant the whole test target
  failed to build (this was flagged, pre-existing, and left alone in ORT-299). Hoisted the suite
  name into a local `let` instead. This is the one-line reason `NostalgiaVisionTests` now actually
  runs.

## Key decisions
- **No image assets.** The project has no `.xcassets` and every existing FX overlay (vignette,
  scanlines, curvature, chroma, glow, noise) is pure SwiftUI `Canvas`/shape drawing. The bevel is
  the same: a procedural cabinet, not a bitmap. This keeps the effect resolution-independent and
  avoids introducing an asset pipeline for one decorative overlay.
- **Cabinet opening is drawn from curvature's own geometry**, not a plain rounded rect, so the two
  knobs compose cleanly together at any combination of strengths.
- **Bevel and curvature can hide each other's edge treatment at full strength on both** — at 100%
  bevel the cabinet's opening sits inside curvature's own rim-shadow band, so you see only the
  inner part of curvature's blurred rim. Treated this as correct (a real cabinet's opening is
  narrower than the tube), not a bug.

## Verification
- `xcodegen generate` + `xcodebuild build` for the tvOS simulator: **build succeeded** (confirmed
  independently, not just via the implementing subagent's report).
- `xcodebuild test -only-testing:NostalgiaVisionTests`: **99 tests, 0 failures** (confirmed
  independently) — first real run of this target; it failed to compile before the `suiteName` fix.
- Visual check: rendered the actual production `BevelOverlay`/`PictureEffectsStage` headlessly via
  `ImageRenderer` on macOS (scratch harness in `/tmp/bevel-preview`, not part of the repo) against a
  color-bars test pattern, at bevel 25%/100% alone and bevel 100% combined with curvature 50%/100%.
  Inspected the PNGs directly: a real wood-cabinet frame with a genuinely transparent cutout showing
  the picture, a speaker grille and two knobs that scale with strength, and a cutout that bows in
  lockstep with the curvature tube when both are on.

## Open items
- None for this task. ORT-301 (Noise effect) is unaffected — `signalNoise` already existed as a
  knob and sits earlier in the `ZStack`, untouched by this change.
