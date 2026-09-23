# Nostalgia Vision Logo

Brand mark for **Nostalgia Vision**, the Analog IPTV Apple TV app that recreates an old television viewing experience.

## Concepts explored

Five initial directions were developed against a warm, limited palette:

| # | Concept | Summary |
|---|---------|---------|
| 1 | **Retro broadcast mark** | Stylized CRT frame with soft amber scan lines and rabbit-ear antenna |
| 2 | **Memory lens** | Concentric faded color rings suggesting recollection and vision |
| 3 | **Neon nostalgia** | Bold 1980s lettering with restrained cyan–magenta neon glow |
| 4 | **Film archive** | Minimal film-frame icon with classic editorial serif typography |
| 5 | **Dreamy monogram** | Softened overlapping “NV” letterforms in dusty rose and amber |

Concept PNGs live in [`concepts/`](concepts/).

## Selected direction

**Concept 1 — Retro broadcast mark** was selected.

Confirmed against the stakeholder reference in [`reference/user-direction.jpg`](reference/user-direction.jpg).

Reasons:

- Matches the product’s CRT / analog broadcast identity more directly than lens, neon, film, or monogram directions
- Echoes in-app picture effects (scan lines) without copying UI chrome
- Reads clearly at app-icon sizes and as a wordmark lockup
- Warm charcoal / cream / amber palette stays nostalgic without neon or generic purple tropes

## Refinement

Focused on composition, typography, color, scalability, and render quality:

- **Composition** — Full CRT silhouette: rabbit-ear antenna, cream screen with soft amber scan lines, bottom recessed indicator (three amber dots + chevron), and two amber knobs at the **bottom-right** of the front panel (like a real TV) — not on the side bezel
- **Typography** — Rounded geometric sans wordmark in title case; charcoal on light, cream on dark
- **Color** — Locked palette (see below), plus an orange/charcoal **swapped** variant
- **Quality** — Primary PNGs are polished illustration renders (soft scan-line glow, anti-aliased edges). SVGs use feathered scan-line gradients for scalable use
- **Scalability** — Size proofs at 64 / 128 / 512

## Color palette

| Token | Hex | Use |
|-------|-----|-----|
| Charcoal | `#1C1F26` | TV body, light-mode wordmark (swapped: accents) |
| Cream | `#F5F0E6` | Screen fill, dark-mode wordmark |
| Amber | `#C4783A` | Scan lines, antenna, knobs, panel accents (swapped: TV body) |
| Recess | `#14161C` | Bottom control panel well |
| Paper | `#FAF7F2` | Light background |
| Night | `#0E1014` | Dark background |

Each logo variant ships with labeled color swatches (name + hex + usage) so the palette can drive the overall app theme.

### Theme packs

| Theme | Board | Machine-readable |
|-------|-------|------------------|
| Standard | [`final/theme-standard.png`](final/theme-standard.png) | [`theme.json`](theme.json) → `themes.standard` |
| Swapped (amber ↔ charcoal) | [`final/theme-swapped.png`](final/theme-swapped.png) | `themes.swapped` |
| Dark | [`final/theme-dark.png`](final/theme-dark.png) | `themes.dark` |

CSS variables: [`theme.css`](theme.css) (`.nv-theme-standard`, `.nv-theme-swapped`, `.nv-theme-dark`).

### Swapped variant

Orange ↔ charcoal: amber TV body with charcoal antenna, scan lines, knobs, and panel accents. Cream screen/background unchanged. See `mark-only-swapped.png`, `mark-swapped.svg`, and `lockup-swapped-light.png`.

## Final files

| File | Use |
|------|-----|
| [`final/mark.svg`](final/mark.svg) | Primary scalable mark |
| [`final/mark-swapped.svg`](final/mark-swapped.svg) | Scalable orange/charcoal-swapped mark |
| [`final/lockup.svg`](final/lockup.svg) | Mark + wordmark lockup |
| [`final/lockup-light.png`](final/lockup-light.png) | Light-background HQ raster lockup |
| [`final/lockup-dark.png`](final/lockup-dark.png) | Dark-background HQ raster lockup |
| [`final/lockup-swapped-light.png`](final/lockup-swapped-light.png) | Light HQ lockup with orange/charcoal swap |
| [`final/mark-only.png`](final/mark-only.png) | HQ raster mark (preferred preview) |
| [`final/mark-only-swapped.png`](final/mark-only-swapped.png) | HQ raster mark, orange/charcoal swap |
| [`final/mark-with-swatches.png`](final/mark-with-swatches.png) | Mark + standard theme swatches |
| [`final/mark-swapped-with-swatches.png`](final/mark-swapped-with-swatches.png) | Swapped mark + swatches |
| [`final/lockup-light-with-swatches.png`](final/lockup-light-with-swatches.png) | Light lockup + standard swatches |
| [`final/lockup-dark-with-swatches.png`](final/lockup-dark-with-swatches.png) | Dark lockup + dark swatches |
| [`final/lockup-swapped-with-swatches.png`](final/lockup-swapped-with-swatches.png) | Swapped lockup + swatches |
| [`final/swatches-standard.png`](final/swatches-standard.png) / [`swapped`](final/swatches-swapped.png) / [`dark`](final/swatches-dark.png) | Standalone swatch strips |
| [`final/theme-standard.png`](final/theme-standard.png) / [`swapped`](final/theme-swapped.png) / [`dark`](final/theme-dark.png) | Full theme boards |
| [`theme.json`](theme.json) | Theme tokens for app theming |
| [`theme.css`](theme.css) | CSS custom properties for each theme |
| [`final/mark-64.png`](final/mark-64.png) / [`128`](final/mark-128.png) / [`512`](final/mark-512.png) | Size proofs |
| [`final/scalability-sheet.png`](final/scalability-sheet.png) | Side-by-side size comparison |
| [`reference/user-direction.jpg`](reference/user-direction.jpg) | Stakeholder reference used for refinement |

## Usage notes

- Prefer HQ PNG lockups/mark for marketing previews; use SVG for app icons and crisp scaling
- Reuse hex tokens from the swatch sheets / `theme.json` / `theme.css` for UI chrome so the product matches the logo
- Keep amber accents on antenna, scan lines, knobs, and the bottom panel only (or the inverse in the swapped variant)
- Do not add neon glow, extra badges, or side-mounted knobs
- Wordmark may sit below the mark (centered) or to the right for horizontal layouts
