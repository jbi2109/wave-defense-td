#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(push_constant, std430) uniform Params {
	uint pass_idx;      // 0: Seed SDF, 1: JFA pass, 2: Seed Flow, 3: Extend Flow, 4: Finalize Flow
	uint step_size;     // For JFA
	vec2 target_pos;    // World pos of target (nexus)
	
	vec2 grid_offset;
	float cell_size;
	uint grid_width;
	uint grid_height;
	uint _pad;
	vec2 target_extents;
	uint use_density_penalty;
} params;

layout(set = 0, binding = 0) uniform sampler2D obstacle_tex;
layout(set = 0, binding = 1) uniform sampler2D density_tex;

// Ping pong buffers for SDF (Jump Flood)
layout(set = 0, binding = 2, rg32f) uniform restrict image2D sdf_ping;
layout(set = 0, binding = 3, rg32f) uniform restrict image2D sdf_pong;

// Ping pong buffers for Flow Field (cost field)
layout(set = 1, binding = 0, r32f) uniform restrict image2D flow_ping;
layout(set = 1, binding = 1, r32f) uniform restrict image2D flow_pong;

// Final flow vectors
layout(set = 1, binding = 2, rgba8) uniform restrict writeonly image2D flow_result_tex;

const float MAX_DIST = 999999.0;
const float MAX_COST = 65535.0;

void pass_seed_sdf(ivec2 gid) {
	float obs = texelFetch(obstacle_tex, gid, 0).r;
	if (obs > 0.5) {
		imageStore(sdf_ping, gid, vec4(vec2(gid), 0.0, 0.0));
	} else {
		imageStore(sdf_ping, gid, vec4(-9999.0, -9999.0, 0.0, 0.0));
	}
}

void pass_jfa(ivec2 gid) {
	vec2 best_pos = vec2(-9999.0, -9999.0);
	float min_dist = MAX_DIST;
	
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			ivec2 sample_pos = gid + ivec2(dx, dy) * int(params.step_size);
			
			if (sample_pos.x >= 0 && sample_pos.x < int(params.grid_width) && 
				sample_pos.y >= 0 && sample_pos.y < int(params.grid_height)) {
				
				vec2 seed_pos = imageLoad(sdf_ping, sample_pos).rg;
				if (seed_pos.x > -9000.0) {
					float d = distance(vec2(gid), seed_pos);
					if (d < min_dist) {
						min_dist = d;
						best_pos = seed_pos;
					}
				}
			}
		}
	}
	
	imageStore(sdf_pong, gid, vec4(best_pos, 0.0, 0.0));
}

void pass_seed_flow(ivec2 gid) {
	vec2 cell_world_pos = (vec2(gid) + params.grid_offset) * params.cell_size + vec2(params.cell_size * 0.5);
	vec2 diff = abs(cell_world_pos - params.target_pos);
	
	bool is_target = diff.x <= max(params.target_extents.x, params.cell_size * 0.5) &&
					 diff.y <= max(params.target_extents.y, params.cell_size * 0.5);
					 
	// Fallback check to clamped center cell
	ivec2 target_cell = ivec2(floor(params.target_pos / params.cell_size - params.grid_offset));
	target_cell.x = clamp(target_cell.x, 0, int(params.grid_width) - 1);
	target_cell.y = clamp(target_cell.y, 0, int(params.grid_height) - 1);
	if (!is_target && gid == target_cell) {
		is_target = true;
	}
	
	float obs = texelFetch(obstacle_tex, gid, 0).r;
	if (obs > 0.5) {
		imageStore(flow_ping, gid, vec4(MAX_COST));
	} else if (is_target) {
		imageStore(flow_ping, gid, vec4(0.0));
	} else {
		imageStore(flow_ping, gid, vec4(MAX_COST));
	}
}

