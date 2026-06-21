@{
    RootModule        = 'PoshPalette.psm1'
    ModuleVersion     = '0.4.2'
    GUID              = '7c9e6a1b-4f2d-4b8e-9a3c-1d5f8b2e0a47'
    Author            = 'PoshPalette contributors'
    Copyright         = '(c) PoshPalette contributors. MIT licensed.'
    Description       = 'Interactive theme picker for PowerShell + Windows Terminal. Browse, preview, and apply a look across all 4 layers (Terminal scheme, PSReadLine, $PSStyle, oh-my-posh) at once, with live preview, 35 bundled themes, scheme import (iTerm2/base16), palette-aware prompt generation, and an auto-updating community catalog.'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @('Start-PoshPalette', 'Install-PoshPaletteTheme', 'Get-PoshPaletteThemes', 'Set-PoshPaletteTheme', 'Import-PoshPaletteTheme', 'Restore-PoshPalette', 'Reset-PoshPalette', 'Import-PoshPaletteScheme', 'Get-PoshPaletteRemoteCatalog', 'Save-PoshPaletteRemoteTheme', 'Update-PoshPaletteCatalog', 'Test-PoshPaletteSetup', 'Install-PoshPaletteFont', 'Set-PoshPaletteScheme', 'Set-PoshPaletteColors', 'Set-PoshPalettePrompt', 'Set-PoshPaletteFont', 'Set-PoshPaletteLayer')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('palette')
    PrivateData       = @{
        PSData = @{
            Tags         = @('terminal','theme','powershell','windows-terminal','psreadline','oh-my-posh','prompt','colorscheme')
            LicenseUri   = 'https://github.com/livlign/posh-palette/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/livlign/posh-palette'
            ReleaseNotes = 'https://github.com/livlign/posh-palette/blob/main/CHANGELOG.md'
        }
    }
}
