extends Node

# Nexus
@warning_ignore("unused_signal")
signal nexus_damaged(amount: int)
@warning_ignore("unused_signal")
signal nexus_destroyed

# Economy
@warning_ignore("unused_signal")
signal enemy_killed(type_idx: int, position: Vector2, gold_yield: int)
@warning_ignore("unused_signal")
signal gold_changed(new_amount: int)
@warning_ignore("unused_signal")
signal mana_changed(current_mana: float, max_mana: float)

# Waves
@warning_ignore("unused_signal")
signal wave_started(wave_num: int, enemy_count: int)
@warning_ignore("unused_signal")
signal wave_cleared(wave_num: int)
@warning_ignore("unused_signal")
signal inter_wave_tick(seconds_remaining: float)

# Turrets
@warning_ignore("unused_signal")
signal turret_placed(turret_type: String, position: Vector2)
@warning_ignore("unused_signal")
signal turret_upgraded(turret_node: Node)
@warning_ignore("unused_signal")
signal turret_sold(turret_node: Node)
