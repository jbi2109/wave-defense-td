import os

turrets = {
    'gatling': {'turret_type': 'gatling', 'damage_override': 10.0, 'attack_range': 200.0, 'fire_rate_override': 0.5, 'size_override': 1.33},
    'flamethrower': {'turret_type': 'laser', 'damage_override': 0.5, 'attack_range': 250.0, 'fire_rate_override': 0.05, 'size_override': 0.4},
    'raygun': {'turret_type': 'ray', 'damage_override': 0.5, 'attack_range': 300.0, 'fire_rate_override': 2.0, 'size_override': 0.28},
    'explosive': {'turret_type': 'melee', 'damage_override': 5.0, 'attack_range': 100.0, 'fire_rate_override': 1.0, 'size_override': 1.0},
    'frost_tower': {'turret_type': 'slow', 'damage_override': 0.2, 'attack_range': 180.0, 'fire_rate_override': 0.8, 'size_override': 0.4}
}

tscn_template = """[gd_scene load_steps=2 format=3 uid="uid://c..."]

[ext_resource type="PackedScene" uid="uid://c867r5v5frnt0" path="res://prefabs/turret.tscn" id="1_base"]

[node name="Turret" instance=ExtResource("1_base")]
{properties}
"""

os.makedirs('prefabs/turrets', exist_ok=True)
for key, props in turrets.items():
    prop_str = '\n'.join(f'{k} = {v}' if isinstance(v, float) else f'{k} = "{v}"' for k, v in props.items())
    content = tscn_template.replace('{properties}', prop_str)
    with open(f'prefabs/turrets/{key}.tscn', 'w') as f:
        f.write(content)
