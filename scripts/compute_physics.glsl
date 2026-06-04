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

#include "res://scripts/sdf_solver.gdshaderinc"

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


// === Helper Functions ===
uint get_hash_index(vec2 pos) {
	int gx = clamp(int(floor(pos.x * params.inv_hash_cell_size)), 0, int(params.hash_width) - 1);
	int gy = clamp(int(floor(pos.y * params.inv_hash_cell_size)), 0, int(params.hash_height) - 1);
	return uint(gy * params.hash_width + gx);
}

void resolve_body_vs_sdf(inout vec2 pos, inout vec2 vel, float radius, sampler2D sdf_tex, sampler2D obstacle_field, vec2 grid_size, float cell_size, vec2 grid_offset) {
	// Convert world position to UV coordinates
	vec2 uv = (pos / cell_size - grid_offset) / grid_size;
	
	// Sample signed distance
	float dist = sample_sdf_distance(uv, sdf_tex, obstacle_field, grid_size, cell_size);
	
	// If the body intersects the wall (dist < radius)
	if (dist < radius) {
		// Estimate gradient to find direction out
		vec2 eps = 1.0 / grid_size;
		vec2 grad = estimate_sdf_gradient(uv, eps, sdf_tex, obstacle_field, grid_size, cell_size);
		
		float grad_len = length(grad);
		if (grad_len > 0.0001) {
			vec2 normal = grad / grad_len;
			
			// Push out of the wall
			float penetration = radius - dist;
			pos += normal * penetration;
			
			// Project velocity along collision normal (sliding)
			float v_dot_n = dot(vel, normal);
			if (v_dot_n < 0.0) {
				vel = vel - normal * v_dot_n;
			}
		}
	}
}

void resolve_circle_vs_sdf(inout vec2 pos, inout vec2 vel, float radius) {
	vec2 grid_size = vec2(textureSize(sdf_field, 0));
	resolve_body_vs_sdf(pos, vel, radius, sdf_field, obstacle_field, grid_size, params.cell_size, params.grid_offset);
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
		vec2 d = ag.pos - params.nexus_pos;
		if (dot(d, d) <= params.nexus_radius * params.nexus_radius) {
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
	
	vec2 ff_pos = (ag.pos / params.cell_size) - params.grid_offset;
	ivec2 tex_size = textureSize(flow_field, 0);
	ivec2 ff_cell = ivec2(floor(ff_pos));
	
	vec2 t_dir = vec2(0.0);
	if (ff_cell.x >= 0 && ff_cell.x < tex_size.x && ff_cell.y >= 0 && ff_cell.y < tex_size.y) {
		vec4 f_val = texelFetch(flow_field, ff_cell, 0);
		t_dir = f_val.xy * 2.0 - 1.0; 
	}
	
	if (length(t_dir) > 0.01) {
		t_dir = normalize(t_dir);
		float freq = 0.006;
		float t = params.time_msec * 0.001 * 0.4;
		float px = ag.pos.x * freq + t;
		float py = ag.pos.y * freq - t;
		vec2 curl = vec2(-sin(px) * sin(py), -cos(px) * cos(py));
		t_dir = normalize(t_dir + 0.15 * curl);
	}
	
	float sm = float(ag.speed_modifier) / 1000.0;
	float current_speed = ag.max_speed * sm;
	vec2 vel = ag.vel;
	
	float lf = 6.0 * params.delta;
	vel = vel + (t_dir * current_speed - vel) * lf;
	
	vec2 target_pos = ag.pos + vel * params.delta;
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
		agents_out[id] = ag;
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
	float radius = my_scale * 10.0;
	
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
	if (isnan(ag.vel.x) || isnan(ag.vel.y) || isinf(ag.vel.x) || isinf(ag.vel.y)) {
		ag.vel = vec2(0.0);
	}
	
	// Write back
	agents_out[id].pos = pos;
	agents_out[id].vel = temp_vel;
	agents_out[id].health = ag.health;
	agents_out[id].max_speed = ag.max_speed;
	agents_out[id].scale = ag.scale;
	agents_out[id].type = ag.type;
	agents_out[id].freeze_timer = ag.freeze_timer;
	agents_out[id].flash_amount = ag.flash_amount;
	agents_out[id].speed_modifier = ag.speed_modifier;
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
		pass_multimesh(id);
	} else if (params.pass_idx == 5) {
		pass_damage(id);
	} else if (params.pass_idx == 6) {
		pass_turret_targeting(id);
	}
}
