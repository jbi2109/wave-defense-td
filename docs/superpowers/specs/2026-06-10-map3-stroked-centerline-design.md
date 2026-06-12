# Map3 — stroked-centerline vector authoring (smooth edges/corners)

**Date:** 2026-06-10
**Status:** Approved design → implementation plan next

## Problem

map3's walkable mask is **traced from a hand-drawn raster** reference
(`tools/map_3_reference.png`) and then raster-smoothed (EDT widen, morphological
close, box-blur). Raster→raster smoothing fights a staircase: it cannot recover
dead-straight walls or clean arcs, so corridor edges and corners still look
jagged/wobbly. map1/map2 look smooth because they rasterize a **vector polygon
once** — there is no staircase source to fight.

## Goal

Author map3's geometry as **vectors** (like map1/map2) and rasterize once, so
corridor walls are perfectly straight and corners are clean arcs. User decisions:

- **Authoring method:** stroked centerlines (not literal outline polygons).
- **Visual rendering:** keep the existing `terrain_mask.gdshader` (mask-driven);
  do NOT convert to Polygon2D grass fills.

Everything downstream of the mask is unchanged.

## Approach — stroked centerlines

Rasterize a vector network once. A mask pixel is **walkable** iff:

```
( dist(pixel, ANY centerline segment) <= corridor_half_width
  OR  inside ANY chamber profile )
AND NOT inside ANY island
```

`dist`-to-segment thresholding yields **straight walls** along each segment and
**round arcs** at every end-cap and join (consecutive capsules overlap at shared
vertices). This is the smoothness, by construction — no blur/morph needed.

### Geometry data (constants at top of `tools/gen_map_3_mask.py`)

- `CORRIDOR_HALF_WIDTH ≈ 65.0` wu → ~130 wu corridors (the ~2× width).
- `CENTERLINES` — list of polylines (each a list of `(x, y)` world coords) tracing
  where enemies walk. Network, anchored to the existing layout:
  1. **Entry corridor:** left edge `(0, 898)` → small circle, on `y≈898`.
  2. **Small-circle ring** (centre ~`(728, 893)`): the corridor passes through;
     the disc chamber (below) provides its body. Centerline continues through.
  3. **Big-chamber rings** (centre ~`(1440, 873)`): upper-arc and lower-arc
     centerlines around the island so there are **two parallel routes**, rejoining
     on the right side of the chamber.
  4. **Comb square-wave** (~`x ∈ [1900, 3400]`): a spine on `y≈898` with vertical
     **up-fingers and down-fingers** (the parallel-route-rich zone). Centerlines
     trace the spine + each finger.
  5. **Exit corridor:** comb tail → right edge `(3840, 898)`, on `y≈898`.
- `CHAMBERS` — two circles, kept **irregular-but-smooth** via radial profile
  `r(θ) = R·(1 + Σ aₖ·sin(kθ + φₖ))`, low harmonics `k ∈ {2,3,5}`, `aₖ ≈ 0.08–0.14`,
  distinct `φ` per circle. Radii kept: big **R365** @ ~`(1440, 873)`, small
  **R130** @ ~`(728, 893)`. (Carried from the current baker's `IRREGULAR_CIRCLES`;
  rasterizes smooth because it's an analytic profile test, not a trace.)
- `ISLANDS` — heart island in the big chamber, subtracted after the union. Carried
  from the current `ISLAND_BLOBS` (overlapping discs centred ~`(1430, 880)`).
- `SPAWN = (40, 898)`, `NEXUS = (3810, 898)` — unchanged.

### Renderer

Replace the trace + EDT-widen + morph-close + box-blur block with a single
rasterization pass over the 960×446 mask (`px_wu ≈ 4` wu/px) applying the
walkable test above. Helper: point-to-segment distance (clamped projection).

### Kept from current baker

- `flood` (4-connected), spawn-connected-component filter (drops specks/orphans),
  **spawn→nexus connectivity assert** (fails the bake loudly), `write_gray_png`.

### Removed from current baker

- `read_png_rgb` / `is_path` (reference trace), the EDT `widen_walkable`,
  `morph_erode` / `morph_close`, the `box_blur_threshold` smoothing passes, the
  hole-fill step (no longer relevant — geometry is authored, not traced),
  `REPAIR_RECTS` (no fragmentation to repair). The reference PNG is no longer read
  (it may stay on disk as an eyeball aid when choosing coordinates).

## Layout fidelity

Redrawn to the **same elements at the same anchor positions** (reuse existing
circle/island/spawn/nexus constants; read comb finger extents off the current
`map_3_mask.png` / screenshots). **Parallel routes preserved** — chamber rings
(top/bottom arcs around islands) + comb up/down fingers — so the 2-variant
route-split still has parallel lanes to split traffic across. Exact pixel-match to
the traced reference is explicitly NOT a goal (impossible to do smoothly).

## Files

- **Rewrite:** `tools/gen_map_3_mask.py` — centerline data + stroke renderer;
  keep flood/component/assert/PNG-writer; drop trace/widen/morph/blur/hole-fill.
- **Regenerate:** `levels/map_3_mask.png` (re-run the baker).
- **Update:** `docs/ARCHITECTURE.md` — map3 baker is now stroked-centerline vector
  (not raster-trace + smooth); note the geometry constants.
- **Untouched:** `shaders/terrain_mask.gdshader`, `levels/map_3_gen.gd`,
  `levels/map_3.tscn`, `battle/flow_field_manager.gd`,
  `shaders/compute_flow_field.glsl`, `shaders/compute_physics.glsl`.

## Verification

1. **Bake:** connectivity assert passes; mask eyeball — corridors ~130 wu wide,
   **straight walls dead-straight (not wavy)**, only corners/turns rounded, both
   circles smooth-irregular, heart island present, comb fingers + chamber rings
   intact (parallel routes alive).
2. **map3** (temp `selected_map="map3"`, auto-test wave, run ~60s untouched): one
   `editor_screenshot(source=game)` mid-wave — route split fills **both arcs of
   each ringed chamber + both comb fingers simultaneously**; a second shot ~10s
   later shows **no lane-flip oscillation**; `logs_read` shows drain (`active>alive`
   grows) + low/transient `stuck`; framerate steady (~60, judged by linear spawn
   cadence).
3. Stop, revert `selected_map` to `""`, confirm clean.

## Risks

- Centerline coords must keep parallel routes alive (mitigated: explicit chamber
  rings + comb fingers). If a ring collapses to a solid disc, that chamber loses
  its split (acceptable for the small circle; the big chamber must keep its ring).
- Connectivity must hold end-to-end — the assert catches a break before ship.
- Corridor width uniform — single `CORRIDOR_HALF_WIDTH`; chambers/fingers may use
  wider local strokes if needed, but default uniform.
- Stamping a centerline too close to a parallel one could merge lanes (kills the
  split) — keep centerlines ≥ `2·half_width + margin` apart where parallelism
  matters; re-check enclosed-region count if unsure.
