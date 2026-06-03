import sys
from PIL import Image

filepath = r"C:\Users\jbijo\.gemini\antigravity\brain\b6490d31-bb78-4086-8308-78eb2028aa47\flamethrower_turret_1779750237557.png"
img = Image.open(filepath).convert("RGBA")
pixels = img.load()

for y in range(5):
    for x in range(5):
        print(f"({x},{y}): {pixels[x,y]}")
