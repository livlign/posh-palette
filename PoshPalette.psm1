# PoshPalette.psm1 - module entry point. Dot-sources sources and exposes the
# public commands.

. "$PSScriptRoot/src/Theme.ps1"
. "$PSScriptRoot/src/Appliers.ps1"
. "$PSScriptRoot/src/Tui.ps1"

# Headless install by name: `Install-PoshPaletteTheme 'tokyo-night'`
function Install-PoshPaletteTheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string] $NameOrPath,
        [switch] $DryRun
    )
    $theme = Import-PoshPaletteTheme -NameOrPath $NameOrPath
    Set-PoshPaletteTheme -Theme $theme -DryRun:$DryRun
}

# Friendly entry point: `palette` launches the interactive picker.
Set-Alias -Name palette -Value Start-PoshPalette

Export-ModuleMember -Function Start-PoshPalette, Install-PoshPaletteTheme, Get-PoshPaletteThemes, Set-PoshPaletteTheme, Import-PoshPaletteTheme, Restore-PoshPalette -Alias palette
