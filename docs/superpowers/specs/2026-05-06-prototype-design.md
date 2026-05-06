# Wave Defense TD - Prototype Design

## Overview
High-performance 2D top-down PvE wave-defense game. Focus on massive unit counts (thousands) using Godot 4 Forward+.

## Architecture

### 1. Flow Field Movement
- **Grid System:** Map divided into a grid (e.g., 32x32 pixels).
- **Dijkstra Map:** Calculate distance from each cell to the "Nexus" (target).
- **Vector Field:** Each cell stores a direction vector pointing to the neighbor with the lowest Dijkstra value.
- **Enemies:** Read the vector at their current position to determine movement direction.

### 2. MultiMesh Swarm Rendering
- **Node:** `MultiMeshInstance2D`.
- **Logic:** Central script updates the transforms of all active enemies in a single `_process` or `_physics_process` loop.
- **State:** Array of structs (or parallel arrays) storing position, health, and velocity.

### 3. Combat System
- **Turrets:** Standard `Node2D` or `Sprite2D`. 
- **Targeting:** Scan for the closest active enemy using `(target_pos - turret_pos).length_squared()` to avoid expensive square root operations.
- **Projectiles:** Simple pooling system or immediate hitscan with visual tracer.

### 4. Game Loop
- **WaveManager:** Spawns batches of enemies at spawn points.
- **Nexus:** Health pool. Game over when health reaches zero.

## Technical Details (Forward+)
- **Renderer:** Forward+ for efficient light/shadow handling if needed later.
- **Performance:** Avoid per-enemy `_process` calls. All logic centralized in `FlowFieldManager` and `EnemyManager`.

## Testing Strategy
- **Simulation Mode:** Auto-spawning enemies and auto-firing turrets to observe swarm behavior and performance.
- **Unit Counts:** Stress test with 1,000, 2,000, and 5,000 units.
