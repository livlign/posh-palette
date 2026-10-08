import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import helpers  # noqa: F401
from posh_palette import DATA_ROOT
from posh_palette.catalog import catalog, catalog_item
from posh_palette.prompt import STYLES, new_omp_config

PS_SCRIPT = r"""
param([string]$Root, [string]$Out)
. "$Root/src/Jsonc.ps1"; . "$Root/src/Theme.ps1"; . "$Root/src/Prompt.ps1"
$res = [ordered]@{}
foreach ($sid in 'tokyo-night','porcelain','bong') {
  $sc = (Get-Content "$Root/schemes/$sid.json" -Raw | ConvertFrom-Json).colors
  foreach ($pf in Get-ChildItem "$Root/prompts" -Filter *.json) {
    $p = Get-Content $pf.FullName -Raw | ConvertFrom-Json
    $a = @{ Style = $p.style }; if ($p.gradient) { $a.Gradient = $p.gradient }
    $res["$sid|$($p.id)"] = New-PoshPaletteOmpConfig $sc @a
  }
}
$res | ConvertTo-Json -Depth 40 | Set-Content $Out -Encoding utf8
"""


class PromptTests(unittest.TestCase):
    def test_every_style_builds(self):
        colors = catalog_item("schemes", "tokyo-night")["colors"]
        for style in STYLES:
            cfg = new_omp_config(colors, style)
            self.assertEqual(cfg["version"], 4)
            self.assertTrue(cfg["blocks"], style)

    def test_colors_come_from_the_scheme(self):
        colors = catalog_item("schemes", "nord")["colors"]
        text = json.dumps(new_omp_config(colors, "classic"))
        self.assertIn(colors["blue"], text)
        self.assertNotIn("#7AA2F7", text)   # the tokyo-night fallback

    def test_unknown_style_rejected(self):
        with self.assertRaises(ValueError):
            new_omp_config({}, "nope")

    def test_catalog_prompts_use_known_styles(self):
        for p in catalog("prompts"):
            if p.get("generate"):
                self.assertIn(p.get("style", "classic"), STYLES, p["id"])

    @unittest.skipUnless(shutil.which("pwsh"), "pwsh not installed")
    def test_parity_with_powershell_generator(self):
        with tempfile.TemporaryDirectory() as d:
            script, out = Path(d) / "gen.ps1", Path(d) / "out.json"
            script.write_text(PS_SCRIPT)
            subprocess.run(["pwsh", "-NoProfile", "-File", str(script), "-Root", str(DATA_ROOT), "-Out", str(out)], check=True)
            ps = json.loads(out.read_text(encoding="utf-8-sig"))
        self.assertGreater(len(ps), 40)
        for key, expected in ps.items():
            sid, pid = key.split("|")
            p = catalog_item("prompts", pid)
            got = new_omp_config(catalog_item("schemes", sid)["colors"], p.get("style", "classic"), p.get("gradient"))
            self.assertEqual(got, expected, key)


if __name__ == "__main__":
    unittest.main()
