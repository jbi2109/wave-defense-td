import re
import sys

def process_glsl():
    with open('scripts/compute_physics.glsl', 'r') as f:
        c = f.read()
    
    # Remove GL_EXT_shader_atomic_float
    c = re.sub(r'#extension GL_EXT_shader_atomic_float : enable\n', '', c)
    
    # Agent struct health float -> int
    c = c.replace('float health;', 'int health;')
    
    # Buffers
    c = re.sub(r'layout\(set = 0, binding = 0, std430\) restrict buffer AgentBuffer \{\s*Agent agents\[\];\s*\};', 
               '''layout(set = 0, binding = 0, std430) restrict buffer AgentBufferIn {
	Agent agents_in[];
};
layout(set = 0, binding = 13, std430) restrict buffer AgentBufferOut {
	Agent agents_out[];
};''', c)
    
    c = c.replace('float speed_modifiers[];', 'int speed_modifiers[];')
    c = c.replace('float flash_amounts[];', 'int flash_amounts[];')

    # Replace basic agents reads/writes
    c = c.replace('agents[id]', 'agents_in[id]')
    c = c.replace('agents[other_id]', 'agents_in[other_id]')
    c = c.replace('agents[a_id]', 'agents_in[a_id]')
    c = c.replace('agents[best_target]', 'agents_in[best_target]')
    
    # Fix agent health atomics in targeting
    c = c.replace('atomicAdd(agents_in[a_id].health, -t.damage);', 'atomicAdd(agents_in[a_id].health, -int(t.damage * 100.0));')
    c = c.replace('atomicAdd(agents_in[best_target].health, -t.damage);', 'atomicAdd(agents_in[best_target].health, -int(t.damage * 100.0));')
    
    # Fix atomicMin / atomicMax for flash/speed
    c = c.replace('flash_amounts[a_id] = 1.0;', 'atomicMax(flash_amounts[a_id], 1000);')
    c = c.replace('flash_amounts[best_target] = 1.0;', 'atomicMax(flash_amounts[best_target], 1000);')
    c = c.replace('speed_modifiers[a_id] = min(speed_modifiers[a_id], 0.4);', 'atomicMin(speed_modifiers[a_id], 400);')

    # pass_binning split to pass_kinematics and pass_binning
    # Let's completely replace the pass_binning code
    old_binning_start = c.find('void pass_binning(uint id)')
    old_binning_end = c.find('void pass_separation(uint id)')
    
    new_kin_bin = """void pass_kinematics(uint id) {
	if (id >= params.active_count) return;
	
	int sm_int = speed_modifiers[id];
	float sm = float(sm_int) / 1000.0;
	if (sm < 1.0) {
		sm = min(1.0, sm + params.delta * 0.4);
	} else if (sm > 1.0) {
		sm = max(1.0, sm - params.delta * 0.4);
	}
	speed_modifiers[id] = int(sm * 1000.0);
	
	int fa_int = flash_amounts[id];
	float fa = float(fa_int) / 1000.0;
	if (fa > 0.0) {
		fa = max(0.0, fa - params.delta * 16.0);
	}
	flash_amounts[id] = int(fa * 1000.0);
	
	Agent ag = agents_in[id];
	
	if (ag.health <= -9000000) return; // Dead and processed
	
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
			
			ivec2 tex_coord = ivec2(id % 256, id / 256);
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
		
		ivec2 tex_coord = ivec2(id % 256, id / 256);
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
	
	float current_speed = ag.max_speed * sm;
	vec2 vel = ag.vel;
	
	float lf = 6.0 * params.delta;
	vel = vel + (t_dir * current_speed - vel) * lf;
	
	vec2 target_pos = ag.pos + vel * params.delta;
	float radius = ag.scale * 10.0;
	resolve_circle_vs_obstacles(target_pos, vel, radius);
	
	if (isnan(target_pos.x) || isnan(target_pos.y)) { target_pos = vec2(0.0); }
	if (isnan(vel.x) || isnan(vel.y)) { vel = vec2(0.0); }
	
	agents_in[id].pos = target_pos;
	agents_in[id].vel = vel;
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
"""
    c = c[:old_binning_start] + new_kin_bin + c[old_binning_end:]

    # pass_separation rewrite to use agents_out and copy specific fields
    c = c.replace('agents_in[id] = ag;', '''agents_out[id].pos = pos;
	agents_out[id].vel = temp_vel;
	agents_out[id].health = ag.health;
	agents_out[id].max_speed = ag.max_speed;
	agents_out[id].scale = ag.scale;
	agents_out[id].type = ag.type;''')
    
    # In pass_damage, fix atomic health
    c = c.replace('ag.health -= ev.damage;', 'atomicAdd(agents_in[id].health, -int(ev.damage * 100.0));')
    c = c.replace('flash_amounts[id] = 1.0;', 'atomicMax(flash_amounts[id], 1000);')
    c = c.replace('ag.health = -100000.0;', 'agents_in[id].health = -10000000;')
    # Remove agents_in[id] = ag; from pass_damage
    c = c.replace('agents_in[id] = ag;\n}', '}')
    
    # In pass_multimesh, read flash_amounts correctly
    c = c.replace('float flash_amt = flash_amounts[id];', 'float flash_amt = float(flash_amounts[id]) / 1000.0;')
    
    # other float to int changes
    c = c.replace('isnan(ag.health) || isinf(ag.health)', 'false')
    c = c.replace('if (ag.health <= 0.0)', 'if (ag.health <= 0)')
    c = c.replace('if (ag.health > 0.0)', 'if (ag.health > 0)')
    c = c.replace('if (a.health > 0.0)', 'if (a.health > 0)')
    
    # In targeting, a.health score
    c = c.replace('score = a.health;', 'score = float(a.health) / 100.0;')
    c = c.replace('score = -a.health;', 'score = float(-a.health) / 100.0;')

    # main changes
    c = c.replace('''	} else if (params.pass_idx == 1) {
		pass_binning(id);
	} else if (params.pass_idx == 2) {''', '''	} else if (params.pass_idx == 1) {
		pass_kinematics(id);
	} else if (params.pass_idx == 2) {
		pass_binning(id);
	} else if (params.pass_idx == 3) {''')
    
    c = c.replace('''pass_separation(id);
	} else if (params.pass_idx == 3) {
		pass_multimesh(id);
	} else if (params.pass_idx == 4) {
		pass_damage(id);
	} else if (params.pass_idx == 5) {
		pass_turret_targeting(id);
	}''', '''pass_separation(id);
	} else if (params.pass_idx == 4) {
		pass_multimesh(id);
	} else if (params.pass_idx == 5) {
		pass_damage(id);
	} else if (params.pass_idx == 6) {
		pass_turret_targeting(id);
	}''')

    with open('scripts/compute_physics.glsl', 'w') as f:
        f.write(c)

