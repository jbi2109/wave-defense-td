#!/usr/bin/env python3
"""Generate the reusable Polygon2D map-piece kit -> levels/pieces/*.tscn.

Each piece is a single smooth Polygon2D scene, math-generated ONCE, designed to patch
together on a 160-unit grid: corridor width W=160, corridors flat-capped and extended a
little past the tile edge so neighbours OVERLAP (the map's walkability is the union of all
"map_path" pieces minus "map_wall" pieces, so overlaps are seamless and gaps never appear).
Straight runs are dead-straight (thick flat-capped lines); corners/junctions round their
outer bend with a disc; chambers are circles/ellipses/hexagons or organic blobs; dirt/rock
pieces are irregular blobs (group "map_wall"). Drag pieces from levels/pieces/ onto the grid
and rotate in 90° steps so corridors line up (diagonal pieces are free-placement).

Geometry is built from four inputs, all routed through one rasterise->contour pipeline:
  polylines (stroked flat-capped + auto-rounded bends) + discs + circles + polys (filled).

Run from the project root:  python tools/gen_map_pieces.py
"""
import math
import os

import numpy as np
import cv2

W = 160.0          # corridor width
HALF = W / 2.0     # 80
T = 160.0          # grid tile
OV = 14.0          # overlap past the tile edge
ARM = T / 2.0 + OV     # 94 — centre to a port (with overlap)
R_CHAMBER = 240.0
R_DIRT = 130.0
SCALE = 4          # px per world unit when rasterising for the contour
EPS = 5.0          # approxPolyDP epsilon (px)

GRASS_UID = "uid://b6cjmch52s2x0"
DIRT_UID = "uid://djvertw8l0foc"
GRASS_PATH = "res://assets/shader/shader-texture_2.png"
DIRT_PATH = "res://assets/shader/Dirt_texture.png"


def arc_pts(cx, cy, r, a0, a1, n=14):
    return [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)))
            for a in [a0 + (a1 - a0) * i / n for i in range(n + 1)]]


def blob_pts(cx, cy, R, harmonics, amps, phases, n=96):
    """Organic radial blob: r(theta) = R * (1 + sum ak*sin(k*theta + phk))."""
    out = []
    for i in range(n):
        th = 2.0 * math.pi * i / n
        r = R
        for k, a, p in zip(harmonics, amps, phases):
            r += R * a * math.sin(k * th + p)
        out.append((cx + r * math.cos(th), cy + r * math.sin(th)))
    return out


def ellipse_pts(cx, cy, rx, ry, n=72):
    return [(cx + rx * math.cos(2 * math.pi * i / n), cy + ry * math.sin(2 * math.pi * i / n))
            for i in range(n)]


def regular_poly_pts(cx, cy, R, sides, rot=0.0):
    return [(cx + R * math.cos(rot + 2 * math.pi * i / sides),
             cy + R * math.sin(rot + 2 * math.pi * i / sides)) for i in range(sides)]


def s_curve_pts(length, shift, n=24):
    """Smooth S that shifts the lane by `shift` over horizontal `length` (flat tangents)."""
    out = []
    for i in range(n + 1):
        t = i / n
        x = -length / 2.0 + length * t
        y = -shift / 2.0 + shift * (3 * t * t - 2 * t * t * t)
        out.append((x, y))
    return out


def _seg_quad(a, b, half):
    dx, dy = b[0] - a[0], b[1] - a[1]
    L = math.hypot(dx, dy)
    if L < 1e-6:
        return None
    nx, ny = -dy / L * half, dx / L * half
    return [(a[0] + nx, a[1] + ny), (b[0] + nx, b[1] + ny),
            (b[0] - nx, b[1] - ny), (a[0] - nx, a[1] - ny)]


