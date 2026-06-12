// Renders a whole map's terrain from a walkable mask in one node:
// grass where mask is white (walkable path), dirt where black (wall). Both
// source textures are tiled in UV space. Used by mask-driven maps whose
// branching/maze shape can't be a single Polygon2D fill (e.g. map3).
//
// Put on a ColorRect sized to the map's world rect (UV runs 0..1 across it).
shader_type canvas_item;

uniform sampler2D mask_tex : filter_linear;                 // L8 walkable mask (white = path)
uniform sampler2D grass_tex : repeat_enable, filter_linear; // path/grass texture
uniform sampler2D dirt_tex : repeat_enable, filter_linear;  // wall/dirt texture
uniform vec2 tile_scale = vec2(13.0, 7.5);                  // texture repeats across the map

void fragment() {
	float m = texture(mask_tex, UV).r;
	vec2 tuv = UV * tile_scale;
	vec4 grass = texture(grass_tex, tuv);
	vec4 dirt = texture(dirt_tex, tuv);
	COLOR = mix(dirt, grass, step(0.5, m));
}
