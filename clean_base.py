import sys
from PIL import Image

filepath = r"f:\GodotGames\wave-defense-td\assets\turrets\base.png"
img = Image.open(filepath).convert("RGBA")
pixels = img.load()
width, height = img.size

# We look for pixels that are very bright green.
# E.g. R < 100, G > 200, B < 100
for y in range(height):
    for x in range(width):
        r, g, b, a = pixels[x, y]
        if g > 150 and r < 100 and b < 100 and a > 0:
            pixels[x, y] = (0, 0, 0, 0)
        # Also clean up anti-aliased green edges
        elif g > r * 1.5 and g > b * 1.5 and g > 100 and a > 0:
            pixels[x, y] = (0, 0, 0, 0)

img.save(filepath)
print("Cleaned green edge from base.png")
