# ORT-301: Noise effect jitter is too aggressive

## Task
The "NOISE" CRT picture-FX knob (`signalNoise`) makes the whole video jump around drastically.
Separate the visual grain from the positional jitter it also drives, and tone the jitter down
significantly.

## State: done, ready for review

## Root cause
`PictureEffectsStage.jitterOffset` had two independent problems, both in
`Sources/UI/PictureEffectsStage.swift`:
- **Modulo bias.** `Int64(bitPattern: s) % 1001` is a *signed* remainder. For roughly half the
  random 64-bit seeds, `Int64(bitPattern: s)` is negative, and Swift's `%` returns a negative
  result for a negative dividend. So each axis actually landed in `[-1.5, 0.5]`, not the intended
  `[-0.5, 0.5]` — twice the intended spread, and biased about -0.5 on average instead of centered
  on zero. Confirmed by simulating 200k draws of the exact formula: measured range `[-1.5, 0.5]`,
  mean `-0.50`.
- **Same seed and cadence as the grain overlay.** The jitter offset and `SignalNoiseOverlay`'s
  grain were driven by the same per-frame seed from a `TimelineView` redrawing at 24fps, so the
  whole picture's position re-rolled 24 times a second at up to ±4pt per axis (further inflated by
  the bias above). That reads as constant high-frequency shaking, not a loose antenna.

Verified by replaying the exact production formula (before/after) over 5 simulated seconds at full
strength in a throwaway Swift script (`swift /tmp/jitter-repro/verify.swift`, not part of the
repo): before, mean magnitude 7.98pt with a constant ~(-3.9, -4.4)pt bias, changing almost every
frame (119/120 transitions); after, mean magnitude 0.72pt centered near (0.04, -0.01), changing
only 29/120 frames.

## What changed
`Sources/UI/PictureEffectsStage.swift` only:
- `jitterOffset` now derives `x`/`y` via unsigned bit-shifting (`(s >> 33) & 0xFFFF`), matching the
  RNG pattern already used by `SignalNoiseOverlay` elsewhere in the file, instead of the biased
  signed modulo.
- Jitter's pixel range dropped from `2.0 + 6.0 * amount.value` (max ±4pt/axis) to
  `0.5 + 1.5 * amount.value` (max ±1pt/axis).
- The jitter offset and the grain overlay now derive from **separate seeds**: `noiseSeed` still
  updates every frame (~24fps) for lively static; `jitterSeed` is quantized to a new
  `jitterUpdatesPerSecond = 6.0` constant, so the picture's position holds for ~166ms before
  re-rolling instead of every ~42ms. This is the literal "separate the visual noise from the
  jitter" ask — they're independently tunable now, not just visually distinct overlays sharing one
  clock.

No new `PictureEffectKind` or settings-UI change — the ask was to decouple and tone down an
existing knob's two internal behaviors, not to expose a second control. `SignalNoiseOverlay` (the
grain itself) is untouched.

## Key decisions
- Kept `signalNoise` a single user-facing knob. The request was about internal coupling and
  intensity, not about giving the user two dials.
- No new unit test for `jitterOffset` — it's a `private` view-internal function with no existing
  test precedent in this codebase (view-level pure functions here are verified by headless
  rendering/simulation instead, matching ORT-300's approach), so a throwaway numeric repro script
  was the appropriate verification tool rather than a permanent test.

## Verification
- `xcodegen generate` + `xcodebuild build` for the tvOS simulator: **build succeeded**.
- `xcodebuild test -only-testing:NostalgiaVisionTests`: **99 tests, 0 failures**, both before and
  after the fix.
- Numeric before/after repro of the exact seed/amplitude/cadence formula (see Root cause) showing
  the bias is gone and both magnitude and update frequency are down roughly 10x at full strength.

## Dependencies
- Blocked by ORT-300 (bevel) — done, unaffected by this change (bevel sits later in the `ZStack`
  and doesn't touch jitter or noise).
- Blocks ORT-302 ("White noise whenever snow plays") — that task's "snow" static is a *separate*
  implementation (`Sources/UI/SnowView.swift`, the no-signal channel screen), not this
  `signalNoise` picture effect, so this change makes no assumptions on ORT-302's behalf.

## Open items
- None for this task.
