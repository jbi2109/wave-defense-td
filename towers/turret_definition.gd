extends Node
class_name TurretDefinition

@export var turret_name: String = ""
@export var turret_type: String = ""
@export var damage: float = 5.0
@export var attack_range: float = 300.0
@export var fire_rate: float = 0.2
@export var scale: float = 1.0
@export var cost: int = 50

# Upgrades & Attributes
@export var upgrade_cost: int = 50
@export var max_level: int = 3
@export var rotates: bool = true
@export var sprite_path: String = ""

@export_group("Upgrade Stats")
@export var damage_upgrade: float = 2.5
@export var damage_upgrade_multiplies: bool = false
@export var speed_upgrade: float = 1.5
@export var speed_upgrade_multiplies: bool = true

