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
	
	// Nexus
	vec2 nexus_pos;
	float nexus_radius;
	uint nexus_valid;
	
	// Type damage map (up to 6 types)
	uint type_nexus_dmg[6];

	// Nexus arrival box half-extents (world units). Agents arrive/damage anywhere in
	// this rect, matching the flow target seed (whole bar), not just a centre circle.
	vec2 nexus_extents;
} params;

// === Data Structures ===
struct Agent {
	vec2 pos;
	vec2 vel;
	int health;
	float max_speed;
	float scale;
	uint type;
	float freeze_timer;
	int flash_amount;
	int speed_modifier;
	uint pad0;
}; // 12 floats = 48 bytes

// === Buffers ===
// Binding 0: Agents
layout(set = 0, binding = 0, std430) restrict buffer AgentBufferIn {
	Agent agents_in[];
};
layout(set = 0, binding = 11, std430) restrict buffer AgentBufferOut {
	Agent agents_out[];
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

// Binding 5: Agent Data Texture (for rendering)
layout(set = 0, binding = 5, rgba32f) restrict writeonly uniform image2D agent_data_tex;

// Binding 12: SDF JFA Texture
layout(set = 0, binding = 12) uniform sampler2D sdf_field;

#include "res://shaders/sdf_solver.gdshaderinc"

// Binding 6: Dead Enemies
layout(set = 0, binding = 6, std430) buffer DeadEnemiesBuffer {
	uint dead_last_write; // offset 0
	uint dead_pad0, dead_pad1, dead_pad2; // offset 4, 8, 12
	uint dead_data[]; // offset 16
};

// Binding 7: Nexus Damage
layout(set = 0, binding = 7, std430) buffer NexusDamageBuffer {
	uint nexus_last_write; // offset 0
	uint nexus_damage_values[]; // offset 4
};

struct DamageEvent {
	vec2 pos;
	float radius;
	float damage;
	uint effect_type;  // 0: Damage, 1: Slow, 2: Freeze, 3: Damage + Slow (Acid)
	float effect_value; // slow factor or freeze duration
	uint pad0;
	uint pad1;
}; // 32 bytes

// Binding 8: Damage Events
layout(set = 0, binding = 8, std430) buffer DamageEventsBuffer {
	uint event_count;
	uint dmg_pad0, dmg_pad1, dmg_pad2;
	DamageEvent damage_events[];
};

struct TurretData {
	vec2 pos;
	float range;
	float damage;
	uint target_mode;
	uint turret_type;
	float cooldown;
	float fire_rate;
	uint instance_id;
	uint padding0, padding1, padding2;
};

// Binding 9: Turrets
layout(set = 0, binding = 9, std430) buffer TurretsBuffer {
	uint turret_count;
	uint tur_pad0, tur_pad1, tur_pad2;
	TurretData turrets[];
};

// Binding 10: Turret Fire Events
layout(set = 0, binding = 10, std430) buffer TurretFireEventsBuffer {
	uint fire_last_write;
	uint fire_pad0, fire_pad1, fire_pad2;
	uint fire_data[];
};


// Hi-res obstacle/SDF subdivision: fine pixels per coarse flow cell.
// Mirrors FlowFieldManager.obs_sub (= 8) → 4 world units per obstacle pixel at
// cell_size 32. The flow field is now built at this same fine resolution, so we can
// no longer derive this ratio from textureSize(obstacle)/textureSize(flow) (== 1);
// keep it as a constant tied to the GDScript obs_sub.
const float OBS_SUB = 8.0;

// === Helper Functions ===
uint get_hash_index(vec2 pos) {
	int gx = clamp(int(floor(pos.x * params.inv_hash_cell_size)), 0, int(params.hash_width) - 1);
	int gy = clamp(int(floor(pos.y * params.inv_hash_cell_size)), 0, int(params.hash_height) - 1);
	return uint(gy * params.hash_width + gx);
}

// Resolve a circle against the high-resolution obstacle map.
// The obstacle texture has obs_sub pixels per tile (obs_sub = obs_tex_size / flow_tex_size).
// Each obs pixel = cell_size/obs_sub world units, giving sub-tile collision precision.
void resolve_circle_vs_sdf(inout vec2 pos, inout vec2 vel, float radius) {
	vec2 tex_size  = vec2(textureSize(obstacle_field, 0));
	float obs_sub  = OBS_SUB;
	float sub_world = params.cell_size / obs_sub;     // world units per obs pixel (e.g. 4)
	
	// Pixel-index range that the circle's AABB could touch
	int min_tx = int(floor((pos.x - radius) / sub_world - params.grid_offset.x * obs_sub));
	int max_tx = int(floor((pos.x + radius) / sub_world - params.grid_offset.x * obs_sub));
	int min_ty = int(floor((pos.y - radius) / sub_world - params.grid_offset.y * obs_sub));
	int max_ty = int(floor((pos.y + radius) / sub_world - params.grid_offset.y * obs_sub));

	for (int ty = min_ty; ty <= max_ty; ty++) {
		for (int tx = min_tx; tx <= max_tx; tx++) {
			if (tx < 0 || ty < 0 || tx >= int(tex_size.x) || ty >= int(tex_size.y)) continue;
			
			// Sample obstacle texture
			vec2 uv = (vec2(tx, ty) + 0.5) / tex_size;
			float is_obs = texture(obstacle_field, uv).r;
			if (is_obs < 0.5) continue;
			
			// AABB of this obs pixel in world space
			vec2 pixel_world = (vec2(tx, ty) / obs_sub + params.grid_offset) * params.cell_size;
			vec2 tile_min = pixel_world;
			vec2 tile_max = pixel_world + vec2(sub_world);
			
			// Circle vs AABB
			vec2 closest = clamp(pos, tile_min, tile_max);
			vec2 delta = pos - closest;
			float dist_sq = dot(delta, delta);
			
			if (dist_sq < radius * radius && dist_sq > 0.0001) {
				float dist = sqrt(dist_sq);
				vec2 normal = delta / dist;
				pos += normal * (radius - dist);
				
				float v_dot_n = dot(vel, normal);
				if (v_dot_n < 0.0) vel -= normal * v_dot_n;
			} else if (dist_sq <= 0.0001) {
				pos.x += radius;
			}
		}
	}
}

// Sample the fine wall-SDF (binding 12) at a world position. Returns the world-unit
// distance to the nearest wall (the field was baked in world units on the CPU). The
// SDF shares the obstacle texture's resolution/world mapping.
float sample_wall_dist(vec2 pos) {
	vec2 tex_size = vec2(textureSize(sdf_field, 0));
	float obs_sub = OBS_SUB;
	float sub_world = params.cell_size / obs_sub;
	vec2 pix = pos / sub_world - params.grid_offset * obs_sub;
	vec2 uv = (pix + 0.5) / tex_size;
	return texture(sdf_field, uv).r;
}

// Sample the fine flow field (built at obstacle resolution) at a world position.
// NEAREST (texelFetch on the agent's own fine cell), like the studio reference's
// per-pixel flow: a walkable fine cell always carries valid flow. Bilinear was tried
// and rejected — at grass/wall corners the 2x2 tap blends in wall texels (encoded as
// zero direction), weakening flow to ~0 so corner agents fall back to straight-line
// nexus steering and pin on the wall (~12 stragglers). Returns a (non-normalized)
// direction; (0,0) only if the cell is out of bounds.
// Per-agent variant: even-id agents (id&1==0) read direction from RG channels
// (variant 0, upper-route bias); odd-id agents read from BA (variant 1, lower-route
// bias). Agents assigned by id — the split is stable and persistent across frames.
vec2 sample_flow_dir(vec2 pos, uint id) {
	ivec2 tex_size = textureSize(flow_field, 0);
	float sub_world = params.cell_size / OBS_SUB;
	vec2 pix = pos / sub_world - params.grid_offset * OBS_SUB;
	ivec2 cell = ivec2(floor(pix));
	if (cell.x < 0 || cell.y < 0 || cell.x >= tex_size.x || cell.y >= tex_size.y) return vec2(0.0);
	vec4 f = texelFetch(flow_field, cell, 0);
	vec2 raw = ((id & 1u) == 0u) ? f.xy : f.zw;
	return raw * 2.0 - 1.0;
}

// Gradient of the wall-SDF (central differences) — points away from the nearest wall.
vec2 wall_gradient(vec2 pos, float eps) {
	float dx = sample_wall_dist(pos + vec2(eps, 0.0)) - sample_wall_dist(pos - vec2(eps, 0.0));
	float dy = sample_wall_dist(pos + vec2(0.0, eps)) - sample_wall_dist(pos - vec2(0.0, eps));
	return vec2(dx, dy) / (2.0 * eps);
}

// === Passes ===

void pass_clear_grid(uint id) {
	if (id < params.hash_width * params.hash_height) {
		counts[id] = 0;
	}
}

void pass_kinematics(uint id) {
	if (id >= params.active_count) return;
	
	Agent ag = agents_in[id];
	
	if (ag.health <= -9000000) return; // Dead and processed
	
	// Decay freeze_timer and speed_modifier
	if (ag.freeze_timer > 0.0) {
		ag.freeze_timer -= params.delta;
		if (ag.freeze_timer <= 0.0) {
			ag.freeze_timer = 0.0;
		} else {
			ag.speed_modifier = 0;
		}
	} else {
		if (ag.speed_modifier < 1000) {
			ag.speed_modifier = min(1000, ag.speed_modifier + int(params.delta * 400.0));
		} else if (ag.speed_modifier > 1000) {
			ag.speed_modifier = max(1000, ag.speed_modifier - int(params.delta * 400.0));
		}
	}
	
	// Decay flash_amount
	if (ag.flash_amount > 0) {
		ag.flash_amount = max(0, ag.flash_amount - int(params.delta * 16000.0));
	}
	
	if (params.nexus_valid > 0u && ag.health > 0) {
		// Arrive anywhere inside the nexus box (+ agent radius), not just within a
		// centre circle — so agents reaching the tall bar's top/edges register instead
		// of milling and overflowing into the corners.
		float arrive_margin = ag.scale * 10.0;
		vec2 ld = abs(ag.pos - params.nexus_pos);
		if (ld.x <= params.nexus_extents.x + arrive_margin &&
			ld.y <= params.nexus_extents.y + arrive_margin) {
			ag.health = 0;
			uint dmg = 0;
			if (ag.type < 6) {
				dmg = params.type_nexus_dmg[ag.type];
			}
			atomicAdd(nexus_damage_values[nexus_last_write], dmg);
			
			uint seg_offset = dead_last_write * 16384;
			uint idx = atomicAdd(dead_data[seg_offset], 1);
			if (idx < 4095) {
				dead_data[seg_offset + 4 + idx * 4 + 0] = id | 0x80000000u; // Mark as nexus death
				dead_data[seg_offset + 4 + idx * 4 + 1] = ag.type;
				dead_data[seg_offset + 4 + idx * 4 + 2] = floatBitsToUint(ag.pos.x);
				dead_data[seg_offset + 4 + idx * 4 + 3] = floatBitsToUint(ag.pos.y);
			}
			agents_in[id].health = -10000000;
			agents_in[id].freeze_timer = 0.0;
			agents_in[id].flash_amount = 0;
			agents_in[id].speed_modifier = 1000;
			
			ivec2 tex_coord = ivec2(id % 512, id / 512);
			imageStore(agent_data_tex, tex_coord, vec4(ag.pos.x, ag.pos.y, 0.0, float(ag.type)));
			return;
		}
	}
	
	if (ag.health <= 0) {
		uint seg_offset = dead_last_write * 16384;
		uint idx = atomicAdd(dead_data[seg_offset], 1);
		if (idx < 4095) {
			dead_data[seg_offset + 4 + idx * 4 + 0] = id;
			dead_data[seg_offset + 4 + idx * 4 + 1] = ag.type;
			dead_data[seg_offset + 4 + idx * 4 + 2] = floatBitsToUint(ag.pos.x);
			dead_data[seg_offset + 4 + idx * 4 + 3] = floatBitsToUint(ag.pos.y);
		}
		agents_in[id].health = -10000000;
		agents_in[id].freeze_timer = 0.0;
		agents_in[id].flash_amount = 0;
		agents_in[id].speed_modifier = 1000;
		
		ivec2 tex_coord = ivec2(id % 512, id / 512);
		imageStore(agent_data_tex, tex_coord, vec4(ag.pos.x, ag.pos.y, 0.0, float(ag.type)));
		return;
	}
	
	if (isnan(ag.pos.x) || isnan(ag.pos.y) || isinf(ag.pos.x) || isinf(ag.pos.y)) { ag.pos = vec2(0.0); }
	if (isnan(ag.vel.x) || isnan(ag.vel.y) || isinf(ag.vel.x) || isinf(ag.vel.y)) { ag.vel = vec2(0.0); }
	if (isnan(ag.scale) || isinf(ag.scale) || ag.scale <= 0.001) { ag.scale = 1.0; }
	
	// Fine flow sample — per-agent variant pick: even id → RG (variant 0), odd → BA (variant 1).
	vec2 t_dir = sample_flow_dir(ag.pos, id);
	
	if (length(t_dir) > 0.01) {
		t_dir = normalize(t_dir);
		float freq = 0.006;
		float t = params.time_msec * 0.001 * 0.4;
		float px = ag.pos.x * freq + t;
		float py = ag.pos.y * freq - t;
		vec2 curl = vec2(-sin(px) * sin(py), -cos(px) * cos(py));
		t_dir = normalize(t_dir + 0.15 * curl);
	} else if (params.nexus_valid > 0u) {
		// Zero-flow cell (no converged flow here). Steer toward the nexus, but bend the
		// direction along the wall-SDF gradient so a stranded agent rounds walls toward
		// open space instead of driving straight into a corner and pinning.
		vec2 to_nexus = params.nexus_pos - ag.pos;
		if (length(to_nexus) > 0.01) {
			t_dir = normalize(to_nexus);
			float wd = sample_wall_dist(ag.pos);
			float av = ag.scale * 10.0 + 16.0;
			if (wd < av) {
				vec2 g = wall_gradient(ag.pos, params.cell_size / OBS_SUB);
				if (length(g) > 0.001) {
					float ww = clamp((av - wd) / av, 0.0, 1.0);
					vec2 bent = t_dir + normalize(g) * (ww * 1.5);
					if (length(bent) > 0.001) t_dir = normalize(bent);
				}
			}
		}
	}

	// Wall-avoidance + track-centering via the fine wall-SDF gradient (points away from
	// the nearest wall; on a corridor the SDF ridge is the centerline, where the two
	// opposite-wall gradients cancel). Two layered terms: a STRONG shove when hugging a
	// wall (keeps agents off edges/corners), plus a WEAK, wider nudge so agents PREFER
	// the middle of the track — a preference, not a rail. Flow still dominates and the
	// separation pass spreads agents across the width.
	{
		float wdist = sample_wall_dist(ag.pos);
		vec2 grad = wall_gradient(ag.pos, params.cell_size / OBS_SUB);
		if (length(grad) > 0.001) {
			grad = normalize(grad);
			float avoid = ag.scale * 10.0 + 16.0;   // tight wall-hug band (strong)
			float center_range = 96.0;              // soft centering band (gentle)
			float avoid_w  = clamp((avoid - wdist) / avoid, 0.0, 1.0) * 1.5;
			float center_w = clamp((center_range - wdist) / center_range, 0.0, 1.0) * 0.35;
			vec2 steered = t_dir + grad * (avoid_w + center_w);
			if (length(steered) > 0.001) {
				t_dir = normalize(steered);
			}
		}
	}


	float sm = float(ag.speed_modifier) / 1000.0;
	float current_speed = ag.max_speed * sm;
	vec2 vel = ag.vel;
	
	float lf = 6.0 * params.delta;
	vel = vel + (t_dir * current_speed - vel) * lf;
	
	vec2 desired_step = vel * params.delta;
	vec2 target_pos = ag.pos + desired_step;
	float radius = ag.scale * 10.0;
	resolve_circle_vs_sdf(target_pos, vel, radius);

	if (isnan(target_pos.x) || isnan(target_pos.y)) { target_pos = vec2(0.0); }
	if (isnan(vel.x) || isnan(vel.y)) { vel = vec2(0.0); }

	agents_in[id].pos = target_pos;
	agents_in[id].vel = vel;
	agents_in[id].health = ag.health;
	agents_in[id].freeze_timer = ag.freeze_timer;
	agents_in[id].flash_amount = ag.flash_amount;
	agents_in[id].speed_modifier = ag.speed_modifier;
}

void pass_binning(uint id) {
	if (id >= params.active_count) return;
	Agent ag = agents_in[id];
	if (ag.health <= 0) return;
	
	uint cell_idx = get_hash_index(ag.pos);
	uint local_idx = atomicAdd(counts[cell_idx], 1);
	if (local_idx < 32) {
		cells[cell_idx * 32 + local_idx] = id;
	}
}
void pass_separation(uint id) {
	if (id >= params.active_count) {
		return;
	}
	
	Agent ag = agents_in[id];
	if (ag.health <= 0) {
		return;
	}

	// Ghosting agents (kinematics is marching them collisionlessly toward the nexus to
	// escape a stuck pocket) bypass separation entirely — otherwise its wall resolve
	// would eject them back out of the wall and undo the phasing. Pass pos/vel through.
	if ((ag.pad0 & 0x80000000u) != 0u) {
		agents_out[id].pos = ag.pos;
		agents_out[id].vel = ag.vel;
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
						Agent other = agents_in[other_id];
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
							
							// Relaxed Verlet constraint projection
							float penetration = sep - dist;
							float mm = my_scale * my_scale;
							float om = other.scale * other.scale;
							float tm = mm + om;
							float weight = (tm > 0.0001) ? (om / tm) : 0.5;
							
							push += push_dir * penetration * weight * params.overlap_weight;
						}
					}
				}
			}
		}
	}
	
	if (length(push) > 0.0) {
		// Cap the maximum separation push per frame to prevent the swarm from exploding into walls
		// when density gets very high. This fixes the hollow center pathing issue.
		float max_push = max(ag.max_speed, 80.0) * params.delta * 1.5;
		if (length(push) > max_push) {
			push = normalize(push) * max_push;
		}
	}
	pos += push;
	float radius = my_scale * 12.0;
	
	// Safe check
	if (isnan(pos.x) || isnan(pos.y) || isinf(pos.x) || isinf(pos.y)) {
		pos = ag.pos;
	}
	
	vec2 temp_vel = ag.vel;
	resolve_circle_vs_sdf(pos, temp_vel, radius);
	
	// Update position and slide velocity
	ag.pos = pos;
	ag.vel = temp_vel;
	
	// Double safety check
	if (isnan(ag.pos.x) || isnan(ag.pos.y) || isinf(ag.pos.x) || isinf(ag.pos.y)) {
		ag.pos = vec2(0.0);
	}
	
	// Write to agents_out instead of agents_in to prevent race conditions (Jacobi iteration)
	agents_out[id].pos = pos;
	agents_out[id].vel = temp_vel;
}

