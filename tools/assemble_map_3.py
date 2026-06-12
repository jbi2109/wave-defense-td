#!/usr/bin/env python3
"""Assemble Map3 from the reusable piece kit -> levels/map_3.tscn.

Symmetry trick: author the CENTRE pieces (on the y=893 axis) and the TOP-half pieces once;
emit the top pieces a second time under a BottomHalf node whose transform reflects about the
axis (position (0, 1786), scale (1,-1)). So the bottom is an exact mirror of the top with no
per-piece math. Walkability is the union of all "map_path" pieces minus "map_wall" (battle.gd),
so overlapping piece ends fuse seamlessly. No mask, no Path2D.

Edit `CENTRE` / `TOP` below (or just drag pieces in the editor) and re-run.
Run from the project root:  python tools/assemble_map_3.py
"""
import math
import os

WORLD = (3840.0, 1786.0)
AXIS = WORLD[1] / 2.0  # 893

# (piece, x, y, degrees[, scale]) — CENTRE pieces sit on/over the axis (not mirrored).
CENTRE = [
    ("cap", 0, AXIS, 0),
    ("straight", 160, AXIS, 0), ("straight", 320, AXIS, 0),
    ("straight", 480, AXIS, 0), ("straight", 640, AXIS, 0),
    ("cross", 800, AXIS, 0),
    ("straight", 960, AXIS, 0), ("straight", 1120, AXIS, 0),
    ("chamber", 1280, AXIS, 0),
    ("dirt_mound", 1280, AXIS, 0, 0.5),
    ("straight", 1600, AXIS, 0),
    ("cross", 1760, AXIS, 0),
    ("straight", 1920, AXIS, 0), ("straight", 2080, AXIS, 0),
    ("straight", 2240, AXIS, 0), ("straight", 2400, AXIS, 0),
    ("chamber", 2720, AXIS, 0),
    ("dirt_mound", 2720, AXIS, 0, 0.6),
    ("straight", 3040, AXIS, 0), ("straight", 3200, AXIS, 0),
    ("straight", 3360, AXIS, 0), ("straight", 3520, AXIS, 0),
    ("straight", 3680, AXIS, 0),
    ("cap", 3840, AXIS, 180),
]

# TOP-half pieces (y < AXIS). Mirrored to the bottom automatically. A loop rising off the two
# crosses (x=800, x=1760) and running across the top, plus a dirt island inside the loop.
TOP = [
    # left riser off cross(800)
    ("straight", 800, AXIS - 160, 90), ("straight", 800, AXIS - 320, 90),
    ("corner", 800, AXIS - 480, -90),          # turn: DOWN + RIGHT
    # top run
    ("straight", 960, AXIS - 480, 0), ("straight", 1120, AXIS - 480, 0),
    ("straight", 1280, AXIS - 480, 0), ("straight", 1440, AXIS - 480, 0),
    ("straight", 1600, AXIS - 480, 0),
    ("corner", 1760, AXIS - 480, 0),           # turn: LEFT + DOWN
    # right riser into cross(1760)
    ("straight", 1760, AXIS - 320, 90), ("straight", 1760, AXIS - 160, 90),
]

GRASS_UID = "uid://b6cjmch52s2x0"
DIRT_UID = "uid://djvertw8l0foc"


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "levels", "map_3.tscn")

    used = []
    for spec in CENTRE + TOP:
        if spec[0] not in used:
            used.append(spec[0])

    # ext_resources (path-only refs avoid stale-UID warnings; the editor adds correct uids)
    ext = []
    ext.append(('Script', 'res://levels/kit_map.gd', 'kit_map'))
    ext.append(('Script', 'res://levels/placement_marker.gd', 'placement_marker'))
    ext.append(('Texture2D', 'res://assets/shader/Dirt_texture.png', 'tex_dirt', DIRT_UID))
    for name in used:
        ext.append(('PackedScene', 'res://levels/pieces/%s.tscn' % name, 'ps_%s' % name))

    L = []
    L.append('[gd_scene load_steps=%d format=3 uid="uid://map3kit"]' % (len(ext) + 1))
    L.append('')
    for e in ext:
        if len(e) == 4:
            L.append('[ext_resource type="%s" uid="%s" path="%s" id="%s"]' % (e[0], e[3], e[1], e[2]))
        else:
            L.append('[ext_resource type="%s" path="%s" id="%s"]' % (e[0], e[1], e[2]))
    L.append('')

    L.append('[node name="Map3" type="Node2D"]')
    L.append('script = ExtResource("kit_map")')
    L.append('world_size = Vector2(%g, %g)' % WORLD)
    L.append('')
    L.append('[node name="Background" type="Polygon2D" parent="."]')
    L.append('z_index = -20')
    L.append('texture_repeat = 2')
    L.append('texture = ExtResource("tex_dirt")')
    L.append('polygon = PackedVector2Array(0, 0, %g, 0, %g, %g, 0, %g)' % (WORLD[0], WORLD[0], WORLD[1], WORLD[1]))
    L.append('')

    counter = {}

    def emit(parent, specs):
        for spec in specs:
            name = spec[0]
            x, y, deg = spec[1], spec[2], spec[3]
            scale = spec[4] if len(spec) > 4 else None
            counter[name] = counter.get(name, 0) + 1
            node = "%s_%d" % ("".join(p.capitalize() for p in name.split("_")), counter[name])
            L.append('[node name="%s" parent="%s" instance=ExtResource("ps_%s")]' % (node, parent, name))
            L.append('position = Vector2(%g, %g)' % (x, y))
            if deg:
                L.append('rotation = %.5f' % math.radians(deg))
            if scale:
                L.append('scale = Vector2(%g, %g)' % (scale, scale))
            L.append('')

    L.append('[node name="Center" type="Node2D" parent="."]')
    L.append('')
    emit("Center", CENTRE)

    L.append('[node name="TopHalf" type="Node2D" parent="."]')
    L.append('')
    emit("TopHalf", TOP)

    # BottomHalf reflects the top about the axis (no per-piece mirror math).
    L.append('[node name="BottomHalf" type="Node2D" parent="."]')
    L.append('position = Vector2(0, %g)' % (2 * AXIS))
    L.append('scale = Vector2(1, -1)')
    L.append('')
    emit("BottomHalf", TOP)

    L.append('[node name="SpawnMarker" type="Marker2D" parent="."]')
    L.append('position = Vector2(40, %g)' % AXIS)
    L.append('script = ExtResource("placement_marker")')
    L.append('kind = "spawn"')
    L.append('extents = Vector2(60, 200)')
    L.append('')
    L.append('[node name="NexusMarker" type="Marker2D" parent="."]')
    L.append('position = Vector2(3800, %g)' % AXIS)
    L.append('script = ExtResource("placement_marker")')
    L.append('kind = "nexus"')
    L.append('extents = Vector2(40, 130)')
    L.append('')

    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(L))
    total = len(CENTRE) + 2 * len(TOP)
    print("wrote %s — %d piece instances (%d centre + %d top x2)" %
          (os.path.relpath(out), total, len(CENTRE), len(TOP)))


if __name__ == "__main__":
    main()
