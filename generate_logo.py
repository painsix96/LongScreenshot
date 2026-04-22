from PIL import Image, ImageDraw, ImageFilter
import math

size = 1024
img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

def lerp_color(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))

# Background: deep indigo -> violet gradient (fully opaque)
top_color = (42, 24, 92)
bottom_color = (95, 38, 145)

for y in range(size):
    t = y / size
    color = lerp_color(top_color, bottom_color, t)
    draw.line([(0, y), (size, y)], fill=color + (255,))

# Subtle radial glow overlay
glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
glow_draw = ImageDraw.Draw(glow)
cx, cy = size // 2, size // 2
max_r = 480
for r in range(max_r, 0, -3):
    t = r / max_r
    alpha = int(20 * (1 - t))
    color = (160, 100, 220, alpha)
    glow_draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color)
img = Image.alpha_composite(img, glow)

draw = ImageDraw.Draw(img)

# 3 stacked rounded rectangles
cx = size // 2
layer_w = 480
layer_h = 300
layer_r = 40
offset_y = 210
offset_x = 50

# Back layer: solid light color (not transparent)
back_box = (cx - layer_w//2 + offset_x, offset_y, cx + layer_w//2 + offset_x, offset_y + layer_h)
back_color = lerp_color((120, 100, 180), (140, 115, 200), 0.5)
draw.rounded_rectangle(back_box, radius=layer_r, fill=back_color + (255,))

# Middle layer
mid_box = (cx - layer_w//2, offset_y + 85, cx + layer_w//2, offset_y + 85 + layer_h)
mid_color = lerp_color((170, 150, 220), (190, 170, 235), 0.5)
draw.rounded_rectangle(mid_box, radius=layer_r, fill=mid_color + (255,))

# Front layer: solid white with subtle gradient
front_box = (cx - layer_w//2 - offset_x, offset_y + 170, cx + layer_w//2 - offset_x, offset_y + 170 + layer_h)
fx1, fy1, fx2, fy2 = front_box

front_img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
front_draw = ImageDraw.Draw(front_img)
for y in range(int(fy1), int(fy2)):
    t = (y - fy1) / layer_h
    r = int(250 - 5 * t)
    g = int(250 - 8 * t)
    b = int(255 - 10 * t)
    front_draw.line([(fx1, y), (fx2, y)], fill=(r, g, b, 255))

mask = Image.new('L', (size, size), 0)
mask_draw = ImageDraw.Draw(mask)
mask_draw.rounded_rectangle(front_box, radius=layer_r, fill=255)
front_img.putalpha(mask)

img = Image.alpha_composite(img, front_img)
draw = ImageDraw.Draw(img)

# Stitch line: dashed with center dot
stitch_y = int(fy1 + layer_h * 0.50)
stitch_color = (140, 110, 210, 230)
dash_len = 18
gap_len = 14
line_start = cx - 110
line_end = cx + 110
x = line_start
while x < line_end:
    seg_end = min(x + dash_len, line_end)
    draw.line([(x, stitch_y), (seg_end, stitch_y)], fill=stitch_color, width=5)
    x += dash_len + gap_len

# Center dot
draw.ellipse([cx - 7, stitch_y - 7, cx + 7, stitch_y + 7], fill=(160, 125, 225, 240))

# Save master
img.save('/Users/chenhanzhong/Documents/trae_projects/Long-Screenshot/app_icon_master.png')

# Generate all required iOS icon sizes
sizes = {
    '20x2': 40,
    '20x3': 60,
    '29x2': 58,
    '29x3': 87,
    '40x2': 80,
    '40x3': 120,
    '60x2': 120,
    '60x3': 180,
    'ipad_20x1': 20,
    'ipad_20x2': 40,
    'ipad_29x1': 29,
    'ipad_29x2': 58,
    'ipad_40x1': 40,
    'ipad_40x2': 80,
    'ipad_76x1': 76,
    'ipad_76x2': 152,
    'ipad_83.5x2': 167,
    'appstore': 1024,
}

for name, s in sizes.items():
    resized = img.resize((s, s), Image.LANCZOS)
    resized.save(f'/Users/chenhanzhong/Documents/trae_projects/Long-Screenshot/icon_{name}.png')

print("Logo generated successfully!")
