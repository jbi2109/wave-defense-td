# Wave Defense TD — Architecture Reference

> The single source of truth for how this project is laid out, how the pieces talk to each other,
> and where new content goes. Companion to `CLAUDE.md` (which holds the short version).
> Last reorganized into the feature-folder layout described here.

---

## 1. Overview

- **Genre:** 2D top-down, PvE wave-defense (inspired by *Sir, We Have an Orc Problem*).
- **Engine:** Godot **4.6**, **Forward+** renderer, D3D12 on Windows, Jolt physics engine selected (gameplay is 2D).
- **Performance core:** enemies are **not nodes**. They are **GPU compute agents** simulated entirely inside the
  `GPUSim` autoload (compute shaders + `RenderingDevice` buffers, drawn via MultiMesh-style GPU draw). The CPU side
  only spawns agents, feeds in textures (flow field, obstacles), and reads back aggregate state like `active_count`.

**Mental model:** `battle.tscn` is the orchestrator scene. Every frame it (1) pushes the current flow-field/obstacle
textures and nexus position into `GPUSim`, (2) dispatches the GPU physics step that moves and collides all enemies,
(3) draws them, then (4) ticks the `WaveManager` which spawns more GPU agents. Towers and abilities affect enemies by
emitting **AOE request signals** that `GPUSim` consumes and applies on the GPU. UI and economy are plain CPU nodes/state.

---

## 2. Boot & scene flow

```
project.godot main_scene
   └─ ui/level_selector.tscn         (entry; lists maps + high scores)
        └─ pick a map → sets Globals.selected_map
             └─ change_scene_to_file("res://battle/battle.tscn")
                  └─ Battle._ready(): loads the map scene from Data.maps[selected_map].scene,
                     builds the flow field, wires signals, resets gold.
                     If Globals.auto_test_active == true → auto-starts wave 1 after ~2s.
   Game over / victory → button → back to ui/level_selector.tscn
```

- Map selection UI lives in `ui/main_menu/` (`map_container`, `select_map_container`) and `ui/level_selector.*`.
- Restart and "play again" both `change_scene_to_file("res://ui/level_selector.tscn")` (see `battle/battle.gd:54-59`).

---

## 3. Autoloads (global singletons)

Registered in `project.godot` `[autoload]`. **Call them by symbol** (`Globals.gold`, `GPUSim.spawn_enemy(...)`), never by path.
Init order is the order in `project.godot`; `GPUSim` first, helpers, then state singletons.

| Symbol | File | Responsibility |
|---|---|---|
| `GPUSim` | `gpu_sim/gpu_sim.gd` | The GPU enemy simulation. Public API: `spawn_enemy(pos, type_index, type_speeds, type_scales, hp, wave_scale)`, `dispatch_physics(delta, ms, ff_data, nexus_data, t_data)`, `update_flow_field_textures(ff_tex, obs_tex, sdf)`, `draw_agents(cam_pos, viewport, zoom)`, `apply_aoe_damage/slow/freeze(...)`. Props: `active_count`, `draw_texture`. Helper class `GPU` lives in `gpu_sim/gpu.gd`. |
| `GlobalEvents` | `globals/global_events.gd` | **Signal bus** — the decoupling spine (snake_case signals). See §4. |
| `Globals` | `globals/globals.gd` | Mutable run state: economy (`gold`, `spend_gold()`, `add_gold()`, `reset_gold()`), mana (`mana`, `spend_mana()`), `equipped_abilities`, `selected_map`, `auto_test_active`, scene refs (`mainNode`, `hud`, `currentMap`). Also declares UI-facing **camelCase** signals (see §4). |
| `Data` | `globals/data.gd` | Static config dict: `maps` (live — name/scene/baseHp/startingGold/spawner_settings), `bullets`, `stats`. The `enemies` dino dict is **unused** (see §10). |
| `SoundManager` | `globals/sound_manager.gd` | Procedural SFX + audio buses. `play_sfx("wave_start" / "wave_clear" / "build" / "hit" / "defeat" / ...)`. |
| `SaveManager` | `globals/save_manager.gd` | High scores (`update_high_score(map_id, wave)`) and settings persistence. |
| `_mcp_game_helper` | `addons/godot_ai/runtime/game_helper.gd` | Editor/runtime MCP bridge (tooling only — leave alone). |

---

## 4. The signal bus & wiring

There are **two** signal systems. Both are live; they overlap and should eventually be consolidated (see §10).

### `GlobalEvents` — gameplay bus (snake_case, in `globals/global_events.gd`)

| Signal | Emitted by | Listened by |
|---|---|---|
| `wave_started(wave, count)` | `WaveManager.start_wave()` | `AbilityManager`, others |
| `wave_cleared(wave)` | `WaveManager.start_inter_wave()` | — |
| `inter_wave_tick(secs)` | `WaveManager.tick()` | — |
| `aoe_damage_requested(pos, r, dmg, is_player)` | `AbilityManager`, `acid_pool_effect` | **`GPUSim` → `apply_aoe_damage`** |
| `aoe_slow_requested(pos, r, factor)` | `AbilityManager`, `acid_pool_effect` | **`GPUSim` → `apply_aoe_slow`** |
| `aoe_freeze_requested(pos, r, dur)` | (frost abilities) | **`GPUSim` → `apply_aoe_freeze`** |
| `nexus_destroyed` | `nexus.gd` (HP ≤ 0) | `Battle._on_nexus_destroyed` (game over) |
| `nexus_damaged(amount)` | **⚠ no emitter found** | `nexus.gd._on_damaged` |
| `enemy_killed(type, pos, gold)` | **⚠ no emitter found** | `Battle._on_enemy_killed` (gold + splitter) |
| `gold_changed(amount)` | `Globals.add_gold/spend_gold` | turret UI |
| `mana_changed(cur, max)` | `Globals._process/spend_mana` | `AbilityManager`, mana bar |
| `turret_placed / turret_upgraded / turret_sold` | placement/turret | UI |
| `turret_update_requested(turret)` | (turret → GPUSim hook) | — |

### `Globals` — UI-facing signals (camelCase, in `globals/globals.gd`)

`goldChanged`, `baseHpChanged`, `waveStarted`, `waveCleared`, `enemyDestroyed`.
Connected in **`ui/hud.gd`** (`_ready`) and the turret UI. `baseHpChanged` is emitted by `nexus.gd`.

