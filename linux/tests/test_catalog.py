import unittest

from helpers import TempHome
from posh_palette import catalog


class CatalogTests(TempHome):
    def test_every_bundled_theme_resolves(self):
        ts = catalog.themes()
        self.assertGreater(len(ts), 40)
        for t in ts:
            r = catalog.resolve(t)
            sc = r["terminal"]["scheme"]
            self.assertTrue(sc["background"].startswith("#"), t["id"])
            self.assertIn("Command", r["psReadLine"], t["id"])
            self.assertTrue(r["prompt"].get("generated") or r["prompt"].get("ohMyPoshTheme"), t["id"])

    def test_themes_sorted_by_order(self):
        orders = [t.get("order") for t in catalog.themes() if t.get("order") is not None]
        self.assertEqual(orders, sorted(orders))

    def test_derived_input_roles(self):
        r = catalog.resolve(catalog.find_theme("tokyo-night"))
        prl = r["psReadLine"]
        self.assertEqual(prl["Keyword"], prl["Operator"])
        self.assertEqual(prl["ContinuationPrompt"], prl["Comment"])

    def test_typed_font_and_prompt_pass_through(self):
        comp = dict(catalog.find_theme("nord"), font="Fira Code", prompt="jandedobbeleer")
        r = catalog.resolve(comp)
        self.assertEqual(r["terminal"]["font"], "Fira Code")
        self.assertEqual(r["prompt"], {"ohMyPoshTheme": "jandedobbeleer"})

    def test_unknown_theme_raises(self):
        with self.assertRaises(catalog.CatalogError):
            catalog.find_theme("no-such-theme")

    def test_current_composition_roundtrip(self):
        self.assertEqual(catalog.current_composition()["id"], catalog.themes()[0]["id"])
        catalog.save_current_composition({"name": "X", "scheme": "nord", "_path": "drop me"})
        self.assertEqual(catalog.current_composition(), {"name": "X", "scheme": "nord"})
        catalog.forget_current_composition()
        self.assertFalse(catalog.current_path().exists())

    def test_cache_adds_but_never_shadows(self):
        d = catalog.cache_root() / "schemes"
        d.mkdir(parents=True)
        (d / "nord.json").write_text('{"id": "nord", "name": "Fake", "colors": {}}')
        (d / "extra.json").write_text('{"id": "extra", "name": "Extra", "colors": {}}')
        self.assertEqual(catalog.catalog_item("schemes", "nord")["name"], "Nord")
        self.assertEqual(catalog.catalog_item("schemes", "extra")["name"], "Extra")


if __name__ == "__main__":
    unittest.main()
