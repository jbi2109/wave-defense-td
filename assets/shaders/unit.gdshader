shader_type canvas_item;

uniform float pulse_speed = 1.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.5, 0.0, 1.0);

void fragment() {
	vec4 base_color = texture(TEXTURE, UV);
	float pulse = (sin(TIME * pulse_speed) + 1.0) * 0.5;
	COLOR = base_color + (glow_color * pulse * 0.2);
}
