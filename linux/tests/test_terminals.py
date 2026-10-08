import unittest

from helpers import TempHome
from posh_palette import files, terminals
from posh_palette.catalog import find_theme, resolve


def theme(tid="tokyo-night", **kw):
    return resolve(dict(find_theme(tid), **kw))


class TerminalTests(TempHome):
    def test_detection(self):
        ct = terminals.current_terminal
        self.assertEqual(ct({"TERM": "xterm-ghostty"}), "ghostty")
        self.assertEqual(ct({"KITTY_WINDOW_ID": "1"}), "kitty")
        self.assertEqual(ct({"TERM": "foot"}), "foot")
        self.assertEqual(ct({"VTE_VERSION": "7600", "TERM": "xterm-256color"}), "vte")
        self.assertFalse(terminals.osc_capable({"TMUX": "/tmp/x", "TERM": "screen"}))
        self.assertTrue(terminals.osc_capable({"TERM": "xterm-256color"}))

    def test_ghostty(self):
        g = terminals.Ghostty()
        cfg = g.config_path()
        cfg.parent.mkdir(parents=True)
        cfg.write_text('font-family="MartianMono Nerd Font"\ntheme = Dracula\n')
        g.apply(theme(opacity=90, acrylic=True), font_ok=True)
        text = cfg.read_text()
        self.assertTrue(text.startswith('font-family="MartianMono Nerd Font"'))
        self.assertIn("palette = 4=#7aa2f7", text)
        self.assertIn("background = #1a1b26", text)
        self.assertIn('font-family = ""\nfont-family = "JetBrainsMono Nerd Font"', text)
        self.assertIn("background-opacity = 0.9", text)
        self.assertIn("background-blur = true", text)
        self.assertTrue(g.managed())
        g.apply(theme(), font_ok=False)
        self.assertNotIn("font-family = \"\"", cfg.read_text())   # font left alone when missing
        g.remove()
        self.assertEqual(cfg.read_text(), 'font-family="MartianMono Nerd Font"\ntheme = Dracula\n')

    def test_ghostty_prefers_existing_legacy_name(self):
        d = self.home / ".config/ghostty"
        d.mkdir(parents=True)
        (d / "config").write_text("")
        self.assertEqual(terminals.Ghostty().config_path().name, "config")

    def test_kitty(self):
        k = terminals.Kitty()
        k.apply(theme(), font_ok=True)
        text = k.config_path().read_text()
        self.assertIn("color12 #7aa2f7", text)
        self.assertIn("font_family JetBrainsMono Nerd Font", text)
        k.remove()
        self.assertEqual(k.config_path().read_text(), "")

    def test_alacritty_fresh(self):
        a = terminals.Alacritty()
        a.apply(theme(), font_ok=True)
        main = a.config_path().read_text()
        self.assertIn(f'general.import = ["{a.theme_path()}"]', main)
        self.assertIn('blue = "#7aa2f7"', a.theme_path().read_text())
        a.apply(theme("nord"), font_ok=True)
        self.assertEqual(a.config_path().read_text().count("import"), 1)
        a.remove()
        self.assertFalse(a.theme_path().exists())
        self.assertNotIn("import", a.config_path().read_text())

    def test_alacritty_with_general_table(self):
        a = terminals.Alacritty()
        a.config_path().parent.mkdir(parents=True)
        a.config_path().write_text('[general]\nlive_config_reload = true\n\n[font]\nsize = 12\n')
        a.apply(theme(), font_ok=True)
        text = a.config_path().read_text()
        self.assertNotIn("general.import", text)
        self.assertLess(text.index("[general]"), text.index("import = ["))
        self.assertLess(text.index("import = ["), text.index("[font]"))
        a.apply(theme("nord"), font_ok=True)   # re-apply keeps it under [general]
        self.assertNotIn("general.import", a.config_path().read_text())
        a.remove()
        self.assertEqual(a.config_path().read_text(), '[general]\nlive_config_reload = true\n\n[font]\nsize = 12\n')

    def test_alacritty_existing_import_gets_a_hint(self):
        a = terminals.Alacritty()
        a.config_path().parent.mkdir(parents=True)
        a.config_path().write_text('[general]\nimport = ["~/x.toml"]\n')
        _, notes = a.apply(theme(), font_ok=True)
        self.assertTrue(notes and "import" in notes[0])
        self.assertNotIn(files.BLOCK_START, a.config_path().read_text())

    def test_foot(self):
        f = terminals.Foot()
        f.config_path().parent.mkdir(parents=True)
        f.config_path().write_text("[main]\nfont=Hack:size=10\n")
        f.apply(theme(), font_ok=True)
        self.assertTrue(f.config_path().read_text().startswith(files.BLOCK_START))
        ini = f.theme_path().read_text()
        self.assertIn("regular4=7aa2f7", ini)
        self.assertIn("font=JetBrainsMono Nerd Font:size=11", ini)
        f.remove()
        self.assertEqual(f.config_path().read_text(), "[main]\nfont=Hack:size=10\n")

    def test_wezterm_scheme_file(self):
        w = terminals.WezTerm()
        w.apply(theme(), font_ok=True)
        self.assertIn('name = "PoshPalette"', w.config_path().read_text())
        self.assertFalse(w.managed())


if __name__ == "__main__":
    unittest.main()
