class_name WorldGen

class WorldData:
    var successful: bool = false
    var world_size: Vector2i = Vector2i.ZERO

    var sdf_data: PackedByteArray = []
    var sdf_image: Image = null
    var sdf_tex: Texture2D = null

    var flow_data: PackedByteArray = []
    var flow_image: Image = null
    var flow_tex: Texture2D = null

    var wall_polygons: Array[CollisionPolygon2D] = []

static func create_polygons_from_sdf(sdf_image: Image, units_per_pixel: float, grid_offset: Vector2 = Vector2.ZERO) -> Array[CollisionPolygon2D]:
    var w := sdf_image.get_width()
    var h := sdf_image.get_height()

    var grid: Array[PackedByteArray] = []
    grid.resize(h)

    for y: int in h:
        grid[y] = PackedByteArray()
        grid[y].resize(w)
        for x: int in w:
            # -------------------------------------------------------------
            # -------------------------------------------------------------
            # -------------------------------------------------------------
            var val := sdf_image.get_pixel(x, y).r
            # -------------------------------------------------------------
            var is_inside: bool = val <= 0.0
            grid[y][x] = 1 if is_inside else 0

    var polygons: Array[CollisionPolygon2D] = []

    var visited: Dictionary[Vector2i, bool] = {}
    var regions: Array[Array] = []
    for y: int in h:
        for x: int in w:
            var p := Vector2i(x, y)
            if grid[y][x] == 1 and not visited.has(p):
                flood_fill(p, grid, visited, regions)

    for region: Array[Vector2i] in regions:
        var contour: PackedVector2Array = trace_boundary(region, grid)
        if contour.size() < 3:
            continue

        var simplified: PackedVector2Array = simplify_collinear(contour)
        var scaled_contour := PackedVector2Array()
        scaled_contour.resize(simplified.size())
        for i: int in scaled_contour.size():
            # -------------------------------------------------------------
            var grid_pt = Vector2(simplified[i]) + grid_offset
            scaled_contour[i] = grid_pt * units_per_pixel

        var poly := CollisionPolygon2D.new()
        poly.build_mode = CollisionPolygon2D.BUILD_SOLIDS
        poly.polygon = scaled_contour
        polygons.append(poly)

    return polygons

const NEIGHBORS: Array[Vector2i] = [
    Vector2i(1, 0), 
    Vector2i(-1, 0), 
    Vector2i(0, 1), 
    Vector2i(0, -1), 
]

static func flood_fill(start: Vector2i, grid: Array[PackedByteArray], visited: Dictionary[Vector2i, bool], regions: Array[Array]) -> void:
    var stack: Array[Vector2i] = [start]
    var pixels: Array[Vector2i] = []

    while stack.size() > 0:
        var p: Vector2i = stack.pop_back()
        if visited.has(p):
            continue
        visited[p] = true
        if grid[p.y][p.x] == 0:
            continue

        pixels.append(p)

        for d: Vector2i in NEIGHBORS:
            var n := p + d
            if n.x >= 0 and n.x < grid[0].size() and n.y >= 0 and n.y < grid.size():
                stack.append(n)

    if pixels.size() > 0:
        regions.append(pixels)

const DIRS: Array[Vector2i] = [
    Vector2i(1, 0), 
    Vector2i(1, 1), 
    Vector2i(0, 1), 
    Vector2i(-1, 1), 
    Vector2i(-1, 0), 
    Vector2i(-1, -1), 
    Vector2i(0, -1), 
    Vector2i(1, -1)
]

static func get_corner(prev: Vector2i, curr: Vector2i) -> Vector2:
    var d := curr - prev

    if d == Vector2i(1, 0):
        return Vector2(curr.x, curr.y)
    elif d == Vector2i(0, 1):
        return Vector2(curr.x + 1, curr.y)
    elif d == Vector2i(-1, 0):
        return Vector2(curr.x + 1, curr.y + 1)
    elif d == Vector2i(0, -1):
        return Vector2(curr.x, curr.y + 1)
    elif d == Vector2i(1, 1):
        return Vector2(curr.x, curr.y)
    elif d == Vector2i(-1, 1):
        return Vector2(curr.x + 1, curr.y)
    elif d == Vector2i(-1, -1):
        return Vector2(curr.x + 1, curr.y + 1)
    elif d == Vector2i(1, -1):
        return Vector2(curr.x, curr.y + 1)

    return Vector2(curr)

static func trace_boundary(region: Array[Vector2i], grid: Array[PackedByteArray]) -> PackedVector2Array:
    var region_set: Dictionary[Vector2i, bool] = {}
    for p: Vector2i in region:
        region_set[p] = true

    var start := -Vector2i.ONE
    for p: Vector2i in region:
        if is_boundary(p, grid):
            start = p
            break

    if start == -Vector2i.ONE:
        return []

    var contour := PackedVector2Array()
    var current := start
    var prev_dir := 0

    while true:
        var found := false
        for i: int in DIRS.size():
            var dir_index := (prev_dir + i) % DIRS.size()
            var d := DIRS[dir_index]
            var n := current + d

            if region_set.has(n) and is_boundary(n, grid):
                contour.append(get_corner(current, n))
                current = n
                prev_dir = (dir_index + 5) % DIRS.size()
                found = true
                break

        if not found or current == start:
            break

    return contour

static func is_boundary(p: Vector2i, grid: Array[PackedByteArray]) -> bool:
    for d: Vector2i in NEIGHBORS:
        var n := p + d
        if n.x < 0 or n.x >= grid[0].size() or n.y < 0 or n.y >= grid.size():
            return true
        if grid[n.y][n.x] == 0:
            return true
    return false

static func simplify_collinear(points: PackedVector2Array) -> PackedVector2Array:
    if points.size() < 3:
        return points

    var result := PackedVector2Array()

    for i in range(points.size()):
        var prev := points[(i - 1 + points.size()) % points.size()]
        var curr := points[i]
        var next := points[(i + 1) % points.size()]

        var v1 := (curr - prev).normalized()
        var v2 := (next - curr).normalized()

        if v1.dot(v2) > 0.999:
            continue

        result.append(curr)

    return result
