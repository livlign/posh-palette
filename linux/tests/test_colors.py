import unittest

import helpers  # noqa: F401
from posh_palette import colors
from posh_palette.catalog import find_theme, resolve


class ColorTests(unittest.TestCase):
    def test_osc_sequence(self):
        seq = colors.osc_sequence({"black": "#000000", "red": "#FF0000", "background": "#1A1B26", "cursorColor": "#ABCDEF"})
        self.assertEqual(seq, "\x1b]4;0;rgb:00/00/00;1;rgb:ff/00/00\x1b\\"
                              "\x1b]11;rgb:1a/1b/26\x1b\\\x1b]12;rgb:ab/cd/ef\x1b\\")

    def test_bad_hex_rejected(self):
        with self.assertRaises(ValueError):
            colors.osc_color("red")

    def test_dark_light(self):
        self.assertTrue(colors.is_dark("#1A1B26"))
        self.assertFalse(colors.is_dark("#FAF4ED"))

    def test_ls_colors(self):
        t = resolve(find_theme("tokyo-night"))
        lc = colors.ls_colors(t)
        self.assertIn("di=1;38;2;122;162;247", lc)   # psStyle.Directory #7AA2F7
        self.assertIn("*.py=38;2;", lc)
        for part in lc.split(":"):
            self.assertRegex(part, r"^[*.\w]+=[\d;]+$")

    def test_blend(self):
        self.assertEqual(colors.blend("#000000", "#FFFFFF", 0.5), "#7F7F7F")


if __name__ == "__main__":
    unittest.main()
