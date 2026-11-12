"""Rasterises BitChord's real artwork straight from its shipped SVGs.

`Logo.svg` (extracted from the release APK) is the 1024x1024 icon: a red
gradient tile with three white wave strokes. `LogoTransparent.svg` is the same
mark without the tile, which is what the app draws in its own headers.

Rather than approximate the shapes, this flattens the SVG's own cubic beziers
and fills them, so the icon and the in-app mark are the real artwork.
"""

import json
import os
import re

from PIL import Image, ImageDraw

ROOT = 'C:/Users/natha/Downloads/bitios/'
SVG_DIR = ROOT + '_assets/real/assets/'
CATALOG = ROOT + 'BitChordIOS12/Resources/Assets.xcassets/'
SS = 4  # supersampling factor


# --- a minimal SVG path reader: M, L, H, V, C, Z, absolute only ------------

def _tokens(d):
    return re.findall(r'[MLHVCZ]|-?\d*\.?\d+', d)


def parse_path(d):
    """Returns a list of subpaths, each a list of (x, y) points."""
    tokens = _tokens(d)
    i = 0
    subpaths = []
    current = []
    x = y = 0.0
    start = (0.0, 0.0)
    command = None
    while i < len(tokens):
        token = tokens[i]
        if token in 'MLHVCZ':
            command = token
            i += 1
            if command == 'Z':
                if current:
                    current.append(start)
                    subpaths.append(current)
                    current = []
                x, y = start
            continue
        if command == 'M':
            x, y = float(tokens[i]), float(tokens[i + 1])
            i += 2
            if current:
                subpaths.append(current)
            current = [(x, y)]
            start = (x, y)
            command = 'L'  # subsequent pairs are line-tos
        elif command == 'L':
            x, y = float(tokens[i]), float(tokens[i + 1])
            i += 2
            current.append((x, y))
        elif command == 'H':
            x = float(tokens[i])
            i += 1
            current.append((x, y))
        elif command == 'V':
            y = float(tokens[i])
            i += 1
            current.append((x, y))
        elif command == 'C':
            x1, y1, x2, y2, x3, y3 = (float(t) for t in tokens[i:i + 6])
            i += 6
            steps = 32
            for step in range(1, steps + 1):
                t = step / steps
                mt = 1 - t
                px = (mt ** 3 * x + 3 * mt * mt * t * x1 + 3 * mt * t * t * x2 + t ** 3 * x3)
                py = (mt ** 3 * y + 3 * mt * mt * t * y1 + 3 * mt * t * t * y2 + t ** 3 * y3)
                current.append((px, py))
            x, y = x3, y3
        else:
            i += 1
    if current:
        subpaths.append(current)
    return subpaths


def read_svg(path):
    text = open(path, encoding='utf-8').read()
    view = re.search(r'viewBox="([^"]+)"', text).group(1)
    vx, vy, vw, vh = (float(v) for v in view.replace(',', ' ').split())
    paths = re.findall(r'<path d="([^"]+)"[^>]*fill="white"', text)
    if not paths:  # fill attribute may come before d
        paths = [m for m in re.findall(r'<path ([^>]+)>', text)]
        paths = [re.search(r'd="([^"]+)"', p).group(1) for p in paths]
    stops = re.findall(r'stop-color="(#[0-9A-Fa-f]{6})"', text)
    return (vx, vy, vw, vh), paths, stops


def draw_mark(svg_path, width, height, colours, background_stops=None):
    (vx, vy, vw, vh), paths, _ = read_svg(svg_path)
    w, h = width * SS, height * SS
    scale = min(w / vw, h / vh)
    offx = (w - vw * scale) / 2
    offy = (h - vh * scale) / 2

    image = Image.new('RGBA', (w, h), (0, 0, 0, 0))

    if background_stops:
        # Vertical linear gradient across the full tile, like the icon's SVG.
        top = tuple(int(background_stops[0][i:i + 2], 16) for i in (1, 3, 5))
        bottom = tuple(int(background_stops[1][i:i + 2], 16) for i in (1, 3, 5))
        gradient = Image.new('RGB', (1, h))
        for row in range(h):
            mix = row / max(1, h - 1)
            gradient.putpixel((0, row), tuple(int(top[c] + (bottom[c] - top[c]) * mix) for c in range(3)))
        image.paste(gradient.resize((w, h)), (0, 0))

    draw = ImageDraw.Draw(image)
    for path in paths:
        for subpath in parse_path(path):
            points = [(offx + px * scale, offy + py * scale) for px, py in subpath]
            if len(points) >= 3:
                draw.polygon(points, fill=colours)

    return image.resize((width, height), Image.LANCZOS)


