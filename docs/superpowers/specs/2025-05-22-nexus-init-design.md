# Wave Defense TD: Global Events & Nexus Design

## Goal
Establish core event bus and the primary defense target (Nexus).

## Architecture
- **GlobalEvents (Autoload)**: Centralized signal hub.
- **Nexus (Prefab)**: Physical entity in game world.

## Components

### 1. GlobalEvents.gd
- Path: `res://scripts/global_events.gd`
- Signals:
  - `nexus_damaged(amount: int)`
  - `nexus_destroyed()`

### 2. nexus.gd
- Path: `res://scripts/nexus.gd`
- State: `health: int` (Exported, default 100)
- Logic:
  - Connects to `GlobalEvents.nexus_damaged` on `_ready()`.
  - Decrements health on damage.
  - Emits `GlobalEvents.nexus_destroyed` when health <= 0.
  - Prints status to console for verification.

### 3. nexus.tscn
- Path: `res://prefabs/nexus.tscn`
- Root: `StaticBody2D` (Script: `nexus.gd`)
- Children:
  - `Sprite2D`: Using `res://icon.svg` as placeholder.
  - `CollisionShape2D`: `CircleShape2D`.

## Success Criteria
- `GlobalEvents` registered in `project.godot`.
- Nexus prefab instantiable with sprite and collision.
- Nexus health updates and destruction logic triggers.
