# ORT-299: Curved-glass screen curvature effect

## Task
The CRT "CURVE" picture effect (`Sources/UI/PictureEffectsStage.swift`) looked like a rounded-corner
crop, not curved glass. Make the edges actually read as a curved screen.

## State: done, ready for review

## What changed
`CurvatureMaskOverlay` in `Sources/UI/PictureEffectsStage.swift` now clips to a pillow/cushion-shaped
path instead of a rounded rect: each edge is a quadratic Bezier that bows inward at its midpoint (not
just the corners), which is the classic silhouette of an old curved CRT tube. Two supporting touches
sell the glass: a blurred dark rim right at the boundary (the glass reads thickest there, same as light
grazing a curved surface) and a soft specular band across the upper rim (light catching glass). All three
scale with the existing `curvature` amount knob, so `OFF`/`25%`/`50%`/`75%`/`100%` still behaves the
same as before, just with a convincing shape at each step.

## Key decision: why the picture itself isn't warped
`PlayerSurface.swift` hosts the real KSPlayer/AVPlayer view as a single `UIViewRepresentable`, reused
across channel changes (documented invariant: "one player, reused, no black flash"). True per-pixel
barrel/pincushion warp of the live video needs either a GPU texture capture (already ruled out — the
top-of-file comment on `PictureEffectsStage.swift` notes KSPlayer's UIKit surface doesn't flatten into
a `drawingGroup`, so shaders silently no-op) or a mesh of several transformed copies of the player view,
which would require hosting the player in more than one place at once, breaking that invariant. So the
curvature illusion is entirely in the overlay's shape and shading, not in warping the decoded frame.
This is a deliberate, bounded choice — not a stopgap.

## Verification
- Rendered the actual production `CurvatureMaskOverlay`/`PictureEffectsStage` code headlessly via
  `ImageRenderer` on macOS (scratch harness in `/tmp/crt-preview`, not part of the repo) against a
  color-bars test pattern, at 25/50/100% and combined with all other effects at 75%, and inspected the
  PNGs directly. Iterated the bow/corner magnitudes once after the first pass looked like a dogbone
  rather than a screen.
- `xcodegen generate` + `xcodebuild build` for the real tvOS 27 simulator target: **build succeeded**.
- Ran the `NostalgiaVisionTests` target: it fails to build for reasons unrelated to this change —
  `Tests/DomainTests/SettingsStorePictureEffectsTests.swift:9` calls `UserDefaults.suiteName` (not a
  real instance member). Confirmed via `git stash` that this was already broken before this change.
  Left untouched — out of scope for this task, flagged separately.

## Open items
- None for this task. The pre-existing broken test file above is worth its own fix but wasn't touched
  here to keep this change scoped to the curvature visual.
