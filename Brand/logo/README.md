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

Reasons:

- Matches the product’s CRT / analog broadcast identity more directly than lens, neon, film, or monogram directions
- Echoes in-app picture effects (scan lines) without copying UI chrome
- Reads clearly at app-icon sizes and as a wordmark lockup
- Warm charcoal / cream / amber palette stays nostalgic without neon or generic purple tropes

## Refinement (second pass)

Focused on composition, typography, color, and scalability:

- **Composition** — Removed bottom control-panel clutter; kept antenna + two knobs as the only hardware accents so the screen and scan lines stay primary
- **Typography** — Rounded geometric sans wordmark in title case; charcoal on light, cream on dark
- **Color** — Locked palette (see below)
- **Scalability** — Delivered SVG mark + lockup, plus PNG lockups (light/dark) and mark-only

## Color palette

| Token | Hex | Use |
|-------|-----|-----|
| Charcoal | `#1C1F26` | TV body, light-mode wordmark |
| Cream | `#F5F0E6` | Screen fill, dark-mode wordmark |
| Amber | `#C4783A` | Scan lines, antenna, knobs |
| Paper | `#FAF7F2` | Light background |
| Night | `#0E1014` | Dark background |

## Final files

| File | Use |
|------|-----|
| [`final/mark.svg`](final/mark.svg) | Primary scalable mark (preferred source) |
| [`final/lockup.svg`](final/lockup.svg) | Mark + wordmark lockup |
| [`final/lockup-light.png`](final/lockup-light.png) | Light-background raster lockup |
| [`final/lockup-dark.png`](final/lockup-dark.png) | Dark-background raster lockup |
| [`final/mark-only.png`](final/mark-only.png) | Raster mark for previews / placeholders |
| [`final/mark-64.png`](final/mark-64.png) / [`128`](final/mark-128.png) / [`512`](final/mark-512.png) | Size proofs from the SVG geometry |
| [`final/scalability-sheet.png`](final/scalability-sheet.png) | Side-by-side size comparison |

## Usage notes

- Prefer the SVG mark for app icons, docs, and marketing; export PNG/PDF as needed
- Keep amber accents sparse — scan lines + antenna + knobs only
- Do not add neon glow, drop shadows, or extra badges on the mark
- Wordmark may sit below the mark (centered) or to the right for horizontal layouts
