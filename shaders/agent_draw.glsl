#[vertex]
#version 450

layout(push_constant, std430) uniform Params {
    vec2 camera_pos;
    vec2 viewport_size;
    float zoom;
    uint active_count;
} params;

layout(set = 0, binding = 0) uniform sampler2D agent_data_tex;

layout(location = 0) out vec2 v_uv;
layout(location = 1) flat out uint v_type;
layout(location = 2) out float v_scale;

void main() {
    uint instance = gl_InstanceIndex;
    if (instance >= params.active_count) {
        gl_Position = vec4(0.0);
        return;
    }

    ivec2 tex_coord = ivec2(instance % 512, instance / 512);
    vec4 data = texelFetch(agent_data_tex, tex_coord, 0);
    vec2 world_pos = data.xy;
    float scale = data.z;
    uint type = uint(floor(data.w + 0.0001));

    if (scale == 0.0) {
        gl_Position = vec4(0.0);
        return;
    }

    vec2 uvs[6] = vec2[](
        vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(1.0, 1.0),
        vec2(-1.0, -1.0), vec2(1.0, 1.0), vec2(-1.0, 1.0)
    );
    
    vec2 uv = uvs[gl_VertexIndex % 6];
    v_uv = uv;
    v_type = type;
    v_scale = abs(scale);

    float radius = abs(scale) * 12.0;
    vec2 local_pos = world_pos + uv * radius;
    
    vec2 screen_pos = (local_pos - params.camera_pos) * params.zoom;
    vec2 ndc = (screen_pos / params.viewport_size) * 2.0 - 1.0;
    
    gl_Position = vec4(ndc, 0.0, 1.0);
}

#[fragment]
#version 450

layout(location = 0) in vec2 v_uv;
layout(location = 1) flat in uint v_type;
layout(location = 2) in float v_scale;

layout(location = 0) out vec4 frag_color;

void main() {
    float d = length(v_uv);
    if (d > 1.0) discard;
    
    vec3 colors[6] = vec3[](
        vec3(1.0, 0.3, 0.3), // Swarmer
        vec3(0.3, 1.0, 0.3), // Spitter
        vec3(0.3, 0.3, 1.0), // Tank
        vec3(1.0, 1.0, 0.3), // Boss
        vec3(1.0, 0.3, 1.0), // Flyer
        vec3(0.3, 1.0, 1.0)  // Fast
    );
    
    vec3 col = colors[v_type % 6];
    float alpha = smoothstep(1.0, 0.85, d);
    frag_color = vec4(col, alpha);
}
