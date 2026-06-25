#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Contrast gate for theme authors. Imports the authoring workbench (tools/) and
# asserts that no bundled theme ships a syntax color that is effectively
# unreadable against its background. This is the automated form of the v0.6.3
# "raise contrast on faint syntax colours" pass - a number, not an eyeball.
#
# Uses ONLY the native WCAG math in the authoring module, so it needs no binary
# dependency and runs identically on every CI OS.

# Built at DISCOVERY time so the data-driven `It -ForEach` below can expand.
$themeIds = Get-ChildItem (Join-Path (Split-Path $PSScriptRoot -Parent) 'themes') -Filter *.json |
    ForEach-Object { ($_ | Get-Content -Raw | ConvertFrom-Json).id }

BeforeAll {
    Import-Module "$PSScriptRoot/../tools/PoshPalette.Authoring.psm1" -Force
}

Describe 'WCAG contrast core' {
    It 'returns 21 for black on white and 1 for identical colors' {
        Get-PPContrastRatio '#000000' '#FFFFFF' | Should -Be 21
        Get-PPContrastRatio '#4DECA0' '#4DECA0' | Should -Be 1
    }
}

Describe 'Bundled theme legibility' {
    It 'discovered themes to lint' {
        # Re-derive at run time: top-level $themeIds is a discovery-scope variable,
        # not in scope inside the It body in Pester v5.
        $count = (Get-ChildItem (Join-Path (Split-Path $PSScriptRoot -Parent) 'themes') -Filter *.json).Count
        $count | Should -BeGreaterThan 0
    }

    It 'every syntax color clears the readability floor: <_>' -ForEach $themeIds {
        $failures = Test-PoshPaletteContrast -Theme $_ | Where-Object { -not $_.Pass }
        $detail = ($failures | ForEach-Object { "$($_.Role)=$($_.Color)@$($_.Ratio):1" }) -join ', '
        $failures | Should -BeNullOrEmpty -Because "these colors are near-invisible on the background: $detail"
    }
}
