shader_type canvas_item;

uniform sampler2D noise_tex : repeat_enable;
uniform vec4 color_a : source_color;
uniform vec4 color_b : source_color;
uniform float scale = 0.002;

varying vec2 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    float n = texture(noise_tex, world_pos * scale).r;
    vec4 tex_color = texture(TEXTURE, UV);
    COLOR = mix(color_a, color_b, n);
    COLOR.a *= tex_color.a;
}
