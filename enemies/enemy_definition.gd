extends Resource
class_name EnemyDefinition

@export var enemy_name: String    = "Swarmer"
@export var texture_path: String  = "res://enemies/art/dino1.png"
@export var hframes: int          = 24
@export var scale: float          = 1.0
@export var speed: float          = 120.0
@export var health: float         = 10.0
@export var spawn_weight: float   = 10.0

# Economy
@export var gold_yield: int       = 5     ## Gold awarded to player on kill

# Combat
@export var armor: float          = 0.0   ## Damage reduction (0=none, 1=immune)
@export var nexus_damage: int     = 1     ## HP removed from nexus on reach

# Identity / behaviour flags
@export var is_boss: bool         = false ## Boss enemies trigger special HUD
@export var min_wave: int         = 1     ## Wave this type starts appearing
@export var death_effect: String  = ""    ## e.g. "explosion", "split" (future)

@export var is_flying: bool        = false ## Flying enemies ignore flow fields
@export var split_count: int       = 0     ## How many smaller swarmers spawn on death
@export var split_type_index: int  = 0     ## Type index of spawned swarmers