### Data-flow diagram

```
                       ┌─────────────────────────────────────────────┐
 WaveManager.tick ─────┤ Battle._spawn_single_enemy → GPUSim.spawn_enemy
                       └─────────────────────────────────────────────┘
                                          │  (GPU agents)
 Battle._process every frame:             ▼
   flow field + nexus data ──► GPUSim.dispatch_physics ──► GPUSim.draw_agents
                                          │
        ┌─────────────────────────────────┴───────────────────────────┐
        ▼ (intended, see §10 gap)                                       ▼
   GlobalEvents.enemy_killed ──► Battle._on_enemy_killed         GlobalEvents.nexus_damaged
        → Globals.add_gold + split spawn                            → nexus.gd → Globals.baseHpChanged
                                                                       → (HP 0) nexus_destroyed → game over

 Abilities / Towers ──► GlobalEvents.aoe_*_requested ──► GPUSim.apply_aoe_* (on GPU agents)
 Economy/HP/wave changes ──► Globals.* / GlobalEvents.* ──► HUD labels
```

**Node lookup convention:** scripts find in-scene nodes via `get_tree().current_scene.get_node_or_null("...")`
(the running scene root is named `Battle`). Do **not** hardcode `/root/...` paths.

---

## 5. Folder-by-folder map

| Folder | Holds | Key files |
|---|---|---|
| `globals/` | Autoload singletons (state, data, events, audio, save). | `globals.gd`, `data.gd`, `global_events.gd`, `sound_manager.gd`, `save_manager.gd` |
| `gpu_sim/` | The GPU enemy simulation autoload + its helper class. | `gpu_sim.gd` (GPUSim), `gpu.gd` (`class GPU`) |
| `battle/` | The main gameplay scene and all in-battle systems. | `battle.tscn`/`battle.gd` (orchestrator), `wave_manager.gd`, `spawner.gd`/`.tscn`, `nexus.gd`/`.tscn`, `flow_field_manager.gd`, `turret_placement_manager.gd`, `enemy_config.gd`, `polygon_duck_type.gd`, `map_wave_config.gd` |
| `towers/` | Turret system + art. | `turret.gd`/`.tscn`, `turret_definition.gd`, art in `towers/art/` |
| `enemies/` | Enemy definition script + sprites. | `enemy_definition.gd`, sprites in `enemies/art/` |
| `abilities/` | Ability manager/config + one subfolder per ability (effect script + art). | `ability_manager.gd`, `ability_config.gd`, `ability_loadout.*`, `frost_nova/`, `acid_pool/`, `chain_lightning/`, `orbital_beam/`, `overdrive/`, `dynamite/` |
| `levels/` | Map scenes + the reusable Polygon2D piece kit. | `map_1.tscn`/`map_2.tscn` — **mask-driven** (`Map1Gen`/`Map2Gen`: hand-typed `ROUTE` outline, `round_polygon`, baked `map_*_mask.png`; 1920×1080). **`map_3.tscn`** is **assembled from the piece kit** `levels/pieces/*.tscn` (~25 pieces: corridors/corners/curves/caps/T/cross, chambers round/oval/large/hex/irregular, irregular dirt/rock blobs incl. **`dirt_mound_map2`** ported from Map2) placed on a 160 grid (wide **3840×1786**); root script `kit_map.gd` (`world_size` only, no mask); walkability = group `map_path` minus `map_wall`. Composite chunks in `levels/prefabs/*.tscn` (`prefab_chamber_island`, `prefab_loop_section`). Spawn/nexus = draggable `SpawnMarker`/`NexusMarker` (`placement_marker.gd`). **No Path2D.** Generators: `tools/gen_map_pieces.py`, `gen_prefabs.py`, `assemble_map_3.py`; map1/2 bakers `gen_map_{1,2}_mask.py`. |
| `ui/` | All menus and HUD (snake_case subfolders). | `level_selector.*`, `settings_menu.*`, `hud.gd`, `hud_build_menu.gd`, `map_selector.tscn`, `main_menu/`, `game_over/`, `map_completed/`, `turret_ui/` |
| `fx/` | Visual-effect helpers (CPU nodes). | `bullet_tracer.gd`, `camera_shake.gd`, `damage_text_manager.gd`, `enemy_health_bars.gd`, `range_indicator.gd`, `wave_announcement.gd` |
| `shaders/` | Compute shaders + includes, plus canvas shaders. | `compute_physics.glsl`, `compute_flow_field.glsl`, `agent_draw.glsl`, `sdf_solver.gdshaderinc`, `bindings.gdshaderinc`, `world_gen/`; **`terrain_mask.gdshader`** (renders grass/dirt from a walkable mask; legacy — no current map uses it, maps render via Polygon2D fills/pieces). |
| `assets/` | Shared, type-based art (not per-entity). | `bullets/`, `shader/`, `tileset/` |
| `tools/` | Python asset-generation scripts + helpers (not shipped). | `gen_tres.py`, `gen_turrets.py`, `process_*`, `install_graphify.ps1` |
| `docs/` | Documentation (this file) + tutorial media. | `ARCHITECTURE.md`, `CONTRIBUTING.md` |
| `_archive/` | Quarantined old/dead/unused files kept for safety. | (review periodically; safe to delete) |
| `addons/` | Third-party plugins: `godot_ai`, `gamedev_ai`, `TileMapDual`, `kaykit_halloween_bits`. (`rmsmartshape` present but **disabled**; maps use mask-driven fills or the Polygon2D piece kit, not SmartShape.) | — |

---

## 6. Core gameplay loop

**Orchestrator:** `battle/battle.gd` (`class Battle`, scene root `Battle`).

