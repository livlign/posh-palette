# Osc.ps1 - SPIKE: apply a scheme's colors via OSC escape sequences instead of
# writing Windows Terminal settings.json. See GitHub issue #12.
#
# This is an ALTERNATE applier for the *colors* of the scheme layer only. It
# lets the 16 ANSI colors + foreground/background/cursor land on terminals that
# aren't Windows Terminal (WezTerm, kitty, Alacritty, iTerm2, VTE, and - per
# real-hardware testing - macOS Terminal.app). Background image, opacity/acrylic
# and font have no OSC equivalent and stay Windows-Terminal-only.
#
# Everything here is additive: it does not touch the existing settings.json /
# $PROFILE appliers. Nothing calls into it yet - it's exposed as standalone
# commands so the approach can be verified on real terminals before it graduates
# into Set-PoshPaletteTheme.
#
# What OSC can/can't do (verified 2026-07-05 on Terminal.app):
#   - Setting (OSC 4/10/11/12) works broadly, including Terminal.app.
#   - Reset (OSC 104/110/111/112) and query (OSC ...;?) do NOT work on
#     Terminal.app - so revert is "drop the emit and open a new session"
#     (OSC state is per-session), never a reset code we can't rely on.

# #RRGGBB (or RRGGBB) -> rgb:RR/GG/BB. Lowercase 8-bit `rgb:` is the most
# portable XParseColor form (preferred over #RRGGBB and over X11 color names).
function ConvertTo-PoshPaletteOscColor {
    param([Parameter(Mandatory)][string] $Hex)
    $h = $Hex.TrimStart('#')
    if ($h -notmatch '^[0-9A-Fa-f]{6}$') { throw "Expected a #RRGGBB hex color, got '$Hex'." }
    'rgb:{0}/{1}/{2}' -f $h.Substring(0, 2).ToLower(), $h.Substring(2, 2).ToLower(), $h.Substring(4, 2).ToLower()
}

# Build the raw OSC byte string that recolors the current terminal from a scheme.
# $SchemeColors is a scheme's `colors` object (background/foreground/cursorColor/
# selectionBackground + the 16 ANSI names) - i.e. schemes/*.json `.colors`, which
# is also exactly $ResolvedTheme.terminal.scheme.
function New-PoshPaletteOscSequence {
    param([Parameter(Mandatory)] $SchemeColors)

    $e  = [char]27      # ESC
    $st = "$e\"         # String Terminator (ESC \) - spec-correct; BEL also works

    # The 16 ANSI palette indices, in Windows Terminal / standard ANSI order.
    $ansi = 'black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white',
            'brightBlack', 'brightRed', 'brightGreen', 'brightYellow',
            'brightBlue', 'brightPurple', 'brightCyan', 'brightWhite'

    $pairs = for ($i = 0; $i -lt $ansi.Count; $i++) {
        $hex = $SchemeColors.($ansi[$i])
        if ($hex) { '{0};{1}' -f $i, (ConvertTo-PoshPaletteOscColor $hex) }
    }

    $sb = [System.Text.StringBuilder]::new()
    # OSC 4 chains all palette entries in one sequence: ESC ] 4 ; i ; spec ; i ; spec ... ST
    if ($pairs)                          { [void]$sb.Append("$e]4;$($pairs -join ';')$st") }
    if ($SchemeColors.foreground)        { [void]$sb.Append("$e]10;$(ConvertTo-PoshPaletteOscColor $SchemeColors.foreground)$st") }
    if ($SchemeColors.background)        { [void]$sb.Append("$e]11;$(ConvertTo-PoshPaletteOscColor $SchemeColors.background)$st") }
    if ($SchemeColors.cursorColor)       { [void]$sb.Append("$e]12;$(ConvertTo-PoshPaletteOscColor $SchemeColors.cursorColor)$st") }
    if ($SchemeColors.selectionBackground) { [void]$sb.Append("$e]17;$(ConvertTo-PoshPaletteOscColor $SchemeColors.selectionBackground)$st") }
    $sb.ToString()
}

# Best-effort guess at whether the current terminal honors OSC color-setting.
# Heuristic and deliberately permissive: OSC set is a silent no-op on most
# terminals that ignore it, and callers can override with -Force. Refine the
# allow/deny lists as real-hardware results come in.
function Test-PoshPaletteOscTerminal {
    # Multiplexers need DCS passthrough we don't emit yet - skip for now.
    if ($env:TMUX -or $env:STY) { return $false }
    # Windows Terminal advertises itself and fully supports OSC.
    if ($env:WT_SESSION) { return $true }
    if ($env:KITTY_WINDOW_ID) { return $true }
    switch ($env:TERM_PROGRAM) {
        'WezTerm'        { return $true }
        'iTerm.app'      { return $true }
        'Apple_Terminal' { return $true }   # verified: OSC 4/10/11 set works
        'vscode'         { return $true }
    }
    # kitty/alacritty/foot/VTE advertise via TERM.
    if ($env:TERM -match '^(xterm|kitty|alacritty|foot|vte|screen-256color-bce)') { return $true }
    $false
}

# The runnable spike command: recolor the CURRENT session from a bundled scheme.
# Per-session only (nothing persisted) - open a new tab/window to revert.
#   Set-PoshPaletteSchemeOsc eclipse
#   Set-PoshPaletteSchemeOsc porcelain -Force     # try a terminal not on the list
#   Set-PoshPaletteSchemeOsc eclipse -ShowBytes   # print the escapes (no apply)
function Set-PoshPaletteSchemeOsc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string] $Scheme,
        [switch] $Force,       # apply even if the terminal isn't on the OSC-safe list
        [switch] $ShowBytes    # print the escape sequence (escaped) instead of applying
    )

    $item = Get-PoshPaletteCatalogItem -Kind 'schemes' -Id $Scheme
    $seq  = New-PoshPaletteOscSequence -SchemeColors $item.colors

    if ($ShowBytes) {
        # Render ESC as \e so the sequence is inspectable without moving the cursor.
        Write-Host ($seq -replace [char]27, '\e')
        return
    }

    if (-not $Force -and -not (Test-PoshPaletteOscTerminal)) {
        Write-Warning ("Terminal not on the OSC-safe list (TERM_PROGRAM='{0}', TERM='{1}'). Re-run with -Force to try anyway." -f $env:TERM_PROGRAM, $env:TERM)
        return
    }

    [Console]::Write($seq)
    Write-Host "  Applied scheme '$($item.name)' to this session via OSC." -ForegroundColor Green
    Write-Host "  (Colors are per-session. Open a new tab/window to revert.)" -ForegroundColor DarkGray
}

# Build the $PROFILE snippet that re-emits the OSC colors on every session start
# (the persistence story). Not wired into the profile writer yet - returned as a
# string so it can be reviewed/tested. Self-guards at runtime so the same profile
# opened in a non-OSC terminal is a harmless no-op.
function New-PoshPaletteOscBlock {
    param([Parameter(Mandatory)] $SchemeColors)
    $seq = New-PoshPaletteOscSequence -SchemeColors $SchemeColors
    # Emit as a here-string that reconstructs the ESC bytes at profile-load time.
    $literal = $seq -replace [char]27, '`e'
    @"
# PoshPalette OSC scheme (per-session color apply; see issue #12)
if (`$env:WT_SESSION -or `$env:TERM_PROGRAM -or (`$env:TERM -match '^(xterm|kitty|alacritty|foot|vte)')) {
    [Console]::Write("$literal")
}
"@
}
