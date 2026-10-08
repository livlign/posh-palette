import os
import shutil
import subprocess
import unittest

from helpers import TempHome
from posh_palette import shells
from posh_palette.catalog import find_theme, resolve
from posh_palette.prompt import save_prompt

THEMES = ("tokyo-night", "porcelain", "bong")


class ShellScriptTests(TempHome):
    def scripts(self, theme_id, managed=("ghostty",)):
        t = resolve(find_theme(theme_id))
        pp = save_prompt(t["prompt"]["config"], t["prompt"]["name"]) if t["prompt"].get("generated") else None
        shells.write_init_scripts(t, list(managed), pp, "/opt/pp/posh-palette")
        return t

    def check_syntax(self, shell, family, args):
        if not shutil.which(shell):
            self.skipTest(f"{shell} not installed")
        for tid in THEMES:
            self.scripts(tid)
            r = subprocess.run([shell, *args, str(shells.init_path(family))], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, f"{shell} {tid}: {r.stderr}")

    def test_bash_syntax(self):
        self.check_syntax("bash", "bash", ["-n"])

    def test_zsh_syntax(self):
        self.check_syntax("zsh", "zsh", ["-n"])

    def test_sh_syntax(self):
        self.check_syntax("sh", "sh", ["-n"])

    def test_fish_syntax(self):
        self.check_syntax("fish", "fish", ["--no-execute"])

    def run_interactive(self, shell, family, cmd, extra=()):
        if not shutil.which(shell):
            self.skipTest(f"{shell} not installed")
        env = dict(os.environ, TERM="xterm-256color", PATH="/usr/bin:/bin")
        env.pop("TMUX", None)
        src = "source" if shell != "sh" else "."
        r = subprocess.run([shell, *extra, "-i", "-c", f"{src} {shells.init_path(family)}; {cmd}"],
                           capture_output=True, text=True, env=env, stdin=subprocess.DEVNULL, timeout=30)
        return r

    def test_bash_sets_ls_colors_and_palette_fn(self):
        t = self.scripts("tokyo-night")
        r = self.run_interactive("bash", "bash", 'printf "%s\\n" "$LS_COLORS"; type -t palette', ("--norc", "--noprofile"))
        self.assertIn("di=1;38;2;122;162;247", r.stdout)
        self.assertIn("function", r.stdout)
        self.assertNotIn("\x1b]4", r.stdout)   # stdout isn't a tty: no OSC
        del t

    def test_zsh_sets_highlight_styles(self):
        self.scripts("tokyo-night")
        r = self.run_interactive("zsh", "zsh", 'print -r -- "$ZSH_HIGHLIGHT_STYLES[command]|$ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE"', ("-f",))
        self.assertEqual(r.stdout.strip(), "fg=#7aa2f7|fg=#5c6694", r.stderr)

    def test_fish_sets_colors(self):
        self.scripts("tokyo-night")
        if not shutil.which("fish"):
            self.skipTest("fish not installed")
        env = dict(os.environ, TERM="xterm-256color")
        r = subprocess.run(["fish", "--no-config", "-i", "-c", f"source {shells.init_path('fish')}; echo $fish_color_command"],
                           capture_output=True, text=True, env=env, stdin=subprocess.DEVNULL, timeout=30)
        self.assertEqual(r.stdout.strip().splitlines()[-1], "7aa2f7", r.stderr)

    def test_osc_skipped_only_for_managed_terminals(self):
        self.scripts("tokyo-night", managed=("ghostty", "kitty"))
        text = shells.init_path("bash").read_text()
        self.assertIn("ghostty|kitty) ;;", text)
        self.assertIn("\\033]4;0;rgb:", text)
        self.assertNotIn("\x1b", text)   # escapes are spelled out, never raw

    def test_referenced_omp_theme(self):
        t = resolve(dict(find_theme("nord"), prompt="jandedobbeleer"))
        shells.write_init_scripts(t, [], None, "/x")
        z = shells.init_path("zsh").read_text()
        self.assertIn("jandedobbeleer.omp.json", z)
        self.assertIn("raw.githubusercontent.com", z)

    def test_wire_and_unwire(self):
        (self.home / ".bashrc").write_text("alias ll='ls -l'\n")
        bash = next(s for s in shells.SHELLS if s.name == "bash")
        self.assertTrue(bash.wire())
        self.assertFalse(bash.wire())
        self.assertTrue(bash.wired())
        self.assertIn(str(shells.init_path("bash")), (self.home / ".bashrc").read_text())
        self.assertTrue(bash.unwire())
        self.assertEqual((self.home / ".bashrc").read_text(), "alias ll='ls -l'\n")

    def test_fish_loader(self):
        fish = next(s for s in shells.SHELLS if s.name == "fish")
        fish.wire()
        p = self.home / ".config/fish/conf.d/posh-palette.fish"
        self.assertTrue(p.exists())
        fish.unwire()
        self.assertFalse(p.exists())

    def test_quoting(self):
        self.assertEqual(shells.fq("a'b\\c"), "'a\\'b\\\\c'")
        self.assertEqual(shells.printf_osc("\x1b]11;x\x1b\\"), "\\033]11;x\\033\\134")


if __name__ == "__main__":
    unittest.main()
