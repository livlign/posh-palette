import unittest
from unittest import mock

from helpers import TempHome
from posh_palette import apply, shells, terminals
from posh_palette.catalog import find_theme, resolve


class ApplyTests(TempHome):
    def setUp(self):
        super().setUp()
        (self.home / ".zshrc").write_text("# mine\n")
        (self.home / ".bashrc").write_text("# mine too\n")
        patches = [
            mock.patch.object(terminals, "installed_adapters", lambda: [terminals.Ghostty()]),
            mock.patch.object(terminals, "emit_live", lambda *a, **k: False),
            mock.patch.object(shells.Shell, "installed", lambda self: self.name in ("zsh", "bash")),
            mock.patch("posh_palette.fonts.is_installed", lambda face, families=None: True),
            mock.patch("posh_palette.ohmyposh.path", lambda: "/usr/bin/oh-my-posh"),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def test_apply_then_reset_is_a_clean_revert(self):
        t = resolve(find_theme("tokyo-night"))
        report = apply.apply_theme(t)
        self.assertFalse([l for l in report.lines if l[0] == "warn"], report.lines)
        self.assertTrue(shells.init_path("zsh").exists())
        self.assertTrue((self.home / ".poshpalette/prompts/pp-auto-powerline.omp.json").exists())
        self.assertIn("ghostty) ;;", shells.init_path("zsh").read_text())
        self.assertIn("palette = 0=", terminals.Ghostty().config_path().read_text())
        apply.reset()
        self.assertEqual((self.home / ".zshrc").read_text(), "# mine\n")
        self.assertEqual((self.home / ".bashrc").read_text(), "# mine too\n")
        self.assertFalse(shells.init_path("zsh").exists())
        self.assertNotIn("palette", terminals.Ghostty().config_path().read_text())

    def test_dry_run_writes_nothing(self):
        apply.apply_theme(resolve(find_theme("nord")), dry_run=True)
        self.assertEqual((self.home / ".zshrc").read_text(), "# mine\n")
        self.assertFalse(shells.init_path("zsh").exists())
        self.assertFalse(terminals.Ghostty().config_path().exists())

    def test_missing_font_is_not_written(self):
        with mock.patch("posh_palette.fonts.is_installed", lambda face, families=None: False):
            report = apply.apply_theme(resolve(find_theme("tokyo-night")), ask=lambda q, d: False)
        self.assertNotIn("font-family", terminals.Ghostty().config_path().read_text())
        self.assertTrue(any("font" in l[1].lower() for l in report.lines))


if __name__ == "__main__":
    unittest.main()
