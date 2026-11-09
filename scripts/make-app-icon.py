#!/usr/bin/env python3
"""Build opaque full-bleed Floretta app icons from the reference painting.

The reference is a rounded paper square on white, with its own shadow.
Pixels of that paper, including the watercolor, are copied unchanged.
White margin, the drop shadow, and a thin band of the old rounded rim are
replaced by a reflection of the solid paper just inside that rim, so the
corners are the same grain and the old arc does not stay as a second edge.

No redraw, no symmetrizing, no sharpening. Cloud has no sips or
CoreGraphics; this uses Pillow and writes an sRGB ICC profile.
"""

from __future__ import annotations

import json
import math
import struct
import zlib
from pathlib import Path

from PIL import Image, ImageCms

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "docs" / "design" / "app-icon-reference.png"
MASTER = 1024
# Pixels this close to terracotta are stained paper, not a clean donor.
HALO = 8
DONOR = 220
# Replace this many pixels of the old rounded rim so it does not stay as a second edge.
RIM = 14

MAC_PIXELS = [
    ("icon_16x16.png", "16x16", "1x", 16),
    ("icon_16x16@2x.png", "16x16", "2x", 32),
    ("icon_32x32.png", "32x32", "1x", 32),
    ("icon_32x32@2x.png", "32x32", "2x", 64),
    ("icon_128x128.png", "128x128", "1x", 128),
    ("icon_128x128@2x.png", "128x128", "2x", 256),
    ("icon_256x256.png", "256x256", "1x", 256),
    ("icon_256x256@2x.png", "256x256", "2x", 512),
    ("icon_512x512.png", "512x512", "1x", 512),
    ("icon_512x512@2x.png", "512x512", "2x", 1024),
]

DESTINATIONS = [
    ROOT / "Floretta" / "macOS" / "Assets.xcassets" / "AppIcon.appiconset",
    ROOT / "Floretta" / "iOS" / "Assets.xcassets" / "AppIcon.appiconset",
    ROOT / "Floretta" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset",
]


def is_ink(rgb: tuple[int, int, int]) -> bool:
    r, g, b = rgb
    # Terracotta is much redder than the warm gray drop shadow.
    return r > 150 and (r - g) > 40 and (r - b) > 55 and (r + g + b) < 680


def is_face(rgb: tuple[int, int, int]) -> bool:
    """Cream paper or terracotta ink. White margin and gray shadow are not."""
    if is_ink(rgb):
        return True
    r, g, b = rgb
    return r >= 236 and (r - b) >= 28 and (g - b) >= 12


def is_neutral_white(rgb: tuple[int, int, int]) -> bool:
    r, g, b = rgb
    return r >= 248 and abs(r - g) <= 8 and abs(g - b) <= 8 and (r - b) < 14


