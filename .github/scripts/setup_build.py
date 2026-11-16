import os, shutil
from PIL import Image

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
    if abs(r-g) < 18 and abs(g-b) < 18 and r > 140:
        px[x,y] = (0,0,0,0)
        st.extend([(x+1,y), (x-1,y), (x,y+1), (x,y-1)])
img.save("assets/icon.png")

shutil.rmtree("android/app/src/main/res/mipmap-anydpi-v26", ignore_errors=True)
for d, sz in [("mdpi",48), ("hdpi",72), ("xhdpi",96), ("xxhdpi",144), ("xxxhdpi",192)]:
    img.resize((sz, sz), Image.LANCZOS).save(f"android/app/src/main/res/mipmap-{d}/ic_launcher.png")

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
