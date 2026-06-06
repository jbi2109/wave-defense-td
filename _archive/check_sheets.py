from PIL import Image, ImageDraw
import os

def create_debug_grid(sheet_path, output_path, cols=24, frame_size=(24, 24)):
    img = Image.open(sheet_path).convert("RGBA")
    w, h = img.size
    
    # Grid parameters
    cell_w = w // cols
    cell_h = h
    
    # Create a new image to draw the grid
    debug_img = Image.new("RGBA", (w + cols + 1, h + 2))
    draw = ImageDraw.Draw(debug_img)
    
    # Draw frames with spacing
    for i in range(cols):
        x0 = i * cell_w
        y0 = 0
        x1 = x0 + cell_w
        y1 = cell_h
        
        frame = img.crop((x0, y0, x1, y1))
        
        # Paste into debug image with 1px margin between frames
        dest_x = i * (cell_w + 1) + 1
        dest_y = 1
        debug_img.paste(frame, (dest_x, dest_y))
        
    # Draw red border lines between cells
    for i in range(cols + 1):
        x = i * (cell_w + 1)
        draw.line([(x, 0), (x, h + 2)], fill=(255, 0, 0, 255))
        
    draw.line([(0, 0), (w + cols + 1, 0)], fill=(255, 0, 0, 255))
    draw.line([(0, h + 1), (w + cols + 1, h + 1)], fill=(255, 0, 0, 255))
    
    debug_img.save(output_path)
    print(f"Saved debug grid to {output_path}")

# Check all sheets in assets/enemies
out_dir = r"C:\Users\jbijo\.gemini\antigravity\brain\b6490d31-bb78-4086-8308-78eb2028aa47"
for name in ["ghoul.png", "hound.png", "abomination.png", "draugr.png", "dullahan.png", "lich.png", "banshee.png", "sludge.png"]:
    src = os.path.join("assets/enemies", name)
    dst = os.path.join(out_dir, "debug_" + name)
    if os.path.exists(src):
        create_debug_grid(src, dst)