def icon(size):
    return draw_mark(SVG_DIR + 'Logo.svg', size, size,
                     (255, 255, 255, 255), background_stops=('#FB5C74', '#FA233B'))


def logo(width):
    height = round(width * 484 / 730)
    return draw_mark(SVG_DIR + 'LogoTransparent.svg', width, height, (255, 255, 255, 255))


def save(image, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    background = Image.new('RGB', image.size, (0, 0, 0))
    if image.mode == 'RGBA':
        background.paste(image, mask=image.split()[3])
    else:
        background.paste(image)
    background.save(path, 'PNG')
    return path


def save_alpha(image, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path, 'PNG')
    return path


ICONS = [
    ('iphone', '20x20', '2x', 40), ('iphone', '20x20', '3x', 60),
    ('iphone', '29x29', '2x', 58), ('iphone', '29x29', '3x', 87),
    ('iphone', '40x40', '2x', 80), ('iphone', '40x40', '3x', 120),
    ('iphone', '60x60', '2x', 120), ('iphone', '60x60', '3x', 180),
    ('ipad', '20x20', '1x', 20), ('ipad', '20x20', '2x', 40),
    ('ipad', '29x29', '1x', 29), ('ipad', '29x29', '2x', 58),
    ('ipad', '40x40', '1x', 40), ('ipad', '40x40', '2x', 80),
    ('ipad', '76x76', '1x', 76), ('ipad', '76x76', '2x', 152),
    ('ipad', '83.5x83.5', '2x', 167),
    ('ios-marketing', '1024x1024', '1x', 1024),
]


def build_icon_set():
    folder = CATALOG + 'AppIcon.appiconset/'
    entries = []
    rendered = {}
    for idiom, size, scale, pixels in ICONS:
        name = 'icon-%s-%s-%s.png' % (idiom, size.replace('.', '_'), scale)
        if pixels not in rendered:
            rendered[pixels] = icon(pixels)
        save(rendered[pixels], folder + name)
        entries.append({'idiom': idiom, 'size': size, 'scale': scale, 'filename': name})
    with open(folder + 'Contents.json', 'w') as handle:
        json.dump({'images': entries, 'info': {'version': 1, 'author': 'xcode'}}, handle, indent=2)
    print('AppIcon: %d sizes' % len(entries))


def build_logo_set():
    folder = CATALOG + 'BrandLogo.imageset/'
    for scale, width in (('1x', 80), ('2x', 160), ('3x', 240)):
        suffix = '' if scale == '1x' else '@' + scale
        save_alpha(logo(width), folder + 'brand-logo' + suffix + '.png')
    contents = {
        'images': [
            {'idiom': 'universal', 'scale': '1x', 'filename': 'brand-logo.png'},
            {'idiom': 'universal', 'scale': '2x', 'filename': 'brand-logo@2x.png'},
            {'idiom': 'universal', 'scale': '3x', 'filename': 'brand-logo@3x.png'},
        ],
        'info': {'version': 1, 'author': 'xcode'},
        'properties': {'template-rendering-intent': 'template'},
    }
    with open(folder + 'Contents.json', 'w') as handle:
        json.dump(contents, handle, indent=2)
    print('BrandLogo: 3 scales')


def build_catalog_root():
    with open(CATALOG + 'Contents.json', 'w') as handle:
        json.dump({'info': {'version': 1, 'author': 'xcode'}}, handle, indent=2)


if __name__ == '__main__':
    os.makedirs(CATALOG, exist_ok=True)
    build_catalog_root()
    build_icon_set()
    build_logo_set()
    icon(1024).save(ROOT + '_assets/icon-preview.png')
    print('preview at _assets/icon-preview.png')
