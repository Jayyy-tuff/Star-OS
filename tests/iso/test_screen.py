# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for screen.py with synthetic images, including wrong ones."""

import os
import struct
import sys
import unittest
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import screen  # noqa: E402

OTHER = (0xEF, 0xF0, 0xF1)


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


def desktop_with_taskbar(width=64, height=48, band=8, button=(2, 20)):
    def colour(x, y):
        if y >= height - band:
            return screen.TASKBAR_BUTTON if button[0] <= x < button[1] else screen.TASKBAR
        return screen.DESKTOP
    return make_image(width, height, colour)


class PpmTest(unittest.TestCase):
    def test_round_trip(self):
        image = desktop_with_taskbar()
        parsed = screen.parse_ppm(ppm(image, comment=True))
        self.assertEqual((parsed.width, parsed.height), (64, 48))
        self.assertEqual(parsed.pixel(0, 0), screen.DESKTOP)
        self.assertEqual(parsed.pixel(5, 47), screen.TASKBAR_BUTTON)

    def test_pixel_byte_that_looks_like_whitespace(self):
        image = make_image(2, 1, lambda x, y: (0x0A, 0x20, 0x09))
        self.assertEqual(screen.parse_ppm(ppm(image)).pixel(1, 0), (0x0A, 0x20, 0x09))

    def test_rejects_ascii_ppm(self):
        with self.assertRaises(ValueError):
            screen.parse_ppm(b"P3\n1 1\n255\n0 0 0\n")

    def test_rejects_truncated_data(self):
        with self.assertRaises(ValueError):
            screen.parse_ppm(ppm(desktop_with_taskbar())[:-10])


class PngTest(unittest.TestCase):
    def test_png_structure_and_pixels(self):
        image = desktop_with_taskbar(width=5, height=3, band=1, button=(0, 0))
        data = screen.png_bytes(image)
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        width, height = struct.unpack(">II", data[16:24])
        self.assertEqual((width, height), (5, 3))
        idat_len = struct.unpack(">I", data[33:37])[0]
        raw = zlib.decompress(data[41:41 + idat_len])
        self.assertEqual(len(raw), 3 * (1 + 5 * 3))
        self.assertEqual(tuple(raw[1:4]), screen.DESKTOP)
        self.assertEqual(tuple(raw[-3:]), screen.TASKBAR)


class AnalyseTest(unittest.TestCase):
    def test_taskbar_band_is_measured(self):
        facts = screen.analyse(desktop_with_taskbar(band=8))
        self.assertEqual(facts["taskbar_rows"], 8)
        self.assertEqual(facts["desktop_fraction"], 1.0)
        self.assertEqual(facts["centre"], "#24364a")

    def test_no_taskbar(self):
        image = make_image(32, 24, lambda x, y: screen.DESKTOP)
        self.assertEqual(screen.analyse(image)["taskbar_rows"], 0)

    def test_wrong_colours_are_not_counted(self):
        # A Breeze-like screen: nothing matches the reserved colours.
        image = make_image(32, 24, lambda x, y: OTHER if y < 20 else (0x20, 0x23, 0x26))
        facts = screen.analyse(image)
        self.assertEqual(facts["taskbar_rows"], 0)
        self.assertEqual(facts["desktop_fraction"], 0.0)

    def test_band_with_mostly_buttons_still_counts(self):
        image = desktop_with_taskbar(width=64, band=6, button=(0, 40))
        self.assertEqual(screen.taskbar_rows(image), 6)

    def test_band_interrupted_by_other_colour(self):
        def colour(x, y):
            if y == 45:
                return OTHER
            return screen.TASKBAR if y >= 40 else screen.DESKTOP
        self.assertEqual(screen.taskbar_rows(make_image(16, 48, colour)), 2)

    def test_tolerance(self):
        near = tuple(c + screen.TOLERANCE for c in screen.TASKBAR)
        far = tuple(c + screen.TOLERANCE + 1 for c in screen.TASKBAR)
        self.assertTrue(screen.close(near, screen.TASKBAR))
        self.assertFalse(screen.close(far, screen.TASKBAR))


if __name__ == "__main__":
    unittest.main()
