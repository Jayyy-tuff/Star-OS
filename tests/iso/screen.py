# SPDX-License-Identifier: GPL-3.0-or-later
"""Screen dump helpers for the ISO tests (standard library only).

QEMU's QMP screendump writes binary PPM (P6). These helpers parse it, convert
it to PNG for upload, and measure the Star OS taskbar band and desktop colour
using the reserved colours of shell/qml/StarOS/Shell/Theme.qml.
"""

import struct
import zlib

TASKBAR = (0x16, 0x20, 0x2C)
TASKBAR_BUTTON = (0x1F, 0x2B, 0x3A)
DESKTOP = (0x24, 0x36, 0x4A)
TOLERANCE = 3


class Image:
    """An RGB image: width, height and rows of (r, g, b) bytes."""

    def __init__(self, width, height, pixels):
        if len(pixels) != width * height * 3:
            raise ValueError("pixel data does not match the image size")
        self.width = width
        self.height = height
        self.pixels = pixels

    def pixel(self, x, y):
        i = (y * self.width + x) * 3
        return tuple(self.pixels[i:i + 3])

    def row(self, y):
        start = y * self.width * 3
        return self.pixels[start:start + self.width * 3]


def _ppm_tokens(data, count):
    """Returns the first COUNT header tokens of a PPM and the data offset."""
    tokens = []
    i = 0
    while len(tokens) < count:
        while i < len(data) and data[i:i + 1].isspace():
            i += 1
        if data[i:i + 1] == b"#":
            while i < len(data) and data[i:i + 1] not in (b"\n", b"\r"):
                i += 1
            continue
        start = i
        while i < len(data) and not data[i:i + 1].isspace():
            i += 1
        if start == i:
            raise ValueError("truncated PPM header")
        tokens.append(data[start:i])
    return tokens, i + 1  # exactly one whitespace byte follows maxval


def parse_ppm(data):
    tokens, offset = _ppm_tokens(data, 4)
    if tokens[0] != b"P6":
        raise ValueError("not a binary PPM (P6)")
    width, height, maxval = (int(t) for t in tokens[1:])
    if maxval != 255:
        raise ValueError("only 8-bit PPM is supported")
    pixels = data[offset:offset + width * height * 3]
    return Image(width, height, bytes(pixels))


def png_bytes(image):
    """Encodes an Image as an 8-bit RGB PNG."""
    raw = b"".join(b"\0" + image.row(y) for y in range(image.height))

    def chunk(kind, body):
        return (struct.pack(">I", len(body)) + kind + body
                + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", image.width, image.height, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def close(colour, want, tolerance=TOLERANCE):
    return all(abs(a - b) <= tolerance for a, b in zip(colour, want))


def row_fraction(image, y, colours):
    """Fraction of a row's pixels close to any of COLOURS."""
    row = image.row(y)
    hits = 0
    for x in range(image.width):
        px = tuple(row[3 * x:3 * x + 3])
        if any(close(px, c) for c in colours):
            hits += 1
    return hits / image.width


def taskbar_rows(image, min_fraction=0.5):
    """Counts rows from the bottom that are mostly taskbar or button colour.

    The taskbar spans the screen width; its buttons, labels and focus ring
    cover part of each row, so a row counts when at least MIN_FRACTION of
    its pixels are taskbar or task-button colour.
    """
    rows = 0
    for y in range(image.height - 1, -1, -1):
        if row_fraction(image, y, (TASKBAR, TASKBAR_BUTTON)) < min_fraction:
            break
        rows += 1
    return rows


def desktop_fraction(image):
    """Fraction of pixels above the taskbar that have the desktop colour."""
    limit = image.height - taskbar_rows(image)
    if limit <= 0:
        return 0.0
    step = max(1, limit // 50)
    sampled = [row_fraction(image, y, (DESKTOP,)) for y in range(0, limit, step)]
    return sum(sampled) / len(sampled)


def analyse(image):
    """Returns the screen facts that the boot test logs."""
    centre = image.pixel(image.width // 2, image.height // 2)
    return {
        "width": image.width,
        "height": image.height,
        "taskbar_rows": taskbar_rows(image),
        "desktop_fraction": round(desktop_fraction(image), 3),
        "centre": "#%02x%02x%02x" % centre,
    }
