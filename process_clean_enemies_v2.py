from PIL import Image, ImageDraw
import os

def process_enemy_sheet(src_path, dst_path, cols, rows, walk_row, is_dullahan=False):
    print(f"Processing {src_path} -> {dst_path} (row {walk_row} of {cols}x{rows})")
    img = Image.open(src_path).convert("RGBA")
    w, h = img.size
    
    # Calculate cell dimensions
    cell_w = w // cols
    cell_h = h // rows
    
    # Detect background color (look for green in corners)
    bg_color = None
    for corner in [(0, 0), (w-1, 0), (0, h-1), (w-1, h-1)]:
        pix = img.getpixel(corner)
        if pix[1] > 120 and pix[1] > pix[0] + 20 and pix[1] > pix[2] + 20:
            bg_color = pix
            break
    if not bg_color:
        bg_color = img.getpixel((0, 0))
    
    # Extract only the walk_row cells
    walk_frames = []
    for c in range(cols):
        x0 = c * cell_w
        y0 = walk_row * cell_h
        x1 = x0 + cell_w
        y1 = y0 + cell_h
        
        cell = img.crop((x0, y0, x1, y1)).convert("RGBA")
        
        # If dullahan, cover the text label at top-left
        if is_dullahan:
            draw = ImageDraw.Draw(cell)
            draw.rectangle([0, 0, int(cell_w * 0.3), int(cell_h * 0.15)], fill=bg_color)
            
        # Pad the cell by 1 pixel with bg_color to ensure contiguous background
        padded = Image.new("RGBA", (cell_w + 2, cell_h + 2), bg_color)
        padded.paste(cell, (1, 1))
        
        # Flood fill transparently from (0, 0)
        ImageDraw.floodfill(padded, (0, 0), (0, 0, 0, 0), thresh=120)
        
        # Crop back to cell_w x cell_h
        cell = padded.crop((1, 1, cell_w + 1, cell_h + 1))
        
        # Clean green outlines/shadows (both color distance and green tinge check)
        cell_pixels = cell.load()
        for y in range(cell_h):
            for x in range(cell_w):
                p = cell_pixels[x, y]
                if p[3] > 0:
                    dist = abs(p[0] - bg_color[0]) + abs(p[1] - bg_color[1]) + abs(p[2] - bg_color[2])
                    is_green = (p[1] > p[0] + 15 and p[1] > p[2] + 15)
                    if dist < 160 or is_green:
                        # Check if bordering transparency
                        is_border = False
                        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
                            nx, ny = x + dx, y + dy
                            if 0 <= nx < cell_w and 0 <= ny < cell_h:
                                if cell_pixels[nx, ny][3] == 0:
                                    is_border = True
                                    break
                            else:
                                is_border = True
                                break
                        if is_border:
                            cell_pixels[x, y] = (0, 0, 0, 0)
                            
        # Resize to 24x24
        resized_cell = cell.resize((24, 24), Image.Resampling.LANCZOS)
        walk_frames.append(resized_cell)
        
    # Construct the final 24 frames
    final_frames = []
    
    # Frames 0-3: Idle (Frame 0 repeated)
    for _ in range(4):
        final_frames.append(walk_frames[0])
        
    # Frames 4-9: Walk (Loop of walk_frames)
    for i in range(6):
        final_frames.append(walk_frames[i % cols])
        
    # Frames 10-14: Sprint (Loop of walk_frames)
    for i in range(5):
        final_frames.append(walk_frames[i % cols])
        
    # Frames 15-23: Rest (Frame 0 repeated)
    for _ in range(9):
        final_frames.append(walk_frames[0])
        
    # Stitch frames horizontally
    total_w = 24 * 24
    total_h = 24
    
    stitched = Image.new("RGBA", (total_w, total_h))
    for idx, f in enumerate(final_frames):
        stitched.paste(f, (idx * 24, 0))
        
    # Save the output
    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    stitched.save(dst_path)
    print(f"Successfully saved stitched sheet to {dst_path}")

if __name__ == "__main__":
    src_dir = r"C:\Users\jbijo\.gemini\antigravity\brain\b6490d31-bb78-4086-8308-78eb2028aa47"
    enemy_configs = {
        "ghoul.png": {"file": "drowned_ghoul_1779909865609.png", "cols": 6, "rows": 4, "walk_row": 1},
        "abomination.png": {"file": "flesh_abomination_1779909914943.png", "cols": 5, "rows": 4, "walk_row": 1},
        "hound.png": {"file": "plague_hound_1779909889897.png", "cols": 4, "rows": 6, "walk_row": 1},
        "draugr.png": {"file": "draugr_warrior_1779909937307.png", "cols": 5, "rows": 4, "walk_row": 1},
        "dullahan.png": {"file": "dullahan_1779909959670.png", "cols": 4, "rows": 4, "walk_row": 1, "is_dullahan": True},
        "lich.png": {"file": "lich_king_1779909980696.png", "cols": 4, "rows": 6, "walk_row": 1},
        "banshee.png": {"file": "banshee_bat_1779910009136.png", "cols": 4, "rows": 6, "walk_row": 0},
        "sludge.png": {"file": "crypt_sludge_1779910032251.png", "cols": 6, "rows": 4, "walk_row": 1}
    }
    
    for dst_name, cfg in enemy_configs.items():
        src_path = os.path.join(src_dir, cfg["file"])
        dst_path = os.path.join("assets/enemies", dst_name)
        is_dullahan = cfg.get("is_dullahan", False)
        process_enemy_sheet(src_path, dst_path, cfg["cols"], cfg["rows"], cfg["walk_row"], is_dullahan)