def process_enemy_manager():
    with open('scripts/enemy_manager.gd', 'r') as f:
        c = f.read()

    # Float arrays to Int32 arrays
    c = c.replace('var healths = PackedFloat32Array()', 'var healths = PackedInt32Array()')
    c = c.replace('var max_healths = PackedFloat32Array()', 'var max_healths = PackedInt32Array()')
    c = c.replace('var speed_modifiers = PackedFloat32Array()', 'var speed_modifiers = PackedInt32Array()')
    c = c.replace('var flash_amounts = PackedFloat32Array()', 'var flash_amounts = PackedInt32Array()')
    
    c = c.replace('flash_amounts.fill(0.0)', 'flash_amounts.fill(0)')
    c = c.replace('flash_amounts[idx] = 0.0', 'flash_amounts[idx] = 0')
    c = c.replace('speed_modifiers[idx] = 1.0', 'speed_modifiers[idx] = 1000')

    # Add agent_buffer_rid_2 and uniform_set_b
    c = c.replace('var uniform_set: RID', 'var uniform_set: RID\\nvar uniform_set_b: RID\\nvar agent_buffer_rid_2: RID')
    
    # Init buffer 2
    init_buf = '''	agent_buffer_rid = rd.storage_buffer_create(agent_data_byte_array.size(), agent_data_byte_array)
	agent_buffer_rid_2 = rd.storage_buffer_create(agent_data_byte_array.size(), agent_data_byte_array)'''
    c = c.replace('	agent_buffer_rid = rd.storage_buffer_create(agent_data_byte_array.size(), agent_data_byte_array)', init_buf)

    # Spawn enemy float writes
    c = c.replace('bytes.encode_float(16, enemy_types[type_index].health)', 'bytes.encode_s32(16, int(enemy_types[type_index].health * 100.0))')
    c = c.replace('speed_bytes.encode_float(0, 1.0)', 'speed_bytes.encode_s32(0, 1000)')
    c = c.replace('flash_bytes.encode_float(0, 0.0)', 'flash_bytes.encode_s32(0, 0)')

    c = c.replace('''			rd.buffer_update(agent_buffer_rid, idx * AGENT_STRUCT_SIZE, AGENT_STRUCT_SIZE, bytes)''', '''			rd.buffer_update(agent_buffer_rid, idx * AGENT_STRUCT_SIZE, AGENT_STRUCT_SIZE, bytes)
			rd.buffer_update(agent_buffer_rid_2, idx * AGENT_STRUCT_SIZE, AGENT_STRUCT_SIZE, bytes)''')

    # Remove enemy copy
    c = c.replace('''				rd.buffer_copy(agent_buffer_rid, agent_buffer_rid, start_byte, dest_byte, AGENT_STRUCT_SIZE)''', '''				rd.buffer_copy(agent_buffer_rid, agent_buffer_rid, start_byte, dest_byte, AGENT_STRUCT_SIZE)
				rd.buffer_copy(agent_buffer_rid_2, agent_buffer_rid_2, start_byte, dest_byte, AGENT_STRUCT_SIZE)''')
    
    # Dead bytes update
    c = c.replace('dead_bytes.encode_float(0, -100000.0)', 'dead_bytes.encode_s32(0, -10000000)')
    c = c.replace('''			rd.buffer_update(agent_buffer_rid, active_count * AGENT_STRUCT_SIZE + 16, 4, dead_bytes)''', '''			rd.buffer_update(agent_buffer_rid, active_count * AGENT_STRUCT_SIZE + 16, 4, dead_bytes)
			rd.buffer_update(agent_buffer_rid_2, active_count * AGENT_STRUCT_SIZE + 16, 4, dead_bytes)''')

    # Push constant sizes
    c = c.replace('rd.compute_list_set_push_constant(compute_list, push_bytes, 80)', 'rd.compute_list_set_push_constant(compute_list, push_bytes, 112)')

    # Add turret size check
    add_tur = '''	if turrets.size() * 48 > turrets_byte_array.size():
		var old_size = turrets_byte_array.size()
		turrets_byte_array.resize(old_size * 2)
		var old_buf = turrets_buffer_rid
		turrets_buffer_rid = rd.storage_buffer_create(turrets_byte_array.size(), turrets_byte_array)
		RenderingServer.call_on_render_thread(func():
			if old_buf.is_valid():
				rd.buffer_copy(old_buf, turrets_buffer_rid, 0, 0, old_size)
				rd.free_rid(old_buf)
			_bindings_dirty = true
		)
		
	turret.gpu_idx = turrets.size()'''
    c = c.replace('	turret.gpu_idx = turrets.size()', add_tur)

    # Bindings creation
    update_bind = '''	var u_agent2 = RDUniform.new()
	u_agent2.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_agent2.binding = 13
	u_agent2.add_id(agent_buffer_rid_2)
	bindings.append(u_agent2)
	uniform_set = rd.uniform_set_create(bindings, shader_rid, 0)
	
	var bindings_b = bindings.duplicate()
	bindings_b[0] = RDUniform.new()
	bindings_b[0].uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	bindings_b[0].binding = 0
	bindings_b[0].add_id(agent_buffer_rid_2)
	bindings_b[12] = RDUniform.new() # Assuming agent2 is at end of original bindings before append
	bindings_b[12].uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	bindings_b[12].binding = 13
	bindings_b[12].add_id(agent_buffer_rid)
	uniform_set_b = rd.uniform_set_create(bindings_b, shader_rid, 0)'''
    c = c.replace('	uniform_set = rd.uniform_set_create(bindings, shader_rid, 0)', update_bind)
    
    # Predelete
    c = c.replace('			if uniform_set.is_valid() and rd.uniform_set_is_valid(uniform_set):\\n				rd.free_rid(uniform_set)', '''			if uniform_set.is_valid() and rd.uniform_set_is_valid(uniform_set):
				rd.free_rid(uniform_set)
			if uniform_set_b.is_valid() and rd.uniform_set_is_valid(uniform_set_b):
				rd.free_rid(uniform_set_b)''')
    c = c.replace('agent_buffer_rid, grid_counts_rid', 'agent_buffer_rid, agent_buffer_rid_2, grid_counts_rid')

    # Dispatch logic
    dispatch_replacement = '''	var current_set = uniform_set
	
	# Pass 0: Clear Grid
	push_bytes.encode_u32(0, 0)
	rd.compute_list_set_push_constant(compute_list, push_bytes, 112)
	rd.compute_list_dispatch(compute_list, grid_groups, 1, 1)
	rd.compute_list_add_barrier(compute_list)
	
	# Pass 1: Kinematics
	push_bytes.encode_u32(0, 1)
	rd.compute_list_set_push_constant(compute_list, push_bytes, 112)
	rd.compute_list_dispatch(compute_list, groups, 1, 1)
	rd.compute_list_add_barrier(compute_list)
	
	# Loop for binning + separation
	for i in range(4):
		# Pass 2: Binning
		push_bytes.encode_u32(0, 2)
		rd.compute_list_set_push_constant(compute_list, push_bytes, 112)
		rd.compute_list_dispatch(compute_list, groups, 1, 1)
		rd.compute_list_add_barrier(compute_list)
		
		# Pass 3: Separation
		push_bytes.encode_u32(0, 3)
		rd.compute_list_set_push_constant(compute_list, push_bytes, 112)
		rd.compute_list_dispatch(compute_list, groups, 1, 1)
		rd.compute_list_add_barrier(compute_list)
		
		# Swap bindings
		current_set = uniform_set_b if current_set == uniform_set else uniform_set
		rd.compute_list_bind_uniform_set(compute_list, current_set, 0)
		
		# Clear grid for next binning
		if i < 3:
			push_bytes.encode_u32(0, 0)
			rd.compute_list_set_push_constant(compute_list, push_bytes, 112)
			rd.compute_list_dispatch(compute_list, grid_groups, 1, 1)
			rd.compute_list_add_barrier(compute_list)
			
	# If current_set != uniform_set, we need to bind uniform_set back for the rest of passes
	# so they read from buf1 (which holds the final data).
	if current_set != uniform_set:
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		
	# Pass 4: MultiMesh
	push_bytes.encode_u32(0, 4)
	rd.compute_list_set_push_constant(compute_list, push_bytes, 112)
	rd.compute_list_dispatch(compute_list, groups, 1, 1)
	rd.compute_list_add_barrier(compute_list)
	
	# Pass 5: Damage
	push_bytes.encode_u32(0, 5)
	rd.compute_list_set_push_constant(compute_list, push_bytes, 112)
	rd.compute_list_dispatch(compute_list, groups, 1, 1)
	rd.compute_list_add_barrier(compute_list)
	
	# Pass 6: Turrets
	push_bytes.encode_u32(0, 6)
	rd.compute_list_set_push_constant(compute_list, push_bytes, 112)
	var turret_groups = max(1, int(ceil(float(turrets.size()) / 256.0)))
	rd.compute_list_dispatch(compute_list, turret_groups, 1, 1)'''
    
    start_disp = c.find('# Pass 0: Clear Grid')
    end_disp = c.find('	rd.compute_list_end()')
    
    if start_disp != -1 and end_disp != -1:
        c = c[:start_disp] + dispatch_replacement + "\\n" + c[end_disp:]

    with open('scripts/enemy_manager.gd', 'w') as f:
        f.write(c)

process_glsl()
process_enemy_manager()
