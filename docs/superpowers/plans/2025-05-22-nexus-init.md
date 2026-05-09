# Global Events & Nexus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Initialize core event bus and basic Nexus entity.

**Architecture:** Global Autoload for signals, Prefab for Nexus with health logic.

**Tech Stack:** Godot 4 (GDScript), Godot AI MCP.

---

### Task 1: Create GlobalEvents Autoload

**Files:**
- Create: `res://scripts/global_events.gd`
- Modify: `project.godot` (via tool)

- [ ] **Step 1: Write GlobalEvents script**

```gdscript
extends Node
signal nexus_damaged(amount: int)
signal nexus_destroyed
```

Run: `mcp_godot-ai_script_create(path="res://scripts/global_events.gd", content="...")`

- [ ] **Step 2: Register GlobalEvents as Autoload**

Run: `mcp_godot-ai_autoload_manage(op="add", params={"name": "GlobalEvents", "path": "res://scripts/global_events.gd"})`

- [ ] **Step 3: Verify Autoload registration**

Run: `mcp_godot-ai_autoload_manage(op="list")`
Expected: `GlobalEvents` in list.

- [ ] **Step 4: Commit**

```bash
git add project.godot scripts/global_events.gd
git commit -m "feat: add GlobalEvents autoload"
```

---

### Task 2: Create Nexus Script

**Files:**
- Create: `res://scripts/nexus.gd`

- [ ] **Step 1: Write Nexus script**

```gdscript
extends StaticBody2D

@export var health: int = 100

func _ready():
    GlobalEvents.nexus_damaged.connect(_on_damaged)

func _on_damaged(amount: int):
    health -= amount
    print("Nexus health: ", health)
    if health <= 0:
        GlobalEvents.nexus_destroyed.emit()
        print("Nexus DESTROYED")
```

Run: `mcp_godot-ai_script_create(path="res://scripts/nexus.gd", content="...")`

- [ ] **Step 2: Commit**

```bash
git add scripts/nexus.gd
git commit -m "feat: add nexus script"
```

---

### Task 3: Create Nexus Prefab

**Files:**
- Create: `res://prefabs/nexus.tscn`

- [ ] **Step 1: Create Scene Root**

Run: `mcp_godot-ai_scene_manage(op="create", params={"path": "res://prefabs/nexus.tscn", "root_type": "StaticBody2D", "root_name": "Nexus"})`

- [ ] **Step 2: Add Sprite2D and CollisionShape2D**

Run `batch_execute`:
1. `create_node` (type="Sprite2D", name="Sprite2D")
2. `set_property` (path="/Nexus/Sprite2D", property="texture", value="res://icon.svg")
3. `create_node` (type="CollisionShape2D", name="CollisionShape2D")
4. `set_property` (path="/Nexus/CollisionShape2D", property="shape", value={"__class__": "CircleShape2D", "radius": 32})

- [ ] **Step 3: Attach Script**

Run: `mcp_godot-ai_script_attach(path="/Nexus", script_path="res://scripts/nexus.gd")`

- [ ] **Step 4: Save and Verify**

Run: `mcp_godot-ai_scene_save()`
Run: `mcp_godot-ai_scene_get_hierarchy()`

- [ ] **Step 5: Commit**

```bash
git add prefabs/nexus.tscn
git commit -m "feat: add nexus prefab"
```

---

### Task 4: Final Verification

- [ ] **Step 1: Run project and check logs**

Run: `mcp_godot-ai_project_run(mode="current")` (with nexus.tscn open)
Check logs for any script errors.

- [ ] **Step 2: DONE**
