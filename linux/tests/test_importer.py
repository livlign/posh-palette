import json
import plistlib
import unittest

from helpers import TempHome
from posh_palette import importer
from posh_palette.colors import ANSI

HEXES = [f"#{i:02X}{i:02X}{i:02X}" for i in range(16)]


class ImportTests(TempHome):
    def write(self, name, text):
        p = self.home / name
        p.write_bytes(text if isinstance(text, bytes) else text.encode())
        return p

    def check(self, scheme):
        for i, n in enumerate(ANSI):
            self.assertEqual(scheme["colors"][n], HEXES[i], n)
        self.assertEqual(scheme["colors"]["background"], "#101010")

    def test_ghostty(self):
        text = "\n".join(f"palette = {i}={h}" for i, h in enumerate(HEXES)) + "\nbackground = 101010\nforeground = #eeeeee\n"
        s, _ = importer.import_scheme(self.write("My Theme", text))
        self.check(s)
        self.assertEqual(s["id"], "my-theme")

    def test_kitty(self):
        text = "\n".join(f"color{i} {h}" for i, h in enumerate(HEXES)) + "\nbackground #101010\nforeground #eeeeee\n"
        self.check(importer.import_scheme(self.write("k.conf", text))[0])

    def test_iterm(self):
        d = {f"Ansi {i} Color": {"Red Component": i / 255, "Green Component": i / 255, "Blue Component": i / 255} for i in range(16)}
        d["Background Color"] = {"Red Component": 16 / 255, "Green Component": 16 / 255, "Blue Component": 16 / 255}
        d["Foreground Color"] = {"Red Component": 1.0, "Green Component": 1.0, "Blue Component": 1.0}
        self.check(importer.import_scheme(self.write("x.itermcolors", plistlib.dumps(d)))[0])

    def test_wt_jsonc(self):
        body = {n: HEXES[i] for i, n in enumerate(ANSI)}
        body.update(background="#101010", foreground="#EEEEEE", name="x")
        text = "// a comment\n" + json.dumps(body)[:-1] + ",}"
        self.check(importer.import_scheme(self.write("x.json", text))[0])

    def test_base16_and_save(self):
        text = "\n".join(f'base0{i:X}: "{i:02x}{i:02x}{i:02x}"' for i in range(16))
        s, dest = importer.import_scheme(self.write("b.yaml", text), save=True)
        self.assertEqual(s["colors"]["blue"], "#0D0D0D")
        self.assertTrue(dest.exists())
        self.assertEqual(json.loads(dest.read_text())["id"], "b")


if __name__ == "__main__":
    unittest.main()
