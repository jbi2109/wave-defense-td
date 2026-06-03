from PIL import Image, ImageDraw
import os

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

def clean_green_outline(img, bg_color, is_green_entity=False):
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
                    
                    should_clean = False
                    if dist < 160:
                        should_clean = True
                    elif is_green and not is_green_entity:
                        should_clean = True
                        
                    if should_clean:
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


def clean_resized_green_outline(img, is_green_entity=False):
    w, h = img.size
    pixels = img.load()
    img_copy = img.copy()
    pixels_copy = img_copy.load()
    
    for y in range(h):
        for x in range(w):
            p = pixels_copy[x, y]
            if p[3] > 0:
                is_green = (p[1] > p[0] + 15 and p[1] > p[2] + 15 and p[1] > 80)
                is_chroma_green = (p[1] > 180 and p[0] < 100 and p[2] < 100)
                
                should_clean = False
                if is_green and not is_green_entity:
                    should_clean = True
                elif is_chroma_green:
                    should_clean = True
                    
                if should_clean:
                    if not is_green_entity:
                        pixels[x, y] = (0, 0, 0, 0)
                    else:
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
                            pixels[x, y] = (0, 0, 0, 0)

def clear_cell_background(cell, is_green_entity):
    cw, ch = cell.size
    pixels = cell.load()
    
    # 1. Clear white borders at corners if any
    for corner in [(0, 0), (cw-1, 0), (0, ch-1), (cw-1, ch-1)]:
        ImageDraw.floodfill(cell, corner, (0, 0, 0, 0), thresh=80)
        
    if not is_green_entity:
        # Globally floodfill from any chroma green pixel
        for y in range(ch):
            for x in range(cw):
                p = pixels[x, y]
                if p[3] > 0:
                    is_chroma_green = (p[1] > 180 and p[0] < 100 and p[2] < 100)
                    if is_chroma_green:
                        ImageDraw.floodfill(cell, (x, y), (0, 0, 0, 0), thresh=120)
        # Globally clear any remaining green pixels
        for y in range(ch):
            for x in range(cw):
                p = pixels[x, y]
                if p[3] > 0:
                    is_green = (p[1] > p[0] + 15 and p[1] > p[2] + 15 and p[1] > 80)
                    if is_green:
                        pixels[x, y] = (0, 0, 0, 0)
    else:
        # Green entity: floodfill from all borders/edges
        for y in range(ch):
            for x in [0, cw-1]:
                p = pixels[x, y]
                if p[3] > 0 and p[1] > p[0] + 15 and p[1] > p[2] + 15 and p[1] > 80:
                    ImageDraw.floodfill(cell, (x, y), (0, 0, 0, 0), thresh=120)
        for x in range(cw):
            for y in [0, ch-1]:
                p = pixels[x, y]
                if p[3] > 0 and p[1] > p[0] + 15 and p[1] > p[2] + 15 and p[1] > 80:
                    ImageDraw.floodfill(cell, (x, y), (0, 0, 0, 0), thresh=120)

def process_enemy_sheet(src_path, dst_path, cols, rows, walk_row, is_dullahan=False, is_green_entity=False):
    print(f"Processing {src_path} -> {dst_path} (row {walk_row} of {cols}x{rows})")
    img = Image.open(src_path).convert("RGBA")
    w, h = img.size
    
    # Calculate cell dimensions
    cell_w = w // cols
    cell_h = h // rows
    
    # Detect background color
    bg_color = find_green_background(img)
    if not bg_color:
        bg_color = (0, 255, 0, 255)
        
    # Clear white borders on original sheet
    for corner in [(0, 0), (w-1, 0), (0, h-1), (w-1, h-1)]:
        ImageDraw.floodfill(img, corner, (0, 0, 0, 0), thresh=80)
        
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
            draw.rectangle([0, 0, int(cell_w * 0.3), int(cell_h * 0.15)], fill=(0, 0, 0, 0))
            
        # Clear background of this cell
        clear_cell_background(cell, is_green_entity)
        
        # Clean green outline on high-res cell (passing is_green_entity)
        clean_green_outline(cell, bg_color, is_green_entity)
        
        # Crop to contents (to remove excess outer whitespace before resize)
        bbox = cell.getbbox()
        if bbox:
            cell = cell.crop(bbox)
            
        # Resize to 24x24
        resized_cell = cell.resize((24, 24), Image.Resampling.LANCZOS)
        
        # Clean outline on 24x24 cell to remove Lanczos interpolation halos
        clean_resized_green_outline(resized_cell, is_green_entity)
        
        walk_frames.append(resized_cell)
        
    # Construct the final 24 frames
    final_frames = []
    for _ in range(4):
        final_frames.append(walk_frames[0])
    for i in range(6):
        final_frames.append(walk_frames[i % cols])
    for i in range(5):
        final_frames.append(walk_frames[i % cols])
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
        "ghoul.png": {"file": "drowned_ghoul_1779909865609.png", "cols": 6, "rows": 4, "walk_row": 1, "is_green_entity": True},
        "abomination.png": {"file": "flesh_abomination_1779909914943.png", "cols": 5, "rows": 4, "walk_row": 1, "is_green_entity": False},
        "hound.png": {"file": "plague_hound_1779909889897.png", "cols": 4, "rows": 6, "walk_row": 1, "is_green_entity": False},
        "draugr.png": {"file": "draugr_warrior_1779909937307.png", "cols": 5, "rows": 4, "walk_row": 1, "is_green_entity": False},
        "dullahan.png": {"file": "dullahan_1779909959670.png", "cols": 4, "rows": 4, "walk_row": 1, "is_dullahan": True, "is_green_entity": False},
        "lich.png": {"file": "lich_king_1779909980696.png", "cols": 4, "rows": 6, "walk_row": 1, "is_green_entity": False},
        "banshee.png": {"file": "banshee_bat_1779910009136.png", "cols": 4, "rows": 6, "walk_row": 0, "is_green_entity": True},
        "sludge.png": {"file": "crypt_sludge_1779910032251.png", "cols": 6, "rows": 4, "walk_row": 1, "is_green_entity": True}
    }
    
    for dst_name, cfg in enemy_configs.items():
        src_path = os.path.join(src_dir, cfg["file"])
        dst_path = os.path.join("assets/enemies", dst_name)
        is_dullahan = cfg.get("is_dullahan", False)
        is_green_entity = cfg.get("is_green_entity", False)
        process_enemy_sheet(src_path, dst_path, cfg["cols"], cfg["rows"], cfg["walk_row"], is_dullahan, is_green_entity)
