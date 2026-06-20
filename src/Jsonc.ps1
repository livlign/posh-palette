# Jsonc.ps1 - JSONC (JSON-with-comments) reading and *surgical* editing.
#
# Windows Terminal's settings.json is JSONC: // line comments, /* */ block
# comments, and tolerated trailing commas. ConvertFrom-Json can't parse it, and
# a naive parse->reserialize round-trip throws away every comment the user wrote.
#
# Remove-JsoncComments handles reading (strip comments, then parse).
# Edit-Jsonc* handle writing: they mutate only the spans that change and leave
# the rest of the file - comments, formatting, key order - byte-for-byte intact.

# --- Reading ------------------------------------------------------------------

# Strip comments while respecting string contents, so a "https://" inside a
# value or a "," inside a string is never mistaken for a comment/separator.
function Remove-JsoncComments {
    param([string] $Text)
    $sb = [System.Text.StringBuilder]::new()
    $inString = $false; $escaped = $false
    $i = 0; $n = $Text.Length
    while ($i -lt $n) {
        $c    = $Text[$i]
        $next = if ($i + 1 -lt $n) { $Text[$i + 1] } else { [char]0 }
        if ($inString) {
            [void]$sb.Append($c)
            if     ($escaped)      { $escaped = $false }
            elseif ($c -eq '\')    { $escaped = $true }
            elseif ($c -eq '"')    { $inString = $false }
            $i++; continue
        }
        if ($c -eq '"')                  { $inString = $true; [void]$sb.Append($c); $i++; continue }
        if ($c -eq '/' -and $next -eq '/') { while ($i -lt $n -and $Text[$i] -ne "`n") { $i++ }; continue }
        if ($c -eq '/' -and $next -eq '*') {
            $i += 2
            while ($i -lt $n -and -not ($Text[$i] -eq '*' -and $i + 1 -lt $n -and $Text[$i + 1] -eq '/')) { $i++ }
            $i += 2; continue
        }
        [void]$sb.Append($c); $i++
    }
    $sb.ToString()
}

function ConvertFrom-Jsonc {
    param([Parameter(Mandatory)][string] $Text, [switch] $AsHashtable)
    $clean = Remove-JsoncComments $Text
    $clean = [regex]::Replace($clean, ',(\s*[}\]])', '$1')   # tolerate trailing commas
    $clean | ConvertFrom-Json -AsHashtable:$AsHashtable
}

# --- Structural scanning (comment- and string-aware) --------------------------

# Given $Open pointing at a '{' or '[', return the index of its matching close.
function Find-JsoncBracketMatch {
    param([string] $Text, [int] $Open)
    $openCh  = $Text[$Open]
    $closeCh = if ($openCh -eq '{') { '}' } else { ']' }
    $depth = 0; $i = $Open; $n = $Text.Length; $inStr = $false; $esc = $false
    while ($i -lt $n) {
        $c    = $Text[$i]
        $next = if ($i + 1 -lt $n) { $Text[$i + 1] } else { [char]0 }
        if ($inStr) {
            if     ($esc)        { $esc = $false }
            elseif ($c -eq '\')  { $esc = $true }
            elseif ($c -eq '"')  { $inStr = $false }
            $i++; continue
        }
        if ($c -eq '"')                    { $inStr = $true; $i++; continue }
        if ($c -eq '/' -and $next -eq '/') { while ($i -lt $n -and $Text[$i] -ne "`n") { $i++ }; continue }
        if ($c -eq '/' -and $next -eq '*') { $i += 2; while ($i -lt $n -and -not ($Text[$i] -eq '*' -and $Text[$i + 1] -eq '/')) { $i++ }; $i += 2; continue }
        if ($c -eq $openCh)  { $depth++ }
        elseif ($c -eq $closeCh) { $depth--; if ($depth -eq 0) { return $i } }
        $i++
    }
    return -1
}

# End index (inclusive) of the JSON value that starts at $Start (first non-ws char).
function Get-JsoncValueEnd {
    param([string] $Text, [int] $Start)
    $c = $Text[$Start]
    if ($c -eq '{' -or $c -eq '[') { return (Find-JsoncBracketMatch $Text $Start) }
    if ($c -eq '"') {
        $i = $Start + 1; $n = $Text.Length; $esc = $false
        while ($i -lt $n) {
            if ($esc) { $esc = $false }
            elseif ($Text[$i] -eq '\') { $esc = $true }
            elseif ($Text[$i] -eq '"') { return $i }
            $i++
        }
        return -1
    }
    # primitive: read until a structural delimiter
    $i = $Start; $n = $Text.Length
    while ($i -lt $n -and $Text[$i] -notin @(',', '}', ']') -and $Text[$i] -ne "`n" -and $Text[$i] -ne "`r") { $i++ }
    return ($i - 1)
}

# Find a depth-1 member inside the object whose '{' is at $ObjOpen.
# Returns @{ ValueStart; ValueEnd } for the member's value, or $null.
function Find-JsoncMember {
    param([string] $Text, [int] $ObjOpen, [string] $Key)
    $close = Find-JsoncBracketMatch $Text $ObjOpen
    $i = $ObjOpen + 1; $depth = 0; $inStr = $false; $esc = $false
    $target = '"' + $Key + '"'
    while ($i -lt $close) {
        $c    = $Text[$i]
        $next = if ($i + 1 -lt $close) { $Text[$i + 1] } else { [char]0 }
        if ($inStr) {
            if     ($esc)        { $esc = $false }
            elseif ($c -eq '\')  { $esc = $true }
            elseif ($c -eq '"')  { $inStr = $false }
            $i++; continue
        }
        if ($c -eq '/' -and $next -eq '/') { while ($i -lt $close -and $Text[$i] -ne "`n") { $i++ }; continue }
        if ($c -eq '/' -and $next -eq '*') { $i += 2; while ($i -lt $close -and -not ($Text[$i] -eq '*' -and $Text[$i + 1] -eq '/')) { $i++ }; $i += 2; continue }
        if ($c -eq '{' -or $c -eq '[') { $depth++; $i++; continue }
        if ($c -eq '}' -or $c -eq ']') { $depth--; $i++; continue }
        if ($c -eq '"') {
            if ($depth -eq 0 -and ($i + $target.Length -le $close) -and $Text.Substring($i, $target.Length) -eq $target) {
                $j = $i + $target.Length
                while ($j -lt $close -and $Text[$j] -ne ':') { $j++ }
                $j++  # past ':'
                while ($j -lt $close -and [char]::IsWhiteSpace($Text[$j])) { $j++ }
                $end = Get-JsoncValueEnd $Text $j
                return @{ ValueStart = $j; ValueEnd = $end }
            }
            $inStr = $true; $i++; continue
        }
        $i++
    }
    return $null
}

# Is the object/array delimited by ($Open..matching) empty (only ws/comments)?
function Test-JsoncEmpty {
    param([string] $Text, [int] $Open)
    $close = Find-JsoncBracketMatch $Text $Open
    $inner = $Text.Substring($Open + 1, $close - $Open - 1)
    return [string]::IsNullOrWhiteSpace((Remove-JsoncComments $inner))
}

# Indentation (leading whitespace of the line) at byte offset $At.
function Get-JsoncIndent {
    param([string] $Text, [int] $At)
    $ls = $Text.LastIndexOf("`n", [Math]::Min($At, $Text.Length - 1))
    $i = $ls + 1; $sb = ''
    while ($i -lt $Text.Length -and ($Text[$i] -eq ' ' -or $Text[$i] -eq "`t")) { $sb += $Text[$i]; $i++ }
    return $sb
}

# Set (or insert) a depth-1 member of the object at $ObjOpen to $RawValue
# (already-serialized JSON text). Returns the new full text.
function Set-JsoncMember {
    param([string] $Text, [int] $ObjOpen, [string] $Key, [string] $RawValue)
    $m = Find-JsoncMember $Text $ObjOpen $Key
    if ($m) {
        return $Text.Substring(0, $m.ValueStart) + $RawValue + $Text.Substring($m.ValueEnd + 1)
    }
    # insert just after the opening brace, matching sibling indentation
    $indent = (Get-JsoncIndent $Text $ObjOpen) + '    '
    $empty  = Test-JsoncEmpty $Text $ObjOpen
    $sep    = if ($empty) { '' } else { ',' }
    $insert = "`n$indent`"$Key`": $RawValue$sep"
    return $Text.Substring(0, $ObjOpen + 1) + $insert + $Text.Substring($ObjOpen + 1)
}

# Upsert an object into the array at $ArrOpen, replacing any element whose
# "name" equals $Name. $RawValue is the serialized object. Returns new text.
function Set-JsoncArrayItemByName {
    param([string] $Text, [int] $ArrOpen, [string] $Name, [string] $RawValue)
    $close = Find-JsoncBracketMatch $Text $ArrOpen
    # find & remove an existing element with matching "name"
    $i = $ArrOpen + 1; $inStr = $false; $esc = $false
    while ($i -lt $close) {
        $c = $Text[$i]
        $next = if ($i + 1 -lt $close) { $Text[$i + 1] } else { [char]0 }
        if ($inStr) {
            if ($esc) { $esc = $false } elseif ($c -eq '\') { $esc = $true } elseif ($c -eq '"') { $inStr = $false }
            $i++; continue
        }
        if ($c -eq '/' -and $next -eq '/') { while ($i -lt $close -and $Text[$i] -ne "`n") { $i++ }; continue }
        if ($c -eq '/' -and $next -eq '*') { $i += 2; while ($i -lt $close -and -not ($Text[$i] -eq '*' -and $Text[$i + 1] -eq '/')) { $i++ }; $i += 2; continue }
        if ($c -eq '"') { $inStr = $true; $i++; continue }
        if ($c -eq '{') {
            $objEnd = Find-JsoncBracketMatch $Text $i
            $nm = Find-JsoncMember $Text $i 'name'
            if ($nm) {
                $val = $Text.Substring($nm.ValueStart, $nm.ValueEnd - $nm.ValueStart + 1).Trim().Trim('"')
                if ($val -eq $Name) {
                    # remove this element plus one adjacent comma
                    $s = $i; $e = $objEnd
                    $k = $e + 1
                    while ($k -lt $close -and [char]::IsWhiteSpace($Text[$k])) { $k++ }
                    if ($k -lt $close -and $Text[$k] -eq ',') { $e = $k }
                    else {
                        $p = $s - 1
                        while ($p -gt $ArrOpen -and [char]::IsWhiteSpace($Text[$p])) { $p-- }
                        if ($p -gt $ArrOpen -and $Text[$p] -eq ',') { $s = $p }
                    }
                    $Text  = $Text.Substring(0, $s) + $Text.Substring($e + 1)
                    $close = Find-JsoncBracketMatch $Text $ArrOpen
                    break
                }
            }
            $i = $objEnd + 1; continue
        }
        $i++
    }
    # insert the new element right after '['
    $indent = (Get-JsoncIndent $Text $ArrOpen) + '    '
    $empty  = Test-JsoncEmpty $Text $ArrOpen
    $body   = ($RawValue -split "`n") -join "`n$indent"
    $sep    = if ($empty) { '' } else { ',' }
    $insert = "`n$indent$body$sep"
    return $Text.Substring(0, $ArrOpen + 1) + $insert + $Text.Substring($ArrOpen + 1)
}
