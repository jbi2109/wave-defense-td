import sys
from PIL import Image
import numpy as np

filepath = r"f:\GodotGames\wave-defense-td\assets\turrets\base.png"
img = Image.open(filepath).convert("RGBA")

# It seems there is a green edge on the bottom and right.
# We will just crop 25 pixels off all sides to be safe and remove any boundary artifacts.
width, height = img.size
cropped = img.crop((25, 25, width - 25, height - 25))

cropped.save(filepath)
print(f"Cropped base.png to {cropped.size}")
