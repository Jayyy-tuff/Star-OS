# SPDX-License-Identifier: GPL-3.0-or-later
"""Screen dump helpers for the ISO tests (standard library only).

QEMU's QMP screendump writes binary PPM (P6). These helpers parse it, convert
it to PNG for upload, and locate the Star OS taskbar. The taskbar is frosted
glass over the wallpaper (M0.3), so it has no fixed colour; what it does have
is a straight top edge across the whole screen. analyse() reports the
strongest such edge in the bottom quarter of the screen.
"""

import struct
import zlib

# Search window and acceptance rules for the taskbar's top edge.
SEARCH_FRACTION = 0.25  # the bottom quarter of the screen
MIN_ROWS = 8  # the taskbar is at least this tall; also skips a bottom border line
MIN_EDGE = 6  # minimum change of a row's mean colour, 0..255 per channel
SEGMENTS = 16  # the edge must show in most of these column segments
MIN_COVERAGE = 0.75
LINE_ROWS = 2  # a highlight line this thin on top of the edge belongs to the band
BAND_ROWS = 16  # rows averaged for the colours above and below the edge


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


def mean_colour(data):
    """Mean (r, g, b) of packed RGB bytes."""
    count = len(data) // 3
    return tuple(sum(data[c::3]) / count for c in range(3))


def difference(a, b):
    """Largest per-channel difference of two colours."""
    return max(abs(x - y) for x, y in zip(a, b))


def hex_colour(colour):
    return "#%02x%02x%02x" % tuple(round(c) for c in colour)


def _segments(image, y):
    """Mean colours of row Y in SEGMENTS equal column ranges."""
    row = image.row(y)
    bounds = [image.width * i // SEGMENTS for i in range(SEGMENTS + 1)]
    return [mean_colour(row[3 * a:3 * b]) for a, b in zip(bounds, bounds[1:]) if b > a]


def _coverage(image, y, strength):
    """Fraction of column segments in which rows Y-1 and Y differ by at least a
    third of the whole rows' difference STRENGTH; relative to the edge, so that
    pixel noise in a narrow segment does not count."""
    above, below = _segments(image, y - 1), _segments(image, y)
    threshold = max(MIN_EDGE / 2, strength / 3)
    hits = sum(1 for a, b in zip(above, below) if difference(a, b) >= threshold)
    return hits / len(above)


def taskbar_edge(image):
    """Finds the taskbar's top edge: (first row of the band, edge strength).

    Candidates are boundaries between adjacent rows in the bottom quarter that
    leave at least MIN_ROWS rows below. The strongest change of the row mean
    that spans most of the width wins. A highlight line of up to LINE_ROWS rows
    right above it (the glass draws a 1 px edge line) is counted into the band.
    Returns (None, strength) when no boundary qualifies.
    """
    if image.width < SEGMENTS or image.height < 2 * MIN_ROWS:
        return None, 0.0
    top = max(1, image.height - max(MIN_ROWS + 1, int(image.height * SEARCH_FRACTION)))
    last = image.height - MIN_ROWS
    means = {y: mean_colour(image.row(y)) for y in range(top - 1 - LINE_ROWS, image.height)
             if y >= 0}
    strength = {y: difference(means[y - 1], means[y]) for y in range(top, last + 1)}
    for y in sorted(strength, key=lambda k: (-strength[k], -k)):
        if strength[y] < MIN_EDGE:
            break
        if _coverage(image, y, strength[y]) < MIN_COVERAGE:
            continue
        edge = y
        for step in range(1, LINE_ROWS + 1):
            above = y - step
            if above - 1 not in means or difference(means[above - 1], means[above]) < strength[y] / 2:
                break
            edge = above
        return edge, strength[y]
    return None, max(strength.values(), default=0.0)


def analyse(image):
    """Returns the screen facts that the boot and session tests log.

    taskbar_rows is the height of the band below the strongest full-width edge
    in the bottom quarter (0 if there is none), edge its strength (largest
    per-channel change of the row mean colour, 0..255), and above / below the
    mean colours of up to BAND_ROWS rows on either side.
    """
    centre = image.pixel(image.width // 2, image.height // 2)
    edge, strength = taskbar_edge(image)
    facts = {
        "width": image.width,
        "height": image.height,
        "taskbar_rows": 0 if edge is None else image.height - edge,
        "edge": round(strength, 1),
        "above": "",
        "below": "",
        "centre": hex_colour(centre),
    }
    if edge is not None:
        start = max(0, edge - BAND_ROWS)
        facts["above"] = hex_colour(mean_colour(b"".join(image.row(y) for y in range(start, edge))))
        # Below the edge line itself, inside the band.
        first = min(image.height - 1, edge + LINE_ROWS)
        stop = min(image.height, first + BAND_ROWS)
        facts["below"] = hex_colour(mean_colour(b"".join(image.row(y) for y in range(first, stop))))
    return facts
