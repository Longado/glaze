# Draws Glaze's 32×32 pixel icon and builds AppIcon.icns. Run: python3 icon/make_icon.py
import os, subprocess, shutil
from PIL import Image

N = 32
BG = (44, 42, 84)                              # night indigo
BEZEL, BEZEL_D = (226, 231, 240), (150, 158, 178)
SCREEN = (22, 24, 38)
CODE = [(120, 220, 140), (255, 128, 170), (255, 214, 102), (130, 180, 255)]
FROST = [(214, 232, 248), (236, 244, 252), (196, 218, 240)]
EYE_W, PUPIL = (250, 250, 255), (38, 36, 72)

img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
px = img.load()

def rounded(x, y, r=6, lo=1, hi=30):
    # pixel-stepped squircle mask
    cx = min(max(x, lo + r), hi - r); cy = min(max(y, lo + r), hi - r)
    return lo <= x <= hi and lo <= y <= hi and (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 2

for y in range(N):
    for x in range(N):
        if rounded(x, y):
            px[x, y] = BG

# monitor bezel + shadow
for y in range(11, 26):
    for x in range(5, 28):
        px[x, y] = BEZEL
for x in range(5, 28): px[x, 25] = BEZEL_D
# screen
for y in range(12, 24):
    for x in range(6, 27):
        px[x, y] = SCREEN
# code lines on the left
lines = [(7, 13, 5, 0), (9, 15, 7, 1), (9, 17, 4, 2), (7, 19, 6, 3), (9, 21, 5, 0)]
for x0, y, w, c in lines:
    for x in range(x0, x0 + w): px[x, y] = CODE[c]
# frost from a diagonal to the right edge, dithered
for y in range(12, 24):
    edge = 14 + (23 - y) // 2 + (12 - (y - 12)) // 3
    for x in range(6, 27):
        if x >= edge:
            px[x, y] = FROST[(x + y) % 2] if x > edge else FROST[2]
# stand
for x in range(14, 19): px[x, 26] = BEZEL_D
for x in range(11, 22): px[x, 27] = BEZEL

# eye above the monitor, glancing away (pupil to the right)
eye = ["..XXXXX..",
       ".XXXXXXX.",
       "XXXXXOOX.",
       ".XXXXOOX.",
       "..XXXXX.."]
for j, row in enumerate(eye):
    for i, ch in enumerate(row):
        if ch == "X": px[12 + i, 4 + j] = EYE_W
        if ch == "O": px[12 + i, 4 + j] = PUPIL

here = os.path.dirname(os.path.abspath(__file__))
img.save(os.path.join(here, "icon-32.png"))
# macOS icon grid: artwork ~824 of 1024 → 32 px × 26 = 832, centred, crisp nearest-neighbour
big = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
big.paste(img.resize((832, 832), Image.NEAREST), (96, 96))
big.save(os.path.join(here, "icon-1024.png"))

iconset = os.path.join(here, "AppIcon.iconset")
shutil.rmtree(iconset, ignore_errors=True); os.makedirs(iconset)
for s in (16, 32, 128, 256, 512):
    big.resize((s, s), Image.NEAREST).save(f"{iconset}/icon_{s}x{s}.png")
    big.resize((s * 2, s * 2), Image.NEAREST).save(f"{iconset}/icon_{s}x{s}@2x.png")
subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(here, "AppIcon.icns")], check=True)
shutil.rmtree(iconset)
print("wrote icon/AppIcon.icns")
