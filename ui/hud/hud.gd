extends CanvasLayer
class_name BattleHUD

## Standalone in-battle HUD. Instanced by battle.tscn but self-contained:
## label updates are driven by GlobalEvents signals (plus polling the enemy
## count), and player intent is reported back through the two signals below.
## Other systems find it via the "battle_hud" group (see AbilityManager).

signal next_wave_pressed
signal exit_requested

@onready var gold_label: Label = $Overlay/GoldLabel
@onready var wave_label: Label = $Overlay/WaveLabel
@onready var hp_label: Label = $Overlay/HPLabel
@onready var enemy_count_label: Label = $Overlay/EnemyCountLabel
@onready var next_wave_button: Button = $Overlay/NextWaveButton
@onready var countdown_label: Label = $Overlay/CountdownLabel
@onready var game_over_container: VBoxContainer = $Overlay/GameOverContainer
@onready var victory_container: VBoxContainer = $Overlay/VictoryContainer
@onready var mana_bar: ProgressBar = $Overlay/ManaBar
@onready var ability_container: HBoxContainer = $Overlay/AbilityContainer

var _last_enemy_count: int = -1

func _ready() -> void:
	add_to_group("battle_hud")
	GlobalEvents.gold_changed.connect(_on_gold_changed)
	GlobalEvents.wave_started.connect(_on_wave_started)
	GlobalEvents.wave_cleared.connect(_on_wave_cleared)
	GlobalEvents.inter_wave_tick.connect(_on_inter_wave_tick)
	GlobalEvents.base_hp_changed.connect(_on_base_hp_changed)
	next_wave_button.pressed.connect(func(): next_wave_pressed.emit())
	$Overlay/GameOverContainer/RestartButton.pressed.connect(func(): exit_requested.emit())
	$Overlay/VictoryContainer/PlayAgainButton.pressed.connect(func(): exit_requested.emit())
	next_wave_button.text = "Start Game"
	next_wave_button.visible = true

func _process(_delta: float) -> void:
	# No per-spawn/per-death signal exists at swarm scale — poll the live count.
	var alive: int = GPUSim.alive_count
	if alive != _last_enemy_count:
		_last_enemy_count = alive
		enemy_count_label.text = "Enemies: %d" % alive

func _on_gold_changed(amount: int) -> void:
	gold_label.text = "Gold: %d" % amount

func _on_wave_started(wave: int, _enemy_count: int) -> void:
	wave_label.text = "Wave: %d" % wave
	next_wave_button.visible = false
	countdown_label.visible = false

func _on_wave_cleared(_wave: int) -> void:
	next_wave_button.text = "Start Early"
	next_wave_button.visible = true

func _on_inter_wave_tick(seconds_left: float) -> void:
	countdown_label.visible = seconds_left > 0.0
	countdown_label.text = "Next Wave in: %ds" % ceili(seconds_left)

func _on_base_hp_changed(hp: int, max_hp: int) -> void:
	hp_label.text = "Base HP: %d/%d" % [hp, max_hp]

func show_game_over() -> void:
	game_over_container.visible = true
	next_wave_button.visible = false
	countdown_label.visible = false

func show_victory() -> void:
	victory_container.visible = true
	next_wave_button.visible = false
	countdown_label.visible = false
