# Design

## System

Spillway uses a brand register for a static marketing/documentation website. The visual system should feel like a precise hydraulic control diagram: calm, engineered, directional, and typed.

## Color

Use OKLCH tokens only. The palette is a restrained-to-committed cobalt system anchored by `oklch(0.541 0.122 248.2)`, with literal white as the primary page background so color belongs to the brand surfaces and controls rather than a tinted neutral wash.

```css
:root {
  --color-bg: oklch(1 0 0);
  --color-surface: oklch(0.965 0.006 248);
  --color-ink: oklch(0.18 0.025 250);
  --color-muted: oklch(0.42 0.028 250);
  --color-primary: oklch(0.54 0.122 248);
  --color-primary-deep: oklch(0.31 0.105 252);
  --color-accent: oklch(0.66 0.145 188);
  --color-accent-soft: oklch(0.91 0.04 188);
  --color-line: oklch(0.86 0.012 248);
}
```

Body text uses `--color-ink` on `--color-bg` for high contrast. Muted text uses `--color-muted` only at normal size where contrast remains readable; on colored fills, use white or near-white text.

## Typography

Use system fonts to avoid adding runtime dependencies. The default stack is a humanist UI sans for body copy and headings; code uses the platform monospace stack only for real code and protocol labels, never as a decorative shorthand.

Headings use balanced wrapping, tight but safe letter spacing no tighter than `-0.03em`, and a display ceiling below `6rem`. Body copy is capped around 65-75 characters.

## Layout

The homepage uses asymmetric panels, hydraulic channels, and structured rows rather than repeated identical feature cards. Sections should vary rhythm: a decisive hero, a compact protocol flow, a split code/API area, then a calm adoption band.

Responsive behavior favors fluid CSS primitives: `clamp()` spacing, flexible wraps, and grids with `repeat(auto-fit, minmax(...))` only where a true two-dimensional layout is needed.

## Components

- **Masthead:** simple wordmark plus compact navigation.
- **Icon:** circular spillway mark with three controlled wave gates; use as favicon and brand mark.
- **Hero panel:** large claim, constrained prose, CTA row, and a protocol diagram.
- **Flow steps:** ordered only when the order explains real protocol movement.
- **Code well:** dark technical surface for real Gleam API names, with readable contrast and no fake terminal chrome.
- **Link buttons:** filled primary and quiet text-link styles; no decorative border-plus-shadow ghost cards.

## Motion

Motion is subtle and purposeful: page elements may settle in with small transform/opacity changes, and flow lines may shift slowly to imply movement. All motion must have a `prefers-reduced-motion: reduce` fallback that removes animation and transition.
