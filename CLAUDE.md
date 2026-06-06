# Wave Defense TD - Godot 4.x Project

## Commands
- Run project: Use `project_run` tool via `godot-ai` MCP server.
- Stop project: Use `project_manage(op="stop")` tool via `godot-ai` MCP server.
- Get editor state: Use `editor_state` tool via `godot-ai` MCP server.

## Project Rules & Memories
- Always use `caveman` skill with `full` intensity for all responses to maximize token efficiency and save quota.
- Must use appropriate agents and skills when required.
- Always follow global rules for this project.

## Project Structure (feature-folder layout)
Files are grouped by feature, not by type. Each entity folder holds its script(s), scene, and art together.
- `globals/` — autoload singletons (globals.gd, data.gd, global_events.gd, sound_manager.gd, save_manager.gd).
- `gpu_sim/` — GPU compute simulation autoload (GPUSim) + GPU helper class.
- `battle/` — main gameplay: battle.tscn/.gd, wave_manager, spawner, nexus, flow_field_manager, turret_placement_manager, enemy_config.
- `towers/` — turret system: turret.gd/.tscn, turret_definition.gd, art under `towers/art/`.
- `enemies/` — enemy_definition.gd + sprites under `enemies/art/`.
- `abilities/` — ability_manager/config/loadout + one subfolder per ability (`frost_nova/`, `acid_pool/`, …) holding its `*_effect.gd` and art.
- `levels/` — map scenes (`map_1.tscn`, `map_2.tscn`) + map_wave_config.gd.
- `ui/` — all menus/HUD; snake_case subfolders `main_menu/ game_over/ map_completed/ turret_ui/`.
- `fx/` — visual-effect helpers (bullet_tracer, camera_shake, damage_text_manager, range_indicator, wave_announcement, enemy_health_bars).
- `shaders/` — `.glsl` / `.gdshaderinc`.
- `assets/` — shared type-based art: `bullets/ shader/ tileset/`.
- `tools/` — Python asset-gen scripts and helper utilities.
- `_archive/` — quarantined old/dead/unused files kept for safety (review periodically; safe to delete).

## File Conventions
- **snake_case** for all files AND folders. Autoload *symbols* keep their PascalCase names (Globals, Data, GPUSim) but their files are snake_case.
- Reference in-scene nodes via `get_tree().current_scene.get_node_or_null("...")`, not hardcoded `/root/...` paths.
- **Never hand-edit `project.godot` while the Godot editor is open** — it rewrites the file from in-memory settings and reverts your changes. Change autoloads with the `autoload_manage` MCP op, project settings with `project_manage(op="settings_set")`.
- When moving files, move the `.uid`/`.import` sidecars with them and rebuild the script-class cache (trigger a filesystem scan) before relying on `class_name` lookups.

## Code Conventions
- Target Godot 4.x using Forward+ Renderer.
- Optimize systems for high performance (MultiMeshInstance2D, compute shaders).
- Maintain correct 2D depth sorting (Y-sorting) in MultiMesh buffers by sorting index arrays by `positions[i].y`.
- Avoid dynamic wiggling/swaying on enemies; keep visual variety static using `visual_offsets` array.
