#!/usr/bin/env python3
"""Generate Schulferien plugin icons — blue calendar with graduation cap."""
import os
import math

SIZES = [16, 32, 48, 64, 128, 256, 512]
ICONS_DIR = os.path.join(os.path.dirname(__file__), '..', 'icons')
os.makedirs(ICONS_DIR, exist_ok=True)

try:
    from PIL import Image, ImageDraw, ImageFont
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

def draw_icon_pil(size):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = max(1, size // 16)
    r = max(2, size // 8)

    # Background rounded rect
    bg_col = (30, 64, 175, 255)   # #1e40af — blue-800
    accent = (96, 165, 250, 255)  # #60a5fa — blue-400
    white  = (255, 255, 255, 255)

    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=bg_col)

    # Calendar body
    cal_x0 = int(size * 0.12)
    cal_y0 = int(size * 0.24)
    cal_x1 = int(size * 0.88)
    cal_y1 = int(size * 0.90)
    cal_r  = max(1, size // 14)
    d.rounded_rectangle([cal_x0, cal_y0, cal_x1, cal_y1], radius=cal_r, fill=white)

    # Calendar header bar
    hdr_y1 = int(size * 0.42)
    d.rounded_rectangle([cal_x0, cal_y0, cal_x1, hdr_y1], radius=cal_r, fill=accent)
    d.rectangle([cal_x0, (hdr_y1 - cal_r), cal_x1, hdr_y1], fill=accent)

    # Ring pegs at top
    peg_r = max(1, size // 20)
    peg_y = cal_y0
    for px in [int(size * 0.32), int(size * 0.68)]:
        d.ellipse([px - peg_r, peg_y - peg_r * 2, px + peg_r, peg_y + peg_r * 2],
                  fill=(30, 64, 175, 255))

    # Grid dots representing dates
    rows, cols = 2, 4
    cell_w = (cal_x1 - cal_x0) / (cols + 1)
    cell_h = (cal_y1 - hdr_y1) / (rows + 1)
    dot_r  = max(1, size // 32)
    for row in range(rows):
        for col in range(cols):
            cx = int(cal_x0 + cell_w * (col + 1))
            cy = int(hdr_y1 + cell_h * (row + 1))
            d.ellipse([cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r], fill=bg_col)

    # Small graduation cap at top-right
    cap_cx = int(size * 0.78)
    cap_cy = int(size * 0.14)
    cap_w  = int(size * 0.20)
    cap_h  = int(size * 0.10)
    yellow = (250, 204, 21, 255)  # #facc15

    # Board (rhombus simplified as polygon)
    hw = cap_w // 2
    hh = cap_h // 2
    board = [
        (cap_cx, cap_cy - hh),
        (cap_cx + hw, cap_cy),
        (cap_cx, cap_cy + hh),
        (cap_cx - hw, cap_cy),
    ]
    d.polygon(board, fill=yellow)

    return img

def draw_icon_svg(size):
    """Fallback SVG-based rasterisation using basic math."""
    s = size
    return None

def generate():
    if HAS_PIL:
        for sz in SIZES:
            img = draw_icon_pil(sz)
            path = os.path.join(ICONS_DIR, f'icon_{sz}.png')
            img.save(path)
            print(f'Saved {path}')
    else:
        print('Pillow not installed — generating placeholder PNGs via Python stdlib')
        import struct, zlib

        def make_png(w, h, pixels_rgba):
            def chunk(t, d):
                c = struct.pack('>I', len(d)) + t + d
                return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)

            raw_rows = b''
            for y in range(h):
                row = b'\x00'
                for x in range(w):
                    row += bytes(pixels_rgba[y * w + x])
                raw_rows += row
            idat = zlib.compress(raw_rows)
            return (b'\x89PNG\r\n\x1a\n'
                    + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                    + chunk(b'IDAT', idat)
                    + chunk(b'IEND', b''))

        for sz in SIZES:
            pixels = []
            for y in range(sz):
                for x in range(sz):
                    r2 = ((x - sz//2)**2 + (y - sz//2)**2)
                    in_circle = r2 < (sz//2 - 1)**2
                    if in_circle:
                        # Blue gradient
                        pixels.append((30, 64, 175))
                    else:
                        pixels.append((0, 0, 0))

            png_data = make_png(sz, sz, pixels)
            path = os.path.join(ICONS_DIR, f'icon_{sz}.png')
            with open(path, 'wb') as f:
                f.write(png_data)
            print(f'Saved placeholder {path}')

if __name__ == '__main__':
    generate()
