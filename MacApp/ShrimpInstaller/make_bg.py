#!/usr/bin/env python3
# Shrimp Kurulum DMG arka planı — koyu tema, sürükle-oku, yönerge.
from PIL import Image, ImageDraw, ImageFont
import os

W, H = 1200, 800  # 2x (create-dmg pencere 600x400)
img = Image.new("RGB", (W, H), (12, 18, 34))
dr = ImageDraw.Draw(img)

# dikey gradyan (üst koyu-mavi -> alt daha koyu)
top = (14, 22, 42); bot = (6, 9, 18)
for y in range(H):
    t = y / H
    r = int(top[0]*(1-t) + bot[0]*t)
    g = int(top[1]*(1-t) + bot[1]*t)
    b = int(top[2]*(1-t) + bot[2]*t)
    dr.line([(0, y), (W, y)], fill=(r, g, b))

def font(sz, bold=True):
    for p in ([r"C:\Windows\Fonts\segoeuib.ttf"] if bold else [r"C:\Windows\Fonts\segoeui.ttf"]) + \
             [r"C:\Windows\Fonts\arialbd.ttf", r"C:\Windows\Fonts\arial.ttf"]:
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()

def ctext(cx, y, s, f, fill):
    bb = dr.textbbox((0, 0), s, font=f); w = bb[2]-bb[0]
    dr.text((cx - w/2, y), s, font=f, fill=fill)

accent = (60, 130, 246)

# başlık
ctext(W/2, 70, "Shrimp Kurulum", font(56), (235, 240, 250))
ctext(W/2, 150, "Uygulamayı Applications klasörüne sürükleyin", font(30, False), (150, 165, 190))

# ikon yuvaları (create-dmg: app 150,200 / apps 450,200 -> 2x: 300,400 / 900,400, y ters degil)
# create-dmg y ekseni ust-sol referansli; ikonlar ~ y=200 (600x400) -> 2x görselde ~ y=400
iy = 380
# sol yuva halkasi
for (cx, lbl) in [(300, ""), (900, "")]:
    dr.rounded_rectangle([cx-95, iy-95, cx+95, iy+95], radius=28, outline=(40, 55, 85), width=3)

# ortada saga ok
ax0, ax1, ay = 470, 730, iy
dr.line([(ax0, ay), (ax1-40, ay)], fill=accent, width=14)
dr.polygon([(ax1-50, ay-45), (ax1, ay), (ax1-50, ay+45)], fill=accent)

# alt yonerge (imzasiz uyari)
ctext(W/2, 660, "Ilk acilista acilmazsa:  sag tik  ->  Ac", font(28), (120, 200, 255))
ctext(W/2, 710, "(Apple imzasiz uygulamalari cift-tikla engeller — sag tik > Ac ile gecilir)", font(20, False), (110, 125, 150))

adir = os.path.join(os.path.dirname(__file__), "assets")
os.makedirs(adir, exist_ok=True)
# @2x (retina, 1200x800) + 1x (600x400) — appdmg retina için ikisini de kullanır
img.save(os.path.join(adir, "dmg-bg@2x.png"))
img.resize((W // 2, H // 2), Image.LANCZOS).save(os.path.join(adir, "dmg-bg.png"))
print("yazildi: dmg-bg.png (600x400) + dmg-bg@2x.png (1200x800)")
