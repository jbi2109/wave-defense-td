# ECC Memory State
## Active Mission
Executing the implementation plan to align `wave-defense-td` with `Sir, we have an orc problem` systems (Map generation, Turret Placement, Scaling).

## Accumulated Discoveries
- Both games use GPU compute for SDF and flow field generation.
- Reference game successfully avoids invisible corners by downloading the generated SDF to CPU, tracing the boundary, and instantiating exact `CollisionPolygon2D`s.
- Reference game scales enemies via `0.2 * r^2 * (1+time) * 2.5^(level-1)`. The user already adopted this but placed it directly inside `enemy_manager.gd`. Needs abstraction to a GameManager singleton.

## Next Steps
- Port `world_gen.gd` from the reference game to the user's game.
