# Fonts.ps1 - download and install Nerd Fonts.
#
# We don't bundle font binaries (they're large and licensed separately), but the
# whole point of the prompt/glyph layers is having a Nerd Font installed. This
# fetches one straight from the nerd-fonts GitHub releases and installs it for the
# current user - no admin, no manual unzip - so a fresh machine is one command away.

# Map a catalog id (or a raw asset name) to the nerd-fonts release asset.
function Get-PoshPaletteFontAsset {
    param([Parameter(Mandatory)][string] $Name)
    $match = Get-PoshPaletteFonts | Where-Object { $_.id -eq $Name -or $_.nerd -eq $Name -or $_.face -eq $Name } | Select-Object -First 1
    if ($match -and $match.nerd) { $match.nerd } else { $Name }
}

function Install-PoshPaletteFont {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string] $Name,   # catalog id (e.g. jetbrains) or asset (e.g. JetBrainsMono)
        [string] $Version = 'latest'
    )
    $asset = Get-PoshPaletteFontAsset $Name
    $url = if ($Version -eq 'latest') {
        "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$asset.zip"
    } else {
        "https://github.com/ryanoasis/nerd-fonts/releases/download/$Version/$asset.zip"
    }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("ppfont_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force -WhatIf:$false | Out-Null
    try {
        $zip = Join-Path $tmp "$asset.zip"
        Write-Host "Downloading $asset Nerd Font from nerd-fonts releases..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $url -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $files = Get-ChildItem $tmp -Recurse -Include '*.ttf', '*.otf'
        if (-not $files) { throw "No font files in $asset.zip (is '$asset' a valid Nerd Font name?)." }

        if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
            $dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
            $reg = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
            New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false | Out-Null
            foreach ($f in $files) {
                if ($PSCmdlet.ShouldProcess($f.Name, 'Install font')) {
                    $dest = Join-Path $dir $f.Name
                    Copy-Item $f.FullName $dest -Force
                    $title = [IO.Path]::GetFileNameWithoutExtension($f.Name)
                    $kind  = if ($f.Extension -eq '.otf') { 'OpenType' } else { 'TrueType' }
                    New-ItemProperty -Path $reg -Name "$title ($kind)" -Value $dest -PropertyType String -Force | Out-Null
                }
            }
        } else {
            $dir = if ($IsMacOS) { Join-Path $HOME 'Library/Fonts' } else { Join-Path $HOME '.local/share/fonts' }
            New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false | Out-Null
            foreach ($f in $files) {
                if ($PSCmdlet.ShouldProcess($f.Name, 'Install font')) { Copy-Item $f.FullName (Join-Path $dir $f.Name) -Force }
            }
            if (-not $IsMacOS -and (Get-Command fc-cache -ErrorAction SilentlyContinue)) { fc-cache -f $dir | Out-Null }
        }

        Write-Host "Installed $($files.Count) file(s) for $asset. Pick it as your terminal font - it's already in the PoshPalette font list." -ForegroundColor Green
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
