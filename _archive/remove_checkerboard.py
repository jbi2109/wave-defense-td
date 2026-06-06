import sys
from PIL import Image

filepath = r"C:\Users\jbijo\.gemini\antigravity\brain\b6490d31-bb78-4086-8308-78eb2028aa47\flamethrower_turret_1779750237557.png"
img = Image.open(filepath).convert("RGBA")
pixels = img.load()
width, height = img.size

# We will sample the 4 corners to find the background colors
corners = [
    pixels[0, 0],
    pixels[width - 1, 0],
    pixels[0, height - 1],
    pixels[width - 1, height - 1]
]

# We might also just want to sample every pixel on the border to build a list of background colors
# But a checkerboard usually only has 2 colors. Let's just sample the border and add any color to our bg_colors list
bg_colors = []
for x in range(width):
    bg_colors.append(pixels[x, 0])
    bg_colors.append(pixels[x, height - 1])
for y in range(height):
    bg_colors.append(pixels[0, y])
    bg_colors.append(pixels[width - 1, y])

# We only want to keep unique colors, but there will be noise.
# So let's define a function that checks if a color is close to ANY of the border colors.
def is_bg(r, g, b, border_colors, tolerance=30):
    # Actually, comparing against all border colors is slow. 
    # Let's just find the average of the "light" border colors and "dark" border colors.
    # Or just use the corners.
    for c in corners:
        if abs(r - c[0]) < tolerance and abs(g - c[1]) < tolerance and abs(b - c[2]) < tolerance:
            return True
    return False

# Since it's a checkerboard, the corners might both be the "light" square or "dark" square.
# Let's find two distinct colors from the border.
distinct_bg = [corners[0]]
for c in bg_colors:
    found = False
    for d in distinct_bg:
        if abs(c[0] - d[0]) < 15 and abs(c[1] - d[1]) < 15 and abs(c[2] - d[2]) < 15:
            found = True
            break
    if not found and len(distinct_bg) < 4:  # At most 4 distinct background colors
        distinct_bg.append(c)

print("Detected background colors:", distinct_bg)

# Flood fill
visited = set()
stack = []
for x in range(width):
    stack.append((x, 0))
    stack.append((x, height - 1))
for y in range(height):
    stack.append((0, y))
    stack.append((width - 1, y))

while stack:
    x, y = stack.pop()
    if (x, y) in visited:
        continue
    visited.add((x, y))
    
    r, g, b, a = pixels[x, y]
    if a == 0:
        continue
        
    # Check if it matches any of the distinct background colors
    is_background = False
    for d in distinct_bg:
        if abs(r - d[0]) < 25 and abs(g - d[1]) < 25 and abs(b - d[2]) < 25:
            is_background = True
            break
            
    if is_background:
        pixels[x, y] = (0, 0, 0, 0)
        if x > 0: stack.append((x - 1, y))
        if x < width - 1: stack.append((x + 1, y))
        if y > 0: stack.append((x, y - 1))
        if y < height - 1: stack.append((x, y + 1))

# Find bounding box
min_x, min_y, max_x, max_y = width, height, 0, 0
for y in range(height):
    for x in range(width):
        if pixels[x, y][3] > 0:
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x)
            max_y = max(max_y, y)

if min_x <= max_x and min_y <= max_y:
    img = img.crop((min_x, min_y, max_x + 1, max_y + 1))

out_path = "assets/turrets/flamethrower.png"
img.save(out_path, format="PNG")
print("Saved transparent image to", out_path)