void pass_apply_separation(uint id) {
	agents_in[id].pos = agents_out[id].pos;
	agents_in[id].vel = agents_out[id].vel;
}

void pass_multimesh(uint id) {
	if (id >= params.active_count) return;
	Agent ag = agents_in[id];
	if (ag.health <= 0) return;
	
	// Calculate animation frame
	float frame_idx = 0.0;
	float speed_sq = ag.vel.x * ag.vel.x + ag.vel.y * ag.vel.y;
	bool is_fast = ag.max_speed >= 120.0;
	float sm = float(ag.speed_modifier) / 1000.0;
	if (speed_sq > 100.0) {
		if (is_fast && sm >= 0.7) {
			frame_idx = 10.0 + mod(params.time_msec * 0.015 + float(id) * 3.0, 5.0);
		} else {
			frame_idx = 4.0 + mod(params.time_msec * 0.012 + float(id) * 3.0, 6.0);
		}
	} else {
		frame_idx = mod(params.time_msec * 0.006 + float(id) * 2.0, 4.0);
	}
	
	float final_scale = (ag.vel.x < 0.0) ? -ag.scale : ag.scale;
	float flash_amt = float(ag.flash_amount) / 1000.0;
	float type_and_frame = float(ag.type) + (floor(frame_idx) / 100.0) + (clamp(flash_amt, 0.0, 1.0) / 10000.0);
	
	ivec2 tex_coord = ivec2(id % 512, id / 512);
	imageStore(agent_data_tex, tex_coord, vec4(ag.pos.x, ag.pos.y, final_scale, type_and_frame));
}

