# Graph Report - wave-defense-td  (2026-05-27)

## Corpus Check
- 54 files · ~1,448,466 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 519 nodes · 443 edges · 80 communities (58 shown, 22 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 13 edges (avg confidence: 0.9)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `9d35f95f`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Gemini Settings IDE|Gemini Settings IDE]]
- [[_COMMUNITY_Design Patterns|Design Patterns]]
- [[_COMMUNITY_Gemini Experimental Settings|Gemini Experimental Settings]]
- [[_COMMUNITY_GitHub Settings|GitHub Settings]]
- [[_COMMUNITY_SmartShape2D|SmartShape2D]]
- [[_COMMUNITY_GameDev Documentation|GameDev Documentation]]
- [[_COMMUNITY_Inventory System|Inventory System]]
- [[_COMMUNITY_Input Management|Input Management]]
- [[_COMMUNITY_Performance & Object Pooling|Performance & Object Pooling]]
- [[_COMMUNITY_Quest System|Quest System]]
- [[_COMMUNITY_Environment Post Processing|Environment Post Processing]]
- [[_COMMUNITY_Data Management|Data Management]]
- [[_COMMUNITY_Godot AI MCP|Godot AI MCP]]
- [[_COMMUNITY_Level Generation|Level Generation]]
- [[_COMMUNITY_Project Structure|Project Structure]]
- [[_COMMUNITY_Resolution Scaling|Resolution Scaling]]
- [[_COMMUNITY_Claude Guidelines|Claude Guidelines]]
- [[_COMMUNITY_Grid Architecture|Grid Architecture]]
- [[_COMMUNITY_Contributing Guides|Contributing Guides]]
- [[_COMMUNITY_Image Processing|Image Processing]]
- [[_COMMUNITY_Agent Code Mod|Agent Code Mod]]
- [[_COMMUNITY_Health Component|Health Component]]
- [[_COMMUNITY_Dialogue Manager|Dialogue Manager]]
- [[_COMMUNITY_Save Manager|Save Manager]]
- [[_COMMUNITY_Shaders|Shaders]]
- [[_COMMUNITY_Responsive UI|Responsive UI]]
- [[_COMMUNITY_UI Styles|UI Styles]]
- [[_COMMUNITY_KayKit Assets|KayKit Assets]]
- [[_COMMUNITY_Shape Anchors|Shape Anchors]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 57|Community 57]]
- [[_COMMUNITY_Community 58|Community 58]]
- [[_COMMUNITY_Community 59|Community 59]]
- [[_COMMUNITY_Community 60|Community 60]]
- [[_COMMUNITY_Community 61|Community 61]]
- [[_COMMUNITY_Community 62|Community 62]]
- [[_COMMUNITY_Community 63|Community 63]]
- [[_COMMUNITY_Community 64|Community 64]]
- [[_COMMUNITY_Community 65|Community 65]]
- [[_COMMUNITY_Community 66|Community 66]]
- [[_COMMUNITY_Community 67|Community 67]]
- [[_COMMUNITY_Community 68|Community 68]]
- [[_COMMUNITY_Community 69|Community 69]]
- [[_COMMUNITY_Community 70|Community 70]]
- [[_COMMUNITY_Community 71|Community 71]]
- [[_COMMUNITY_Community 72|Community 72]]
- [[_COMMUNITY_Community 73|Community 73]]
- [[_COMMUNITY_Community 74|Community 74]]
- [[_COMMUNITY_Community 75|Community 75]]
- [[_COMMUNITY_Community 76|Community 76]]

## God Nodes (most connected - your core abstractions)
1. `Properties` - 15 edges
2. `TileMapDual` - 10 edges
3. `14. COMMON RECIPES` - 9 edges
4. `experimental` - 8 edges
5. `GDScript Modern Features` - 8 edges
6. `SmartShape2D - Toolbar` - 8 edges
7. `Usage` - 7 edges
8. `SmartShape2D - QuickStart` - 7 edges
9. `Edge Material` - 7 edges
10. `Godot 4.x Animation and Cutscenes Guide` - 6 edges

## Surprising Connections (you probably didn't know these)
- `Event Bus` --semantically_similar_to--> `Autoload Singleton Pattern`  [INFERRED] [semantically similar]
  addons/gamedev_ai/skills/common_architectures.md → addons/gamedev_ai/skills/gdscript_recipes_and_patterns.md
