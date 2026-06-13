# Wave Defense TD - Godot 4.x Project

## Commands
- Run project: Use `project_run` tool via `godot-ai` MCP server.
- Stop project: Use `project_manage(op="stop")` tool via `godot-ai` MCP server.
- Get editor state: Use `editor_state` tool via `godot-ai` MCP server.

## Project Rules & Memories
- **Always use these three skills every session:**
  - `caveman` (full intensity) — for all responses, to maximize token efficiency and save quota.
  - `superpowers` — follow its skill-driven workflow (brainstorming, TDD, debugging, etc.).
  - `andrej-karpathy-skills` (karpathy-guidelines) — surgical changes, surface assumptions, avoid overcomplication.
- **Always read `docs/ARCHITECTURE.md` BEFORE starting any task** — it is the source of truth for layout, wiring, and where features go.
- **Always update `docs/ARCHITECTURE.md` when a task is finished** if the work changed structure, wiring, signals, autoloads, or known issues. Keep it accurate.
- Must use appropriate agents and skills when required.
- Always follow global rules for this project.

## Project Structure (feature-folder layout)
Files are grouped by feature, not by type. Each entity folder holds its script(s), scene, art and stat resources together.
- `globals/` — autoload singletons (globals.gd, data.gd, global_events.gd, sound_manager.gd, save_manager.gd).
- `gpu_sim/` — GPU compute simulation autoload (GPUSim) + GPU helper class. Drains the GPU death/nexus buffers every 0.2s and emits `enemy_killed`/`nexus_damaged`.
- `battle/` — main gameplay: battle.tscn/.gd, wave_manager, spawner, nexus, flow_field_manager, turret_placement_manager, enemy_config.
- `towers/` — turret system: turret.gd/.tscn, turret_definition.gd (Resource) + one `.tres` per turret in `towers/definitions/`, art under `towers/art/`.
- `enemies/` — enemy_definition.gd (Resource) + one `.tres` per enemy in `enemies/definitions/` (array order in battle.tscn = GPU type index — append only), sprites under `enemies/art/`.
- `abilities/` — ability_manager/config/loadout + one subfolder per ability (`frost_nova/`, `acid_pool/`, …) holding its `*_effect.gd` and art.
- `levels/` — map scenes (`map_1..3.tscn`), the Polygon2D piece kit (`pieces/`, `prefabs/`), and per-map `MapConfig` resources (`map_config.gd` + `map_N_config.tres`, exported as `config` on each map root: waves, base HP, starting gold).
- `ui/` — `level_selector.*` (data-driven: one card per `Data.maps` entry), `settings_menu.*`, `hud/` (standalone BattleHUD scene + build menu).
- `fx/` — visual-effect helpers (bullet_tracer, camera_shake, damage_text_manager, range_indicator, wave_announcement, enemy_health_bars).
- `shaders/` — `.glsl` / `.gdshaderinc`.
- `assets/` — shared type-based art: `bullets/ shader/ tileset/`.
- `tools/` — Python asset-gen scripts and helper utilities.
- `_archive/` — quarantined old/dead/unused files, `.gdignore`d so Godot never scans it (review periodically; safe to delete).

## Hard-won runtime rules
- Never `change_scene_to_file` directly from inside a battle — use `Battle.exit_to_selector()` (changing scene mid GPU dispatch segfaults; see ARCHITECTURE §10).
- Hand-written `.tres`/`.tscn` must reference resources by path-only `ext_resource` (no hand-rolled `uid=` attrs).
- Enemy definition array order is the GPU type index — never reorder, only append.

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