void pass_damage(uint id) {
	if (id >= params.active_count) return;
	Agent ag = agents_in[id];
	if (ag.health <= 0) return;
	
	for (uint i = 0; i < event_count; i++) {
		DamageEvent ev = damage_events[i];
		vec2 d = ag.pos - ev.pos;
		float dsq = dot(d, d);
		if (dsq < ev.radius * ev.radius) {
			if (ev.damage > 0.0) {
				ag.health -= int(ev.damage * 100.0);
				ag.flash_amount = 1000;
			}
			
			// Apply Slow/Freeze
			if (ev.effect_type == 1) { // Slow
				ag.speed_modifier = min(ag.speed_modifier, int(ev.effect_value * 1000.0));
			} else if (ev.effect_type == 2) { // Freeze
				ag.freeze_timer = max(ag.freeze_timer, ev.effect_value);
				ag.speed_modifier = 0;
			} else if (ev.effect_type == 3) { // Damage + Slow (Acid)
				ag.speed_modifier = min(ag.speed_modifier, int(ev.effect_value * 1000.0));
			}
		}
	}
	
	if (ag.health <= 0) {
		uint seg_offset = dead_last_write * 16384;
		uint idx = atomicAdd(dead_data[seg_offset], 1);
		if (idx < 4095) {
			dead_data[seg_offset + 4 + idx * 4 + 0] = id;
			dead_data[seg_offset + 4 + idx * 4 + 1] = ag.type;
			dead_data[seg_offset + 4 + idx * 4 + 2] = floatBitsToUint(ag.pos.x);
			dead_data[seg_offset + 4 + idx * 4 + 3] = floatBitsToUint(ag.pos.y);
		}
		agents_in[id].health = -10000000;
		agents_in[id].freeze_timer = 0.0;
		agents_in[id].flash_amount = 0;
		agents_in[id].speed_modifier = 1000;
		
		ivec2 tex_coord = ivec2(id % 512, id / 512);
		imageStore(agent_data_tex, tex_coord, vec4(ag.pos.x, ag.pos.y, 0.0, float(ag.type)));
	} else {
		agents_in[id].health = ag.health;
		agents_in[id].speed_modifier = ag.speed_modifier;
		agents_in[id].freeze_timer = ag.freeze_timer;
		agents_in[id].flash_amount = ag.flash_amount;
	}
}

