# Specification: Studio Game Comparison and Improvement Design

This document provides a highly detailed, comprehensive comparison between our current implementation in `wave-defense-td` and the "gold standard" studio game `Sir, we have an orc problem` (referred to as the "Studio Game"). It outlines concrete architectural and mathematical designs to elevate our game to the same premium quality.

---

## 1. High-Level Architecture Comparison

| Feature / System | Current Game (`wave-defense-td`) | Studio Game (`Sir, we have an orc problem`) |
| :--- | :--- | :--- |
| **Simulation Pipeline** | Hybrid GPU-CPU: Kinematics and separation run on GPU, but target selection and death processing require constant sync and async buffer checking. | 100% GPU-Driven: Rigid body physics, contact handling, collisions, state updates, and rendering parameters are processed on the GPU. CPU only schedules and reads back small status buffers. |
| **Level Geometry** | Pre-scanned TileMap or static boundaries evaluated once on the CPU to build a walkability grid. | Dynamic Image Masks: B&W maps generate GPU-side Signed Distance Fields (SDFs) and Dijkstra flow fields. CPU extracts collision polygons from the GPU-computed SDF. |
| **Enemy Physics** | Simple 2D flow-field following with an ad-hoc GPU separation pass to prevent stacking. | Custom 2D Rigid Body Physics: Full dynamic integration with mass, velocity, coefficient of restitution, wall sliding, and particle-based contact solvers. |
| **Turret Targeting** | Immediate line-of-sight/cone sweeps targeting the closest, strongest, first, or last enemy. | Focal target points placed in the level. Turrets sweep their barrels in a cone that dynamically narrows as the target is placed further away. Fired projectiles are real GPU rigidbodies. |
| **AoE / Abilities** | CPU-side calculations matching area bounds, sending damage updates to the GPU. | GPU Contact Handlers: Dynamic shapes registered in GPU buffers. Compute passes evaluate intersections and apply damage/effects natively. |

---

## 2. Mathematical Equations and Systems Comparison

### A. Enemy Spawning and Difficulty Scaling

#### Studio Game System
In the Studio Game, enemies are spawned with organic variance. Rather than static tier lists (e.g., small, medium, large), enemies are generated on a continuous spectrum using power-law random distributions.

1. **Size (Radius) Distribution:**
   $$R = R_{min} + (R_{max} - R_{min}) \cdot f_{rand}^{10.0}$$
   - $R_{min} = 2.0$, $R_{max} = 4.0$ (world units)
   - $f_{rand} \in [0, 1)$ is a uniform random float.
   - *Behavior:* Raising the random float to the 10th power produces a distribution where the vast majority of enemies are standard-sized orcs ($R \approx 2.0$), but occasionally spawns massive "giant" orcs ($R \approx 4.0$).

2. **Mass Scaling:**
   $$M = C_{mass} \cdot R^2 \cdot C_{density}$$
   - $C_{mass} = 100.0$, $C_{density} = 0.15$
   - $M = 15.0 \cdot R^2$
   - *Behavior:* Mass scales quadratically with radius, reflecting realistic area-based physics. Larger orcs are much harder to push around, blocking smaller orcs behind them and creating realistic choke point behaviors.

3. **Difficulty / Health Progression:**
   The Studio Game calculates health based on three variables: enemy size, wave progression time, and level index.
   
   - **Level Buff Factor:**
     $$H_{level}(L) = 2.5^{L - 1}$$
     *Behavior:* The health of all enemies scales exponentially with the level index $L$. Level 1 = 1.0x, Level 2 = 2.5x, Level 3 = 6.25x, Level 4 = 15.63x.
     
   - **Progress Buff Factor:**
     $$H_{progress}(T_{rel}) = 1.0 + T_{rel} \cdot C_{time\_buff}$$
     - $C_{time\_buff} = 1.0$
     - $T_{rel} = \frac{N_{spawned}}{N_{total}}$ (relative index spawned in the current wave).
     - *Behavior:* Health increases linearly as the wave progresses. Enemies spawned at the end of the wave have exactly twice the base health of those spawned at the start, preventing the end of waves from feeling too easy.
     
   - **Radius Buff Factor:**
     $$H_{radius}(R) = R^2 \cdot C_{radius\_buff}$$
     - $C_{radius\_buff} = 0.2$
     - *Behavior:* Health scales quadratically with radius, making larger enemies exponentially more resilient.
     
   - **Final Health Equation:**
     $$Health(R, T_{rel}, L) = H_{radius}(R) \cdot H_{progress}(T_{rel}) \cdot H_{level}(L)$$
     $$Health(R, T_{rel}, L) = (0.2 \cdot R^2) \cdot (1.0 + T_{rel}) \cdot (2.5^{L - 1})$$

#### Our Current System
Currently, `wave-defense-td` uses hardcoded values in `EnemyDefinition` classes. Abominations, Banshees, and Swarmers have fixed scales, health, and speeds. Spawning does not scale dynamically within a level or wave.

#### Proposed Improvement Plan
Implement continuous enemy scaling. Modify `main.gd` and `enemy_manager.gd` to accept dynamic radius inputs and calculate mass and health using the Studio Game's equations. Introduce a Level Difficulty scaling variable in `Globals`.

