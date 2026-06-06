bool is_target(vec4 c) {
    return c.r > 0.5;
}

bool is_inside(vec4 c) {
    return c.b > 0.5;
}


const uint NEIGHBOR_4_COUNT = 4;
const ivec2 OFFSETS_4[4] = ivec2[](
                ivec2(0,-1),
    ivec2(-1, 0),           ivec2(1, 0),
                ivec2(0, 1)
);


const uint NEIGHBOR_8_COUNT = 8;
const ivec2 OFFSETS_8[8] = ivec2[](
    ivec2(-1,-1), ivec2(0,-1), ivec2(1,-1),
    ivec2(-1, 0),              ivec2(1, 0),
    ivec2(-1, 1), ivec2(0, 1), ivec2(1, 1)
);

const vec2 DIRECTIONS_8[8] = vec2[](
    normalize(vec2(-1,-1)), vec2(0,-1), normalize(vec2(1,-1)),
    vec2(-1, 0),                        vec2(1, 0),
    normalize(vec2(-1, 1)), vec2(0, 1), normalize(vec2(1, 1))
);
const float DISTANCES_8[8] = float[](
    1.41, 1.0, 1.41,
    1.0,       1.0,
    1.41, 1.0, 1.41
);