void pass_turret_targeting(uint t_id) {
	if (t_id >= turret_count) return;
	
	TurretData t = turrets[t_id];
	t.cooldown -= params.delta;
	
	if (t.cooldown <= 0.0) {
		// Find target
		float best_score = -1000000.0; // max score is best (e.g. max hp for STRONGEST, min dist for CLOSEST)
		uint best_target = 0xFFFFFFFFu;
		vec2 best_pos = vec2(0.0);
		
		int gx = clamp(int(floor(t.pos.x * params.inv_hash_cell_size)), 0, int(params.hash_width) - 1);
		int gy = clamp(int(floor(t.pos.y * params.inv_hash_cell_size)), 0, int(params.hash_height) - 1);
		
		int search_cells = int(ceil(t.range * params.inv_hash_cell_size));
		
		for (int dy = -search_cells; dy <= search_cells; dy++) {
			for (int dx = -search_cells; dx <= search_cells; dx++) {
				int nx = gx + dx;
				int ny = gy + dy;
				if (nx >= 0 && nx < int(params.hash_width) && ny >= 0 && ny < int(params.hash_height)) {
					uint cell_idx = uint(ny * params.hash_width + nx);
					uint cell_count = min(counts[cell_idx], 32u);
					
					for (uint i = 0; i < cell_count; i++) {
						uint a_id = cells[cell_idx * 32 + i];
						if (a_id < params.active_count) {
							Agent a = agents_in[a_id];
							if (a.health > 0) {
								vec2 to_enemy = a.pos - t.pos;
								float dsq = dot(to_enemy, to_enemy);
								if (dsq <= t.range * t.range) {
									// Check 15-degree total cone targeting (7.5 degrees half-angle)
									float sweep_angle = uintBitsToFloat(t.padding0);
									vec2 sweep_dir = vec2(cos(sweep_angle), sin(sweep_angle));
									float dot_prod = dot(to_enemy, sweep_dir);
									if (dot_prod > 0.0 && (dot_prod * dot_prod) >= 0.9829629 * dsq) {
										if (t.turret_type == 1 || t.turret_type == 2) {
											atomicAdd(agents_in[a_id].health, -int(t.damage * 100.0));
											atomicMax(agents_in[a_id].flash_amount, 1000);
											if (t.turret_type == 2) {
												atomicMin(agents_in[a_id].speed_modifier, 400);
											}
										}
										
										float score = 0.0;
										if (t.target_mode == 3) { // CLOSEST
											score = -dsq; 
										} else if (t.target_mode == 2) { // STRONGEST
											score = float(a.health) / 100.0;
										} else if (t.target_mode == 0) { // FIRST
											score = float(-a.health) / 100.0; 
										} else { // LAST
											score = float(a.health) / 100.0;
										}
										
										if (score > best_score) {
											best_score = score;
											best_target = a_id;
											best_pos = a.pos;
										}
									}
								}
							}
						}
					}
				}
			}
		}
		
		if (best_target != 0xFFFFFFFFu) {
			if (t.turret_type == 0) {
				atomicAdd(agents_in[best_target].health, -int(t.damage * 100.0));
				atomicMax(agents_in[best_target].flash_amount, 1000);
			}
			t.cooldown = t.fire_rate;
			uint seg_offset = fire_last_write * 16384;
			uint e_idx = atomicAdd(fire_data[seg_offset], 1);
			if (e_idx < 4095) {
				fire_data[seg_offset + 4 + e_idx * 4 + 0] = t.instance_id;
				fire_data[seg_offset + 4 + e_idx * 4 + 1] = best_target;
				fire_data[seg_offset + 4 + e_idx * 4 + 2] = floatBitsToUint(best_pos.x);
				fire_data[seg_offset + 4 + e_idx * 4 + 3] = floatBitsToUint(best_pos.y);
			}
		}
	}
	
	turrets[t_id] = t;
}

void main() {
	uint id = gl_GlobalInvocationID.x;
	
	if (params.pass_idx == 0) {
		pass_clear_grid(id);
	} else if (params.pass_idx == 1) {
		pass_kinematics(id);
	} else if (params.pass_idx == 2) {
		pass_binning(id);
	} else if (params.pass_idx == 3) {
		pass_separation(id);
	} else if (params.pass_idx == 4) {
		pass_apply_separation(id);
	} else if (params.pass_idx == 5) {
		pass_multimesh(id);
	} else if (params.pass_idx == 6) {
		pass_damage(id);
	} else if (params.pass_idx == 7) {
		pass_turret_targeting(id);
	}
}
