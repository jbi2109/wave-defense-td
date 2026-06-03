import os
from PIL import Image, ImageDraw

def find_green_background(img):
    w, h = img.size
    green_counts = {}
    for y in range(0, h, max(1, h // 30)):
        for x in range(0, w, max(1, w // 30)):
            p = img.getpixel((x, y))
            if p[1] > 80 and p[1] > p[0] + 15 and p[1] > p[2] + 15:
                key = (p[0] // 10 * 10, p[1] // 10 * 10, p[2] // 10 * 10)
                green_counts[key] = green_counts.get(key, 0) + 1
    if not green_counts:
        return None
    best_key = max(green_counts, key=green_counts.get)
    sum_r = sum_g = sum_b = count = 0
    for y in range(0, h, max(1, h // 40)):
        for x in range(0, w, max(1, w // 40)):
            p = img.getpixel((x, y))
            key = (p[0] // 10 * 10, p[1] // 10 * 10, p[2] // 10 * 10)
            if key == best_key:
                sum_r += p[0]
                sum_g += p[1]
                sum_b += p[2]
                count += 1
    if count > 0:
        return (sum_r // count, sum_g // count, sum_b // count, 255)
    return (best_key[0], best_key[1], best_key[2], 255)

src_dir = r"C:\Users\jbijo\.gemini\antigravity\brain\b6490d31-bb78-4086-8308-78eb2028aa47"
p = os.path.join(src_dir, "banshee_bat_1779910009136.png")
img = Image.open(p).convert("RGBA")
w, h = img.size

bg_color = find_green_background(img)
print("Detected bg_color:", bg_color)

# Clear white border frame from corners
for corner in [(0, 0), (w-1, 0), (0, h-1), (w-1, h-1)]:
    ImageDraw.floodfill(img, corner, (0, 0, 0, 0), thresh=80)

# Find green background point
green_point = None
for y in range(h):
    for x in range(w):
        p_val = img.getpixel((x, y))
        if p_val[3] > 0 and p_val[1] > p_val[0] + 20 and p_val[1] > p_val[2] + 20:
            green_point = (x, y)
            break
    if green_point:
        break

print("Detected green point for floodfill:", green_point)
if green_point:
    ImageDraw.floodfill(img, green_point, (0, 0, 0, 0), thresh=120)

# Check if image is empty or not
pixels = img.load()
opaque_count = 0
for y in range(h):
    for x in range(w):
        if pixels[x, y][3] > 0:
            opaque_count += 1

print("Opaque pixels remaining after keying:", opaque_count)