void pass_extend_flow(ivec2 gid) {
	float current_cost = imageLoad(flow_ping, gid).r;
	float obs = texelFetch(obstacle_tex, gid, 0).r;
	
	if (obs > 0.5) {
		imageStore(flow_pong, gid, vec4(MAX_COST));
		return;
	}
	
	float min_cost = current_cost;
	
	// Calculate SDF-based penalty
	vec2 nearest_obs = imageLoad(sdf_ping, gid).rg;
	float penalty = 0.0;
	if (nearest_obs.x > -9000.0) {
		float dist = distance(vec2(gid), nearest_obs);
		if (dist < 1.1) {
			// Immediate neighbor (cardinal or diagonal)
			penalty = 15.0; // Approximation of CPU logic
		} else if (dist < 2.0) {
			penalty = 8.0;
		}
	}
	
	if (params.use_density_penalty > 0) {
		float d = texelFetch(density_tex, gid, 0).r * 255.0;
		penalty += min(d * 2.0, 25.0);
	}
	
	// Check neighbors
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			if (dx == 0 && dy == 0) continue;
			
			ivec2 n_pos = gid + ivec2(dx, dy);
			if (n_pos.x >= 0 && n_pos.x < int(params.grid_width) && 
				n_pos.y >= 0 && n_pos.y < int(params.grid_height)) {
				
				float n_obs = texelFetch(obstacle_tex, n_pos, 0).r;
				if (n_obs < 0.5) {
					// Extra check for diagonals to prevent corner scraping
					if (abs(dx) == 1 && abs(dy) == 1) {
						if (texelFetch(obstacle_tex, gid + ivec2(dx, 0), 0).r > 0.5 ||
							texelFetch(obstacle_tex, gid + ivec2(0, dy), 0).r > 0.5) {
							continue;
						}
					}
					
					float n_cost = imageLoad(flow_ping, n_pos).r;
					float edge_cost = (abs(dx) + abs(dy) == 1) ? 10.0 : 14.0;
					float total_cost = n_cost + edge_cost + penalty;
					
					if (total_cost < min_cost) {
						min_cost = total_cost;
					}
				}
			}
		}
	}
	
	imageStore(flow_pong, gid, vec4(min_cost));
}

void pass_finalize_flow(ivec2 gid) {
	float obs = texelFetch(obstacle_tex, gid, 0).r;
	if (obs > 0.5) {
		imageStore(flow_result_tex, gid, vec4(0.5, 0.5, 0.0, 1.0));
		return;
	}
	
	float min_cost = imageLoad(flow_ping, gid).r;
	ivec2 best_dir = ivec2(0, 0);
	
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			if (dx == 0 && dy == 0) continue;
			
			ivec2 n_pos = gid + ivec2(dx, dy);
			if (n_pos.x >= 0 && n_pos.x < int(params.grid_width) && 
				n_pos.y >= 0 && n_pos.y < int(params.grid_height)) {
				
				float n_obs = texelFetch(obstacle_tex, n_pos, 0).r;
				if (n_obs < 0.5) {
					// Prevent corner scraping
					if (abs(dx) == 1 && abs(dy) == 1) {
						if (texelFetch(obstacle_tex, gid + ivec2(dx, 0), 0).r > 0.5 ||
							texelFetch(obstacle_tex, gid + ivec2(0, dy), 0).r > 0.5) {
							continue;
						}
					}
					
					float n_cost = imageLoad(flow_ping, n_pos).r;
					if (n_cost < min_cost) {
						min_cost = n_cost;
						best_dir = ivec2(dx, dy);
					}
				}
			}
		}
	}
	
	vec2 flow_vec = vec2(0.0);
	if (best_dir != ivec2(0, 0)) {
		flow_vec = normalize(vec2(best_dir));
	}
	
	// Map [-1, 1] to [0, 1] for the texture
	vec2 mapped_flow = (flow_vec + 1.0) * 0.5;
	imageStore(flow_result_tex, gid, vec4(mapped_flow, 0.0, 1.0));
}

void main() {
	ivec2 gid = ivec2(gl_GlobalInvocationID.xy);
	if (gid.x >= params.grid_width || gid.y >= params.grid_height) return;

	if (params.pass_idx == 0) pass_seed_sdf(gid);
	else if (params.pass_idx == 1) pass_jfa(gid);
	else if (params.pass_idx == 2) pass_seed_flow(gid);
	else if (params.pass_idx == 3) pass_extend_flow(gid);
	else if (params.pass_idx == 4) pass_finalize_flow(gid);
}
