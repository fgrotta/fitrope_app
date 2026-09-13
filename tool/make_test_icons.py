#!/usr/bin/env python3
"""Genera le icone "TEST" a partire da quelle di produzione.

Le icone prodotte sono **committate** in `tool/test_icons/`: la CI non esegue
questo script (non avrebbe Pillow ne' i font di sistema), si limita a copiarne
l'output con `tool/apply_test_branding.py`. Rilancialo solo quando cambiano le
icone di produzione:

    python3 tool/make_test_icons.py

Richiede Pillow e un font bold di sistema (i default sono quelli macOS).
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(ROOT, "web")
OUT = os.path.join(ROOT, "tool", "test_icons")

BAND_COLOR = (230, 81, 0)  # arancione scuro: contrasto AA con testo bianco
TEXT_COLOR = (255, 255, 255)
LABEL = "TEST"

# La banda sta fra il 62% e l'80% dell'altezza: dentro la "safe zone" delle
# icone maskable (cerchio centrato, raggio 40%), quindi la scritta sopravvive
# anche quando il launcher ritaglia l'icona in tondo.
BAND_TOP = 0.62
BAND_BOTTOM = 0.80

FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial Black.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]

# Le icone di test stanno fuori da web/ apposta: tutto cio' che sta in web/
# finisce nel bundle di produzione, e le icone TEST non devono uscire li'.
# sorgente (relativa a web/) -> destinazione (relativa a tool/test_icons/)
TARGETS = [
    ("icons/Icon-192.png", "Icon-192.png"),
    ("icons/Icon-512.png", "Icon-512.png"),
    ("icons/Icon-maskable-192.png", "Icon-maskable-192.png"),
    ("icons/Icon-maskable-512.png", "Icon-maskable-512.png"),
    ("favicon.png", "favicon.png"),
]


def load_font(size):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    sys.exit("Nessun font bold trovato: aggiungine uno a FONT_CANDIDATES")


def badge(src_path, dst_path):
    img = Image.open(src_path).convert("RGB")
    w, h = img.size
    draw = ImageDraw.Draw(img)

    top, bottom = int(h * BAND_TOP), int(h * BAND_BOTTOM)
    draw.rectangle([0, top, w, bottom], fill=BAND_COLOR)

    # Sotto i 64 px "TEST" e' illeggibile: resta la sola banda colorata, che a
    # quella dimensione (favicon nella tab) e' gia' il segnale.
    if w >= 64:
        band_h = bottom - top
        font = load_font(int(band_h * 0.78))
        box = draw.textbbox((0, 0), LABEL, font=font)
        draw.text(
            ((w - (box[2] - box[0])) / 2 - box[0],
             top + (band_h - (box[3] - box[1])) / 2 - box[1]),
            LABEL,
            font=font,
            fill=TEXT_COLOR,
        )

    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    img.save(dst_path)
    print("scritto", os.path.relpath(dst_path, ROOT))


def make_ico():
    """favicon.ico multi-size (16/32/48) come l'originale."""
    src = Image.open(os.path.join(OUT, "Icon-192.png"))
    dst = os.path.join(OUT, "favicon.ico")
    src.save(dst, sizes=[(16, 16), (32, 32), (48, 48)])
    print("scritto", os.path.relpath(dst, ROOT))


def main():
    for src, dst in TARGETS:
        badge(os.path.join(WEB, src), os.path.join(OUT, dst))
    make_ico()


if __name__ == "__main__":
    main()
