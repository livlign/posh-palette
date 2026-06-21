# PoshPalette.psm1 - module entry point. Dot-sources sources and exposes the
# public commands.

. "$PSScriptRoot/src/Jsonc.ps1"
. "$PSScriptRoot/src/Theme.ps1"
. "$PSScriptRoot/src/Prompt.ps1"
. "$PSScriptRoot/src/Appliers.ps1"
. "$PSScriptRoot/src/Layers.ps1"
. "$PSScriptRoot/src/Import.ps1"
. "$PSScriptRoot/src/Remote.ps1"
. "$PSScriptRoot/src/Fonts.ps1"
. "$PSScriptRoot/src/Doctor.ps1"
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
    # Remember the composition so later per-layer tweaks build on this theme.
    if (-not $DryRun) {
        try {
            $comp = if (Test-Path $NameOrPath) { Get-Content $NameOrPath -Raw | ConvertFrom-Json }
                    else { (Get-PoshPaletteThemes | Where-Object { $_.Id -eq $NameOrPath -or $_.Name -eq $NameOrPath } | Select-Object -First 1).Data }
            if ($comp) { Save-PoshPaletteCurrentComposition (ConvertTo-PoshPaletteHashtable $comp) }
        } catch { Write-Verbose "Could not save current composition: $_" }
    }
}

# Friendly entry point: `palette` launches the interactive picker.
Set-Alias -Name palette -Value Start-PoshPalette

Export-ModuleMember -Function Start-PoshPalette, Install-PoshPaletteTheme, Get-PoshPaletteThemes,
    Set-PoshPaletteTheme, Import-PoshPaletteTheme, Restore-PoshPalette, Reset-PoshPalette,
    Import-PoshPaletteScheme, Get-PoshPaletteRemoteCatalog, Save-PoshPaletteRemoteTheme, Update-PoshPaletteCatalog,
    Test-PoshPaletteSetup, Install-PoshPaletteFont,
    Set-PoshPaletteScheme, Set-PoshPaletteColors, Set-PoshPalettePrompt, Set-PoshPaletteFont, Set-PoshPaletteLayer -Alias palette
