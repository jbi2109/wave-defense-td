#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

// === Push Constants ===
layout(push_constant, std430) uniform Params {
	uint pass_idx;      // 0: clear grid, 1: binning & kinematics, 2: separation & multimesh, 3: damage
	uint active_count;
	float delta;
	float time_msec;
	
	// Grid params
	vec2 grid_offset; // the offset of the flow field grid
	float cell_size;  // 32.0 typically
	float inv_cell_size;
	
	// Spatial Hash
	uint hash_width;
	uint hash_height;
	float hash_cell_size;
	float inv_hash_cell_size;
	
	float separation_multiplier;
	float overlap_weight;
	
	// Explosion event
	vec2 explosion_pos;
	float explosion_radius;
	float explosion_damage;
} params;

// === Data Structures ===
struct Agent {
	vec2 pos;
	vec2 vel;
	float health;
	float max_speed;
	float scale;
	uint type;
}; // 8 floats = 32 bytes

// === Buffers ===
// Binding 0: Agents
layout(set = 0, binding = 0, std430) restrict buffer AgentBuffer {
	Agent agents[];
};

// Binding 1: Spatial Hash Counts
layout(set = 0, binding = 1, std430) restrict buffer GridCounts {
	uint counts[];
};

// Binding 2: Spatial Hash Cells (Hard-capped size)
// Max agents per cell = 32. size = hash_width * hash_height * 32
layout(set = 0, binding = 2, std430) restrict buffer GridCells {
	uint cells[];
};

// === Textures ===
// Binding 3: Flow Field Texture
layout(set = 0, binding = 3) uniform sampler2D flow_field;

// Binding 4: Obstacle Texture
layout(set = 0, binding = 4) uniform sampler2D obstacle_field;

// Binding 5: Speed Modifiers
layout(set = 0, binding = 5, std430) buffer SpeedModifierBuffer {
	float speed_modifiers[];
};

// === Helper Functions ===
uint get_hash_index(vec2 pos) {
	int gx = clamp(int(floor(pos.x * params.inv_hash_cell_size)), 0, int(params.hash_width) - 1);
	int gy = clamp(int(floor(pos.y * params.inv_hash_cell_size)), 0, int(params.hash_height) - 1);
	return uint(gy * params.hash_width + gx);
}

void resolve_circle_vs_obstacles(inout vec2 pos, inout vec2 vel, float radius) {
	ivec2 tex_size = textureSize(obstacle_field, 0);
	
	// 2 iterations for clean corner resolution
	for (int iter = 0; iter < 2; iter++) {
		vec2 ff_pos = (pos / params.cell_size) - params.grid_offset;
		ivec2 center_cell = ivec2(floor(ff_pos));
		
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				ivec2 cell = center_cell + ivec2(dx, dy);
				if (cell.x >= 0 && cell.x < tex_size.x && cell.y >= 0 && cell.y < tex_size.y) {
					float is_obs = texelFetch(obstacle_field, cell, 0).r;
					if (is_obs > 0.5) {
						vec2 cell_min = (vec2(cell) + params.grid_offset) * params.cell_size;
						vec2 cell_max = cell_min + vec2(params.cell_size);
						
						if (pos.x >= cell_min.x && pos.x <= cell_max.x && pos.y >= cell_min.y && pos.y <= cell_max.y) {
							// Center is inside the obstacle cell! Push it out to the nearest edge.
							float dl = pos.x - cell_min.x;
							float dr = cell_max.x - pos.x;
							float dt = pos.y - cell_min.y;
							float db = cell_max.y - pos.y;
							
							float min_d = min(min(dl, dr), min(dt, db));
							vec2 normal;
							if (min_d == dl) {
								normal = vec2(-1.0, 0.0);
							} else if (min_d == dr) {
								normal = vec2(1.0, 0.0);
							} else if (min_d == dt) {
								normal = vec2(0.0, -1.0);
							} else {
								normal = vec2(0.0, 1.0);
							}
							
							pos += normal * (min_d + radius);
							
							// Project velocity along collision normal (sliding)
							float v_dot_n = dot(vel, normal);
							if (v_dot_n < 0.0) {
								vel = vel - normal * v_dot_n;
							}
						} else {
							vec2 closest = clamp(pos, cell_min, cell_max);
							vec2 diff = pos - closest;
							float dsq = dot(diff, diff);
							
							if (dsq < radius * radius) {
								float dist = sqrt(dsq);
								vec2 normal;
								float penetration;
								
								if (dist < 0.0001) {
									normal = vec2(0.0, -1.0);
									penetration = radius;
								} else {
									normal = diff / dist;
									penetration = radius - dist;
								}
								pos += normal * penetration;
								
								// Project velocity along collision normal (sliding)
								float v_dot_n = dot(vel, normal);
								if (v_dot_n < 0.0) {
									vel = vel - normal * v_dot_n;
								}
							}
						}
					}
				}
			}
		}
	}
}

