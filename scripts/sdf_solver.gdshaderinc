// scripts/sdf_solver.gdshaderinc
// Central differences gradient estimation for sampler2D JFA textures

float sample_sdf_distance(vec2 uv, sampler2D sdf_tex, sampler2D obstacle_field, vec2 grid_size, float cell_size) {
    vec2 nearest_cell = texture(sdf_tex, uv).rg;
    if (nearest_cell.x < -9000.0) {
        return 999999.0;
    }
    vec2 curr_cell = uv * grid_size;
    float dist_cells = distance(curr_cell, nearest_cell);
    float dist_world = dist_cells * cell_size;
    float is_obs = texture(obstacle_field, uv).r;
    return (is_obs > 0.5) ? -dist_world : dist_world;
}

vec2 estimate_sdf_gradient(vec2 uv, vec2 eps, sampler2D sdf_tex, sampler2D obstacle_field, vec2 grid_size, float cell_size) {
    float dx = sample_sdf_distance(uv + vec2(eps.x, 0.0), sdf_tex, obstacle_field, grid_size, cell_size) - 
               sample_sdf_distance(uv - vec2(eps.x, 0.0), sdf_tex, obstacle_field, grid_size, cell_size);
    float dy = sample_sdf_distance(uv + vec2(0.0, eps.y), sdf_tex, obstacle_field, grid_size, cell_size) - 
               sample_sdf_distance(uv - vec2(0.0, eps.y), sdf_tex, obstacle_field, grid_size, cell_size);
    return vec2(dx, dy) / (2.0 * eps);
}
