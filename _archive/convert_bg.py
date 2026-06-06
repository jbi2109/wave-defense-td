from PIL import Image

def remove_background(filepath):
    try:
        img = Image.open(filepath).convert("RGBA")
        datas = img.getdata()
        
        # Get background color from top-left pixel
        bg_color = datas[0]
        
        newData = []
        # Tolerance for JPEG artifacts
        tolerance = 30
        for item in datas:
            if abs(item[0]-bg_color[0]) < tolerance and \
               abs(item[1]-bg_color[1]) < tolerance and \
               abs(item[2]-bg_color[2]) < tolerance:
                newData.append((255, 255, 255, 0))
            else:
                newData.append(item)
                
        img.putdata(newData)
        # Ensure it saves as proper PNG
        img.save(filepath, format="PNG")
        print(f"Processed {filepath}")
    except Exception as e:
        print(f"Error processing {filepath}: {e}")

remove_background("assets/turrets/flamethrower.png")
remove_background("assets/turrets/frost.png")
