@{
    RootModule        = 'PoshPalette.psm1'
    ModuleVersion     = '0.9.0'
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
            ReleaseNotes = 'v0.9.0: experimental cross-terminal scheme colors via OSC escape sequences. New opt-in commands (Set-PoshPaletteSchemeOsc, New-PoshPaletteOscSequence, Test-PoshPaletteOscTerminal) apply a scheme''s 16 ANSI colors + fg/bg/cursor beyond Windows Terminal (WezTerm, macOS Terminal.app, kitty, and other OSC-capable terminals); per-session, additive, and it does not change the existing settings.json / $PROFILE appliers. Full history in CHANGELOG.md.'
        }
    }
}
