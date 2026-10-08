import re
import unittest

import helpers  # noqa: F401
from posh_palette import tui
from posh_palette.catalog import catalog, find_theme, resolve

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


class TuiTests(unittest.TestCase):
    def test_width(self):
        self.assertEqual(tui.width("abc"), 3)
        self.assertEqual(tui.width("⚡x"), 3)
        self.assertEqual(tui.clip("⚡⚡⚡", 3), ("⚡", 2))

    def test_preview_rows_fill_the_panel_exactly(self):
        for p in catalog("prompts"):
            t = resolve(dict(find_theme("tokyo-night"), prompt=p["id"]))
            for _, _, text in tui.preview(t, 42, 4, 120):
                self.assertEqual(tui.width(ANSI_RE.sub("", text)), 74, p["id"])

    def test_preview_skipped_when_narrow(self):
        self.assertEqual(tui.preview(resolve(find_theme("nord")), 42, 4, 70), [])

    def test_prompt_parts_cover_generated_styles(self):
        for p in catalog("prompts"):
            t = resolve(dict(find_theme("nord"), prompt=p["id"]))
            self.assertTrue(tui.prompt_parts(t), p["id"])

    def test_window(self):
        self.assertEqual(tui.window(10, 0, 0, 20), 0)
        self.assertEqual(tui.window(50, 30, 0, 10), 21)
        self.assertEqual(tui.window(50, 5, 21, 10), 5)


if __name__ == "__main__":
    unittest.main()
