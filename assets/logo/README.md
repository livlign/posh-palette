# Posh Palette logo

A shell prompt fused with a palette: a `>` chevron followed by an underscore that
is the palette, a thin pill stepping through five shades. Pure monochrome. The ink
is always `currentColor` and the shades are opacity steps, so one file works on any
background (black on light, white on dark).

## Files

| File | Use |
|------|-----|
| `mark.svg` | The icon. Inherits `currentColor`, so embed it where a color is set (site, HTML, the app). |
| `mark-readme.svg` | Same mark, self-switching (`#18191b` light / `#ffffff` dark) for when it is opened directly with no color context. |
| `mark-light.svg` | Fixed dark ink. The light-theme half of the GitHub `<picture>` pair. |
| `mark-dark.svg` | Fixed white ink. The dark-theme half of the GitHub `<picture>` pair. |
| `wordmark.svg` | Horizontal lockup: mark + `posh palette` in monospace. `currentColor`. |
| `favicon.svg` | Simplified 3-step mark for 16px. Self-switching. The primary favicon. |
| `favicon-32.png`, `favicon-16.png` | Rasterized dark-ink fallbacks for browsers without SVG favicons. |

## Theme-aware embedding (GitHub README)

GitHub serves SVGs through `<img>`, where `currentColor` falls back to black and an
internal `@media` query does not switch. Use the fixed-color pair in a `<picture>`:

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo/mark-dark.svg">
  <img alt="Posh Palette" src="assets/logo/mark-light.svg" width="96">
</picture>
```

Anywhere the text color is inherited (a styled web page, the docs site), use the
single `mark.svg` or `wordmark.svg` and let `currentColor` do the work. For a tab
icon, point to `favicon.svg` and keep the PNGs as fallbacks:

```html
<link rel="icon" href="assets/logo/favicon.svg" type="image/svg+xml">
<link rel="icon" href="assets/logo/favicon-32.png" sizes="32x32">
```
