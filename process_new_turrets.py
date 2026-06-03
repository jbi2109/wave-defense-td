import glob
import os
from PIL import Image, ImageDraw

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
        
        # Detect background color (look for green in corners)
        bg_color = None
        for corner in [(0, 0), (w-1, 0), (0, h-1), (w-1, h-1)]:
            pix = img.getpixel(corner)
            if pix[1] > 120 and pix[1] > pix[0] + 20 and pix[1] > pix[2] + 20:
                bg_color = pix
                break
        if not bg_color:
            bg_color = img.getpixel((0, 0))
            
        # Pad by 1 pixel with bg_color to ensure floodfill escapes properly
        padded = Image.new("RGBA", (w + 2, h + 2), bg_color)
        padded.paste(img, (1, 1))
        
        # Flood fill from (0,0)
        ImageDraw.floodfill(padded, (0, 0), (0, 0, 0, 0), thresh=120)
        
        # Crop back
        img = padded.crop((1, 1, w + 1, h + 1))
        
        # Clean green outlines/shadows (both color distance and green tinge check)
        pixels = img.load()
        for y in range(h):
            for x in range(w):
                p = pixels[x, y]
                if p[3] > 0:
                    dist = abs(p[0] - bg_color[0]) + abs(p[1] - bg_color[1]) + abs(p[2] - bg_color[2])
                    is_green = (p[1] > p[0] + 15 and p[1] > p[2] + 15)
                    if dist < 160 or is_green:
                        # Check if bordering transparency
                        is_border = False
                        for dx, dy in [(-1,0), (1,0), (0,-1), (0,1)]:
                            nx, ny = x+dx, y+dy
                            if 0 <= nx < w and 0 <= ny < h:
                                if pixels[nx, ny][3] == 0:
                                    is_border = True
                                    break
                            else:
                                is_border = True
                                break
                        if is_border:
                            pixels[x, y] = (0, 0, 0, 0)
                            
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
