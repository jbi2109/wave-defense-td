# Graph Report - .  (2026-06-04)

## Corpus Check
- 17 files · ~1,413,088 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 522 nodes · 491 edges · 58 communities (45 shown, 13 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 13 edges (avg confidence: 0.9)
- Token cost: 1,250 input · 850 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Gemini Settings IDE|Gemini Settings IDE]]
- [[_COMMUNITY_Design Patterns|Design Patterns]]
- [[_COMMUNITY_Python Tooling|Python Tooling]]
- [[_COMMUNITY_Gemini Experimental Settings|Gemini Experimental Settings]]
- [[_COMMUNITY_GitHub Settings|GitHub Settings]]
- [[_COMMUNITY_SmartShape2D|SmartShape2D]]
- [[_COMMUNITY_GameDev Documentation|GameDev Documentation]]
- [[_COMMUNITY_Inventory System|Inventory System]]
- [[_COMMUNITY_AI Plugin Modifiers|AI Plugin Modifiers]]
- [[_COMMUNITY_Input Management|Input Management]]
- [[_COMMUNITY_Performance & Object Pooling|Performance & Object Pooling]]
- [[_COMMUNITY_Quest System|Quest System]]
- [[_COMMUNITY_Environment Post Processing|Environment Post Processing]]
- [[_COMMUNITY_AI Action Resetter|AI Action Resetter]]
- [[_COMMUNITY_Data Management|Data Management]]
- [[_COMMUNITY_Godot AI MCP|Godot AI MCP]]
- [[_COMMUNITY_Level Generation|Level Generation]]
- [[_COMMUNITY_Project Structure|Project Structure]]
- [[_COMMUNITY_Resolution Scaling|Resolution Scaling]]
- [[_COMMUNITY_Graphify Tooling|Graphify Tooling]]
- [[_COMMUNITY_AI Tool Append|AI Tool Append]]
- [[_COMMUNITY_AI Patch Handlers|AI Patch Handlers]]
- [[_COMMUNITY_AI Refactor Tools|AI Refactor Tools]]
- [[_COMMUNITY_Claude Guidelines|Claude Guidelines]]
- [[_COMMUNITY_Grid Architecture|Grid Architecture]]
- [[_COMMUNITY_Settings File|Settings File]]
- [[_COMMUNITY_Contributing Guides|Contributing Guides]]
- [[_COMMUNITY_Debugging Output|Debugging Output]]
- [[_COMMUNITY_Agent Code Mod|Agent Code Mod]]
- [[_COMMUNITY_Health Component|Health Component]]
- [[_COMMUNITY_Modern GDScript|Modern GDScript]]
- [[_COMMUNITY_Signals & Tweens|Signals & Tweens]]
- [[_COMMUNITY_Networking & Multiplayer|Networking & Multiplayer]]
- [[_COMMUNITY_Dialogue Manager|Dialogue Manager]]
- [[_COMMUNITY_Save Manager|Save Manager]]
- [[_COMMUNITY_Shaders|Shaders]]
- [[_COMMUNITY_Responsive UI|Responsive UI]]
- [[_COMMUNITY_UI Styles|UI Styles]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
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

## God Nodes (most connected - your core abstractions)
1. `Properties` - 15 edges
2. `TileMapDual` - 10 edges
3. `SmartShape2D` - 9 edges
4. `experimental` - 8 edges
5. `14. COMMON RECIPES` - 8 edges
6. `SmartShape2D - Toolbar` - 8 edges
7. `Edge Material` - 8 edges
8. `Usage` - 7 edges
9. `SmartShape2D - QuickStart` - 7 edges
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

## Communities (58 total, 13 thin omitted)

### Community 0 - "Gemini Settings IDE"
Cohesion: 0.07
Nodes (30): The shape is not rendered, Why aren't my textures repeating?, Why does changing the width look so ugly?, Why isn't my shape updating when I change the Light Mask?, Corner Textures, Fit Mode, Normal Range, Normal Texture and Repeat (+22 more)

### Community 1 - "Design Patterns"
Cohesion: 0.07
Nodes (29): code:gdscript (extends Node), code:bash (git add project.godot scripts/global_events.gd), code:gdscript (extends StaticBody2D), code:bash (git add scripts/nexus.gd), code:bash (git add prefabs/nexus.tscn), Global Events & Nexus Implementation Plan, Task 1: Create GlobalEvents Autoload, Task 2: Create Nexus Script (+21 more)

### Community 2 - "Python Tooling"
Cohesion: 0.08
Nodes (23): GameDev AI Skills, 1. The Core Nodes, 2. Setting Up the Agent (CharacterBody), 3. Dynamic Obstacles and Avoidance, 4. Re-baking Navigation at Runtime, code:gdscript (class_name Enemy), Godot 4.x AI and Pathfinding Guide, 1. AnimationPlayer vs AnimationTree (+15 more)

### Community 3 - "Gemini Experimental Settings"
Cohesion: 0.08
Nodes (22): Code style, code:gdscript (def test():), Finally but most importantly, How to contribute, Submitting a pull request, Submitting an issue, Testing, Basic usage (+14 more)

### Community 4 - "GitHub Settings"
Cohesion: 0.09
Nodes (21): Autoload Singleton Pattern, BulletPool, Object Pooling, 14. COMMON RECIPES, 16. MATCH STATEMENT, code:gdscript (extends CharacterBody2D), code:gdscript (match state:), code:gdscript (get_tree().change_scene_to_file("res://scenes/main_menu.tscn) (+13 more)

### Community 5 - "SmartShape2D"
Cohesion: 0.09
Nodes (22): GITHUB_PERSONAL_ACCESS_TOKEN, experimental, autoMemory, contextManagement, gemma, generalistProfile, useOSC52Copy, useOSC52Paste (+14 more)

### Community 6 - "GameDev Documentation"
Cohesion: 0.14
Nodes (17): 1.x, 2.0, 2.1, 2.2, 2.x, Changes, Changes in 0.91, Changes in 1.3 (+9 more)

### Community 7 - "Inventory System"
Cohesion: 0.12
Nodes (15): code:gdscript (extends Node), code:gdscript (extends StaticBody2D), code:bash (git add res/scripts/global_events.gd res/scripts/nexus.gd re), code:bash (git add res/scripts/flow_field_manager.gd), code:gdscript (extends MultiMeshInstance2D), code:bash (git add res/scripts/enemy_manager.gd), code:gdscript (extends Sprite2D), code:bash (git add res/scripts/turret.gd res/prefabs/turret.tscn) (+7 more)

### Community 8 - "AI Plugin Modifiers"
Cohesion: 0.14
Nodes (15): Composition over Inheritance, Event Bus, Finite State Machine, Finite State Machine, 1. COMPOSITION OVER INHERITANCE, 2. FINITE STATE MACHINES (FSM), 3. EVENT BUS (AUTOLOAD SIGNALS), code:gdscript (# The Player Scene structure:) (+7 more)

### Community 9 - "Input Management"
Cohesion: 0.12
Nodes (15): 1. Important Rules for Saving, 2. Approach A: Dictionary & JSON (Best for simple configurations and generic states), 3. Approach B: Custom Resources (Best for Inventories and RPG Stats), 4. Security Warning, code:gdscript (# Player.gd), code:gdscript (# SaveManager.gd), code:gdscript (func load_game() -> void:), code:gdscript (var my_inventory: InventoryData = InventoryData.new()) (+7 more)

### Community 10 - "Performance & Object Pooling"
Cohesion: 0.13
Nodes (14): 10. ABSTRACT CLASSES (NEW in Godot 4.5+), 11. STATIC VARIABLES & METHODS, 4. ANNOTATIONS (MODERN SYSTEM — replaces keywords), 6. PROPERTIES (SETTERS & GETTERS), 7. AWAIT (replaces yield), 8. SUPER() (replaces dot-call syntax), 9. LAMBDA FUNCTIONS & CALLABLES, code:gdscript (@tool                   # Run script in editor) (+6 more)

### Community 11 - "Quest System"
Cohesion: 0.15
Nodes (14): InventoryData, ItemData, 1. Core Architecture (The 3 Resources), 2. Using the Inventory in the Game, 3. Creating Items, 4. Why Use This Pattern?, code:gdscript (class_name ItemData), code:gdscript (class_name SlotData) (+6 more)

### Community 12 - "Environment Post Processing"
Cohesion: 0.14
Nodes (13): DataManager, 1. When to use JSON vs Resources, 2. Parsing JSON Data (Godot 4 Syntax), 3. Designing the JSON Structure, 4. Crafting System Architecture, 5. Security Note, Checking Recipes, code:gdscript (# DataManager.gd (Autoload)) (+5 more)

### Community 13 - "AI Action Resetter"
Cohesion: 0.15
Nodes (13): InputManager, RemapButton, 1. Core Concepts, 2. Reading Inputs Properly, 3. Remapping Architecture, 4. Saving and Loading Keybinds, 5. Summary Check, code:gdscript (# InputManager.gd (Autoload recommended)) (+5 more)

### Community 14 - "Data Management"
Cohesion: 0.15
Nodes (12): Anchoring Nodes to the Shape, Basic understanding, Corners, Creating a Shape, Editing the Shape, Material Overrides, Multiple Edge Materials in One Edge, Multiple Textures (+4 more)

### Community 15 - "Godot AI MCP"
Cohesion: 0.17
Nodes (11): Collision Generation Options, Collision Tool, Create Mode, Defer Mesh Updates, Edge Mode, More Options, Origin Set, Perform Version Check (+3 more)

### Community 16 - "Level Generation"
Cohesion: 0.17
Nodes (11): Feature-Based Organization, 1. Feature-Based Organization (Preferred for Scalability), 2. Type-Based Organization (Alternative), code:block1 (res://), code:block2 (res://), Core Organizing Philosophy, Folder Naming Conventions (CRITICAL), Godot Project Structure & File Organization (+3 more)

### Community 17 - "Project Structure"
Cohesion: 0.17
Nodes (11): FastNoiseLite, 1. FastNoiseLite for Terrain Data, 2. Reading Noise and Setting Tiles, 3. Autotiling (Terrain Connecting), 4. Chunk-Based Infinite Generation, 5. Performance Tips, code:gdscript (var noise: FastNoiseLite = FastNoiseLite.new()), code:gdscript (@export var terrain_layer: TileMapLayer) (+3 more)

### Community 18 - "Resolution Scaling"
Cohesion: 0.22
Nodes (3): clean_green_outline(), find_green_background(), process_image()

### Community 19 - "Graphify Tooling"
Cohesion: 0.18
Nodes (10): Godot AI, code:bash (curl -LsSf https://astral.sh/uv/install.sh | sh), code:powershell (powershell -ExecutionPolicy ByPass -c "irm https://astral.sh), code:bash (brew install uv), code:bash (pipx install uv), Documentation, License, Quick Start (+2 more)

### Community 20 - "AI Tool Append"
Cohesion: 0.18
Nodes (10): 1. The Core Principle, 2. Setting Up Translations (CSV Method), 3. Using Translations in the Engine, 4. Changing the Language at Runtime, 5. Localizing Assets (Images/Audio), code:gdscript (func _ready():), code:gdscript (# LanguageSettings.gd), Godot 4.x Localization and i18n Guide (+2 more)

### Community 21 - "AI Patch Handlers"
Cohesion: 0.18
Nodes (10): 1. The Core Philosophy, 2. Remote Procedure Calls (RPC), 3. MultiplayerSynchronizer (State Syncing), 4. MultiplayerSpawner (Node Instantiation), 5. Peer ID Management, code:gdscript (# Player.gd), code:gdscript (# LevelManager.gd (Server only logic)), code:gdscript (func _enter_tree():) (+2 more)

### Community 22 - "AI Refactor Tools"
Cohesion: 0.20
Nodes (9): SafeAreaUI, 1. Handling Multiple Resolutions, 2. Setting Up Touch Controls, 3. Emulating Touch from Mouse, 4. Safe Areas (Mobile Notches), code:gdscript (# SafeAreaUI.gd), Godot 4.x Mobile Controls and Resolution Scaling Guide, On-Screen Gameplay Buttons (D-Pad, Attack) (+1 more)

### Community 23 - "Claude Guidelines"
Cohesion: 0.20
Nodes (9): SDFGI, 1. The WorldEnvironment Node, 2. Global Illumination (SDFGI vs. VoxelGI), 3. Volumetric Fog, 4. Post-Processing Essentials (Glow and Tonemapping), 5. Performance Note, Fog Volumes, Godot 4.x Post-Processing and Environment Guide (+1 more)

### Community 24 - "Grid Architecture"
Cohesion: 0.24
Nodes (9): 1. SHADER TYPES, 2. BUILT-IN VARIABLES, 3.1. The "Hit Flash" (Blinking solid white when taking damage), 3.2. Scrolling Texture (e.g., Water, Lava, Backgrounds), 3. EXAMPLES, 4. PERFORMANCE BEST PRACTICES, code:glsl (vec4 tex_color = texture(TEXTURE, UV);), code:glsl (shader_type canvas_item;) (+1 more)

### Community 25 - "Settings File"
Cohesion: 0.20
Nodes (9): 1. Flow Field Movement, 2. MultiMesh Swarm Rendering, 3. Combat System, 4. Game Loop, Architecture, Overview, Technical Details (Forward+), Testing Strategy (+1 more)

### Community 26 - "Contributing Guides"
Cohesion: 0.22
Nodes (8): 1. Collision Layers vs. Collision Masks (CRITICAL), 2. CharacterBody2D / CharacterBody3D (`move_and_slide`), 3. Handling Interactions (Area vs PhysicsBody), 4. RayCast Performance, code:gdscript (class_name Player), code:gdscript (func _on_hitbox_body_entered(body: Node2D) -> void:), Godot 4.x Physics and Collision Handling Guide, Naming Layers

### Community 27 - "Debugging Output"
Cohesion: 0.22
Nodes (8): 1. GlobalEvents.gd, 2. nexus.gd, 3. nexus.tscn, Architecture, Components, Goal, Success Criteria, Wave Defense TD: Global Events & Nexus Design

### Community 29 - "Agent Code Mod"
Cohesion: 0.29
Nodes (6): 12. TWEENS (Tween NODE removed — use create_tween), 5. SIGNALS (MODERN SYNTAX), code:gdscript (# Declaration:), code:block2 (# emit_signal("health_changed", old, new)  → use health_chan), code:gdscript (# MODERN — create_tween() (no Tween node):), code:block4 (# var tween = Tween.new()    — Tween node REMOVED)

### Community 30 - "Health Component"
Cohesion: 0.29
Nodes (6): 1. FILE STRUCTURE & CODE ORDER, 2. NAMING CONVENTIONS, 3. STATIC TYPING (ALWAYS USE), code:gdscript (# 01. @tool / @icon / @static_unload), code:gdscript (enum Direction { UP, DOWN, LEFT, RIGHT }), code:gdscript (# Explicit type (when type is not obvious or is int/float am)

### Community 31 - "Modern GDScript"
Cohesion: 0.29
Nodes (6): 1. CONTROL NODES STRICTNESS, 2. ANCHORS AND CONTAINERS (RESPONSIVE UI), 3. THEMING AND STYLEBOXFLAT, 4. RESOLUTION INDEPENDENCE, code:gdscript (# Typical Responsive Menu Structure:), Godot 4.6 UI & UX Patterns

### Community 32 - "Signals & Tweens"
Cohesion: 0.48
Nodes (5): clean_green_outline(), clean_resized_green_outline(), clear_cell_background(), find_green_background(), process_enemy_sheet()

### Community 33 - "Networking & Multiplayer"
Cohesion: 0.33
Nodes (5): code:glsl (shader_type canvas_item;), Default Normals, Encoding Normal data in the canvas_item Vertex Shader Color Parameter, Normals, Writing a Shader

### Community 34 - "Dialogue Manager"
Cohesion: 0.40
Nodes (4): Activate Plugin, Asset Library, Manual Install, SmartShape2D - Install

### Community 35 - "Save Manager"
Cohesion: 0.40
Nodes (4): Controls - Point Create, Controls - Point Edit, Overlap, SmartShape2D - Controls and Hotkeys

### Community 36 - "Shaders"
Cohesion: 0.40
Nodes (4): Converting Projects from Godot 3.x, Removed Features, Repeating Textures and Normal Textures with CanvasTexture, Using SmartShape2D with Godot 4

### Community 37 - "Responsive UI"
Cohesion: 0.40
Nodes (4): Code Conventions, Commands, Project Rules & Memories, Wave Defense TD - Godot 4.x Project

## Knowledge Gaps
- **256 isolated node(s):** `contextManagement`, `generalistProfile`, `autoMemory`, `useOSC52Copy`, `useOSC52Paste` (+251 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `code:gdscript (class_name State extends Node)` connect `Design Patterns` to `AI Plugin Modifiers`, `Performance & Object Pooling`?**
  _High betweenness centrality (0.023) - this node is a cross-community bridge._
- **Why does `2. FINITE STATE MACHINES (FSM)` connect `AI Plugin Modifiers` to `Design Patterns`?**
  _High betweenness centrality (0.018) - this node is a cross-community bridge._
- **What connects `contextManagement`, `generalistProfile`, `autoMemory` to the rest of the system?**
  _271 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Gemini Settings IDE` be split into smaller, more focused modules?**
  _Cohesion score 0.06628787878787878 - nodes in this community are weakly interconnected._
- **Should `Design Patterns` be split into smaller, more focused modules?**
  _Cohesion score 0.06854838709677419 - nodes in this community are weakly interconnected._
- **Should `Python Tooling` be split into smaller, more focused modules?**
  _Cohesion score 0.07692307692307693 - nodes in this community are weakly interconnected._
- **Should `Gemini Experimental Settings` be split into smaller, more focused modules?**
  _Cohesion score 0.08333333333333333 - nodes in this community are weakly interconnected._