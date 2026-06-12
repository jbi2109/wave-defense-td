extends Resource
class_name MapConfig

## Per-map gameplay configuration. Each map scene exports one of these on its
## root (see levels/map_*_config.tres), so a map carries its own wave pacing,
## base HP and starting gold — drop a new map in without touching battle.tscn.

@export var base_enemies_per_wave: int = 100
@export var wave_scaler: float = 1.1
@export var spawn_rate: float = 0.001  ## Seconds between individual spawns
@export var inter_wave_duration: float = 30.0  ## Seconds between waves
@export var max_waves: int = 15

@export var base_hp: int = 10  ## Nexus hit points (enemies deal EnemyDefinition.nexus_damage per leak)
@export var starting_gold: int = 150
