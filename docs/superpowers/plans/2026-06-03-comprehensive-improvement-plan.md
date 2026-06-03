# Comprehensive Game Improvement Plan (Studio Game Comparison)

This plan provides an exhaustive roadmap to overhaul, optimize, and expand the systems in `wave-defense-td` to match and exceed the features of the game studio's gold standard game `Sir, we have an orc problem`. 

---

## Part 1: Physics Engine Overhaul (100% GPU Rigidbodies)

### 1.1 Complete Projectile Integration in GPU Sim
The Studio Game does not calculate damage immediately. It treats every projectile (bullets, cannonballs, mortar fragments, rockets, flames) as a dynamic physical body simulated on the GPU.
- **Implement Projectile Buffer:** Add a `struct Projectile { vec2 pos; vec2 vel; float radius; float mass; float health; float lifetime; uint contact_handler; }` buffer inside `compute_physics.glsl`.
- **Integrate Motion:** Write a compute shader pass that simulates velocity, drag, and lifetime depletion for all active projectiles.
- **Implement Projectile Spatial Grid Binning:** Projectiles must be binned into the same spatial grid cells as enemies, allowing highly optimized local collision tests on the GPU.

### 1.2 GPU Contact Handlers and Collision Solvers
- **Add Contact Handlers:** Implement the contact handler struct on the GPU:
  ```glsl
  struct ContactHandler {
      float damage_self;      // Damage applied to the projectile (usually 1.0 to destroy it)
      float damage_other;     // Damage applied to the enemy (e.g. 5.0)
      float damage_falloff;   // 0.0 for flat damage, 1.0 for linear AoE falloff
      uint flags;             // Bitflags (1: destroy on contact, 2: apply slow, 4: pierce)
      float fire_timer;       // Timer to apply tick damage
  };
  ```
- **Physics Solver Integrations:** 
  - Bullet-vs-Enemy collisions: Evaluate overlapping circles. On contact, decrement the bullet's health and apply `damage_other` to the enemy.
  - Bullet-vs-Wall collisions: Sample the SDF texture. If the distance to the wall is less than the bullet's radius, resolve the collision. Cannonballs and bullets should bounce or spark, whereas rockets explode and flames decay.

---

## Part 2: Interactive Target Dragging & Remapped Sweeps

### 2.1 Full Interactive Drag & Drop Target Markers
- **Focal Target Nodes:** During the BUILD phase, every turret placed in the scene must instantiate a visual `FocalTarget` indicator sprite (`assets/turrets/target.png`) in the level.
- **Target Editing UI:** When the player clicks on a built turret during the BUILD phase, it displays:
  - An arc preview showing the exact sweep angle boundary lines.
  - A distance indicator illustrating the turret's reach.
  - Drag-and-drop handles on the Target Marker to allow the player to position it.
- **remapped sweep cone equations:** 
  Ensure the math matches:
  $$\theta_{sweep} = \text{lerp}(\theta_{max}, \theta_{min}, \text{clamp}(\text{remap}(\sqrt{D}, \sqrt{D_{min}}, \sqrt{D_{max}}, 0.0, 1.0), 0.0, 1.0))$$
  - Gunner: min angle $2^{\circ}$, max angle $60^{\circ}$, range 100.
  - Cannon: min angle $0.5^{\circ}$, max angle $30^{\circ}$, range 200.

### 2.2 Visual Targeting Previews
- **Arc Preview Shaders:** Implement the dotted spread-preview line shader (`res://levels/world/flow_preview_sprite.gdshader` style) to display the dynamic targeting boundaries as the player drags the target marker.
- **Dynamic Speed Modulation:** When the target is close, the sweep speed $\omega$ increases to allow spraying nearby groups. When the target is far, the sweep speed decreases for high-precision sniper fire.

---

## Part 3: Mask-Based Map Pipeline & Polygon Extraction

