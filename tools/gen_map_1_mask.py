#!/usr/bin/env python3
"""Offline baker for the map_1 walkable mask (the "orc way" map pipeline).

Mirrors `levels/map_1_gen.gd::round_polygon` exactly, rasterises the rounded
walkable corridor into a grayscale PNG (white = walkable, black = wall), and
prints the rounded polygon as a Godot `PackedVector2Array(...)` literal for the
visual `Grass_Path` fill in map_1.tscn.

Run from the project root:  python tools/gen_map_1_mask.py
Writes: levels/map_1_mask.png

Used because Godot game_eval result-marshalling is focus-gated and stalls on a
heavy synchronous bake; this produces an identical mask without a running editor.
Keep in sync with map_1_gen.gd if the route/radius/algorithm changes.
"""
import os
import struct
import zlib

WORLD = (1920.0, 1080.0)
MASK = (480, 270)
CORNER_RADIUS = 60.0
SAMPLES = 8

# Original sharp 12-point walkable corridor outline (must match map_1_gen.gd).
ROUTE = [
    (0, 200), (600, 200), (600, 700), (1100, 700),
    (1100, 200), (1920, 200), (1920, 400), (1300, 400),
    (1300, 900), (400, 900), (400, 400), (0, 400),
]


def round_polygon(points, radius, samples=SAMPLES):
    n = len(points)
    if n < 3:
        return list(points)
    out = []
    for i in range(n):
        p0 = points[(i - 1) % n]
        p1 = points[i]
        p2 = points[(i + 1) % n]
        # Keep left/right map-edge corners square (spawn/nexus openings).
        if p1[0] <= 1.0 or p1[0] >= WORLD[0] - 1.0:
            out.append(p1)
            continue
        vin = (p1[0] - p0[0], p1[1] - p0[1])
        vout = (p2[0] - p1[0], p2[1] - p1[1])
        len_in = (vin[0] ** 2 + vin[1] ** 2) ** 0.5
        len_out = (vout[0] ** 2 + vout[1] ** 2) ** 0.5
        if len_in < 1e-3 or len_out < 1e-3:
            out.append(p1)
            continue
        din = (vin[0] / len_in, vin[1] / len_in)
        dout = (vout[0] / len_out, vout[1] / len_out)
        if din[0] * dout[0] + din[1] * dout[1] > 0.999:  # straight-through
            out.append(p1)
            continue
        r = min(radius, len_in * 0.5, len_out * 0.5)
        a = (p1[0] - din[0] * r, p1[1] - din[1] * r)
        c = (p1[0] + dout[0] * r, p1[1] + dout[1] * r)
        for s in range(samples + 1):
            t = s / samples
            omt = 1.0 - t
            x = omt * omt * a[0] + 2 * omt * t * p1[0] + t * t * c[0]
            y = omt * omt * a[1] + 2 * omt * t * p1[1] + t * t * c[1]
            out.append((x, y))
    return out


def point_in_polygon(x, y, poly):
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return inside


def write_gray_png(path, width, height, pixels):
    """pixels: bytes of length width*height, 8-bit grayscale."""
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))

    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: none
        raw.extend(pixels[y * width:(y + 1) * width])
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(sig)
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_path = os.path.join(root, "levels", "map_1_mask.png")
    poly = round_polygon(ROUTE, CORNER_RADIUS)

    w, h = MASK
    pixels = bytearray(w * h)
    for py in range(h):
        wy = (py + 0.5) / h * WORLD[1]
        for px in range(w):
            wx = (px + 0.5) / w * WORLD[0]
            if point_in_polygon(wx, wy, poly):
                pixels[py * w + px] = 255
    write_gray_png(out_path, w, h, pixels)

    coords = ", ".join("%g, %g" % (round(p[0], 2), round(p[1], 2)) for p in poly)
    print("wrote %s (%dx%d), %d rounded points" % (out_path, w, h, len(poly)))
    print("POLY:PackedVector2Array(%s)" % coords)


if __name__ == "__main__":
    main()