def build_polygon(polylines, discs, circles, polys=None, half=HALF, margin=24, eps=EPS):
    polys = polys or []
    # Auto-round internal bends: a disc at every interior polyline vertex (so corners/arcs
    # are smooth) while the polyline END points stay flat (so ports butt cleanly).
    auto = list(discs)
    for pl in polylines:
        for i in range(1, len(pl) - 1):
            auto.append((pl[i], half))

    pts = []
    for pl in polylines:
        for (x, y) in pl:
            pts += [(x - half, y - half), (x + half, y + half)]
    for (c, r) in auto + circles:
        pts += [(c[0] - r, c[1] - r), (c[0] + r, c[1] + r)]
    for poly in polys:
        pts += list(poly)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    minx, maxx = min(xs) - margin, max(xs) + margin
    miny, maxy = min(ys) - margin, max(ys) + margin
    w_px = int(round((maxx - minx) * SCALE))
    h_px = int(round((maxy - miny) * SCALE))
    img = np.zeros((h_px, w_px), np.uint8)

    def to_px(p):
        return [int(round((p[0] - minx) * SCALE)), int(round((p[1] - miny) * SCALE))]

    for pl in polylines:
        for i in range(len(pl) - 1):
            q = _seg_quad(pl[i], pl[i + 1], half)
            if q:
                cv2.fillConvexPoly(img, np.array([to_px(p) for p in q], np.int32), 255)
    for poly in polys:
        cv2.fillPoly(img, [np.array([to_px(p) for p in poly], np.int32)], 255)
    for (c, r) in auto + circles:
        cv2.circle(img, tuple(to_px(c)), int(round(r * SCALE)), 255, -1, lineType=cv2.LINE_8)

    cnts, _ = cv2.findContours(img, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cnt = max(cnts, key=cv2.contourArea)
    approx = cv2.approxPolyDP(cnt, eps, True).reshape(-1, 2)
    return [(round(px / SCALE + minx, 1), round(py / SCALE + miny, 1)) for px, py in approx]


# Map2's hand-authored irregular central island, recentred on its centroid to a piece.
_MAP2_FLAT = [
    413.38, 451.07, 416.38, 439.33, 420.57, 428.65, 425.94, 419.03, 432.51, 410.48, 440.26,
    402.98, 449.2, 396.54, 459.33, 391.16, 470.65, 386.84, 551.35, 361.16, 563.3, 357.71,
    575.3, 354.94, 587.36, 352.85, 599.48, 351.44, 611.66, 350.71, 623.9, 350.66, 636.2,
    351.3, 648.56, 352.61, 699.44, 359.39, 710.86, 361.7, 720.36, 365.31, 727.92, 370.24,
    733.55, 376.47, 737.24, 384.01, 739.01, 392.85, 738.85, 403.01, 736.75, 414.48, 715.25,
    499.52, 712.53, 511.65, 710.5, 523.8, 709.16, 535.96, 708.51, 548.14, 708.54, 560.34,
    709.26, 572.55, 710.68, 584.78, 712.78, 597.03, 757.22, 819.97, 758.74, 831.55, 758.4,
    841.8, 756.2, 850.71, 752.15, 858.28, 746.24, 864.52, 738.48, 869.41, 728.86, 872.96,
    717.38, 875.17, 591.62, 890.83, 579.45, 891.71, 567.76, 891.26, 556.55, 889.48, 545.81,
    886.38, 535.55, 881.95, 525.76, 876.19, 516.45, 869.11, 507.62, 860.7, 397.38, 744.3,
    389.47, 735.03, 382.94, 725.35, 377.78, 715.28, 374, 704.81, 371.59, 693.94, 370.56,
    682.67, 370.9, 671, 372.62, 658.93,
]


def _map2_mound():
    raw = list(zip(_MAP2_FLAT[::2], _MAP2_FLAT[1::2]))
    cx = sum(p[0] for p in raw) / len(raw)
    cy = sum(p[1] for p in raw) / len(raw)
    return [(x - cx, y - cy) for x, y in raw]


# name -> (polylines, discs, circles, polys, group, is_dirt)
def piece_specs():
    A = ARM
    curve = [(-A, 0.0)] + arc_pts(-160.0, 160.0, 160.0, 270, 360, 14) + [(0.0, A)]
    P = "map_path"
    Wll = "map_wall"
    return {
        # --- original geometric kit (kept byte-stable: same shapes as before) ---
        "straight":   ([[(-A, 0.0), (A, 0.0)]], [], [], [], P, False),
        "corner":     ([[(-A, 0.0), (0.0, 0.0), (0.0, A)]], [((0.0, 0.0), HALF)], [], [], P, False),
        "curve":      ([curve], [], [], [], P, False),
        "tjunction":  ([[(-A, 0.0), (A, 0.0)], [(0.0, 0.0), (0.0, A)]], [((0.0, 0.0), HALF)], [], [], P, False),
        "cross":      ([[(-A, 0.0), (A, 0.0)], [(0.0, -A), (0.0, A)]], [((0.0, 0.0), HALF)], [], [], P, False),
        "cap":        ([[(0.0, 0.0), (A, 0.0)]], [((0.0, 0.0), HALF)], [], [], P, False),
        "chamber":    ([], [], [((0.0, 0.0), R_CHAMBER)], [], P, False),
        "dirt_mound": ([], [], [((0.0, 0.0), R_DIRT)], [], Wll, True),

        # --- extra corridors ---
        "straight_2":      ([[(-(T + OV), 0.0), (T + OV, 0.0)]], [], [], [], P, False),
        "straight_3":      ([[(-(1.5 * T + OV), 0.0), (1.5 * T + OV, 0.0)]], [], [], [], P, False),
        "s_curve":         ([s_curve_pts(2 * T + 2 * OV, 160.0)], [], [], [], P, False),
        "y_fork":          ([[(-A, 0.0), (0.0, 0.0), (130.0, -130.0)], [(0.0, 0.0), (130.0, 130.0)]],
                            [((0.0, 0.0), HALF)], [], [], P, False),
        "diagonal":        ([[(-180.0, -180.0), (180.0, 180.0)]], [], [], [], P, False),
        "diagonal_corner": ([[(-A, 0.0), (0.0, 0.0), (130.0, 130.0)]], [((0.0, 0.0), HALF)], [], [], P, False),

        # --- chambers (walkable hubs) ---
        "chamber_oval":       ([], [], [], [ellipse_pts(0, 0, 300, 180)], P, False),
        "chamber_large":      ([], [], [((0.0, 0.0), 340.0)], [], P, False),
        "chamber_hex":        ([], [], [], [regular_poly_pts(0, 0, 240, 6, rot=0.0)], P, False),
        "chamber_irregular":  ([], [], [], [blob_pts(0, 0, 240, [2, 3, 5], [0.12, 0.10, 0.07], [0.7, 1.8, 0.3])], P, False),
        "chamber_irregular_2": ([], [], [], [blob_pts(0, 0, 230, [2, 3, 4], [0.10, 0.13, 0.06], [2.1, 0.5, 1.4])], P, False),

        # --- dirt / rock (irregular obstacles + islands) ---
        "dirt_mound_map2": ([], [], [], [_map2_mound()], Wll, True),
        "dirt_blob_s":     ([], [], [], [blob_pts(0, 0, 70, [2, 3, 5], [0.15, 0.10, 0.08], [1.0, 2.4, 0.6])], Wll, True),
        "dirt_blob_m":     ([], [], [], [blob_pts(0, 0, 120, [2, 3, 5], [0.13, 0.11, 0.07], [0.3, 1.7, 2.5])], Wll, True),
        "dirt_blob_l":     ([], [], [], [blob_pts(0, 0, 180, [2, 3, 4], [0.12, 0.09, 0.08], [1.9, 0.8, 2.2])], Wll, True),
        "dirt_oval":       ([], [], [], [ellipse_pts(0, 0, 160, 90)], Wll, True),
        "rock_cluster":    ([], [], [], [
            blob_pts(-55, -15, 62, [2, 3], [0.18, 0.12], [0.5, 2.0]),
            blob_pts(52, -28, 70, [2, 3, 5], [0.15, 0.10, 0.08], [1.8, 0.4, 1.2]),
            blob_pts(6, 46, 64, [2, 4], [0.16, 0.10], [2.4, 0.9]),
        ], Wll, True),
    }


def to_node_name(name):
    return "".join(p.capitalize() for p in name.split("_"))


def write_piece(out_dir, name, poly, group, is_dirt):
    node = to_node_name(name)
    tex_uid = DIRT_UID if is_dirt else GRASS_UID
    tex_path = DIRT_PATH if is_dirt else GRASS_PATH
    z = -9 if is_dirt else -10
    poly_lit = ", ".join("%g, %g" % (x, y) for x, y in poly)
    lines = [
        '[gd_scene load_steps=2 format=3 uid="uid://kitpiece%s"]' % name.replace("_", ""),
        '',
        '[ext_resource type="Texture2D" uid="%s" path="%s" id="1_tex"]' % (tex_uid, tex_path),
        '',
        '[node name="%s" type="Polygon2D" groups=["%s"]]' % (node, group),
        'z_index = %d' % z,
        'texture_repeat = 2',
        'texture = ExtResource("1_tex")',
        'polygon = PackedVector2Array(%s)' % poly_lit,
        '',
    ]
    path = os.path.join(out_dir, "%s.tscn" % name)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("  %-18s %3d pts -> %s" % (name, len(poly), os.path.relpath(path)))


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "levels", "pieces")
    os.makedirs(out_dir, exist_ok=True)
    print("Generating map-piece kit (W=%g, tile=%g) -> %s" % (W, T, os.path.relpath(out_dir)))
    for name, (polylines, discs, circles, polys, group, is_dirt) in piece_specs().items():
        eps = 2.0 if name == "dirt_mound_map2" else EPS   # keep the Map2 mound's lumpy detail
        poly = build_polygon(polylines, discs, circles, polys=polys, eps=eps)
        write_piece(out_dir, name, poly, group, is_dirt)
    print("Done.")


if __name__ == "__main__":
    main()
