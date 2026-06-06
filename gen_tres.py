import os

enemies = {
    'swarmer': {'enemy_name': '"Swarmer"', 'scale': 1.4, 'gold_yield': 3},
    'tank': {'enemy_name': '"Tank"', 'texture_path': '"res://assets/enemies/dino2.png"', 'scale': 1.4, 'speed': 60.0, 'health': 50.0, 'spawn_weight': 0.5, 'gold_yield': 10, 'armor': 0.3, 'min_wave': 3},
    'runner': {'enemy_name': '"Runner"', 'texture_path': '"res://assets/enemies/dino3.png"', 'scale': 1.4, 'speed': 200.0, 'health': 8.0, 'spawn_weight': 3.0, 'min_wave': 6},
    'armored': {'enemy_name': '"Armored"', 'texture_path': '"res://assets/enemies/dino4.png"', 'scale': 1.4, 'speed': 70.0, 'health': 80.0, 'spawn_weight': 2.0, 'gold_yield': 15, 'armor': 0.6, 'min_wave': 8},
    'mini_boss': {'enemy_name': '"Mini Boss"', 'texture_path': '"res://assets/enemies/dino2.png"', 'scale': 2.5, 'speed': 40.0, 'health': 500.0, 'spawn_weight': 0.0, 'gold_yield': 100, 'armor': 0.2, 'nexus_damage': 5, 'is_boss': 'true', 'min_wave': 5},
    'big_boss': {'enemy_name': '"Big Boss"', 'scale': 3.5, 'speed': 25.0, 'health': 2000.0, 'spawn_weight': 0.0, 'gold_yield': 500, 'armor': 0.4, 'nexus_damage': 10, 'is_boss': 'true', 'min_wave': 15},
    'flyer': {'enemy_name': '"Flyer"', 'texture_path': '"res://assets/enemies/dino3.png"', 'scale': 1.4, 'speed': 150.0, 'health': 15.0, 'spawn_weight': 1.5, 'gold_yield': 8, 'min_wave': 11},
    'splitter': {'enemy_name': '"Splitter"', 'texture_path': '"res://assets/enemies/dino2.png"', 'scale': 1.4, 'speed': 50.0, 'health': 120.0, 'spawn_weight': 1.0, 'gold_yield': 20, 'min_wave': 13}
}

tres_template = """[gd_resource type="Resource" script_class="EnemyResource" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/enemy_resource.gd" id="1_script"]

[resource]
script = ExtResource("1_script")
{properties}
"""

os.makedirs('resources/enemies', exist_ok=True)
for key, props in enemies.items():
    prop_str = '\n'.join(f'{k} = {v}' for k, v in props.items())
    content = tres_template.replace('{properties}', prop_str)
    with open(f'resources/enemies/{key}.tres', 'w') as f:
        f.write(content)