1. **`_ready()`** — resolve `Globals.selected_map` (default `"map1"`), instantiate the map scene from
   `Data.maps[id].scene`, **`_apply_map_config()`** (see below), run `_setup_map_logic()`, generate the flow field around
   the nexus, wire `WaveManager.enemy_config`, connect `GlobalEvents.nexus_destroyed`/`enemy_killed`, hook HUD buttons,
   `Globals.reset_gold()`.
   - **`_apply_map_config(map_root)`** — optional **per-map world config**. Reads `world_size` / `spawn_pos` /
     `spawn_extents` / `nexus_pos` / `nexus_extents` from the map root (every read falls back to the `battle.tscn`
     defaults, so map1/map2 — which expose none — are unchanged). Sets `Battle.map_world_size` (the mask-UV domain,
     a `var` not a const), relocates `$Nexus` / `$EnemySpawner`, and calls **`_fit_camera()`** (zoom-only fit:
     `camera.zoom = viewport / map_world_size`, keeping the camera's FIXED_TOP_LEFT anchor at (0,0) so the GPU
     agent-draw mapping stays valid). map3 ships a wide 3840×1786 world (cover-fit, panned with left- or middle-drag); map1/map2 stay 1920×1080 at zoom 1.0.
2. **`_setup_map_logic()`** — determines the walkable region, marks flow-field cells walkable/blocked, commits obstacles,
   and rasterizes a **high-res obstacle image** (multithreaded via `WorkerThreadPool`) uploaded to the GPU for wall
   collision + SDF. Walkability comes from one of three sources, decided by `_point_walkable()` / `_gather_map_polys()`:
   - **Mask-driven ("orc way", map1/map2):** the map root provides `get_mask_image()` (white = walkable), sampled
     directly (mapped through `Battle.map_world_size`) — paint a mask, derive SDF + flow.
   - **Piece-kit union (map3 + new maps):** no mask — walkable = inside **any** Polygon2D in group `map_path` **and
     not** inside any in group `map_wall`, gathered **recursively** under the map root (so nested prefab pieces count)
     and AABB-culled. This is how kit-assembled maps work (see Map Building Pipeline).
   - **Legacy single Polygon2D:** otherwise reads named nodes `Grass_Path`/`Dirt_Mound`/`Top_Dirt`/`Bottom_Dirt`.
   Both paths feed the identical obstacle-grid → hi-res mask → `_build_wall_sdf` → GPU flow-field pipeline.
   - **Turret placement** (`turret_placement_manager.gd`) is **mask-based**: `_is_position_valid` forbids placing on
     walkable cells by sampling `flow_field.obs_image` (white = wall = OK, black = path = blocked) — accurate for any
     map shape incl. mazes/loops/islands, replacing the old single-`Grass_Path`-polygon test.
3. **`_process(delta)`** — `_update_hud()` (polls `Globals.gold`, `wave_manager.current_wave`, `GPUSim.active_count`
   into `$HUD/Overlay/*` labels) → push flow-field + nexus data into `GPUSim.update_flow_field_textures` +
   `GPUSim.dispatch_physics` → `GPUSim.draw_agents` on the render thread → `wave_manager.tick(delta, _spawn_single_enemy)`
   → inter-wave / victory checks → update Next-Wave button + countdown label.
   - **Congestion-aware repath + hybrid per-agent route splitting (all maps):** every ~2s the debug readback
     (`GPUSim.get_agent_data_async`) feeds `FlowFieldManager.update_density(positions, healths)` (blurred coarse
     density texture; dead agents filtered) and kicks `start_flow_rebuild()`. The rebuild is **amortized**:
     `tick_flow_rebuild()` (called each frame) submits ≤`rebuild_passes_per_frame` (250) extend passes per frame,
     skipping the SDF JFA (obstacles static; `_sdf_set_for_flow` persisted from load). **Both route-split variants
     are rebuilt sequentially**: variant 0 converges (writes RG), then variant 1 converges (writes BA);
     `_rebuild_active` stays true until variant 1 finalizes; agents keep the old field throughout.
     The flow shader's density penalty (`compute_flow_field.glsl`, `min(d*density_scale, density_cap)` via push
     constants at offsets 52/56) prices congested cells. The **structured vertical bias** (push offset 60 `variant`,
     offset 64 `route_bias`) adds a small y-position cost so the two variants prefer opposite halves of the map
     (variant 0 upper, variant 1 lower), splitting circle arcs and comb fingers simultaneously without oscillation
     — the static split ends the density-oscillation that pure congestion-penalty tuning cannot fix.
     Physics picks channels by `id & 1` in `sample_flow_dir(pos, id)` (`compute_physics.glsl`).
     Defaults: `density_penalty_scale=15`, `density_penalty_cap=100`, `route_split_bias=8`.
     `update_density` keeps a **decay-max density memory** (`DENSITY_RETENTION=0.65` per 2s) so lanes cool
     gradually. Other export: `rebuild_passes_per_frame` (250).
     Verified: game holds 60 FPS during rebuilds.
4. **Spawning** — `_spawn_single_enemy()` picks a spawner (group `"spawner"`), chooses a type via
   `_determine_enemy_type_to_spawn()` (boss overrides: type `5` on the final wave, type `4` on waves 5 & 10) and
   `_weighted_type_for_wave()` (weights by `spawn_weight`, gated by `min_wave`), then `GPUSim.spawn_enemy(...)`.
5. **Kills / splitting** — `_on_enemy_killed()` awards `Globals.add_gold` and spawns split children (`type_split_count`/`type_split_type`).
   *(Depends on `enemy_killed` being emitted — see §10.)*
6. **Game over / victory** — `nexus_destroyed` → `_on_nexus_destroyed()`; reaching `max_waves` with no enemies → `_on_victory()`.
   Both record a high score via `SaveManager.update_high_score`.

**Wave lifecycle:** `battle/wave_manager.gd` (`class WaveManager`). `start_wave()` computes
`enemies_for_wave()` (geometric scaling by `wave_scaler`; final wave = 1 Big Boss), spawns over time in `tick()`,
then `start_inter_wave()` runs the countdown; `skip_inter_wave()` is the "Start Early" button. Exports are overridden
per map by a `MapWaveConfig` child node.

**Economy:** `Globals.gold` mutated only through `spend_gold()` / `add_gold()` (which emit `GlobalEvents.gold_changed`).
**Mana:** regenerates in `Globals._process`; `spend_mana()` for ability costs.

**Abilities:** `abilities/ability_manager.gd` (`class AbilityManager`) builds `all_abilities` from `AbilityConfig`
resources (or a hardcoded fallback dict), loads the equipped set from `Globals.equipped_abilities`, handles cooldown/mana,
spawns the matching `abilities/<name>/<name>_effect.gd` visual, and emits `GlobalEvents.aoe_*_requested` so `GPUSim` applies
the effect to agents.

