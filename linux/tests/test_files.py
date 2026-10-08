import unittest

from helpers import TempHome
from posh_palette import files


class FileTests(TempHome):
    def test_upsert_replace_remove(self):
        p = self.home / ".zshrc"
        p.write_text("export A=1\n# keep me\n")
        self.assertTrue(files.upsert_block(p, "echo one"))
        self.assertFalse(files.upsert_block(p, "echo one"))   # idempotent
        self.assertTrue(files.upsert_block(p, "echo two"))
        text = p.read_text()
        self.assertEqual(text.count(files.BLOCK_START), 1)
        self.assertIn("echo two", text)
        self.assertNotIn("echo one", text)
        self.assertTrue(files.remove_block(p))
        self.assertEqual(p.read_text(), "export A=1\n# keep me\n")
        self.assertTrue(list(self.home.glob(".zshrc.poshpalette-*.bak")))

    def test_block_at_start(self):
        p = self.home / "foot.ini"
        p.write_text("[colors]\nalpha=1\n")
        files.upsert_block(p, "include=/x", position="start")
        self.assertTrue(p.read_text().startswith(files.BLOCK_START))
        files.remove_block(p)
        self.assertEqual(p.read_text(), "[colors]\nalpha=1\n")

    def test_creates_missing_file(self):
        p = self.home / "new" / "conf"
        files.upsert_block(p, "x = 1")
        self.assertIn("x = 1", p.read_text())

    def test_symlinked_rc_keeps_link(self):
        target = self.home / "dotfiles" / "zshrc"
        target.parent.mkdir()
        target.write_text("A=1\n")
        link = self.home / ".zshrc"
        link.symlink_to(target)
        files.upsert_block(link, "B=2")
        self.assertTrue(link.is_symlink())
        self.assertIn("B=2", target.read_text())

    def test_dry_run_writes_nothing(self):
        p = self.home / ".bashrc"
        p.write_text("A=1\n")
        self.assertTrue(files.upsert_block(p, "B=2", dry_run=True))
        self.assertEqual(p.read_text(), "A=1\n")


if __name__ == "__main__":
    unittest.main()
