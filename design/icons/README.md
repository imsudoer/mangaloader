# Manga Loader — icon concepts

Eight flat-vector concepts for the launcher icon and the notification glyph.
Plate `#1E1E1E`, mark `#D2D7DF`, single accent `#8A897C`. No gradients, filters,
masks or text — every mark is rects and paths so the renderer reproduces it
exactly.

Colour compositions keep the mark inside the Android adaptive safe zone (66 %
circle, 169 px radius at 512). Mono marks are 24 × 24 viewBox, white on
transparent.

| # | Concept | Idea | At 24 px |
|---|---------|------|----------|
| 01 | Split Page | A page cut by a wide diagonal seam; the lifted half is sage. | A light square split by a dark diagonal band, the top wedge dimmed. |
| 02 | Panel Grid | Four manga panels in a 2 × 2 grid, the last one in sage. | Four light blocks in a 2 × 2 arrangement. |
| 03 | Bookmark | A bookmark with an off-centre bottom notch, so the short prong reads as a speech-bubble tail. | A narrow light ribbon with a dark notch at the foot. |
| 04 | Shelf | Three books on a shelf, the right one leaning. | Three short bars standing on a thin base line. |
| 05 | Corner Fold | A page with its top-right corner turned down; the turned flap is sage. | A page with a diagonal cut at the top right. |
| 06 | Progress Page | A page whose last strip is detached as a reading-progress bar. | A light block above a short sage bar. |
| 07 | Open Spread | Two hard-edged pages meeting at a plate-coloured fold, no page curves. | Two angled blocks meeting at a dark centre line. |
| 08 | Panel Inset | An L-shaped panel with a smaller sage panel set into its cut corner. | An L with a small square in the notch. |

## Recommended: 02 Panel Grid

It is the only concept that says manga rather than reading in general, and it is
the one that survives every reduction without losing information:

- At 24 px the four blocks stay four blocks; the gutters are real gaps, not
  hairlines that disappear.
- The silhouette is compact and symmetric, so a circular or squircle mask never
  clips a meaningful part of it.
- The single sage panel is the only accent, which gives the mark a focal point
  without a second colour.
- The mono version is the same four blocks with wider gutters, so the
  notification glyph and the launcher icon are visibly the same mark.

Runner-up: 01 Split Page, if the launcher should look less literal and more like
a reading surface than a panel layout.

## Files

```
design/icons/
  01-split-page.svg          512 colour, plate + mark
  01-split-page-mono.svg     24 mono, white on transparent
  ...
  render.py                  svglib + reportlab rasteriser
  preview.html               review page for all concepts
  png/                       rendered output
```

PNG names are `<concept>-<size>.png` for colour (512, 192, 96, 48) and
`<concept>-mono-<size>.png` for mono (96, 48, 24), for example
`02-panel-grid-512.png` and `02-panel-grid-mono-24.png`.

## Render

```
python design/icons/render.py
```

Requires `svglib`, `reportlab` and, for reportlab 5, the `rlPyCairo` backend
(`python -m pip install rlPyCairo`). The script rejects any SVG element that is
not `rect`, `circle` or `path`, checks that every PNG has the requested pixel
size, and checks that mono PNGs kept an alpha channel.