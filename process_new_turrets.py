import glob
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

def clean_green_outline(img, bg_color):
    w, h = img.size
    for _ in range(5):
        img_copy = img.copy()
        pixels_copy = img_copy.load()
        pixels_orig = img.load()
        cleaned_any = False
        
        for y in range(h):
            for x in range(w):
                p = pixels_copy[x, y]
                if p[3] > 0:
                    dist = abs(p[0] - bg_color[0]) + abs(p[1] - bg_color[1]) + abs(p[2] - bg_color[2])
                    is_green = (p[1] > p[0] + 15 and p[1] > p[2] + 15 and p[1] > 80)
                    if dist < 160 or is_green:
                        is_border = False
                        for dx, dy in [(-1,0), (1,0), (0,-1), (0,1)]:
                            nx, ny = x+dx, y+dy
                            if 0 <= nx < w and 0 <= ny < h:
                                if pixels_copy[nx, ny][3] < 120:
                                    is_border = True
                                    break
                            else:
                                is_border = True
                                break
                        if is_border:
                            pixels_orig[x, y] = (0, 0, 0, 0)
                            cleaned_any = True
        if not cleaned_any:
            break

def process_image(src_pattern, dst_path):
    files = glob.glob(src_pattern)
    if not files:
        print(f"No files found for {src_pattern}")
        return
    
    filepath = files[-1]
    print(f"Processing {filepath}")
    
    try:
        img = Image.open(filepath).convert("RGBA")
        w, h = img.size
        
        # Detect background color
        bg_color = find_green_background(img)
        if not bg_color:
            bg_color = (0, 255, 0, 255)
            
        # Clear white border frame from corners
        for corner in [(0, 0), (w-1, 0), (0, h-1), (w-1, h-1)]:
            ImageDraw.floodfill(img, corner, (0, 0, 0, 0), thresh=80)
            
        # Globally floodfill from any chroma green pixel to clear pockets
        pixels = img.load()
        for y in range(h):
            for x in range(w):
                p = pixels[x, y]
                if p[3] > 0:
                    is_chroma_green = (p[1] > 180 and p[0] < 100 and p[2] < 100)
                    if is_chroma_green:
                        ImageDraw.floodfill(img, (x, y), (0, 0, 0, 0), thresh=120)
            
        # Clean outlines on the high-res image
        clean_green_outline(img, bg_color)
        
        # Crop to contents
        bbox = img.getbbox()
        if bbox:
            img = img.crop(bbox)
            
        img.save(dst_path, format="PNG")
        print(f"Saved to {dst_path}")
    except Exception as e:
        print(f"Error processing {filepath}: {e}")

src_dir = r"C:\Users\jbijo\.gemini\antigravity\brain\b6490d31-bb78-4086-8308-78eb2028aa47"

process_image(os.path.join(src_dir, "turret_base_new_*.png"), "assets/turrets/base.png")
process_image(os.path.join(src_dir, "gun_gatling_*.png"), "assets/turrets/technoturret.png")
process_image(os.path.join(src_dir, "gun_flamethrower_*.png"), "assets/turrets/flamethrower.png")
process_image(os.path.join(src_dir, "gun_raygun_*.png"), "assets/turrets/reallaser.png")
process_image(os.path.join(src_dir, "gun_frost_*.png"), "assets/turrets/frost_turret.png")
