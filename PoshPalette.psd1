@{
    RootModule        = 'PoshPalette.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '7c9e6a1b-4f2d-4b8e-9a3c-1d5f8b2e0a47'
    Author            = 'PoshPalette contributors'
    Description       = 'VS Code-style theme picker for PowerShell + Windows Terminal. Styles all 4 layers (Terminal scheme, PSReadLine, $PSStyle, oh-my-posh) with live preview.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @('Start-PoshPalette', 'Install-PoshPaletteTheme', 'Get-PoshPaletteThemes', 'Set-PoshPaletteTheme', 'Import-PoshPaletteTheme', 'Restore-PoshPalette')
    AliasesToExport   = @('palette')
    PrivateData       = @{ PSData = @{ Tags = @('terminal','theme','powershell','windows-terminal','psreadline','oh-my-posh') } }
}
