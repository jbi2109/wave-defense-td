# Wave Defense TD Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a high-performance prototype featuring a flow-field swarm of orcs targeting a nexus, defended by a turret.

**Architecture:** Centralized `FlowFieldManager` for pathing and `EnemyManager` using `MultiMeshInstance2D` for swarm rendering. `Turret` nodes use squared distance checks for efficient targeting.

**Tech Stack:** Godot 4.6+ (Forward+), GDScript.

---

## File Structure

- `res://scenes/main.tscn`: Main entry point.
- `res://scripts/flow_field_manager.gd`: Grid-based pathing logic.
- `res://scripts/enemy_manager.gd`: MultiMesh rendering and swarm lifecycle.
- `res://scripts/turret.gd`: Turret AI and firing.
- `res://scripts/nexus.gd`: Base health and game state.
- `res://scripts/global_events.gd`: Signal bus for decoupling.
- `res://prefabs/turret.tscn`: Instantiable turret.
- `res://prefabs/nexus.tscn`: Instantiable nexus.

---

## Tasks

### Task 1: Initialize Global Events and Basic Nexus

**Files:**
- Create: `res://scripts/global_events.gd` (Autoload)
- Create: `res://scripts/nexus.gd`
- Create: `res://prefabs/nexus.tscn`

- [ ] **Step 1: Create Global Events script**
```gdscript
extends Node
signal nexus_damaged(amount: int)
signal nexus_destroyed
```

- [ ] **Step 2: Create Nexus script**
```gdscript
extends StaticBody2D
@export var health: int = 100
func _ready():
    GlobalEvents.nexus_damaged.connect(_on_damaged)
func _on_damaged(amount):
    health -= amount
    if health <= 0:
        GlobalEvents.nexus_destroyed.emit()
```

- [ ] **Step 3: Register GlobalEvents Autoload**
- [ ] **Step 4: Commit**
```bash
git add res/scripts/global_events.gd res/scripts/nexus.gd res/prefabs/nexus.tscn
git commit -m "feat: init global events and nexus"
```

### Task 2: Flow Field Grid Logic

**Files:**
- Create: `res://scripts/flow_field_manager.gd`

- [ ] **Step 1: Implement Flow Field grid generation**
```gdscript
extends Node2D
class_name FlowFieldManager

@export var grid_size: Vector2i = Vector2i(50, 50)
@export var cell_size: int = 32
var grid = [] # 2D array of vectors

func generate_field(target_pos: Vector2):
    # TODO: Implement Dijkstra and Vector Field
    pass

func get_direction(world_pos: Vector2) -> Vector2:
    var grid_pos = Vector2i(world_pos / float(cell_size))
    # Return vector from grid
    return Vector2.ZERO
```

- [ ] **Step 2: Commit**
```bash
git add res/scripts/flow_field_manager.gd
git commit -m "feat: add flow field skeleton"
```

### Task 3: Enemy Manager (MultiMesh Swarm)

**Files:**
- Create: `res://scripts/enemy_manager.gd`

- [ ] **Step 1: Setup MultiMeshInstance2D**
```gdscript
extends MultiMeshInstance2D

@export var max_enemies: int = 2000
var active_count: int = 0
var positions = PackedVector2Array()
var velocities = PackedVector2Array()

func _ready():
    multimesh.instance_count = max_enemies
    positions.resize(max_enemies)
    velocities.resize(max_enemies)

func _process(delta):
    for i in range(active_count):
        # Update movement logic here
        pass
```

- [ ] **Step 2: Commit**
```bash
git add res/scripts/enemy_manager.gd
git commit -m "feat: init enemy multimesh manager"
```

### Task 4: Turret AI

**Files:**
- Create: `res://scripts/turret.gd`
- Create: `res://prefabs/turret.tscn`

- [ ] **Step 1: Implement turret targeting**
```gdscript
extends Sprite2D

@export var range: float = 300.0
@export var fire_rate: float = 0.1

func _process(delta):
    var target = find_target()
    if target:
        look_at(target)
```

- [ ] **Step 2: Commit**
```bash
git add res/scripts/turret.gd res/prefabs/turret.tscn
git commit -m "feat: add basic turret targeting"
```
