import sys

with open('scenes/main.tscn', 'r') as f:
    lines = f.readlines()

new_lines = []
skip = False
for line in lines:
    if line.startswith('[node name="GatlingGun"') or \
       line.startswith('[node name="Flamethrower"') or \
       line.startswith('[node name="Raygun"') or \
       line.startswith('[node name="Explosive"') or \
       line.startswith('[node name="FrostTower"') or \
       line.startswith('[node name="Swarmer"') or \
       line.startswith('[node name="Tank"') or \
       line.startswith('[node name="Runner"') or \
       line.startswith('[node name="Armored"') or \
       line.startswith('[node name="MiniBoss"') or \
       line.startswith('[node name="BigBoss"') or \
       line.startswith('[node name="Flyer"') or \
       line.startswith('[node name="Splitter"'):
        skip = True
        continue
    
    if skip and line.startswith('[node '):
        skip = False
        
    if not skip:
        if 'overlap_weight =' in line:
            continue
        new_lines.append(line)

with open('scenes/main.tscn', 'w') as f:
    f.writelines(new_lines)
