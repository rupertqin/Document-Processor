#!/usr/bin/env python3
"""Generate a perfectly centered macOS app icon for PDF Compressor."""

from PIL import Image, ImageDraw, ImageFont
import math

SIZE = 1024
OUTPUT = "/Users/rupert/code/Document-Processor/generated-images/pdf_icon_perfect.png"

# Colors
BLUE_BG = (37, 99, 235)          # #2563EB royal blue
WHITE = (255, 255, 255)
LIGHT_BLUE = (96, 165, 250)      # #60A5FA
DARK_BLUE = (29, 78, 216)        # #1D4ED8

img = Image.new("RGB", (SIZE, SIZE), BLUE_BG)
draw = ImageDraw.Draw(img)

# --- Draw document shape (white rounded rectangle, centered) ---
doc_w = 500
doc_h = 650
doc_x = (SIZE - doc_w) // 2    # mathematically centered
doc_y = (SIZE - doc_h) // 2 - 30
radius = 40

# Main document body
draw.rounded_rectangle(
    [doc_x, doc_y, doc_x + doc_w, doc_y + doc_h],
    radius=radius,
    fill=WHITE
)

# Document "fold" corner (top-right)
fold_size = 80
draw.polygon([
    (doc_x + doc_w - fold_size, doc_y),
    (doc_x + doc_w, doc_y),
    (doc_x + doc_w, doc_y + fold_size),
], fill=LIGHT_BLUE)

# Horizontal lines on document (representing text)
line_start_x = doc_x + 60
line_end_x = doc_x + doc_w - 60
for i, y_offset in enumerate([180, 260, 340]):
    line_y = doc_y + y_offset
    # Make last line shorter (like a text block)
    end_x = line_end_x - (100 if i == 2 else 0)
    draw.rounded_rectangle(
        [line_start_x, line_y, end_x, line_y + 20],
        radius=6,
        fill=LIGHT_BLUE
    )

# "PDF" text area at top of document
text_bg_y = doc_y + 60
draw.rounded_rectangle(
    [doc_x + 40, text_bg_y, doc_x + 180, text_bg_y + 60],
    radius=8,
    fill=DARK_BLUE
)

# Try to load a font, fall back to default
try:
    font_large = ImageFont.truetype("/System/Library/Fonts/HelveticaNeue-Bold.ttf", 72)
except:
    font_large = ImageFont.load_default()

# Draw "PDF" text
bbox = draw.textbbox((0, 0), "PDF", font=font_large)
text_w = bbox[2] - bbox[0]
text_h = bbox[3] - bbox[1]
text_x = doc_x + 40 + (140 - text_w) // 2
text_y = text_bg_y + (60 - text_h) // 2 - 4
draw.text((text_x, text_y), "PDF", fill=WHITE, font=font_large)

# --- Compression arrows (bottom area, indicating "squish") ---
arrow_y = doc_y + doc_h + 40
arrow_size = 50

# Top arrow (pointing down)
draw.polygon([
    (SIZE // 2 - arrow_size, arrow_y),
    (SIZE // 2 + arrow_size, arrow_y),
    (SIZE // 2, arrow_y + arrow_size),
], fill=WHITE)

# Gap
gap = 30

# Bottom arrow (pointing up, indicating compression)
arrow_y2 = arrow_y + arrow_size + gap
draw.polygon([
    (SIZE // 2 - arrow_size, arrow_y2 + arrow_size),
    (SIZE // 2 + arrow_size, arrow_y2 + arrow_size),
    (SIZE // 2, arrow_y2),
], fill=WHITE)

# Optional: small "Z" or dots to indicate compression
draw.text((SIZE // 2 - 15, arrow_y + arrow_size + gap // 2 - 10), "···", fill=WHITE)

# Save
img.save(OUTPUT, "PNG")
print(f"Icon saved to {OUTPUT}")

# Also create @2x version
import subprocess
dst = "/Users/rupert/code/Document-Processor/Document-processor/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
subprocess.run(["sips", "-s", "format", "png", OUTPUT, "--out", dst, "-z", "1024", "1024"], capture_output=True)
print(f"Copied to AppIcon set: {dst}")
