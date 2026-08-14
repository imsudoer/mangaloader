from PIL import Image
img = Image.open(r'C:\Users\Andre\.gemini\antigravity\brain\69853ca8-a7c5-404c-9d87-3f85823fadf5\manga_icon_minimal_1786656008011.jpg').convert('RGBA')
data = list(img.getdata())

newData = []
for item in data:
    r, g, b = item[0], item[1], item[2]
    # White background removal: if pixel is close to white, make transparent
    if r > 240 and g > 240 and b > 240:
        newData.append((r, g, b, 0))
    elif r > 200 and g > 200 and b > 200:
        # Semi-transparent for anti-aliased edges
        alpha = int(255 - ((r + g + b) / 3.0 - 200) * (255.0 / 55.0))
        if alpha < 0: alpha = 0
        if alpha > 255: alpha = 255
        newData.append((r, g, b, alpha))
    else:
        newData.append((r, g, b, 255))

img.putdata(newData)
img = img.resize((512, 512), Image.Resampling.LANCZOS)
img.save(r'd:\Bshvv\rust\mangaloader\assets\icon_monet.png', 'PNG')
print('Icon saved!')