- `StateMachine` --implements--> `Finite State Machine`  [INFERRED]
  addons/gamedev_ai/skills/common_architectures.md → addons/gamedev_ai/skills/state_machine_implementation.md
- `SmartShape2D` --references--> `Shape Material`  [EXTRACTED]
  addons/rmsmartshape/documentation/Quickstart.md → addons/rmsmartshape/documentation/Resources.md

## Hyperedges (group relationships)
- **Image Processing Pipeline** — check_colors_py, clean_base_py, convert_bg_py, crop_base_py, process_new_turrets_py, remove_checkerboard_py, image_processing_concept [INFERRED 0.95]
- **GameDev AI AST Modifiers** — append_node_tools_py, patch_handlers_py, refactor_py, restore_actions_py, ai_agent_code_modification [INFERRED 0.95]
- **GameDev AI Knowledge Skills** — ai_and_pathfinding_md, animation_and_cutscenes_md, audio_management_best_practices_md, gamedev_ai_skills_concept [INFERRED 0.95]
- **Inventory Resource System** — item_data, slot_data, inventory_data [EXTRACTED 1.00]
- **SmartShape Material Hierarchy** — shape_material, edge_meta_material, edge_material [EXTRACTED 1.00]

## Communities (80 total, 22 thin omitted)

### Community 0 - "Gemini Settings IDE"
Cohesion: 0.09
Nodes (22): GITHUB_PERSONAL_ACCESS_TOKEN, experimental, autoMemory, contextManagement, gemma, generalistProfile, useOSC52Copy, useOSC52Paste (+14 more)

### Community 1 - "Design Patterns"
Cohesion: 0.25
Nodes (7): Autoload Singleton Pattern, Composition over Inheritance, Event Bus, Finite State Machine, Finite State Machine, State, StateMachine

### Community 3 - "Gemini Experimental Settings"
Cohesion: 0.08
Nodes (23): 1.x, 2.0, 2.1, 2.2, 2.x, Changes, Changes in 0.91, Changes in 1.0 (+15 more)