**Turrets:** `battle/turret_placement_manager.gd` (`class TurretPlacementManager`) discovers turret definitions from its
child nodes (keyed by `turret_type`), handles the place/aim state machine, and instances `towers/turret.tscn`.
`towers/turret.gd` (`class Turret`) targets agents and fires.

---

## 7. Data-driven design

Entity stats live as **child Nodes inside `battle.tscn`**, each carrying a definition script. The manager reads them at `_ready()`.

| Definition | Script (class) | Where instances live | Read by |
|---|---|---|---|
| Enemy type | `enemies/enemy_definition.gd` (`EnemyDefinition`) | children of `EnemyManager` in `battle.tscn` | `battle/enemy_config.gd` (`EnemyConfig`) → `type_healths/speeds/scales/split_*` arrays |
| Turret type | `towers/turret_definition.gd` (`TurretDefinition`) | children of `TurretPlacementManager` | `TurretPlacementManager.definitions{}` keyed by `turret_type` |
| Wave config | `battle/map_wave_config.gd` (`MapWaveConfig`) | child of `WaveManager` named by map id | `WaveManager._ready` |
| Ability | `abilities/ability_config.gd` (`AbilityConfig`, a `Resource`) | `AbilityManager.ability_configs` (or fallback dict) | `AbilityManager._initialize_abilities` |

**`EnemyDefinition` fields:** `enemy_name`, `texture_path`, `hframes`, `scale`, `speed`, `health`, `spawn_weight`,
`gold_yield`, `armor`, `nexus_damage`, `is_boss`, `min_wave`, `is_flying`, `split_count`, `split_type_index`, `death_effect`.

**`TurretDefinition` fields:** `turret_name`, `turret_type`, `damage`, `attack_range`, `fire_rate`, `scale`, `cost`,
`upgrade_cost`, `max_level`, `rotates`, `sprite_path`, plus an Upgrade Stats group.

`EnemyConfig` detects a child as an enemy type by checking `"enemy_definition" in child.get_script().resource_path`;
`TurretPlacementManager` uses the same trick with `"turret_definition"`. So the **filename of the definition script
matters** — keep them named `enemy_definition.gd` / `turret_definition.gd`.

---

## 8. Where new features go (by type)

**New enemy**
1. In `battle.tscn`, add a child `Node` under `EnemyManager`; attach `enemies/enemy_definition.gd`.
2. Set its exports (name, `health`, `speed`, `scale`, `spawn_weight`, `min_wave`, `gold_yield`, `split_*`, etc.).
3. Put its sprite in `enemies/art/` and point `texture_path` at it.
4. It auto-appears in spawning via `spawn_weight` (gated by `min_wave`). For boss behavior, see the type-index overrides in `battle.gd:_determine_enemy_type_to_spawn` (currently magic ints — see §10).

**New turret**
1. In `battle.tscn`, add a child `Node` under `TurretPlacementManager`; attach `towers/turret_definition.gd` with a unique `turret_type`.
2. Set stats/cost/upgrades; put the sprite in `towers/art/` and set `sprite_path`.
3. Surface it in the build menu — `ui/hud_build_menu.gd` and `ui/turret_ui/` (`turret_buy_container`, `turrets_panel`).
4. Firing/behavior shared by `towers/turret.gd`; add a special case there only if needed.

**New ability**
1. Create `abilities/<name>/<name>_effect.gd` (extends `Node2D`): build a sprite in `_ready`, implement `init(pos, radius)`,
   and a `_process` that advances a timer and `queue_free()`s when done. Put art in `abilities/<name>/`.
   *(A shared `base_effect.gd` is a planned refactor — see §10/background task.)*
2. In `abilities/ability_manager.gd`: `load("res://abilities/<name>/<name>_effect.gd")`, add a cast branch, and add the
   ability's stats to the `all_abilities` dict (or an `AbilityConfig` resource).
3. Add the ability name to `Globals.equipped_abilities` (and the loadout UI in `abilities/ability_loadout.*`).
4. For effects on enemies, emit `GlobalEvents.aoe_damage_requested` / `aoe_slow_requested` / `aoe_freeze_requested`;
   `GPUSim` applies them.

**New map** — three supported styles:
- *Piece kit (recommended):* drag pieces from `levels/pieces/` (+ `levels/prefabs/`) onto a `kit_map.gd` root
  (pieces already carry group `map_path`/`map_wall`), add `SpawnMarker`/`NexusMarker`. See the **Map Building
  Pipeline** below; `tools/assemble_map_3.py` is the worked example.
- *Mask-driven ("orc way"):* hand-author a `ROUTE`/`ISLAND` outline + bake a mask (map1/map2).
- *Legacy single Polygon2D:* nodes named `Grass_Path`/`Dirt_Mound`/`Top_Dirt`/`Bottom_Dirt`.

Then register (full registration — map1 is the mask example, map3 the kit example):
1. Add an entry to `Data.maps` in `globals/data.gd` (name, `scene` path, `baseHp`, `startingGold`, `spawner_settings`).
   Filenames match in-game order: id `mapN` → `map_N.tscn`.
2. Add a `MapWaveConfig` child node named with the map id under `WaveManager` in `battle.tscn` to tune waves
   (`wave_manager.gd` looks it up by id — no script change).
3. Add the map id to `SaveManager.high_scores` in `globals/save_manager.gd`.
4. Add a card to the (hardcoded) `ui/level_selector.tscn` + a `_on_mapN_selected()` handler in `level_selector.gd`.

### Map Building Pipeline (the "orc way")
Reproducible recipe for authoring a mask-driven map. Reference implementations: `map_1.tscn` +
`levels/map_1_gen.gd` + `tools/gen_map_1_mask.py` (corridor only); `map_2.tscn` + `map_2_gen.gd` +
`gen_map_2_mask.py` (corridor **+ a central island obstacle**). World rect is **1920×1080** (matches the
`Background` polygon and `Battle.MAP_WORLD_SIZE`).

