@{
    RootModule        = 'PoshPalette.psm1'
    ModuleVersion     = '0.8.2'
    GUID              = '7c9e6a1b-4f2d-4b8e-9a3c-1d5f8b2e0a47'
    Author            = 'PoshPalette contributors'
    Copyright         = '(c) PoshPalette contributors. MIT licensed.'
    Description       = 'Interactive theme picker for PowerShell + Windows Terminal. Browse, preview, and apply a look across all 4 layers (Terminal scheme, PSReadLine, $PSStyle, oh-my-posh) at once, with live preview, 47 bundled themes, scheme import (iTerm2/base16), palette-aware prompt generation, and an auto-updating community catalog.'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @('Start-PoshPalette', 'Install-PoshPaletteTheme', 'Get-PoshPaletteThemes', 'Set-PoshPaletteTheme', 'Import-PoshPaletteTheme', 'Restore-PoshPalette', 'Reset-PoshPalette', 'Import-PoshPaletteScheme', 'Get-PoshPaletteRemoteCatalog', 'Save-PoshPaletteRemoteTheme', 'Update-PoshPaletteCatalog', 'Test-PoshPaletteSetup', 'Install-PoshPaletteFont', 'Set-PoshPaletteScheme', 'Set-PoshPaletteColors', 'Set-PoshPalettePrompt', 'Set-PoshPaletteFont', 'Set-PoshPaletteLayer', 'Set-PoshPaletteSchemeOsc', 'New-PoshPaletteOscSequence', 'Test-PoshPaletteOscTerminal')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('palette')
    PrivateData       = @{
        PSData = @{
            Tags         = @('terminal','theme','powershell','pwsh','windows-terminal','psreadline','oh-my-posh','prompt','colorscheme','color-scheme','tui','nerd-fonts')
            LicenseUri   = 'https://github.com/livlign/posh-palette/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/livlign/posh-palette'
            IconUri      = 'https://livlign.github.io/posh-palette/icon-256.png'
            ReleaseNotes = 'v0.8.2: table headers are now a single uniform color. PowerShell 7.4+ styles calculated column headers (e.g. Length in a dir listing) with a separate green-by-default property; PoshPalette now sets it alongside TableHeader so the whole header row matches the theme. Full history in CHANGELOG.md.'
        }
    }
}