### Community 4 - "GitHub Settings"
Cohesion: 0.12
Nodes (16): 10. ABSTRACT CLASSES (NEW in Godot 4.5+), 11. STATIC VARIABLES & METHODS, 4. ANNOTATIONS (MODERN SYSTEM — replaces keywords), 6. PROPERTIES (SETTERS & GETTERS), 7. AWAIT (replaces yield), 8. SUPER() (replaces dot-call syntax), 9. LAMBDA FUNCTIONS & CALLABLES, code:gdscript (@tool                   # Run script in editor) (+8 more)

### Community 5 - "SmartShape2D"
Cohesion: 0.40
Nodes (5): Edge Material, Edge Meta Material, Shape Material, SmartShape2D, SS2D_Shape

### Community 7 - "Inventory System"
Cohesion: 0.83
Nodes (3): InventoryData, ItemData, SlotData

### Community 11 - "Quest System"
Cohesion: 0.67
Nodes (3): QuestManager, QuestObjective, Quest

### Community 26 - "Contributing Guides"
Cohesion: 0.22
Nodes (8): Code style, code:gdscript (def test():), code:gdscript (def test():), Finally but most importantly, How to contribute, Submitting a pull request, Submitting an issue, Testing

### Community 41 - "Community 41"
Cohesion: 0.12
Nodes (16): Collision Generation Method, Collision Offset, Collision Polygon Node Path, Collision Size, Collision Update Mode, Curve Bake Interval, Editor Debug, Flip Edges (+8 more)

### Community 42 - "Community 42"
Cohesion: 0.12
Nodes (16): Basic usage, Collisions, Contributing, FAQ and troubleshoot, Hex tiles and more, IMPORTANT ANNOUNCEMENT, Index, Installation (+8 more)

### Community 43 - "Community 43"
Cohesion: 0.12
Nodes (15): 1. Important Rules for Saving, 2. Approach A: Dictionary & JSON (Best for simple configurations and generic states), 3. Approach B: Custom Resources (Best for Inventories and RPG Stats), 4. Security Warning, code:gdscript (# Player.gd), code:gdscript (# SaveManager.gd), code:gdscript (func load_game() -> void:), code:gdscript (var my_inventory: InventoryData = InventoryData.new()) (+7 more)

### Community 44 - "Community 44"
Cohesion: 0.13
Nodes (14): 14. COMMON RECIPES, 15. STRINGNAME OPTIMIZATION, 16. MATCH STATEMENT, code:gdscript (extends CharacterBody2D), code:gdscript (match state:), code:gdscript (extends CharacterBody3D), code:gdscript (get_tree().change_scene_to_file("res://scenes/main_menu.tscn), code:gdscript (var enemy_scene: PackedScene = preload("res://scenes/enemy.t) (+6 more)

### Community 45 - "Community 45"
Cohesion: 0.13
Nodes (14): 1. Dialogue Architecture (Native Approach), 2. Quest System Architecture (Resource-Based), 3. Global Quest Manager (Autoload), 4. Best Practices, code:json ([), code:gdscript (extends Node), code:gdscript (class_name Quest), code:gdscript (class_name QuestObjective) (+6 more)

### Community 46 - "Community 46"
Cohesion: 0.15
Nodes (12): 1. COMPOSITION OVER INHERITANCE, 2. FINITE STATE MACHINES (FSM), 3. EVENT BUS (AUTOLOAD SIGNALS), code:gdscript (# The Player Scene structure:), code:gdscript (# HealthComponent.gd), code:gdscript (# The Enemy Scene structure:), code:gdscript (class_name State extends Node), code:gdscript (class_name StateMachine extends Node) (+4 more)

### Community 47 - "Community 47"
Cohesion: 0.15
Nodes (12): 1. When to use JSON vs Resources, 2. Parsing JSON Data (Godot 4 Syntax), 3. Designing the JSON Structure, 4. Crafting System Architecture, 5. Security Note, Checking Recipes, code:gdscript (# DataManager.gd (Autoload)), code:json ({) (+4 more)

### Community 48 - "Community 48"
Cohesion: 0.15
Nodes (12): Anchoring Nodes to the Shape, Basic understanding, Corners, Creating a Shape, Editing the Shape, Material Overrides, Multiple Edge Materials in One Edge, Multiple Textures (+4 more)

### Community 49 - "Community 49"
Cohesion: 0.17
Nodes (11): 1. Core Concepts, 2. Reading Inputs Properly, 3. Remapping Architecture, 4. Saving and Loading Keybinds, 5. Summary Check, code:gdscript (# InputManager.gd (Autoload recommended)), code:gdscript (# RemapButton.gd), code:gdscript (# Inside your InputManager.gd) (+3 more)

### Community 50 - "Community 50"
Cohesion: 0.17
Nodes (11): 1. Core Architecture (The 3 Resources), 2. Using the Inventory in the Game, 3. Creating Items, 4. Why Use This Pattern?, code:gdscript (class_name ItemData), code:gdscript (class_name SlotData), code:gdscript (class_name InventoryData), Godot 4.x Inventory and Item Systems Guide (+3 more)

### Community 51 - "Community 51"
Cohesion: 0.17
Nodes (11): 1. SHADER TYPES, 2. BUILT-IN VARIABLES, 3.1. The "Hit Flash" (Blinking solid white when taking damage), 3.2. Scrolling Texture (e.g., Water, Lava, Backgrounds), 3. EXAMPLES, 4. PERFORMANCE BEST PRACTICES, code:glsl (vec4 tex_color = texture(TEXTURE, UV);), code:glsl (shader_type canvas_item;) (+3 more)

### Community 52 - "Community 52"
Cohesion: 0.17
Nodes (11): Corner Textures, Edge Material, Edge Meta Material, Fit Mode, Normal Range, Normal Texture and Repeat, Repeat Textures, Shape Materials (+3 more)

### Community 53 - "Community 53"
Cohesion: 0.17
Nodes (11): Collision Generation Options, Collision Tool, Create Mode, Defer Mesh Updates, Edge Mode, More Options, Origin Set, Perform Version Check (+3 more)

### Community 54 - "Community 54"
Cohesion: 0.18
Nodes (10): 1. FastNoiseLite for Terrain Data, 2. Reading Noise and Setting Tiles, 3. Autotiling (Terrain Connecting), 4. Chunk-Based Infinite Generation, 5. Performance Tips, code:gdscript (var noise: FastNoiseLite = FastNoiseLite.new()), code:gdscript (@export var terrain_layer: TileMapLayer), code:gdscript (func generate_autotiled_grass() -> void:) (+2 more)

### Community 55 - "Community 55"
Cohesion: 0.18
Nodes (10): 1. The Core Principle, 2. Setting Up Translations (CSV Method), 3. Using Translations in the Engine, 4. Changing the Language at Runtime, 5. Localizing Assets (Images/Audio), code:gdscript (func _ready():), code:gdscript (# LanguageSettings.gd), Godot 4.x Localization and i18n Guide (+2 more)

### Community 56 - "Community 56"
Cohesion: 0.18
Nodes (10): 1. The Core Philosophy, 2. Remote Procedure Calls (RPC), 3. MultiplayerSynchronizer (State Syncing), 4. MultiplayerSpawner (Node Instantiation), 5. Peer ID Management, code:gdscript (# Player.gd), code:gdscript (# LevelManager.gd (Server only logic)), code:gdscript (func _enter_tree():) (+2 more)

### Community 57 - "Community 57"
Cohesion: 0.18
Nodes (10): 1. Feature-Based Organization (Preferred for Scalability), 2. Type-Based Organization (Alternative), code:block1 (res://), code:block2 (res://), Core Organizing Philosophy, Folder Naming Conventions (CRITICAL), Godot Project Structure & File Organization, Mandatory Standard Directories (+2 more)

### Community 58 - "Community 58"
Cohesion: 0.20
Nodes (9): 1. The Golden Rule of Audio, 2. Audio Buses, 3. The AudioManager (Autoload Pool), 4. Preventing Monotony (Godot 4 Randomizer), 5. Music Crossfading, code:gdscript (# AudioManager.gd (Autoload)), code:gdscript (func play_sfx_2d(stream: AudioStream, pos: Vector2) -> void:), Godot 4.x Audio Management Best Practices (+1 more)

### Community 59 - "Community 59"
Cohesion: 0.20
Nodes (9): code:bash (curl -LsSf https://astral.sh/uv/install.sh | sh), code:powershell (powershell -ExecutionPolicy ByPass -c "irm https://astral.sh), code:bash (brew install uv), code:bash (pipx install uv), Documentation, Godot AI, License, Quick Start (+1 more)

### Community 60 - "Community 60"
Cohesion: 0.22
Nodes (8): 1. Handling Multiple Resolutions, 2. Setting Up Touch Controls, 3. Emulating Touch from Mouse, 4. Safe Areas (Mobile Notches), code:gdscript (# SafeAreaUI.gd), Godot 4.x Mobile Controls and Resolution Scaling Guide, On-Screen Gameplay Buttons (D-Pad, Attack), UI Anchoring

### Community 61 - "Community 61"
Cohesion: 0.22
Nodes (8): 1. Collision Layers vs. Collision Masks (CRITICAL), 2. CharacterBody2D / CharacterBody3D (`move_and_slide`), 3. Handling Interactions (Area vs PhysicsBody), 4. RayCast Performance, code:gdscript (class_name Player), code:gdscript (func _on_hitbox_body_entered(body: Node2D) -> void:), Godot 4.x Physics and Collision Handling Guide, Naming Layers

### Community 62 - "Community 62"
Cohesion: 0.22
Nodes (8): 1. Why use this architecture?, 2. The Base `State` Class, 3. The `StateMachine` Class, 4. Usage Example, 5. Best Practices, code:gdscript (class_name State), code:gdscript (class_name StateMachine), Godot 4.x State Machine Implementation Guide

### Community 63 - "Community 63"
Cohesion: 0.25
Nodes (7): 1. AnimationPlayer vs AnimationTree, 2. Setting Up an AnimationTree, 3. The BlendSpace2D, 4. Driving the AnimationTree via Code, 5. Cutscenes and Timelines, code:gdscript (@onready var anim_tree: AnimationTree = $AnimationTree), Godot 4.x Animation and Cutscenes Guide

### Community 64 - "Community 64"
Cohesion: 0.25
Nodes (7): 12. TWEENS (Tween NODE removed — use create_tween), 5. SIGNALS (MODERN SYNTAX), code:gdscript (# Declaration:), code:block2 (# emit_signal("health_changed", old, new)  → use health_chan), code:gdscript (# MODERN — create_tween() (no Tween node):), code:block4 (# var tween = Tween.new()    — Tween node REMOVED), GDScript Signals and Tweens

### Community 65 - "Community 65"
Cohesion: 0.25
Nodes (7): 1. FILE STRUCTURE & CODE ORDER, 2. NAMING CONVENTIONS, 3. STATIC TYPING (ALWAYS USE), code:gdscript (# 01. @tool / @icon / @static_unload), code:gdscript (enum Direction { UP, DOWN, LEFT, RIGHT }), code:gdscript (# Explicit type (when type is not obvious or is int/float am), GDScript Style Guide

### Community 66 - "Community 66"
Cohesion: 0.25
Nodes (7): 1. MULTIMESH FOR RENDERING EFFICIENCY, 2. OBJECT POOLING, 3. STRINGNAME OPTIMIZATIONS, 4. GDSCRIPT EXECUTION BEST PRACTICES, code:gdscript (# Example: Spawning 1000 bullets efficiently using MultiMesh), code:gdscript (class_name BulletPool extends Node), Godot 4.6 Performance Optimization

### Community 67 - "Community 67"
Cohesion: 0.25
Nodes (7): 1. The WorldEnvironment Node, 2. Global Illumination (SDFGI vs. VoxelGI), 3. Volumetric Fog, 4. Post-Processing Essentials (Glow and Tonemapping), 5. Performance Note, Fog Volumes, Godot 4.x Post-Processing and Environment Guide

### Community 68 - "Community 68"
Cohesion: 0.29
Nodes (6): 1. The Core Nodes, 2. Setting Up the Agent (CharacterBody), 3. Dynamic Obstacles and Avoidance, 4. Re-baking Navigation at Runtime, code:gdscript (class_name Enemy), Godot 4.x AI and Pathfinding Guide

### Community 69 - "Community 69"
Cohesion: 0.29
Nodes (6): 1. CONTROL NODES STRICTNESS, 2. ANCHORS AND CONTAINERS (RESPONSIVE UI), 3. THEMING AND STYLEBOXFLAT, 4. RESOLUTION INDEPENDENCE, code:gdscript (# Typical Responsive Menu Structure:), Godot 4.6 UI & UX Patterns

### Community 70 - "Community 70"
Cohesion: 0.33
Nodes (5): SmartShape2D - FAQ, The shape is not rendered, Why aren't my textures repeating?, Why does changing the width look so ugly?, Why isn't my shape updating when I change the Light Mask?

### Community 71 - "Community 71"
Cohesion: 0.33
Nodes (5): code:glsl (shader_type canvas_item;), Default Normals, Encoding Normal data in the canvas_item Vertex Shader Color Parameter, Normals, Writing a Shader

### Community 72 - "Community 72"
Cohesion: 0.40
Nodes (4): Controls - Point Create, Controls - Point Edit, Overlap, SmartShape2D - Controls and Hotkeys

### Community 73 - "Community 73"
Cohesion: 0.40
Nodes (4): Converting Projects from Godot 3.x, Removed Features, Repeating Textures and Normal Textures with CanvasTexture, Using SmartShape2D with Godot 4

### Community 74 - "Community 74"
Cohesion: 0.40
Nodes (4): Activate Plugin, Asset Library, Manual Install, SmartShape2D - Install

### Community 75 - "Community 75"
Cohesion: 0.40
Nodes (4): Code Conventions, Commands, Project Rules & Memories, Wave Defense TD - Godot 4.x Project

## Knowledge Gaps
- **262 isolated node(s):** `contextManagement`, `generalistProfile`, `autoMemory`, `useOSC52Copy`, `useOSC52Paste` (+257 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **22 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What connects `contextManagement`, `generalistProfile`, `autoMemory` to the rest of the system?**
  _278 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Gemini Settings IDE` be split into smaller, more focused modules?**
  _Cohesion score 0.08695652173913043 - nodes in this community are weakly interconnected._
- **Should `Gemini Experimental Settings` be split into smaller, more focused modules?**
  _Cohesion score 0.08333333333333333 - nodes in this community are weakly interconnected._
- **Should `GitHub Settings` be split into smaller, more focused modules?**
  _Cohesion score 0.11764705882352941 - nodes in this community are weakly interconnected._
- **Should `Community 41` be split into smaller, more focused modules?**
  _Cohesion score 0.11764705882352941 - nodes in this community are weakly interconnected._
- **Should `Community 42` be split into smaller, more focused modules?**
  _Cohesion score 0.11764705882352941 - nodes in this community are weakly interconnected._
- **Should `Community 43` be split into smaller, more focused modules?**
  _Cohesion score 0.125 - nodes in this community are weakly interconnected._