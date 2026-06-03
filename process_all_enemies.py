from PIL import Image, ImageDraw
import os

def process_enemy_sheet(src_path, dst_path, cols, rows, is_dullahan=False):
    print(f"Processing {src_path} -> {dst_path} ({cols}x{rows})")
    img = Image.open(src_path).convert("RGBA")
    w, h = img.size
    
    # Calculate cell dimensions
    cell_w = w // cols
    cell_h = h // rows
    
    # Background color is at (0,0)
    bg_color = img.getpixel((0, 0))
    
    frames = []
    
    for r in range(rows):
        for c in range(cols):
            # Crop the cell
            x0 = c * cell_w
            y0 = r * cell_h
            x1 = x0 + cell_w
            y1 = y0 + cell_h
            
            cell = img.crop((x0, y0, x1, y1)).convert("RGBA")
            
            # If dullahan, cover the text label at top-left
            if is_dullahan:
                draw = ImageDraw.Draw(cell)
                # Overwrite top-left region with background color
                draw.rectangle([0, 0, int(cell_w * 0.3), int(cell_h * 0.15)], fill=bg_color)
                
            # Perform flood fill from corners to make background transparent
            # We use a color tolerance of 100
            for start_point in [(0, 0), (cell_w - 1, 0), (0, cell_h - 1), (cell_w - 1, cell_h - 1)]:
                # Check if the pixel is not already transparent
                p = cell.getpixel(start_point)
                if p[3] > 0:
                    ImageDraw.floodfill(cell, start_point, (0, 0, 0, 0), thresh=100)
            
            # Additional cleanup of any stray green pixels around borders
            # (Just in case floodfill didn't reach everything)
            cell_pixels = cell.load()
            tolerance = 60
            for y in range(cell_h):
                for x in range(cell_w):
                    p = cell_pixels[x, y]
                    if p[3] > 0:
                        dist = abs(p[0] - bg_color[0]) + abs(p[1] - bg_color[1]) + abs(p[2] - bg_color[2])
                        if dist < tolerance:
                            cell_pixels[x, y] = (0, 0, 0, 0)
                            
            # Resize frame to target size (24x24)
            resized_cell = cell.resize((24, 24), Image.Resampling.LANCZOS)
            frames.append(resized_cell)
            
    # Pad or slice to exactly 24 frames
    original_count = len(frames)
    if original_count < 24:
        # Loop walk cycle to pad to 24 frames
        while len(frames) < 24:
            frames.append(frames[len(frames) % original_count])
    elif original_count > 24:
        # Slice to 24 frames
        frames = frames[:24]
        
    # Stitch frames horizontally
    total_w = 24 * 24
    total_h = 24
    
    stitched = Image.new("RGBA", (total_w, total_h))
    for idx, f in enumerate(frames):
        stitched.paste(f, (idx * 24, 0))
        
    # Save the output
    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    stitched.save(dst_path)
    print(f"Successfully saved stitched sheet of size {stitched.size} to {dst_path}")

if __name__ == "__main__":
    src_dir = r"C:\Users\jbijo\.gemini\antigravity\brain\b6490d31-bb78-4086-8308-78eb2028aa47"
    enemy_configs = {
        "ghoul.png": {
            "file": "drowned_ghoul_1779909865609.png",
            "cols": 6,
            "rows": 4
        },
        "abomination.png": {
            "file": "flesh_abomination_1779909914943.png",
            "cols": 5,
            "rows": 4
        },
        "hound.png": {
            "file": "plague_hound_1779909889897.png",
            "cols": 4,
            "rows": 6
        },
        "draugr.png": {
            "file": "draugr_warrior_1779909937307.png",
            "cols": 5,
            "rows": 4
        },
        "dullahan.png": {
            "file": "dullahan_1779909959670.png",
            "cols": 4,
            "rows": 4,
            "is_dullahan": True
        },
        "lich.png": {
            "file": "lich_king_1779909980696.png",
            "cols": 4,
            "rows": 6
        },
        "banshee.png": {
            "file": "banshee_bat_1779910009136.png",
            "cols": 4,
            "rows": 6
        },
        "sludge.png": {
            "file": "crypt_sludge_1779910032251.png",
            "cols": 6,
            "rows": 4
        }
    }
    
    for dst_name, cfg in enemy_configs.items():
        src_path = os.path.join(src_dir, cfg["file"])
        dst_path = os.path.join("assets/enemies", dst_name)
        is_dullahan = cfg.get("is_dullahan", False)
        process_enemy_sheet(src_path, dst_path, cfg["cols"], cfg["rows"], is_dullahan)
