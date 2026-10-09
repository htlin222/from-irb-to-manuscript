"""Convert result figures (PNG) to JCRP upload format: JPEG, within max pixels, at most 1 MB.

Usage: uv run python manuscript/style/figures_to_jpeg.py <max_w> <max_h> <in.png>=<out.jpg> ...
Prints one line per image: out_path width height bytes
"""
import sys
from pathlib import Path

from PIL import Image

MAX_BYTES = 1024 * 1024


def convert(src, dst, max_w, max_h):
    img = Image.open(src).convert("RGB")
    img.thumbnail((max_w, max_h), Image.LANCZOS)   # keeps aspect ratio, never enlarges
    Path(dst).parent.mkdir(parents=True, exist_ok=True)
    for quality in (92, 85, 75, 65):
        img.save(dst, "JPEG", quality=quality, optimize=True)
        if Path(dst).stat().st_size <= MAX_BYTES:
            break
    print(dst, img.width, img.height, Path(dst).stat().st_size)


if __name__ == "__main__":
    max_w, max_h = int(sys.argv[1]), int(sys.argv[2])
    for pair in sys.argv[3:]:
        src, dst = pair.split("=", 1)
        convert(src, dst, max_w, max_h)
