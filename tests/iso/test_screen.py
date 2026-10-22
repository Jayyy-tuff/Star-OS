# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for screen.py with synthetic images, including wrong ones."""

import os
import random
import struct
import sys
import unittest
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import screen  # noqa: E402

NIGHT = (0x10, 0x14, 0x38)
GLASS = (0x26, 0x2b, 0x45)
HIGHLIGHT = (0x5a, 0x5e, 0x74)


def make_image(width, height, colour_of):
    pixels = bytearray()
    for y in range(height):
        for x in range(width):
            pixels.extend(colour_of(x, y))
    return screen.Image(width, height, bytes(pixels))


def ppm(image, comment=False):
    header = b"P6\n" + (b"# made by a test\n" if comment else b"")
    header += f"{image.width} {image.height}\n255\n".encode()
    return header + image.pixels


def clamp(v):
    return max(0, min(255, int(v)))


def noisy(colour, rng, amount):
    return tuple(clamp(c + rng.randint(-amount, amount)) for c in colour)


def glass_screen(width=160, height=120, band=24, line=True, noise=10, seed=7, band_from=0,
                 band_to=None, glass=GLASS):
    """A wallpaper-like vertical gradient with noise, and a glass-like noisy
    band of BAND rows at the bottom (optionally with a lighter top line, and
    only between columns BAND_FROM and BAND_TO)."""
    rng = random.Random(seed)
    band_to = width if band_to is None else band_to

    def colour(x, y):
        if y >= height - band and band_from <= x < band_to:
            base = HIGHLIGHT if line and y == height - band else glass
            return noisy(base, rng, noise)
        shade = y * 24 // height
        return noisy((NIGHT[0] + shade, NIGHT[1] + shade // 2, NIGHT[2] + shade), rng, noise)
    return make_image(width, height, colour)


class PpmTest(unittest.TestCase):
    def test_round_trip(self):
        image = make_image(64, 48, lambda x, y: GLASS if y >= 40 else NIGHT)
        parsed = screen.parse_ppm(ppm(image, comment=True))
        self.assertEqual((parsed.width, parsed.height), (64, 48))
        self.assertEqual(parsed.pixel(0, 0), NIGHT)
        self.assertEqual(parsed.pixel(5, 47), GLASS)

    def test_pixel_byte_that_looks_like_whitespace(self):
        image = make_image(2, 1, lambda x, y: (0x0A, 0x20, 0x09))
        self.assertEqual(screen.parse_ppm(ppm(image)).pixel(1, 0), (0x0A, 0x20, 0x09))

    def test_rejects_ascii_ppm(self):
        with self.assertRaises(ValueError):
            screen.parse_ppm(b"P3\n1 1\n255\n0 0 0\n")

    def test_rejects_truncated_data(self):
        with self.assertRaises(ValueError):
            screen.parse_ppm(ppm(glass_screen())[:-10])


class PngTest(unittest.TestCase):
    def test_png_structure_and_pixels(self):
        image = make_image(5, 3, lambda x, y: GLASS if y == 2 else NIGHT)
        data = screen.png_bytes(image)
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        width, height = struct.unpack(">II", data[16:24])
        self.assertEqual((width, height), (5, 3))
        idat_len = struct.unpack(">I", data[33:37])[0]
        raw = zlib.decompress(data[41:41 + idat_len])
        self.assertEqual(len(raw), 3 * (1 + 5 * 3))
        self.assertEqual(tuple(raw[1:4]), NIGHT)
        self.assertEqual(tuple(raw[-3:]), GLASS)


class AnalyseTest(unittest.TestCase):
    def test_glass_band_with_highlight_line(self):
        facts = screen.analyse(glass_screen(band=24))
        self.assertEqual(facts["taskbar_rows"], 24)
        self.assertGreaterEqual(facts["edge"], screen.MIN_EDGE)
        # Means of the noisy regions, within the noise's averaging error.
        above = bytes.fromhex(facts["above"][1:])
        below = bytes.fromhex(facts["below"][1:])
        self.assertLessEqual(screen.difference(below, GLASS), 2)
        self.assertLess(screen.difference(above, NIGHT), 30)
        self.assertGreater(screen.difference(above, below), 8)
        self.assertEqual(set(facts), {"width", "height", "taskbar_rows", "edge", "above", "below",
                                      "centre"})

    def test_glass_band_without_line(self):
        self.assertEqual(screen.analyse(glass_screen(band=24, line=False))["taskbar_rows"], 24)

    def test_band_darker_than_the_wallpaper(self):
        facts = screen.analyse(glass_screen(band=16, glass=(0x04, 0x06, 0x12)))
        self.assertEqual(facts["taskbar_rows"], 16)

    def test_line_brighter_than_the_step(self):
        # The line-to-glass change is the strongest; the line still counts.
        facts = screen.analyse(glass_screen(band=20, glass=(0x12, 0x16, 0x3a), noise=4))
        self.assertEqual(facts["taskbar_rows"], 20)

    def test_band_at_full_hd(self):
        image = glass_screen(width=1920, height=1080, band=48, noise=6)
        facts = screen.analyse(image)
        self.assertEqual((facts["width"], facts["height"]), (1920, 1080))
        self.assertEqual(facts["taskbar_rows"], 48)

    def test_no_band(self):
        facts = screen.analyse(glass_screen(band=0))
        self.assertEqual(facts["taskbar_rows"], 0)
        self.assertLess(facts["edge"], screen.MIN_EDGE)
        self.assertEqual((facts["above"], facts["below"]), ("", ""))

    def test_flat_image(self):
        facts = screen.analyse(make_image(64, 48, lambda x, y: NIGHT))
        self.assertEqual((facts["taskbar_rows"], facts["edge"]), (0, 0.0))
        self.assertEqual(facts["centre"], "#101438")

    def test_band_too_thin(self):
        # A line along the bottom (a border, not a taskbar) is not reported.
        self.assertEqual(screen.analyse(glass_screen(band=3))["taskbar_rows"], 0)

    def test_edge_above_the_bottom_quarter(self):
        self.assertEqual(screen.analyse(glass_screen(band=60))["taskbar_rows"], 0)

    def test_partial_width_band(self):
        # A window edge across a third of the screen is not the taskbar.
        image = glass_screen(band=24, band_from=40, band_to=93, glass=(0x90, 0x90, 0x90))
        self.assertEqual(screen.analyse(image)["taskbar_rows"], 0)

    def test_vertical_split(self):
        image = make_image(64, 48, lambda x, y: GLASS if x < 32 else NIGHT)
        self.assertEqual(screen.analyse(image)["taskbar_rows"], 0)

    def test_tiny_image(self):
        facts = screen.analyse(make_image(4, 4, lambda x, y: GLASS))
        self.assertEqual(facts["taskbar_rows"], 0)
        self.assertEqual(facts["centre"], "#262b45")

    def test_strongest_of_two_edges(self):
        # A faint stripe higher up loses against the taskbar's edge.
        def colour(x, y):
            if y >= 100:
                return GLASS
            if 92 <= y < 96:
                return (NIGHT[0] + 8, NIGHT[1] + 8, NIGHT[2] + 8)
            return NIGHT
        self.assertEqual(screen.analyse(make_image(80, 120, colour))["taskbar_rows"], 20)

    def test_facts_are_simple_values(self):
        facts = screen.analyse(glass_screen())
        for value in facts.values():
            self.assertIsInstance(value, (int, float, str))


if __name__ == "__main__":
    unittest.main()