// === Passes ===

void pass_clear_grid(uint id) {
	if (id < params.hash_width * params.hash_height) {
		counts[id] = 0;
	}
}

void pass_binning(uint id) {
	if (id >= params.active_count) return;
	
	Agent ag = agents[id];
	if (isnan(ag.health) || isinf(ag.health)) {
		ag.health = 0.0;
	}
	if (ag.health <= 0.0) return; // Dead
	
	if (isnan(ag.pos.x) || isnan(ag.pos.y) || isinf(ag.pos.x) || isinf(ag.pos.y)) {
		ag.pos = vec2(0.0);
	}
	if (isnan(ag.vel.x) || isnan(ag.vel.y) || isinf(ag.vel.x) || isinf(ag.vel.y)) {
		ag.vel = vec2(0.0);
	}
	if (isnan(ag.scale) || isinf(ag.scale) || ag.scale <= 0.001) {
		ag.scale = 1.0;
	}
	
	// 1. Flow field acceleration
	// Convert world pos to flow field cell index
	vec2 ff_pos = (ag.pos / params.cell_size) - params.grid_offset;
	ivec2 tex_size = textureSize(flow_field, 0);
	ivec2 ff_cell = ivec2(floor(ff_pos));
	
	vec2 t_dir = vec2(0.0);
	if (ff_cell.x >= 0 && ff_cell.x < tex_size.x && ff_cell.y >= 0 && ff_cell.y < tex_size.y) {
		vec4 f_val = texelFetch(flow_field, ff_cell, 0);
		// Flow field texture will be encoded as R=x, G=y (from -1 to 1, mapped to 0 to 1)
		t_dir = f_val.xy * 2.0 - 1.0; 
	}
	
	if (length(t_dir) > 0.01) {
		t_dir = normalize(t_dir);
		
		// Apply minor curl noise (divergence-free perturbation) to break alignment
		float freq = 0.006;
		float t = params.time_msec * 0.001 * 0.4;
		float px = ag.pos.x * freq + t;
		float py = ag.pos.y * freq - t;
		
		vec2 curl = vec2(-sin(px) * sin(py), -cos(px) * cos(py));
		t_dir = normalize(t_dir + 0.15 * curl);
	}
	
	// Move
	float current_speed = ag.max_speed * speed_modifiers[id];
	vec2 vel = ag.vel;
	
	// Safe check
	if (isnan(vel.x) || isnan(vel.y) || isinf(vel.x) || isinf(vel.y)) {
		vel = vec2(0.0);
	}
	if (isnan(ag.pos.x) || isnan(ag.pos.y) || isinf(ag.pos.x) || isinf(ag.pos.y)) {
		ag.pos = vec2(0.0);
	}

	float lf = 6.0 * params.delta;
	vel = vel + (t_dir * current_speed - vel) * lf;
	
	vec2 target_pos = ag.pos + vel * params.delta;
	float radius = ag.scale * 10.0;
	resolve_circle_vs_obstacles(target_pos, vel, radius);
	
	ag.pos = target_pos;
	ag.vel = vel;
	
	// Double safety check
	if (isnan(ag.pos.x) || isnan(ag.pos.y) || isinf(ag.pos.x) || isinf(ag.pos.y)) {
		ag.pos = vec2(0.0);
	}
	if (isnan(ag.vel.x) || isnan(ag.vel.y) || isinf(ag.vel.x) || isinf(ag.vel.y)) {
		ag.vel = vec2(0.0);
	}
	
	agents[id] = ag;
	
	// 2. Bin into spatial hash
	uint cell_idx = get_hash_index(ag.pos);
	uint local_idx = atomicAdd(counts[cell_idx], 1);
	if (local_idx < 32) { // MAX_PER_CELL = 32
		cells[cell_idx * 32 + local_idx] = id;
	}
}

