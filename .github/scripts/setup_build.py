import os, shutil
from PIL import Image

# 1. Strip light/checkerboard background from icon_raw.jpg -> transparent RGBA
img = Image.open("assets/icon_raw.jpg").convert("RGBA")
w, h = img.size
px = img.load()
vis = set()
st = [(0,0), (w-1,0), (0,h-1), (w-1,h-1), (int(w*0.44), int(h*0.34))]
while st:
    x, y = st.pop()
    if (x,y) in vis or not (0 <= x < w and 0 <= y < h):
        continue
    vis.add((x,y))
    r, g, b, a = px[x,y]
    if abs(r-g) < 22 and abs(g-b) < 22 and r > 130:
        px[x,y] = (0,0,0,0)
        st.extend([(x+1,y), (x-1,y), (x,y+1), (x,y-1)])

# Crop to tight bounding box of the 'e' glyph
bbox = img.getbbox()
if bbox:
    img = img.crop(bbox)
img.save("assets/icon.png")

# 2. Build foreground (padded to 62% inside transparent square) + monochrome mask
def make_padded(src, canvas_sz, mono=False):
    canvas = Image.new("RGBA", (canvas_sz, canvas_sz), (0, 0, 0, 0))
    target = int(canvas_sz * 0.62)
    ratio = min(target / src.width, target / src.height)
    nw, nh = max(1, int(src.width * ratio)), max(1, int(src.height * ratio))
    resized = src.resize((nw, nh), Image.LANCZOS)
    if mono:
        r, g, b, a = resized.split()
        resized = Image.merge("RGBA", (
            a.point(lambda _: 255),
            a.point(lambda _: 255),
            a.point(lambda _: 255),
            a
        ))
    canvas.paste(resized, ((canvas_sz - nw) // 2, (canvas_sz - nh) // 2), resized)
    return canvas

res = "android/app/src/main/res"
for d, sz, fg_sz in [
    ("mdpi", 48, 108),
    ("hdpi", 72, 162),
    ("xhdpi", 96, 216),
    ("xxhdpi", 144, 324),
    ("xxxhdpi", 192, 432),
]:
    os.makedirs(f"{res}/mipmap-{d}", exist_ok=True)
    os.makedirs(f"{res}/drawable-{d}", exist_ok=True)
    # Legacy pre-Oreo fallback icon (transparent background)
    make_padded(img, sz).save(f"{res}/mipmap-{d}/ic_launcher.png")
    # Adaptive foreground & monochrome layers
    make_padded(img, fg_sz, mono=False).save(f"{res}/drawable-{d}/ic_launcher_foreground.png")
    make_padded(img, fg_sz, mono=True).save(f"{res}/drawable-{d}/ic_launcher_monochrome.png")

# 3. Day/Night adaptive background color (Light in day theme, Dark in night theme)
os.makedirs(f"{res}/values", exist_ok=True)
os.makedirs(f"{res}/values-night", exist_ok=True)
open(f"{res}/values/ic_launcher_background.xml", "w").write(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#F4F1EA</color>\n</resources>\n'
)
open(f"{res}/values-night/ic_launcher_background.xml", "w").write(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#1C1C1E</color>\n</resources>\n'
)

# 4. Adaptive icon descriptor (supports Light/Dark + Android 13+ Material You themed icons)
os.makedirs(f"{res}/mipmap-anydpi-v26", exist_ok=True)
adaptive_xml = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
'''
open(f"{res}/mipmap-anydpi-v26/ic_launcher.xml", "w").write(adaptive_xml)
open(f"{res}/mipmap-anydpi-v26/ic_launcher_round.xml", "w").write(adaptive_xml)

# 5. AndroidManifest configuration
p = "android/app/src/main/AndroidManifest.xml"
s = open(p).read()
s = s.replace('android:label="epaper_reader"', 'android:label="NuzEPpr"')
s = s.replace('<application', '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>\n    <application', 1)
flt = (
    '<intent-filter>'
    '<action android:name="android.intent.action.VIEW"/>'
    '<action android:name="android.intent.action.EDIT"/>'
    '<category android:name="android.intent.category.DEFAULT"/>'
    '<category android:name="android.intent.category.BROWSABLE"/>'
    '<data android:scheme="content" android:mimeType="application/pdf"/>'
    '<data android:scheme="file" android:mimeType="application/pdf"/>'
    '<data android:host="*" android:mimeType="application/pdf"/>'
    '<data android:pathPattern=".*\\.pdf"/>'
    '</intent-filter></activity>'
)
open(p, "w").write(s.replace("</activity>", flt, 1))
