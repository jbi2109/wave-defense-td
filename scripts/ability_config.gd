extends Resource
class_name AbilityConfig

@export var name: String = ""
@export var cost: float = 0.0
@export var cooldown: float = 0.0
@export var radius: float = 0.0
@export var damage: float = 0.0
@export var duration: float = 0.0
@export var bounces: int = 0
@export var bounce_range: float = 0.0
@export var multiplier: float = 1.0
@export var slow_factor: float = 0.0
@export_enum("target", "instant") var type: String = "target"
