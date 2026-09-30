#!/usr/bin/env python3
"""Post-processing delle immagini della Guida Admin (richiede Pillow).

    compose_anim.py FRAMES_DIR OUT.webp   # frame PNG -> WebP animato in loop
    compose_anim.py --optimize DIR        # riduce i PNG a 256 colori

Le animazioni sono una sequenza di passi, non un video: ogni frame resta fermo
abbastanza da leggerlo e l'ultimo un po' di più, prima che il loop riparta.
`Image.asset` riproduce il WebP animato da solo, senza `video_player`.

I PNG di una UI hanno pochi colori: la palette a 256 senza dithering li riduce
di circa due terzi senza differenze visibili, e tiene piccolo il repo.
"""

import glob
import os
import sys

from PIL import Image

STEP_MS = 1600
LAST_MS = 3200
ANIM_WIDTH = 960
WEBP_QUALITY = 80


def compose(frames_dir, out_file):
    paths = sorted(glob.glob(os.path.join(frames_dir, "*.png")))
    if not paths:
        sys.exit(f"Nessun frame in {frames_dir}")
    frames = []
    for p in paths:
        img = Image.open(p).convert("RGB")
        if img.width > ANIM_WIDTH:
            height = round(img.height * ANIM_WIDTH / img.width)
            img = img.resize((ANIM_WIDTH, height), Image.LANCZOS)
        frames.append(img)
    durations = [STEP_MS] * (len(frames) - 1) + [LAST_MS]
    frames[0].save(
        out_file,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        quality=WEBP_QUALITY,
        method=6,
    )


def optimize(directory):
    for p in sorted(glob.glob(os.path.join(directory, "*.png"))):
        img = Image.open(p).convert("RGB")
        img.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(
            p, optimize=True
        )


def main(argv):
    if len(argv) == 3 and argv[1] == "--optimize":
        optimize(argv[2])
    elif len(argv) == 3:
        compose(argv[1], argv[2])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