void pass_separation(uint id) {
	if (id >= params.active_count) {
		return;
	}
	
	Agent ag = agents[id];
	if (isnan(ag.health) || isinf(ag.health)) {
		ag.health = 0.0;
	}
	if (ag.health <= 0.0) {
		return;
	}
	
	if (isnan(ag.pos.x) || isnan(ag.pos.y) || isinf(ag.pos.x) || isinf(ag.pos.y)) {
		ag.pos = vec2(0.0);
	}
	if (isnan(ag.vel.x) || isnan(ag.vel.y) || isinf(ag.vel.x) || isinf(ag.vel.y)) {
		ag.vel = vec2(0.0);
	}
	if (isnan(ag.scale) || isinf(ag.scale) || ag.scale <= 0.001) {
		ag.scale = 1.0;
	}
	
	vec2 pos = ag.pos;
	float my_scale = ag.scale;
	
	// Query neighbors
	int gx = clamp(int(floor(pos.x * params.inv_hash_cell_size)), 0, int(params.hash_width) - 1);
	int gy = clamp(int(floor(pos.y * params.inv_hash_cell_size)), 0, int(params.hash_height) - 1);
	
	vec2 push = vec2(0.0);
	
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			int nx = gx + dx;
			int ny = gy + dy;
			if (nx >= 0 && nx < int(params.hash_width) && ny >= 0 && ny < int(params.hash_height)) {
				uint cell_idx = uint(ny * params.hash_width + nx);
				uint cell_count = min(counts[cell_idx], 32u);
				
				for (uint i = 0; i < cell_count; i++) {
					uint other_id = cells[cell_idx * 32 + i];
					if (other_id != id && other_id < params.active_count) {
						Agent other = agents[other_id];
						vec2 d = pos - other.pos;
						float dsq = dot(d, d);
						float sep = params.separation_multiplier * (my_scale + other.scale);
						
						if (dsq < sep * sep) {
							float dist = sqrt(dsq);
							vec2 push_dir;
							if (dist < 0.0001) {
								// Enemies stacked exactly on top of each other. Push apart based on ID to break symmetry.
								float angle = float(id % 8) * 0.785398;
								push_dir = vec2(cos(angle), sin(angle));
								dist = 0.1;
							} else {
								push_dir = d / dist;
							}
							
							// Distance-based attenuation (quadratic decay to 0 at boundary)
							float ratio = clamp(dist / sep, 0.0, 1.0);
							float atten = 1.0 - ratio;
							float smooth_factor = atten * atten;
							
							float mm = my_scale * my_scale;
							float om = other.scale * other.scale;
							float tm = mm + om;
							
							float push_mag = sep * smooth_factor * params.overlap_weight * 0.5;
							push += push_dir * push_mag * (om / tm);
						}
					}
				}
			}
		}
	}
	
	if (length(push) > 0.0) {
		// Cap the maximum separation push per frame to prevent the swarm from exploding into walls
		// when density gets very high. This fixes the hollow center pathing issue.
		float max_push = ag.max_speed * params.delta * 1.5;
		if (length(push) > max_push) {
			push = normalize(push) * max_push;
		}
	}
	pos += push;
	float radius = my_scale * 10.0;
	
	// Safe check
	if (isnan(pos.x) || isnan(pos.y) || isinf(pos.x) || isinf(pos.y)) {
		pos = ag.pos;
	}
	
	vec2 temp_vel = ag.vel;
	resolve_circle_vs_obstacles(pos, temp_vel, radius);
	
	// Update position and slide velocity
	ag.pos = pos;
	ag.vel = temp_vel;
	
	// Double safety check
	if (isnan(ag.pos.x) || isnan(ag.pos.y) || isinf(ag.pos.x) || isinf(ag.pos.y)) {
		ag.pos = vec2(0.0);
	}
	if (isnan(ag.vel.x) || isnan(ag.vel.y) || isinf(ag.vel.x) || isinf(ag.vel.y)) {
		ag.vel = vec2(0.0);
	}
	
	// Write back
	agents[id] = ag;
	
}

void pass_damage(uint id) {
	if (id >= params.active_count) return;
	Agent ag = agents[id];
	if (isnan(ag.health) || isinf(ag.health)) {
		ag.health = 0.0;
	}
	if (ag.health <= 0.0) return;
	
	vec2 d = ag.pos - params.explosion_pos;
	float dsq = dot(d, d);
	if (dsq < params.explosion_radius * params.explosion_radius) {
		ag.health -= params.explosion_damage;
		agents[id] = ag;
	}
}

void main() {
	uint id = gl_GlobalInvocationID.x;
	
	if (params.pass_idx == 0) {
		pass_clear_grid(id);
	} else if (params.pass_idx == 1) {
		pass_binning(id);
	} else if (params.pass_idx == 2) {
		pass_separation(id);
	} else if (params.pass_idx == 3) {
		pass_damage(id);
	}
}
