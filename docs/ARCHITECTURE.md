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
| `battle/` | The main gameplay scene and all in-battle systems. | `battle.tscn`/`battle.gd` (orchestrator), `wave_manager.gd`, `spawner.gd`/`.tscn`, `nexus.gd`/`.tscn`, `flow_field_manager.gd`, `turret_placement_manager.gd`, `enemy_config.gd`, `polygon_duck_type.gd` |
| `towers/` | Turret system + art. | `turret.gd`/`.tscn`, `turret_definition.gd`, art in `towers/art/` |
| `enemies/` | Enemy definition script + sprites. | `enemy_definition.gd`, sprites in `enemies/art/` |
| `abilities/` | Ability manager/config + one subfolder per ability (effect script + art). | `ability_manager.gd`, `ability_config.gd`, `ability_loadout.*`, `frost_nova/`, `acid_pool/`, `chain_lightning/`, `orbital_beam/`, `overdrive/`, `dynamite/` |
| `levels/` | Map scenes + wave config. | `map_1.tscn`, `map_2.tscn`, `map_wave_config.gd` (`class MapWaveConfig`) |
| `ui/` | All menus and HUD (snake_case subfolders). | `level_selector.*`, `settings_menu.*`, `hud.gd`, `hud_build_menu.gd`, `map_selector.tscn`, `main_menu/`, `game_over/`, `map_completed/`, `turret_ui/` |
| `fx/` | Visual-effect helpers (CPU nodes). | `bullet_tracer.gd`, `camera_shake.gd`, `damage_text_manager.gd`, `enemy_health_bars.gd`, `range_indicator.gd`, `wave_announcement.gd` |
| `shaders/` | Compute shaders + includes. | `compute_physics.glsl`, `compute_flow_field.glsl`, `agent_draw.glsl`, `sdf_solver.gdshaderinc`, `bindings.gdshaderinc`, `world_gen/` |
| `assets/` | Shared, type-based art (not per-entity). | `bullets/`, `shader/`, `tileset/` |
| `tools/` | Python asset-generation scripts + helpers (not shipped). | `gen_tres.py`, `gen_turrets.py`, `process_*`, `install_graphify.ps1` |
| `docs/` | Documentation (this file) + tutorial media. | `ARCHITECTURE.md`, `CONTRIBUTING.md` |
| `_archive/` | Quarantined old/dead/unused files kept for safety. | (review periodically; safe to delete) |
| `addons/` | Third-party plugins: `godot_ai`, `gamedev_ai`, `rmsmartshape`, `TileMapDual`. | — |

---

## 6. Core gameplay loop

**Orchestrator:** `battle/battle.gd` (`class Battle`, scene root `Battle`).

1. **`_ready()`** — resolve `Globals.selected_map` (default `"map1"`), instantiate the map scene from
   `Data.maps[id].scene`, run `_setup_map_logic()`, generate the flow field around the nexus, wire `WaveManager.enemy_config`,
   connect `GlobalEvents.nexus_destroyed`/`enemy_killed`, hook HUD buttons, `Globals.reset_gold()`.
2. **`_setup_map_logic()`** — reads the SmartShape map polygons (`Grass_Path`, `Dirt_Mound`, `Top_Dirt`, `Bottom_Dirt`),
   marks flow-field cells walkable/blocked, commits obstacles, and rasterizes a **high-res obstacle image**
   (multithreaded via `WorkerThreadPool`) uploaded to the GPU for wall collision.
3. **`_process(delta)`** — `_update_hud()` (polls `Globals.gold`, `wave_manager.current_wave`, `GPUSim.active_count`
   into `$HUD/Overlay/*` labels) → push flow-field + nexus data into `GPUSim.update_flow_field_textures` +
   `GPUSim.dispatch_physics` → `GPUSim.draw_agents` on the render thread → `wave_manager.tick(delta, _spawn_single_enemy)`
   → inter-wave / victory checks → update Next-Wave button + countdown label.
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
| Wave config | `levels/map_wave_config.gd` (`MapWaveConfig`) | child of `WaveManager` named by map id | `WaveManager._ready` |
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

**New map**
1. Author `levels/map_N.tscn` (SmartShape polygons named `Grass_Path`, `Dirt_Mound`, `Top_Dirt`, `Bottom_Dirt` so
   `battle._setup_map_logic` can read them).
2. Add an entry to `Data.maps` in `globals/data.gd` (name, `scene` path, `baseHp`, `startingGold`, `spawner_settings`).
3. Add a `MapWaveConfig` child node named with the map id under `WaveManager` in `battle.tscn` to tune waves.

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
- **Broken / missing asset refs:** `ui/main_menu/main_menu.tscn` references a missing `assets/menu/bg.png`;
  several `assets/tileset/*.tres` point at `res://assets/<file>.png` that should be `res://assets/tileset/<file>.png`.
- **Dead / quirky data:** `Data.enemies` (the `redDino`/`blueDino`… dict) is unused — the live enemy data is the
  `EnemyDefinition` child nodes. In `Data.maps`, `map1` and `map2` point at **swapped** scene files
  (`map1` → `map_2.tscn`, `map2` → `map_1.tscn`).
- **`_archive/`** holds quarantined old/dead files (dead enemy `.tres`, root scene strays, scratch scripts, `world_gen.gd`).
  Review and delete when you're confident they're not needed.

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
| `levels/map_wave_config.gd` (`MapWaveConfig`) | Per-map wave tuning. |
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