### 3.1 Signed Distance Field (SDF) and Dijkstra Flow Fields on GPU
The Studio Game parses obstacle maps directly from image masks.
- **Jump-Flood Shader (`world_gen/sdf`):** Implement a GPU-side Jump-Flood Algorithm (JFA) shader inside our codebase. The shader will read a B&W PNG map layout (Black = Wall, White = Path):
  - Pass 1 (`seed.glsl`): Write maximum coordinates for boundary pixels.
  - Pass 2 (`jump_flood.glsl`): Ping-pong dispatches doubling distances ($1, 2, 4, 8, 16, \dots$).
  - Pass 3 (`finalize.glsl`): Output the Euclidean distance to the nearest wall.
- **GPU Pathfinding flow field (`world_gen/flow_field`):** 
  Implement Dijkstra flow fields directly on the GPU using a flood-fill texture update shader. The shader initializes the Nexus coordinate as zero, and spreads outward through walkable pixels, choosing the path of least cost (taking SDF distance and enemy density into account).

### 3.2 Automated Collision Shape Generator (`WorldGen.gd`)
- **Marching Squares & Boundary Tracing:** Write a CPU-side parser that reads the generated SDF image:
  - Find all closed loops where the distance is less than zero (walls).
  - Run a marching squares or boundary tracing loop to extract vertex loops.
- **Ramer-Douglas-Peucker (RDP) Simplification:** Run collinear simplification checks to reduce thousands of pixel-based points into clean, low-vertex polygons.
- **Collision Creation:** Instantiate `CollisionPolygon2D` nodes inside an Area2D container under the map root, allowing Godot's physics engine and `TurretPlacementManager` to query boundaries natively.

---

## Part 4: Upgrade Systems & Persistent Tech Trees

### 4.1 Upgrades Spreadsheet Integration
- **Upgrades Resource Sheets:** Define all turret upgrades (Cannon Count, Cannon Damage, Flamethrower Range, etc.) as custom resources (`UpgradeData`) or spreadsheets.
- **Tech Tree UI:** Create a dedicated Main Menu Scene for the **Tech Tree** (similar to `res://tech_tree/tech_tree.tscn`).
  - Tech tree nodes representing unlocks (e.g., unlocking Laser Turret or Flamethrower).
  - Upgrades representing stat increments (e.g., Cannon penetration count +1).
  - Nodes draw connection paths showing unlock requirements.
- **Tech Tree Autoload (`tech_tree.gd`):** 
  Create a global autoload node that tracks upgrade purchase states, manages the current marks (currency), and exposes helper methods like `TechTree.get_upgrade(&"cannon_damage").current_value` to turret scripts.

### 4.2 Dynamic Stat Upgrades
- In `turret.gd`, rewrite the base stats to add the autoload values:
  `damage = BASE_DAMAGE + TechTree.get_upgrade("gatling_damage").current_value`
  `fire_rate = BASE_FIRE_RATE + TechTree.get_upgrade("gatling_firerate").current_value`
  - Re-upload updated stats to the GPU `TurretBuffer` whenever an upgrade is purchased or when a turret is constructed.

---

## Part 5: Sound & Visual Juiciness (Screenshakes & Tracers)

### 5.1 Polyphonic Sound Managers
- **AudioManager Autoload:** The Studio Game uses polyphonic audio playback to handle hundreds of gunshots and explosions without clicking or performance drops.
  - Implement `AudioStreamPlayer2D` pools in `sound_manager.gd`.
  - Use `AudioStreamPlaybackPolyphonic` for high-frequency turrets (like the Gatling turret firing 10 rounds per second).
- **Pitch Randomization:** Apply a pitch scale modifier between $0.9$ and $1.1$ on all SFX to make repetitive sounds feel organic and less grating.

### 5.2 Compute-Driven Visual Particles & Emitters
- **GPU Corpses & Blood Splatters:** 
  Instead of instantiating individual CPUParticles2D nodes on the CPU when an enemy dies (which drops framerate at 10k+ counts), write death positions into a static GPU texture (`corpses_tex`).
  - Use a CanvasItem shader on a single fullscreen overlay quad to sample `corpses_tex` and paint blood splatters, scorch marks, and skeletal remains directly onto the background.
- **Damage Text Pools:**
  Implement a dynamic floating text system using a custom canvas item draw script that batches numbers in a single vertex array, rather than instantiating Control/Label nodes.