def fit_sheet(image: Image.Image) -> tuple[int, int, int, int, int, int]:
    """Return left, top, canvas side, box width, box height, corner radius.

    The flat sides of the paper, not the shadow, define the sheet. The
    canvas is the square of the longer side. The short side is extended
    with mirrored paper.
    """
    pixels = image.load()
    width, height = image.size
    rows: list[tuple[int, int, int]] = []
    for y in range(height):
        xs = [x for x in range(width) if is_face(pixels[x, y])]
        if len(xs) > 40:
            rows.append((xs[-1] - xs[0], xs[0], xs[-1]))
    max_span = max(span for span, _left, _right in rows)
    wide = [row for row in rows if row[0] >= max_span - 8]
    left = sorted(row[1] for row in wide)[len(wide) // 2]
    right = sorted(row[2] for row in wide)[len(wide) // 2]
    box_w = right - left + 1

    cols: list[tuple[int, int, int]] = []
    for x in range(left, right + 1):
        ys = [y for y in range(height) if is_face(pixels[x, y])]
        if len(ys) > 40:
            cols.append((ys[-1] - ys[0], ys[0], ys[-1]))
    max_height = max(span for span, _top, _bottom in cols)
    tall = [col for col in cols if col[0] >= max_height - 8]
    top = sorted(col[1] for col in tall)[len(tall) // 2]
    bottom = sorted(col[2] for col in tall)[len(tall) // 2]
    box_h = bottom - top + 1
    side = max(box_w, box_h)
    radius = _fit_radius(pixels, left, top, box_w, width)
    print(
        f"sheet left={left} top={top} box={box_w}x{box_h} "
        f"side={side} radius={radius}"
    )
    return left, top, side, box_w, box_h, radius


def _fit_radius(pixels, left: int, top: int, box_w: int, width: int) -> int:
    samples: list[tuple[int, int]] = []
    for dy in range(0, box_w // 2, 4):
        y = top + dy
        xs = [x for x in range(width) if is_face(pixels[x, y])]
        if len(xs) < 20:
            continue
        samples.append((dy, xs[0] - left))
        if xs[0] - left <= 1:
            break
    best_error = None
    best_radius = box_w // 5
    for radius in range(40, box_w // 2):
        error = 0.0
        for dy, inset in samples:
            if dy >= radius:
                predicted = 0.0
            else:
                inner = radius * radius - (radius - dy) * (radius - dy)
                predicted = 0.0 if inner <= 0 else radius - math.sqrt(inner)
            error += (predicted - inset) ** 2
        error /= max(len(samples), 1)
        if best_error is None or error < best_error:
            best_error = error
            best_radius = radius
    return best_radius


def keep_pixel(rgb: tuple[int, int, int]) -> bool:
    """Paper or ink worth copying. Margin, shadow, and the pale rim are not."""
    if is_ink(rgb):
        return True
    r, g, b = rgb
    return r >= 240 and (r - b) >= 24 and (g - b) >= 10


def extend_to_square(image: Image.Image) -> Image.Image:
    pixels = image.load()
    width, height = image.size
    left, top, side, box_w, box_h, radius = fit_sheet(image)
    halo = ink_halo(pixels, width, height, HALO)
    donor = find_donor(pixels, halo, width, height, left, top, box_w, box_h)
    print(f"donor origin=({donor[0]},{donor[1]}) size={DONOR}")
    keep = [[False] * side for _ in range(side)]
    for y in range(side):
        src_y = top + y
        if not 0 <= src_y < height:
            continue
        for x in range(side):
            src_x = left + x
            if 0 <= src_x < width and keep_pixel(pixels[src_x, src_y]):
                keep[y][x] = True
    margin = _border_margin(keep, side)
    near_edge = _rim_mask(margin, side, RIM)
    square = Image.new("RGB", (side, side))
    out = square.load()
    copied = 0
    filled = 0
    for y in range(side):
        src_y = top + y
        for x in range(side):
            src_x = left + x
            # Interior fibers stay, even when a pixel is paler than the keep test.
            # Only the margin and the old rim are rebuilt.
            if (
                not margin[y][x]
                and not near_edge[y][x]
                and 0 <= src_x < width
                and 0 <= src_y < height
            ):
                out[x, y] = pixels[src_x, src_y]
                copied += 1
                continue
            out[x, y] = continued_paper(
                pixels, width, height, left, top, box_w, box_h, donor, margin, near_edge, x, y, side
            )
            filled += 1
    print(f"copied {copied} sheet pixels, filled {filled} corner pixels")
    return square


def _border_margin(keep, side: int) -> list[list[bool]]:
    """Non-paper pixels connected to the square's edge. Interior holes are not margin."""
    margin = [[False] * side for _ in range(side)]
    queue: list[tuple[int, int]] = []
    for i in range(side):
        for x, y in ((i, 0), (i, side - 1), (0, i), (side - 1, i)):
            if not keep[y][x] and not margin[y][x]:
                margin[y][x] = True
                queue.append((x, y))
    head = 0
    while head < len(queue):
        x, y = queue[head]
        head += 1
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < side and 0 <= ny < side and not keep[ny][nx] and not margin[ny][nx]:
                margin[ny][nx] = True
                queue.append((nx, ny))
    return margin


def _rim_mask(margin, side: int, rim: int) -> list[list[bool]]:
    """True for sheet pixels within `rim` steps of the margin."""
    dist = [[rim + 1] * side for _ in range(side)]
    queue: list[tuple[int, int]] = []
    for y in range(side):
        for x in range(side):
            if margin[y][x]:
                dist[y][x] = 0
                queue.append((x, y))
    head = 0
    while head < len(queue):
        x, y = queue[head]
        head += 1
        base = dist[y][x]
        if base >= rim:
            continue
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < side and 0 <= ny < side and dist[ny][nx] > base + 1:
                dist[ny][nx] = base + 1
                queue.append((nx, ny))
    return [[(not margin[y][x]) and dist[y][x] <= rim for x in range(side)] for y in range(side)]


def ink_halo(pixels, width: int, height: int, radius: int) -> bytearray:
    halo = bytearray(width * height)
    points = [
        (x, y)
        for y in range(height)
        for x in range(width)
        if is_ink(pixels[x, y])
    ]
    limit = radius * radius
    for x, y in points:
        y0 = max(0, y - radius)
        y1 = min(height - 1, y + radius)
        x0 = max(0, x - radius)
        x1 = min(width - 1, x + radius)
        for yy in range(y0, y1 + 1):
            dy = yy - y
            row = yy * width
            for xx in range(x0, x1 + 1):
                dx = xx - x
                if dx * dx + dy * dy <= limit:
                    halo[row + xx] = 1
    return halo


def find_donor(pixels, halo, width, height, left, top, box_w, box_h) -> tuple[int, int]:
    """A square of clean paper grain used only to fill the outside corners."""
    step = 8
    for y in range(0, box_h - DONOR, step):
        for x in range(0, box_w - DONOR, step):
            if _donor_clear(pixels, halo, width, height, left + x, top + y):
                return (left + x, top + y)
    raise SystemExit("no clean paper patch for the icon corners")


def _donor_paper(rgb: tuple[int, int, int]) -> bool:
    if is_ink(rgb):
        return False
    r, g, b = rgb
    return r >= 232 and (r - b) >= 18 and (g - b) >= 8


def _donor_clear(pixels, halo, width, height, origin_x: int, origin_y: int) -> bool:
    for y in range(origin_y, origin_y + DONOR, 2):
        row = y * width
        for x in range(origin_x, origin_x + DONOR, 2):
            if halo[row + x] or not _donor_paper(pixels[x, y]):
                return False
    return True


def continued_paper(
    pixels, width, height, left, top, box_w, box_h, donor, margin, near_edge, x, y, side
) -> tuple[int, int, int]:
    """Reflect the solid paper across the old rim.

    The pale rim is not copied. A pixel just outside the solid sheet samples
    the pixel just inside it, so the grain joins without a second rounded edge.
    """
    cx = (box_w - 1) / 2
    cy = (box_h - 1) / 2
    dx = cx - x
    dy = cy - y
    distance = math.hypot(dx, dy) or 1.0
    ux, uy = dx / distance, dy / distance
    solid = None
    step = 1.0
    while step < distance:
        ix = int(round(x + ux * step))
        iy = int(round(y + uy * step))
        if 0 <= ix < side and 0 <= iy < side and not margin[iy][ix] and not near_edge[iy][ix]:
            solid = step
            break
        step += 1.0
    if solid is not None:
        sample = 2 * solid
        return _bilinear_paper(
            pixels, width, height, left + x + ux * sample, top + y + uy * sample, donor
        )
    donor_x, donor_y = donor
    return pixels[donor_x + DONOR // 2, donor_y + DONOR // 2]


def _bilinear_paper(pixels, width, height, sx: float, sy: float, donor) -> tuple[int, int, int]:
    x0 = int(math.floor(sx))
    y0 = int(math.floor(sy))
    tx = sx - x0
    ty = sy - y0
    acc = [0.0, 0.0, 0.0]
    weight = 0.0
    for oy, fy in ((0, 1 - ty), (1, ty)):
        for ox, fx in ((0, 1 - tx), (1, tx)):
            ix, iy = x0 + ox, y0 + oy
            if not (0 <= ix < width and 0 <= iy < height):
                continue
            color = pixels[ix, iy]
            if not keep_pixel(color) or is_ink(color):
                continue
            w = fx * fy
            acc[0] += color[0] * w
            acc[1] += color[1] * w
            acc[2] += color[2] * w
            weight += w
    if weight < 0.25:
        donor_x, donor_y = donor
        return pixels[donor_x + DONOR // 2, donor_y + DONOR // 2]
    return (int(acc[0] / weight), int(acc[1] / weight), int(acc[2] / weight))


def srgb_profile() -> tuple[bytes, str]:
    created = ImageCms.createProfile("sRGB")
    profile = ImageCms.ImageCmsProfile(created)
    description = (ImageCms.getProfileDescription(profile) or "sRGB").strip()
    return profile.tobytes(), description or "sRGB"


def settle_resize(image: Image.Image, size: int) -> Image.Image:
    """Downscale, then pull LANCZOS overshoot back into the paper range.

    The sheet has no neutral-white pixel. A ringing filter can still invent
    some. Those pixels are pushed back to the warm floor. The painting is
    left alone: terracotta already sits far from that floor.
    """
    resized = image.resize((size, size), Image.Resampling.LANCZOS)
    pixels = resized.load()
    for y in range(size):
        for x in range(size):
            r, g, b = pixels[x, y]
            if r - b >= 20 and r - g >= 8:
                continue
            b = min(b, r - 20)
            g = min(g, r - 8)
            pixels[x, y] = (r, max(g, 0), max(b, 0))
    return resized


def save_srgb(image: Image.Image, path: Path, profile: bytes) -> None:
    image = image.convert("RGB")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", icc_profile=profile, optimize=False)


def mac_contents() -> dict:
    images = []
    for filename, size, scale, _pixels in MAC_PIXELS:
        images.append(
            {
                "filename": filename,
                "idiom": "mac",
                "scale": scale,
                "size": size,
            }
        )
    return {"images": images, "info": {"author": "xcode", "version": 1}}


def ios_contents() -> dict:
    return {
        "images": [
            {
                "filename": "icon_1024x1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }


def combined_contents() -> dict:
    return {
        "images": mac_contents()["images"] + ios_contents()["images"],
        "info": {"author": "xcode", "version": 1},
    }


def write_set(directory: Path, files: dict[str, Image.Image], contents: dict, profile: bytes) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    for name, image in files.items():
        save_srgb(image, directory / name, profile)
    (directory / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def icc_name(data: bytes) -> str:
    offset = 8
    while offset + 8 <= len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        kind = data[offset + 4 : offset + 8]
        chunk = data[offset + 8 : offset + 8 + length]
        if kind == b"iCCP":
            _name, rest = chunk.split(b"\x00", 1)
            compressed = rest[1:]
            try:
                profile = zlib.decompress(compressed)
            except zlib.error:
                profile = compressed
            text = profile.decode("latin1", "replace")
            if "sRGB" in text or "sRGB" in profile.decode("utf-16-be", "ignore"):
                return "sRGB"
            return "ICC Profile"
        if kind == b"IEND":
            break
        offset += 12 + length
    return "untagged"


def png_facts(path: Path) -> str:
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    offset = 8
    width = height = color = 0
    has_trns = False
    while offset + 8 <= len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        kind = data[offset + 4 : offset + 8]
        chunk = data[offset + 8 : offset + 8 + length]
        if kind == b"IHDR":
            width, height, _bit, color, *_rest = struct.unpack(">IIBBBBB", chunk)
        elif kind == b"tRNS":
            has_trns = True
        elif kind == b"IEND":
            break
        offset += 12 + length
    alpha = "yes" if color in (4, 6) or has_trns else "no"
    return (
        f"{path.name}: pixelWidth: {width} pixelHeight: {height} "
        f"hasAlpha: {alpha} space: {icc_name(data)} colorType: {color}"
    )


def corner_rgb(path: Path) -> str:
    image = Image.open(path).convert("RGB")
    pixels = image.load()
    w, h = image.size
    points = {
        "tl": pixels[0, 0],
        "tr": pixels[w - 1, 0],
        "bl": pixels[0, h - 1],
        "br": pixels[w - 1, h - 1],
    }
    parts = []
    for name, rgb in points.items():
        mark = "(WHITE)" if rgb == (255, 255, 255) else ""
        parts.append(f"{name}={rgb}{mark}")
    return path.name + " " + " ".join(parts)


def assert_full_bleed(path: Path) -> None:
    image = Image.open(path).convert("RGB")
    pixels = image.load()
    width, height = image.size
    white = 0
    for y in range(height):
        for x in range(width):
            if is_neutral_white(pixels[x, y]):
                white += 1
    if white:
        raise SystemExit(f"{path} still has {white} neutral-white pixels")
    for rgb in (pixels[0, 0], pixels[width - 1, 0], pixels[0, height - 1], pixels[width - 1, height - 1]):
        if rgb == (255, 255, 255) or is_neutral_white(rgb):
            raise SystemExit(f"{path} corner is white {rgb}")


def main() -> None:
    source = Image.open(REFERENCE).convert("RGB")
    square = extend_to_square(source)
    master = settle_resize(square, MASTER)
    profile, description = srgb_profile()
    print("icc", description, "bytes", len(profile))
    files: dict[str, Image.Image] = {"icon_1024x1024.png": master}
    for filename, _size, _scale, pixels in MAC_PIXELS:
        if pixels == MASTER:
            files[filename] = master
        else:
            files[filename] = settle_resize(master, pixels)

    mac_dir, ios_dir, resource_dir = DESTINATIONS
    mac_files = {name: image for name, image in files.items() if name != "icon_1024x1024.png"}
    write_set(mac_dir, mac_files, mac_contents(), profile)
    write_set(ios_dir, {"icon_1024x1024.png": master}, ios_contents(), profile)
    write_set(resource_dir, files, combined_contents(), profile)

    print("reference", source.size, "square", square.size, "master", master.size)
    for directory in DESTINATIONS:
        print("#", directory.relative_to(ROOT))
        for path in sorted(directory.glob("*.png")):
            assert_full_bleed(path)
            print(png_facts(path))
            print(corner_rgb(path))


if __name__ == "__main__":
    main()
