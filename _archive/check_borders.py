import os
from PIL import Image

src_dir = r"C:\Users\jbijo\.gemini\antigravity\brain\b6490d31-bb78-4086-8308-78eb2028aa47"
p = os.path.join(src_dir, "banshee_bat_1779910009136.png")
if os.path.exists(p):
    img = Image.open(p)
    w, h = img.size
    print("Banshee size:", w, "x", h)
    print("Corners:")
    print("  (0,0):", img.getpixel((0,0)))
    print("  (w-1,0):", img.getpixel((w-1, 0)))
    print("  (0,h-1):", img.getpixel((0, h-1)))
    print("  (w-1,h-1):", img.getpixel((w-1, h-1)))
    
    # Check what the actual green color is in the background
    # Let's sample a few border pixels
    print("Samples at x=5, y=5:", img.getpixel((5, 5)))
    print("Samples at x=w//2, y=5:", img.getpixel((w//2, 5)))
else:
    print("File not found:", p)