**Islands / holes:** to carve an obstacle, add an `ISLAND` polygon and bake walkable =
`in(round_polygon(ROUTE)) AND NOT in(round_polygon(ISLAND))` (see `Map2Gen.bake_mask_to_file`). Render the
island as a `Dirt_Mound` Polygon2D with the rounded island polygon + dirt texture at a `z_index` **above**
`Grass_Path` (a visual hole over the grass fill); the mask already makes it a wall. The same `round_polygon`
smooths the island (its points aren't near the map edges, so the edge-square rule never triggers).

**Two map styles** (different geometry sources, one downstream pipeline):
1. *Mask-driven outline* (map1/map2) — a single closed `ROUTE` polygon (+ optional `ISLAND`s), `round_polygon`-
   filleted, baked to a B&W mask; visual is a `Grass_Path` Polygon2D (+ `Dirt_Mound`). Good for one snaking path.
2. *Piece kit* (map3 + new maps) — assemble the map from prebuilt smooth Polygon2D pieces in `levels/pieces/`
   (generated once by `tools/gen_map_pieces.py`: ~25 pieces — straight/corner/curve/cap/T/cross; chambers
   round/oval/large/hex/irregular; irregular dirt/rock blobs incl. `dirt_mound_map2` ported from Map2 — plus
   composite chunks in `levels/prefabs/` via `gen_prefabs.py`). Each piece is math-generated once (flat-capped
   stroked quads + auto-rounded bends + filled discs/blobs → `findContours`/`approxPolyDP`), shares corridor width
   160, snaps to a 160 grid, and overlaps slightly at its flat ports so the walkable union has no seams. Path
   pieces are in group `map_path`, dirt/rock in `map_wall`; the root carries `kit_map.gd` (just `world_size`).
   **No per-map mask, no baker, no Path2D** — `battle.gd` `_gather_map_polys`/`_point_walkable` derive walkability
   from the group union (recursive → nested prefab pieces count). `tools/assemble_map_3.py` is the worked example:
   it lays the top half on the grid and mirrors it with a `scale=(1,-1)` `BottomHalf` node for exact top/bottom
   symmetry, and emits `SpawnMarker`/`NexusMarker`. Edit by dragging pieces in the editor (snap 160, rotate 90°),
   or tweak the assembler and re-run. *(History: map3 was earlier a hand-drawn raster trace, then a
   stroked-centerline baker, then an OpenCV image-contour trace of `Map3.png`; all replaced by this reusable
   piece kit so maps are patched together from pre-smoothed assets instead of re-smoothed each time.)*

**Larger-than-screen maps:** export `world_size` on the map root (spawn/nexus come from draggable `SpawnMarker`/`NexusMarker`, else `spawn_pos`/`nexus_pos` exports, else `battle.tscn` defaults); `battle.gd`
`_apply_map_config` picks them up and the camera **cover-fits** (`_fit_camera`: zoom = max(viewport/world) so the world
fills the screen, no letterbox); wider worlds are explored with **left-drag or middle-drag panning + wheel zoom**
(`battle.gd _unhandled_input`, zoom clamped to [cover, cover×2.5], view clamped inside the world rect; the GPU agent
draw reads the live camera pos/zoom each frame so pan/zoom stay registered). Left-drag pan engages only past a ~6px
threshold and only while turret placement is idle (`TurretPlacementManager.is_placing()`), so it never steals a
placement/cone-edit click. The HUD-click guard in
`turret_placement_manager.gd` is screen-space (`get_viewport().get_mouse_position().y < 900`). The flow-field grid is **adaptive**:
`_apply_map_config` grows it (grow-only) to cover `world_size` via `FlowFieldManager.resize_grid` (keeps `cell_size=32`/
`obs_sub=8`, so the world↔fine-px ratio and straggler tuning are preserved; only the cell count grows; map1/map2 keep the
default 100×60 grid). map3 = 3840×1786 → grid ≈ 140×76.

1. **Define the route.** List the walkable corridor outline as a `PackedVector2Array` in world coords, and pick a
   corner radius (≈60 world units = "moderate"). See `ROUTE` / `CORNER_RADIUS` in `map_1_gen.gd`.
2. **Round the corners.** `Map1Gen.round_polygon(points, radius)` replaces each sharp vertex with a quadratic-Bezier
   fillet (clamped to half the shorter edge). Vertices on the left/right map edges (`x≈0` / `x≈WORLD width`) are kept
   **square** — these are the corridor mouths behind the spawner and the nexus, which must stay flush, not pinched.
   The same `tools/gen_map_1_mask.py` mirrors this exactly in Python.
3. **Bake the mask PNG.** Rasterize the rounded polygon to an L8 image — white = walkable, black = wall — at quarter
   world res (480×270, ≈4px/cell). Run `python tools/gen_map_1_mask.py` (reliable, offline) → writes
   `levels/map_N_mask.png` and prints the rounded polygon as a `PackedVector2Array(...)` literal.
   *(`Map1Gen.bake_mask_to_file()` does the same in-engine, but Godot `game_eval` result-marshalling is focus-gated
   and stalls on the heavy loop, so the Python baker is the practical path. Keep the two algorithms in sync.)*
   Let the editor import the new PNG (a filesystem scan generates its `.import`).
4. **Build the `.tscn`.** Root `Node2D` with script `map_1_gen.gd` (exposes `@export var mask_path: String` and
   `get_mask_image()`, which prefers the imported `Texture2D` (`ResourceLoader.load(...).get_image()`, export-safe)
   and falls back to a raw `Image.load()`). Set `mask_path` to the baked PNG. Children: `Background` Polygon2D
   (full-rect dirt texture) + `Grass_Path`
   Polygon2D (grass texture, `polygon` = the printed rounded points) + empty `Dirt_Mound`/`Top_Dirt`/`Bottom_Dirt`
   placeholders; keep `battle/polygon_duck_type.gd` on the Polygon2D nodes for the fallback interface. Give the scene
   a unique `uid://`.
5. **Runtime contract.** `battle.gd` auto-detects `get_mask_image()` via `_point_walkable()` and feeds it to
   SDF→flow — **no per-map battle edits needed**. World→mask mapping: `uv = wp / MAP_WORLD_SIZE`; points outside the
   rect are walls.
6. **Verify.** Open the scene → run `battle.tscn` with the map selected (default id `map1` loads `map_1.tscn`) →
   confirm enemies follow the rounded path and turret placement validates against walls.

**Other**
- **VFX helper** → `fx/` (CPU node spawned by gameplay).
- **Shader** → `shaders/` (update the `load("res://shaders/...")` path in `gpu_sim.gd` / `flow_field_manager.gd`).
- **UI screen** → `ui/<feature>/` (snake_case folder + files).
- **New autoload** → put the script in `globals/`, then register it with the `autoload_manage` MCP op
  (**never** hand-edit `project.godot` while the editor is open — see §9).

---

## 9. Conventions

- **snake_case** for all files and folders. Autoload **symbols** keep their PascalCase names (`Globals`, `Data`, `GPUSim`)
  but their files are snake_case (`globals.gd`, `data.gd`).
- Find in-scene nodes via `get_tree().current_scene.get_node_or_null("...")`, not `/root/...`.
- **Never hand-edit `project.godot` while the Godot editor is open** — the editor rewrites it from in-memory settings and
  reverts your change. Change autoloads with the `autoload_manage` MCP op; change project settings with
  `project_manage(op="settings_set")`.
- **Moving files:** move the `.uid` and `.import` sidecars along with the file, then trigger a filesystem scan so the
  script-class cache rebuilds before relying on `class_name` lookups. Definition-script **filenames** are load-bearing
  (`enemy_definition.gd`, `turret_definition.gd`) because discovery matches on the path substring.
- Rendering/perf rules (from `CLAUDE.md`): keep MultiMesh Y-sorting correct by sorting index arrays by `positions[i].y`;
  keep enemy visual variety static via `visual_offsets` (no per-frame wiggle).

---

## 10. Known issues / tech debt

- **Battle-teardown RID double-free — FIXED (2026-06-11).** Leaving a battle spammed "Attempted to free invalid
  ID" (`flow_field_manager._notification`, `gpu_sim.gd`) + a `battle._process` `!is_inside_tree` warning — a teardown
  ordering race (freeing a bound texture auto-invalidates its uniform set, so the later set-free double-freed). Fixes:
  `flow_field_manager._notification` frees uniform sets **before** their textures; `GPUSim.release_flow_bindings()`
  (called from `battle._exit_tree()` before the flow field tears down) drops the physics uniform set first;
  `battle._process` early-returns when `not is_inside_tree()`.
- **Map scene-UID churn — FIXED (2026-06-11).** Hand-written `.tscn` files with invalid (underscore) `uid://` strings
  made the editor reassign uids and collide map_1 with map_2 ("UID duplicate"), and freshly added scripts referenced by
  stale uid warned "invalid UID … using text path". Fixes: generated maps/pieces/prefabs use valid no-underscore uids
  (`uid://kitpiece<name>`, `uid://map3kit`, …); map_2 got a unique uid; a reimport rebuilt the uid cache.
- **Ability AOE damage upload — FIXED (2026-06-06).** Abilities (`aoe_damage/slow/freeze_requested` → `GPUSim.apply_aoe_*`)
  collected hits into `pending_damages` but **never uploaded them** to `damage_events_buffer_rid`, so the compute
  shader's `pass_damage` saw `event_count == 0` and applied nothing on **any** map (only turrets killed enemies).
  `gpu_sim.gd dispatch_physics` now serializes `pending_damages` into the 32-byte `DamageEvent` layout, `buffer_update`s
  it (with `event_count`) before the compute list, and clears `pending_damages` every frame.
- **VFX z-order / new CanvasLayers — FIXED (2026-06-06).** The GPU agents draw into a fullscreen overlay
  (`RigidbodiesTexture`) that used to sit inside the `HUD` CanvasLayer, so world-space ability effects + the AOE range
  ring (parented to `Battle`) rendered *under* the enemies. `battle.tscn` now has three layered CanvasLayers:
  `AgentLayer` (layer 1, holds the agent overlay) < `EffectsLayer` (layer 2, `follow_viewport_enabled`) < `HUD`
  (layer 3, UI). `ability_manager.gd` parents all effects + the ring to `EffectsLayer` via `_vfx_parent()`;
  `battle.gd` reads the overlay at `$AgentLayer/RigidbodiesDebug/RigidbodiesTexture`.
- **Enemy stragglers — FIXED (2026-06-06).** The coarse flow-field obstacle mask sampled one point per 32px tile
  centre, so path-edge cells were flagged blocked and got a zero flow vector while the 8x physics collision still let
  agents stand there — crowd pressure stranded enemies on those dead cells. Three layered fixes in order of effect:
  (1) `battle.gd._setup_map_logic` 3x3-multisamples each cell (walkable if any sub-point is grass-not-obstacle) so the
  flow mask matches the fine collision and path edges get real flow; (2) `compute_physics.glsl pass_kinematics` adds a
  nexus-fallback (`t_dir = normalize(nexus_pos - pos)`) for any remaining zero-flow cell; (3) `pass_kinematics`
  anti-wedge: this pass is only ever blocked by walls (agent-agent is the separation pass), so when an agent wants to
  move but the wall cancels >80% of the step it is jammed in a concave corner — it slides sideways toward the nexus
  side to round the corner instead of stalling. A small controlled batch drains fully; very high crowd counts (10000+)
  may still leave a few corner stragglers under heavy separation pressure.
- **Straggler residual — SDF wall-avoidance (2026-06-07).** Root cause is structural: the **coarse 32px flow field**
  marks a cell walkable (3×3 "any sub-point grass") while the **finer collision** (hi-res obstacle, 4px/pixel) still
  blocks most of it, so flow points into a wall on path-edge cells; separation pressure shoves lone agents there and they
  pin. Measured on a 10000-enemy wave (map2 / blob map) with a temporary stuck-counter logger (live + near-stationary
  agents via the production-safe `GPUSim.get_agent_data_async`): baseline plateaus at **~28** permanently-jammed agents
  (~0.3%). Reactive `pass_kinematics` patches were tried and **rejected** (flow-intent wedge ≈ 28; an escape probe helped
  to ~19 at a 2.5s gate but worsened to ~47 at a short gate; a nexus "squeeze" worsened to ~32). **Fix = continuous
  SDF wall-avoidance steering:** a fine signed-distance field (free-space distance to nearest wall, world units) is built
  once at map load by a CPU two-pass chamfer distance transform over the hi-res obstacle mask in
  `battle.gd._build_wall_sdf` (the GPU JFA generator `GPU.generate_sdf_tex` is unusable — its `shaders/world_gen/sdf/*.glsl`
  sources are missing), stored as `FlowFieldManager.wall_sdf_texture` (`FORMAT_RF`), passed to GPUSim as the binding-12
  `sdf_field` (was a dead binding) via `update_flow_field_textures`. In `compute_physics.glsl pass_kinematics`, agents
  within ~agent-radius of a wall bend their desired direction along the SDF gradient (away from the wall), so flow carries
  them along path centers; in narrow corridors the two opposing gradients cancel at the centre so **paths stay passable**
  (verified: 9992/10000 drain). **Result: ~28 → ~7** (~75% fewer stragglers), no corridor blockage. The remaining ~7 sit
  at degenerate concave spots where the gradient is ~0; pushing harder (weight 2.5, 2× gradient eps) gave no improvement
  (~8) so the gentler tuning was kept. Tuning lives in `pass_kinematics` (`avoid` distance, gradient `eps`, repulsion
  weight 1.5).
- **Stragglers — fine flow + whole-box nexus + iterated separation (2026-06-08).** Compared the studio game
  `Sir, we have an orc problem`: it has **no goal-seek code** — agents purely follow a flow field that **fully converges**
  over its small (≤512px) map (seeded from a goal *region*), so every walkable pixel (incl. dead-end pockets) points back
  to the goal. The derivative's coarse 32px flow converged but mismatched the 4px collision; a naive fine flow regressed
  because it could not converge cheaply. Final fix has three parts:
  (1) **Fine-resolution flow field** — `FlowFieldManager` now builds the flow textures at the hi-res collision resolution
  (`grid_size * obs_sub` = 800×480), fed the `hi_res_obs_texture`; `generate_field_gpu` uses fine push constants
  (`cell_size/obs_sub`, `grid_offset*obs_sub`) and a raised linear-extend cap (`min(total, 6000)`) so the field converges
  over the whole fine path (built once at map load; nexus is static). `compute_physics.glsl` samples it **nearest**
  (`sample_flow_dir`, via the shared `OBS_SUB=8` mapping) — bilinear was rejected because the 2×2 tap blends wall texels
  (zero dir) at grass/wall corners and weakens flow to ~0. `compute_flow_field.glsl` samples the coarse `density_tex` by
  normalized UV (it stays 100×60 while the compute runs fine).
  (2) **Whole-box nexus arrival/damage zone** — the flow target was already the full nexus rect, but the kill check was a
  64px circle around the box centre, so agents reaching the tall bar's top/edges never "arrived", milled, and overflowed
  into the top corners. `pass_kinematics` now tests the full box (`abs(pos-nexus_pos) <= nexus_extents + agent_radius`);
  `nexus_extents` is a new push-constant `vec2` (push grew 96→112 bytes, `PushAttribute` size + `dispatch_physics`
  `push.resize(112)` + encode at offset 96), fed from `nexus.extents` via `battle.gd` `nex_data`.
  (3) **Iterated separation** — `gpu_sim.gd` runs the {clear-grid, bin, separate, apply} cluster `SEPARATION_ITERATIONS=6`
  times/frame (orc-style impulse relaxation) instead of one capped nudge, so crowd pressure dissipates instead of pinning
  lone agents. (4) Zero-flow **nexus-fallback hardened**: blends the nexus direction with the wall-SDF gradient so a
  stranded agent rounds walls toward open space instead of driving straight into a corner.
  **Result on a 10000-enemy map2 wave: residual ~3 (~0.03%, 9997/10000 drain)**, down from ~12 (broken fine flow) and the
  ~7 SDF-only baseline; the top-corner pileup the player reported is gone, corridors stay passable.
  (5) **Track-centering + anti-wedge removal (2026-06-08).** The reactive `pass_kinematics` anti-wedge slide was deleted
  (fine flow + whole-box nexus made it redundant). The near-wall-only SDF steer was unified into two layered terms via the
  same wall-SDF gradient (points away from the nearest wall; on a corridor the SDF ridge is the centerline): a **strong**
  shove when hugging a wall (`avoid = scale*10+16`, weight 1.5) **plus** a **gentle, wider centering nudge**
  (`center_range = 96px`, weight 0.35) so agents *prefer* the middle of the track — a preference, not a rail (flow still
  dominates, separation spreads them across the width; the bias fades to 0 at the centerline where grad≈0). Tunables:
  `center_range`, `0.35`. **Result: the residual ~3 dropped to 0 — full 10000/10000 drain, stuck=0 on map2**, no corridor
  clog. Centering keeps agents off edges/corners so nothing strands.
  (6) **Flow-level wall-clearance cost (2026-06-08).** The runtime steering alone still let the crowd hug walls + inside
  corners, because the **flow field itself** ran shortest-path along walls: at fine resolution the old wall penalty in
  `compute_flow_field.glsl pass_extend_flow` only covered ~2 fine px (~8px) of clearance (it was tuned for the coarse grid
  where the same threshold meant ~32–64px). Replaced it with a **clearance cost ramp** using the JFA SDF distance:
  `penalty = (WALL_CLEAR - dist) * 4.0` for `dist < WALL_CLEAR` (`WALL_CLEAR = 14` fine px ≈ 56px), so cost rises toward
  walls and the min-cost path bows to the corridor **centerline** (symmetric in narrow corridors → centerline is the
  cheapest lane, still passable). This centers **all** agents at the flow level (verified on map1: sparse stream rides
  corridor centers and rounds corners through the middle, not the inside wall). A first attempt also bumped the runtime
  centering to `0.5/128`, which over-steered and reintroduced ~8 stragglers — reverted to `0.35/96`; the flow-level
  clearance does the centering, the runtime term stays a gentle assist. **Result: centered lanes AND stuck=0 (10000/10000
  drain) on map2.** Tunables: `WALL_CLEAR`, the `4.0` strength.
- **Spatial-hash dimension fix (2026-06-07).** `gpu_sim.gd dispatch_physics` hardcoded `hw=hh=256` into the push
  constant while the grid buffers are allocated at `HASH_WIDTH/HEIGHT = 128` (`HASH_CELLS`). The shader indexed
  `gy*256+gx` into a 128²-entry buffer. In-bounds for the current map (gx≤90, gy≤50, so it's a pure index bijection with
  no behavioural change — verified) but would OOB on a taller/wider map. Now uses the `HASH_WIDTH/HEIGHT` constants.
  **Testing caveat:** the godot-ai MCP `editor_screenshot(source=game)` and any render-thread `rd.buffer_get_data`
  readback during play raise `"Found open compute list at the end of the frame"` and can HALT GPUSim compute (agents
  freeze at full velocity — a probe artifact, not a game bug). Verify straggler behaviour by letting a wave run
  untouched, then taking at most ONE screenshot.
- **Two signal systems.** `Globals` camelCase (`goldChanged`, `baseHpChanged`, `waveStarted`, `waveCleared`,
  `enemyDestroyed`) feed the UI; `GlobalEvents` snake_case is the gameplay bus. They overlap (`goldChanged` vs
  `gold_changed`, `waveStarted` vs `wave_started`). Consolidating onto `GlobalEvents` is a cleanup candidate — but the
  camelCase ones are **currently connected** (`ui/hud.gd`, turret UI) so do not delete them blindly.
- **Dual HUD wiring.** `ui/hud.gd` updates `%HPLabel`/`%GoldLabel`/… from the `Globals` camelCase signals, while
  `battle.gd._update_hud()` separately polls `Globals.gold`/`wave`/`active_count` into its own inline
  `$HUD/Overlay/{GoldLabel,WaveLabel,EnemyCountLabel}`. Two parallel HUD update paths exist.
- **GPU→gameplay readback gap (verify).** `GlobalEvents.enemy_killed` and `nexus_damaged` are **declared and connected**
  (`battle.gd` listens to `enemy_killed`; `nexus.gd` listens to `nexus_damaged`) but **no code emits them**. That means
  kill-rewards-gold and enemy-reaches-nexus-damages-HP via these signals are likely **inactive**. Confirm how `GPUSim`
  reports kills and nexus hits back to the CPU (probably needs a compute-buffer readback that emits these signals).
- **Deferred refactors** (tracked as background task `task_999e220c`, need in-game playtest to verify):
  ability-effect base class (`abilities/base_effect.gd`), routing all economy through `Globals.spend_gold/add_gold`,
  and a shared enum for turret target-modes + enemy-type indices (replace the magic `4`/`5` in `battle.gd`).
- **Broken / missing asset refs — FIXED (2026-06-06).** `ui/main_menu/main_menu.tscn` no longer references the
  missing `assets/menu/bg.png` (the dead `ext_resource` + `TextureRect.texture` were removed; the `TextureRect`
  node remains with a blank texture). The eight `assets/tileset/*.tres` texture paths were corrected from
  `res://assets/<file>.png` to `res://assets/tileset/<file>.png`.
- **Dead / quirky data:** `Data.enemies` (the `redDino`/`blueDino`… dict) is unused — the live enemy data is the
  `EnemyDefinition` child nodes. (`Data.maps` id↔file mapping is now aligned: `map1` → `map_1.tscn`,
  `map2` → `map_2.tscn`.)
- **`_archive/`** holds quarantined old/dead files (dead enemy `.tres`, scratch scripts, `world_gen.gd`).
  The two root-scene stray `.tscn` (`level_selector_root_stray`, `map_2_root_stray`) were deleted on 2026-06-06 —
  they pointed at pre-refactor `res://scripts/*.gd` paths and spammed "File not found" on every editor scan.
  Review and delete the rest when you're confident they're not needed.

---

## 11. Appendix

### Major files by folder

| Path | Purpose |
|---|---|
| `gpu_sim/gpu_sim.gd` | GPUSim autoload — GPU enemy simulation, AOE application, draw. |
| `gpu_sim/gpu.gd` | `class GPU` — compute helpers (BaseCompute/SimpleCompute wrappers). |
| `globals/globals.gd` | Run state, economy, mana, equipped abilities, UI signals. |
| `globals/global_events.gd` | Gameplay signal bus. |
| `globals/data.gd` | Static config (`maps`, `bullets`, `stats`). |
| `globals/sound_manager.gd` / `save_manager.gd` | SFX / persistence. |
| `battle/battle.gd` (`Battle`) | Orchestrator: map load, flow field, per-frame GPU dispatch, spawning, win/lose. |
| `battle/wave_manager.gd` (`WaveManager`) | Wave/inter-wave lifecycle, spawn pacing. |
| `battle/enemy_config.gd` (`EnemyConfig`) | Reads enemy-type child nodes into stat arrays. |
| `battle/flow_field_manager.gd` (`FlowFieldManager`) | Flow-field + SDF + obstacle textures for the GPU. |
| `battle/turret_placement_manager.gd` (`TurretPlacementManager`) | Turret defs discovery + placement state machine. |
| `battle/nexus.gd` / `spawner.gd` | Base HP/destruction; enemy spawn points (group `"spawner"`). |
| `towers/turret.gd` (`Turret`) / `turret_definition.gd` (`TurretDefinition`) | Turret behavior / stats. |
| `enemies/enemy_definition.gd` (`EnemyDefinition`) | Enemy stat definition. |
| `abilities/ability_manager.gd` (`AbilityManager`) | Cast/cooldown/mana, spawns effects, emits AOE requests. |
| `abilities/<name>/<name>_effect.gd` | Per-ability visual + AOE emission. |
| `battle/map_wave_config.gd` (`MapWaveConfig`) | Per-map wave tuning. |
| `ui/level_selector.*` | Entry screen. `ui/hud*.gd` in-battle HUD/build menu. |
| `fx/*.gd` | Tracers, camera shake, damage text, health bars, range indicator, wave banner. |
| `shaders/compute_physics.glsl` | Main enemy physics compute (includes `sdf_solver.gdshaderinc`). |
| `shaders/compute_flow_field.glsl` / `agent_draw.glsl` | Flow-field compute / agent draw. |

### `GlobalEvents` cheat-sheet

```
Waves:    wave_started(wave,count)  wave_cleared(wave)  inter_wave_tick(secs)
Economy:  gold_changed(amount)      mana_changed(cur,max)
Nexus:    nexus_damaged(amount)*    nexus_destroyed
Enemies:  enemy_killed(type,pos,gold)*
Turrets:  turret_placed(type,pos)   turret_upgraded(node)  turret_sold(node)  turret_update_requested(node)
AOE→GPU:  aoe_damage_requested(pos,r,dmg,is_player)  aoe_slow_requested(pos,r,factor)  aoe_freeze_requested(pos,r,dur)
          (* = declared/connected but no emitter found — see §10)
```