---

### B. Turrets: Focal Target and Dynamic Cone Scaling

#### Studio Game System
Towers in the Studio Game do not scan 360 degrees. Players place a focal target marker in the level for each turret. The turret rotates to face the marker and sweeps its barrel back and forth.

1. **Targeting Angle Sweep ($\theta_{sweep}$):**
   The angle width of the turret's fire cone is inversely proportional to the distance to the target marker.
   
   - Let $D_{target}$ be the distance from the turret to its target marker.
   - Let $D_{min} = 20.0$, $D_{max} = 100.0$ be the targeting distance constraints.
   - Let $\theta_{min} = 2.0^{\circ}$, $\theta_{max} = 60.0^{\circ}$ be the sweep constraints (for the Gunner turret).
   
   $$\theta_{sweep} = \text{lerp}(\theta_{max}, \theta_{min}, \text{clamp}(\text{remap}(\sqrt{D_{target}}, \sqrt{D_{min}}, \sqrt{D_{max}}, 0.0, 1.0), 0.0, 1.0))$$
   
   - *Behavior:* Placing the target close to the turret creates a wide, short-range defensive spray ($60^{\circ}$ spread). Placing the target far away concentrates the fire into a tight, long-range sniper stream ($2^{\circ}$ spread).

2. **Barrel Sweeping Animation:**
   The turret sweeps its barrel back and forth within the calculated angle:
   $$\theta(t) = \theta_{center} + \sin(t \cdot \omega) \cdot \frac{\theta_{sweep}}{2}$$
   where $\omega$ is the sweep speed.

3. **GPU Physics Projectiles:**
   Bullets are spawned on the GPU as physical rigidbodies. They possess velocity, radius, mass, and health (penetration count). The GPU physics solver integrates their motion and checks collisions against enemies.

#### Our Current System
Our turrets target using a designated cone angle set during placement. While the sweep logic is similar, the cone width is static, and the player cannot dynamically adjust the range and focus via a drag-and-drop focal target marker. Additionally, our targeting applies instantaneous raycast-like damage on the GPU rather than simulating physical projectiles.

#### Proposed Improvement Plan
1. **Interactive Target Placement:** Update the turret placement UI to allow dragging a target circle. Connect this target's distance to the turret's sweep angle using the remapped square-root equation.
2. **GPU Projectile System:** Expand the compute shader to simulate projectiles. Bullets will travel, check collisions via spatial hashing, bounce or penetrate, and decay.

---

## 3. Map Generation & Unwalkable Collisions

### Studio Game System
The Studio Game features a fully automated map pipeline:
1. **Image Mask:** Levels are loaded from a texture where pixels represent terrain/walkable paths.
2. **Jump-Flood SDF:** A compute shader seeds the image mask and runs a Jump-Flood Algorithm (JFA) to generate a high-precision Signed Distance Field (SDF).
3. **GPU Flow Field:** The Dijkstra vector field is computed on the GPU using the SDF and target coordinates.
4. **Collision Polygon Extraction:** During level loading, the CPU parses the SDF texture. It identifies regions where the distance is negative (unwalkable walls), runs a contour boundary-tracing algorithm to trace the edges, and runs a collinear simplification algorithm (or Ramer-Douglas-Peucker) to build `CollisionPolygon2D` vertices.
5. **Tower Placement Validation:** Tower placement is verified by checking if the tower's `BuildArea` circle shape is fully outside these unwalkable polygons using `Geometry2D.is_point_in_polygon`.

### Our Current System
Currently, we draw shapes in the editor (SmartShapeMap). In `main.gd`, we loop cell-by-cell on the CPU and check if the cell's center is walkable, setting individual obstacles in the FlowFieldManager. This is slow and limits map generation.

### Proposed Improvement Plan
Create a custom mask-based map generation system.
- Map data should load a 2D B&W png.
- Write a boundary tracer script `WorldGen.gd` that reads the obstacle map (or the generated flow field/SDF texture), extracts contours, simplifies them using collinear checks, and builds `CollisionPolygon2D` obstacles automatically.
- Let the player place towers anywhere on the map, validating placement using the generated polygons.

---

## 4. Architectural Enhancements Summary

To implement these systems, the following work steps are planned:

1. **Phase 1: Focal Target Targeting and Sweep Equations**
   - Modify `turret_placement_manager.gd` to support drawing target paths, drag-and-drop targets, and calculating distance-based remapped sweep angles.
   - Update `turret.gd` and the GPU compute shader `compute_physics.glsl` to handle dynamic targeting sweep angles.
   
2. **Phase 2: Mathematical Enemy Scaling**
   - Overhaul `main.gd` spawning logic to apply power-law radius, quadratic mass, and wave-progression health buffs.
   - Update `enemy_manager.gd` to store these values and write them into the GPU buffers.
   
3. **Phase 3: Automated Map Polygon Extraction**
   - Write `WorldGen` logic to automatically parse walkable/unwalkable mask files, trace contours, and instantiate collision polygons in the scene tree.
   - Hook up `TurretPlacementManager` to validate placement against these shapes.
