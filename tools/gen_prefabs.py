#!/usr/bin/env python3
"""Generate composite prefab assets from the piece kit -> levels/prefabs/*.tscn.

A prefab is a ready-made multi-piece chunk you drop into a map as ONE node. It instances
kit pieces (levels/pieces/*.tscn); because those pieces carry the "map_path"/"map_wall"
groups, battle.gd's recursive walkability gather picks them up even when nested inside a
prefab inside a map. Mirror-symmetric prefabs reflect a TOP container about y=0 with a
scale=(1,-1) BottomHalf node (same trick as assemble_map_3.py).

Run from the project root:  python tools/gen_prefabs.py
"""
import math
import os

# (piece, x, y, degrees[, scale])
PREFABS = {
    "prefab_chamber_island": {
        "centre": [("chamber", 0, 0, 0), ("dirt_mound_map2", 0, 0, 0, 0.55)],
        "top": [],
    },
    "prefab_loop_section": {
        "centre": [
            ("cross", -480, 0, 0),
            ("straight", -320, 0, 0), ("straight", -160, 0, 0), ("straight", 0, 0, 0),
            ("straight", 160, 0, 0), ("straight", 320, 0, 0),
            ("cross", 480, 0, 0),
        ],
        "top": [
            ("straight", -480, -160, 90), ("straight", -480, -320, 90),
            ("corner", -480, -480, -90),
            ("straight", -320, -480, 0), ("straight", -160, -480, 0), ("straight", 0, -480, 0),
            ("straight", 160, -480, 0), ("straight", 320, -480, 0),
            ("corner", 480, -480, 0),
            ("straight", 480, -320, 90), ("straight", 480, -160, 90),
        ],
    },
}


def emit(name, spec, out_dir):
    centre, top = spec["centre"], spec["top"]
    used = []
    for s in centre + top:
        if s[0] not in used:
            used.append(s[0])
    ext = [('PackedScene', 'res://levels/pieces/%s.tscn' % p, 'ps_%s' % p) for p in used]

    L = ['[gd_scene load_steps=%d format=3 uid="uid://%s"]' % (len(ext) + 1, name.replace("_", "")), '']
    for e in ext:
        L.append('[ext_resource type="%s" path="%s" id="%s"]' % e)
    L.append('')
    node = "".join(p.capitalize() for p in name.split("_"))
    L.append('[node name="%s" type="Node2D"]' % node)
    L.append('')

    counter = {}

    def place(parent, specs):
        for s in specs:
            p, x, y, deg = s[0], s[1], s[2], s[3]
            scale = s[4] if len(s) > 4 else None
            counter[p] = counter.get(p, 0) + 1
            nm = "%s_%d" % ("".join(w.capitalize() for w in p.split("_")), counter[p])
            L.append('[node name="%s" parent="%s" instance=ExtResource("ps_%s")]' % (nm, parent, p))
            L.append('position = Vector2(%g, %g)' % (x, y))
            if deg:
                L.append('rotation = %.5f' % math.radians(deg))
            if scale:
                L.append('scale = Vector2(%g, %g)' % (scale, scale))
            L.append('')

    if top:
        L.append('[node name="Center" type="Node2D" parent="."]'); L.append('')
        place("Center", centre)
        L.append('[node name="TopHalf" type="Node2D" parent="."]'); L.append('')
        place("TopHalf", top)
        L.append('[node name="BottomHalf" type="Node2D" parent="."]')
        L.append('scale = Vector2(1, -1)'); L.append('')
        place("BottomHalf", top)
    else:
        place(".", centre)

    path = os.path.join(out_dir, "%s.tscn" % name)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(L))
    print("  %-22s %2d pieces -> %s" % (name, len(centre) + 2 * len(top), os.path.relpath(path)))


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "levels", "prefabs")
    os.makedirs(out_dir, exist_ok=True)
    print("Generating prefabs -> %s" % os.path.relpath(out_dir))
    for name, spec in PREFABS.items():
        emit(name, spec, out_dir)
    print("Done.")


if __name__ == "__main__":
    main()
