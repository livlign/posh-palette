# Import.ps1 - bring outside color schemes into the catalog.
#
# The moat is being the integration layer: rather than re-typing palettes, import
# the formats the community already publishes - iTerm2 .itermcolors, base16 yaml,
# and Windows Terminal scheme JSON - into a PoshPalette schemes/*.json entry.

$script:AnsiOrder = @('black','red','green','yellow','blue','purple','cyan','white',
    'brightBlack','brightRed','brightGreen','brightYellow','brightBlue','brightPurple','brightCyan','brightWhite')

function ConvertTo-PoshPaletteHex {
    param([double] $R, [double] $G, [double] $B)   # components 0..1
    '#{0:X2}{1:X2}{2:X2}' -f [int][Math]::Round($R * 255), [int][Math]::Round($G * 255), [int][Math]::Round($B * 255)
}

# iTerm2 .itermcolors is an XML plist of "Ansi N Color" + Background/Foreground/Cursor dicts.
function ConvertFrom-ITermColors {
    param([Parameter(Mandatory)][string] $Text)
    [xml] $xml = $Text
    $root = $xml.plist.dict
    $map = @{}
    $keys = $root.key
    $dicts = $root.dict
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $d = $dicts[$i]
        $comp = @{}
        for ($j = 0; $j -lt $d.key.Count; $j++) { $comp[$d.key[$j]] = [double]$d.real[$j] }
        $map[$keys[$i]] = ConvertTo-PoshPaletteHex $comp['Red Component'] $comp['Green Component'] $comp['Blue Component']
    }
    $colors = [ordered]@{}
    for ($i = 0; $i -lt 16; $i++) { $colors[$script:AnsiOrder[$i]] = $map["Ansi $i Color"] }
    $colors['background']          = $map['Background Color']
    $colors['foreground']          = $map['Foreground Color']
    $colors['cursorColor']         = ($map['Cursor Color']    ?? $map['Foreground Color'])
    $colors['selectionBackground'] = ($map['Selection Color'] ?? $map['Background Color'])
    $colors
}

# base16 yaml: base00..base0F hex values, mapped to ANSI via the standard template.
function ConvertFrom-Base16 {
    param([Parameter(Mandatory)][string] $Text)
    $b = @{}
    foreach ($line in ($Text -split "`n")) {
        if ($line -match '^\s*(base0[0-9A-Fa-f])\s*:\s*"?#?([0-9A-Fa-f]{6})"?') {
            $b[$Matches[1].ToLower()] = '#' + $Matches[2].ToUpper()
        }
    }
    if ($b.Count -lt 16) { throw "Not a base16 scheme (found $($b.Count)/16 base colors)." }
    [ordered]@{
        black = $b['base00']; red = $b['base08']; green = $b['base0b']; yellow = $b['base0a']
        blue = $b['base0d']; purple = $b['base0e']; cyan = $b['base0c']; white = $b['base05']
        brightBlack = $b['base03']; brightRed = $b['base08']; brightGreen = $b['base0b']; brightYellow = $b['base0a']
        brightBlue = $b['base0d']; brightPurple = $b['base0e']; brightCyan = $b['base0c']; brightWhite = $b['base07']
        background = $b['base00']; foreground = $b['base05']
        cursorColor = $b['base05']; selectionBackground = $b['base02']
    }
}

# Windows Terminal scheme JSON is already close to our shape; normalize keys.
function ConvertFrom-WtScheme {
    param([Parameter(Mandatory)][string] $Text)
    $s = ConvertFrom-Jsonc $Text
    $colors = [ordered]@{}
    foreach ($k in $script:AnsiOrder) { if ($s.$k) { $colors[$k] = $s.$k } }
    foreach ($k in 'background','foreground','cursorColor','selectionBackground') { if ($s.$k) { $colors[$k] = $s.$k } }
    $colors
}

# Detect format, parse, and (optionally) save into schemes/<id>.json.
function Import-PoshPaletteScheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string] $Path,
        [string] $Id,
        [string] $Name,
        [ValidateSet('auto','iterm','base16','wt')] [string] $Format = 'auto',
        [switch] $Save
    )
    if (-not (Test-Path $Path)) { throw "File not found: $Path" }
    $text = Get-Content $Path -Raw
    $ext  = [IO.Path]::GetExtension($Path).ToLower()

    if ($Format -eq 'auto') {
        $Format = if ($ext -eq '.itermcolors' -or $text -match '<plist') { 'iterm' }
                  elseif ($ext -in '.yaml','.yml' -or $text -match '(?m)^\s*base0[0-9A-Fa-f]\s*:') { 'base16' }
                  else { 'wt' }
    }
    $colors = switch ($Format) {
        'iterm'  { ConvertFrom-ITermColors $text }
        'base16' { ConvertFrom-Base16 $text }
        'wt'     { ConvertFrom-WtScheme $text }
    }

    if (-not $Id)   { $Id   = [IO.Path]::GetFileNameWithoutExtension($Path).ToLower() -replace '[^a-z0-9]+','-' -replace '(^-|-$)','' }
    if (-not $Name) { $Name = (Get-Culture).TextInfo.ToTitleCase(($Id -replace '-',' ')) }
    $scheme = [ordered]@{ id = $Id; name = $Name; colors = $colors }

    if ($Save) {
        $dir  = Join-Path (Get-PoshPaletteDataRoot) 'schemes'
        $dest = Join-Path $dir "$Id.json"
        Set-Content -Path $dest -Value ($scheme | ConvertTo-Json -Depth 32) -Encoding utf8
        Write-Host "Imported scheme '$Id' -> $dest" -ForegroundColor Green
    }
    [pscustomobject]$scheme
}
