shader_type canvas_item;

uniform sampler2D noise_tex;
uniform float wind_speed = 0.5;
uniform float wind_strength = 0.05;

void fragment() {
	vec2 uv = UV + vec2(TIME * wind_speed, TIME * wind_speed * 0.5);
	float noise = texture(noise_tex, uv).r;
	vec4 base_color = texture(TEXTURE, UV);
	COLOR = mix(base_color, base_color * 1.2, noise * wind_strength);
}
