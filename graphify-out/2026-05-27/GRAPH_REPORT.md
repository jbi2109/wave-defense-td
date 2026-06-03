# Graph Report - .  (2026-05-27)

## Corpus Check
- Large corpus: 199 files ╖ ~1,385,200 words. Semantic extraction will be expensive (many Claude tokens). Consider running on a subfolder.

## Summary
- 105 nodes · 70 edges · 41 communities (20 shown, 21 thin omitted)
- Extraction: 81% EXTRACTED · 19% INFERRED · 0% AMBIGUOUS · INFERRED: 13 edges (avg confidence: 0.9)
- Token cost: 1,250 input · 850 output

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

## God Nodes (most connected - your core abstractions)
1. `experimental` - 8 edges
2. `github` - 4 edges
3. `ui` - 4 edges
4. `GameDev AI Skills` - 3 edges
5. `Finite State Machine` - 3 edges
6. `StateMachine` - 3 edges
7. `SlotData` - 3 edges
8. `mcpServers` - 2 edges
9. `env` - 2 edges
10. `model` - 2 edges

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

## Communities (41 total, 21 thin omitted)

### Community 0 - "Gemini Settings IDE"
Cohesion: 0.20
Nodes (9): ide, enabled, mcpServers, model, name, ui, showMemoryUsage, showModelInfoInChat (+1 more)

### Community 1 - "Design Patterns"
Cohesion: 0.25
Nodes (7): Autoload Singleton Pattern, Composition over Inheritance, Event Bus, Finite State Machine, Finite State Machine, State, StateMachine

### Community 3 - "Gemini Experimental Settings"
Cohesion: 0.25
Nodes (8): experimental, autoMemory, contextManagement, gemma, generalistProfile, useOSC52Copy, useOSC52Paste, worktrees

### Community 4 - "GitHub Settings"
Cohesion: 0.40
Nodes (5): GITHUB_PERSONAL_ACCESS_TOKEN, args, command, env, github

### Community 5 - "SmartShape2D"
Cohesion: 0.40
Nodes (5): Edge Material, Edge Meta Material, Shape Material, SmartShape2D, SS2D_Shape

### Community 7 - "Inventory System"
Cohesion: 0.83
Nodes (3): InventoryData, ItemData, SlotData

### Community 11 - "Quest System"
Cohesion: 0.67
Nodes (3): QuestManager, QuestObjective, Quest

## Knowledge Gaps
- **27 isolated node(s):** `contextManagement`, `generalistProfile`, `autoMemory`, `useOSC52Copy`, `useOSC52Paste` (+22 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **21 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `experimental` connect `Gemini Experimental Settings` to `Gemini Settings IDE`?**
  _High betweenness centrality (0.024) - this node is a cross-community bridge._
- **Why does `mcpServers` connect `Gemini Settings IDE` to `GitHub Settings`?**
  _High betweenness centrality (0.016) - this node is a cross-community bridge._
- **Why does `github` connect `GitHub Settings` to `Gemini Settings IDE`?**
  _High betweenness centrality (0.014) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `GameDev AI Skills` (e.g. with `ai_and_pathfinding.md` and `animation_and_cutscenes.md`) actually correct?**
  _`GameDev AI Skills` has 3 INFERRED edges - model-reasoned connections that need verification._
- **What connects `contextManagement`, `generalistProfile`, `autoMemory` to the rest of the system?**
  _43 weakly-connected nodes found - possible documentation gaps or missing edges._