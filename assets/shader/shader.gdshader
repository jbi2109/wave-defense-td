// Custom tile shader with natural organic blending
shader_type canvas_item;

uniform sampler2D lane_tex: repeat_enable, filter_linear_mipmap;
uniform sampler2D stone_tex: repeat_enable, filter_linear_mipmap;
uniform vec4 fg_color : source_color;
uniform vec4 bg_color : source_color;
uniform float tolerance : hint_range(0, 1);
uniform float lane_scale = 256.0;
uniform float stone_scale = 256.0;

varying vec2 world_position;

// Simple random function
float rand(vec2 n) { 
    return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}

// 2D Noise
float noise(vec2 p){
    vec2 ip = floor(p);
    vec2 u = fract(p);
    u = u*u*(3.0-2.0*u);
    
    float res = mix(
        mix(rand(ip),rand(ip+vec2(1.0,0.0)),u.x),
        mix(rand(ip+vec2(0.0,1.0)),rand(ip+vec2(1.0,1.0)),u.x),u.y);
    return res*res;
}

float get_seam_mask(vec2 uv) {
    vec2 f = fract(uv);
    vec2 e = smoothstep(0.0, 0.15, f) * (1.0 - smoothstep(0.85, 1.0, f));
    return e.x * e.y;
}

// Anti-tiling organic blend for the stone texture
vec4 get_organic_stone(sampler2D tex, vec2 uv) {
    vec2 uv1 = uv;
    mat2 rot1 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
    vec2 uv2 = rot1 * uv * 1.37 + vec2(0.54, 0.81);
    mat2 rot2 = mat2(vec2(-0.6, -0.8), vec2(0.8, -0.6));
    vec2 uv3 = rot2 * uv * 0.73 + vec2(0.12, 0.43);

    vec4 c1 = texture(tex, uv1);
    vec4 c2 = texture(tex, uv2);
    vec4 c3 = texture(tex, uv3);
    
    float n1 = noise(uv * 1.5);
    float n2 = noise(uv * 1.5 + vec2(12.3, 4.5));
    float n3 = noise(uv * 1.5 + vec2(7.8, -9.1));
    
    float w1 = (n1 * n1 + 0.15) * get_seam_mask(uv1);
    float w2 = (n2 * n2 + 0.15) * get_seam_mask(uv2);
    float w3 = (n3 * n3 + 0.15) * get_seam_mask(uv3);
    
    float sum = w1 + w2 + w3 + 0.001;
    return (c1 * w1 + c2 * w2 + c3 * w3) / sum;
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    vec2 lane_uv = world_position / lane_scale;
    vec2 stone_uv = world_position / stone_scale;
    
    vec4 lane_color = texture(lane_tex, lane_uv);
    vec4 stone_color = get_organic_stone(stone_tex, stone_uv);
    
    // Strict grid layout, no noise perturbation
    vec2 pert_uv = UV;
    vec4 curr_color = texture(TEXTURE, pert_uv);
    float dist_fg = distance(curr_color.rgb, fg_color.rgb);
    
    // 4-tap edge detection for thick black stroke on the stone side
    vec2 off = TEXTURE_PIXEL_SIZE * 4.0; // Stroke thickness
    
    // No noise wobble for the stroke
    vec2 stroke_uv = pert_uv;
    
    float d1 = distance(texture(TEXTURE, stroke_uv + vec2(off.x, 0.0)).rgb, fg_color.rgb);
    float d2 = distance(texture(TEXTURE, stroke_uv - vec2(off.x, 0.0)).rgb, fg_color.rgb);
    float d3 = distance(texture(TEXTURE, stroke_uv + vec2(0.0, off.y)).rgb, fg_color.rgb);
    float d4 = distance(texture(TEXTURE, stroke_uv - vec2(0.0, off.y)).rgb, fg_color.rgb);
    
    float is_stone = smoothstep(0.5, 0.8, dist_fg);
    float neighbor_stone = (d1 + d2 + d3 + d4) / 4.0;
    
    // Expanded threshold makes the line much thicker and more solid
    float stroke_mask = is_stone * (1.0 - smoothstep(0.4, 0.95, neighbor_stone));
    
    // Soft transition for natural blending (no dither noise)
    float path_weight = 1.0 - smoothstep(tolerance, tolerance + 0.5, dist_fg);
    
    vec4 final_color = mix(stone_color, lane_color, path_weight);
    
    // Apply black stroke around the drawing
    final_color.rgb = mix(final_color.rgb, vec3(0.05, 0.05, 0.05), stroke_mask * 0.85);
    
    final_color.a = 1.0;
    COLOR = final_color;
}