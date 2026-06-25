# Prompt.ps1 - palette-aware oh-my-posh prompt generation.
#
# Most oh-my-posh themes hardcode their own colors, so swapping the prompt while
# keeping a scheme leaves the prompt clashing with everything else. The 'auto'
# prompt sidesteps that: it generates a clean oh-my-posh config whose segment
# colors are pulled straight from the active scheme, so the prompt always matches.

# Build an oh-my-posh config (v4) from a scheme's colors. -Style picks the layout.
# Simple house styles (classic/minimal/powerline/robby/twoline/arrow/lambda/pure/
# spaceship/atomic/smoothie) are hand-built. The four named after real oh-my-posh
# community themes - 1_shell, cert, clean-detailed, velvet - are faithful 1:1 ports
# of those themes (same blocks, segments, glyphs, templates and options); only the
# hardcoded colors are swapped for the active scheme so the prompt always matches.
function New-PoshPaletteOmpConfig {
    param(
        [Parameter(Mandatory)] $Colors,
        [ValidateSet('classic','minimal','powerline','robby','twoline','arrow','lambda','pure','spaceship','atomic','smoothie','1_shell','cert','clean-detailed','velvet','avit','darkblood','tokyonight','dracula')] [string] $Style = 'classic',
        # Optional fixed segment-fill ramp for the 'dracula' style (a designed
        # gradient). When absent, that style falls back to scheme accent colors.
        [string[]] $Gradient
    )

    $get = {
        param($name, $fallback)
        $v = $Colors.$name
        if ([string]::IsNullOrWhiteSpace($v)) { $fallback } else { $v }
    }
    $bg     = & $get 'background' '#1A1B26'
    $black  = & $get 'black'  '#15161E'
    $blue   = & $get 'blue'   '#7AA2F7'
    $green  = & $get 'green'  '#9ECE6A'
    $red    = & $get 'red'    '#F7768E'
    $purple = & $get 'purple' '#BB9AF7'
    $cyan   = & $get 'cyan'   '#7DCFFF'
    $yellow = & $get 'yellow' '#E0AF68'
    $fg     = & $get 'foreground' '#C0CAF5'
    $chg    = "{{ if or (.Working.Changed) (.Staging.Changed) }}$red{{ end }}"
    # The detailed git template shared by the ported themes (branch, upstream, ahead/
    # behind, working/staging counts, stash) - byte-for-byte the upstream template.
    $gitFull = "{{ .UpstreamIcon }}{{ .HEAD }}{{if .BranchStatus }} {{ .BranchStatus }}{{ end }}{{ if .Working.Changed }} $([char]0xF044) {{ .Working.String }}{{ end }}{{ if and (.Working.Changed) (.Staging.Changed) }} |{{ end }}{{ if .Staging.Changed }} $([char]0xF046) {{ .Staging.String }}{{ end }}{{ if gt .StashCount 0 }} $([char]0xEB4B) {{ .StashCount }}{{ end }}"

    # Reusable plain segments (scheme-colored).
    $pathSeg = { param($fg, $tpl) [ordered]@{ type = 'path'; style = 'plain'; foreground = $fg; properties = [ordered]@{ style = 'folder' }; template = $tpl } }
    $gitSeg  = { param($fg, $tpl) [ordered]@{ type = 'git'; style = 'plain'; foreground = $fg; foreground_templates = @($chg); properties = [ordered]@{ fetch_status = $true; branch_icon = '' }; template = $tpl } }
    $timeSeg = { param($fg) [ordered]@{ type = 'time'; style = 'plain'; foreground = $fg; template = '{{ .CurrentDate | date "15:04" }} ' } }
    $statSeg = { param($fg, $tpl) [ordered]@{ type = 'status'; style = 'plain'; foreground = $fg; foreground_templates = @("{{ if gt .Code 0 }}$red{{ end }}"); properties = [ordered]@{ always_enabled = $true }; template = $tpl } }
    $textSeg = { param($fg, $tpl) [ordered]@{ type = 'text'; style = 'plain'; foreground = $fg; template = $tpl } }
    $line    = { param($segs, [bool]$nl = $false) $b = [ordered]@{ type = 'prompt'; alignment = 'left'; segments = @($segs) }; if ($nl) { $b['newline'] = $true }; $b }

    $blocks = @(switch ($Style) {
        'robby' {
            & $line @(
                (& $textSeg $cyan '❯❯')
                (& $pathSeg $blue ' {{ .Path }} ')
                (& $gitSeg  $green 'git:({{ .HEAD }}) ')
                (& $timeSeg $yellow)
            )
        }
        'minimal' { & $line @((& $statSeg $purple '❯ ')) }
        'powerline' {
            & $line @(
                [ordered]@{ type = 'path'; style = 'powerline'; powerline_symbol = "$([char]0xE0B0)"; foreground = $bg; background = $blue; properties = [ordered]@{ style = 'folder' }; template = ' {{ .Path }} ' }
                [ordered]@{ type = 'git'; style = 'powerline'; powerline_symbol = "$([char]0xE0B0)"; foreground = $bg; background = $green; background_templates = @("{{ if or (.Working.Changed) (.Staging.Changed) }}$purple{{ end }}"); properties = [ordered]@{ fetch_status = $true; branch_icon = '' }; template = " $([char]0xE0A0) {{ .HEAD }} " }
                [ordered]@{ type = 'status'; style = 'powerline'; powerline_symbol = "$([char]0xE0B0)"; foreground = $bg; background = $cyan; background_templates = @("{{ if gt .Code 0 }}$red{{ end }}"); properties = [ordered]@{ always_enabled = $true }; template = ' {{ if gt .Code 0 }}✗{{ else }}✓{{ end }} ' }
            )
        }
        'twoline' {
            (& $line @(
                (& $textSeg $cyan '╭─ ')
                (& $pathSeg $blue '{{ .Path }} ')
                (& $gitSeg  $green '● {{ .HEAD }} ')
                (& $timeSeg $yellow)
            ))
            (& $line @(
                (& $textSeg $cyan '╰─')
                (& $statSeg $purple '❯ ')
            ) $true)
        }
        'arrow' {
            & $line @(
                (& $pathSeg $blue '{{ .Path }} ')
                (& $textSeg $cyan 'on ')
                (& $gitSeg  $green '● {{ .HEAD }} ')
                (& $timeSeg $yellow)
                (& $statSeg $purple '❯ ')
            )
        }
        'lambda' {
            & $line @(
                (& $textSeg $purple 'λ ')
                (& $pathSeg $blue '{{ .Path }} ')
                (& $textSeg $green '→ ')
            )
        }
        'spaceship' {
            # spaceship-prompt inspired: path · "on" · branch · time · ➜
            & $line @(
                (& $pathSeg $blue '{{ .Path }} ')
                (& $textSeg $cyan 'on ')
                (& $gitSeg  $purple "$([char]0x2387) {{ .HEAD }} ")
                (& $timeSeg $yellow)
                (& $statSeg $green "$([char]0x279C) ")
            )
        }
        'atomic' {
            # a leading bolt, then filled powerline segments
            & $line @(
                (& $textSeg $purple "$([char]0x26A1) ")
                [ordered]@{ type = 'path'; style = 'powerline'; powerline_symbol = "$([char]0xE0B0)"; foreground = $bg; background = $blue; properties = [ordered]@{ style = 'folder' }; template = ' {{ .Path }} ' }
                [ordered]@{ type = 'git'; style = 'powerline'; powerline_symbol = "$([char]0xE0B0)"; foreground = $bg; background = $green; background_templates = @("{{ if or (.Working.Changed) (.Staging.Changed) }}$red{{ end }}"); properties = [ordered]@{ fetch_status = $true; branch_icon = '' }; template = " $([char]0xE0A0) {{ .HEAD }} " }
                (& $statSeg $purple "$([char]0x276F) ")
            )
        }
        'smoothie' {
            # soft rounded powerline segments (rounded cap separator)
            & $line @(
                [ordered]@{ type = 'path'; style = 'powerline'; powerline_symbol = "$([char]0xE0B4)"; foreground = $bg; background = $purple; properties = [ordered]@{ style = 'folder' }; template = ' {{ .Path }} ' }
                [ordered]@{ type = 'git'; style = 'powerline'; powerline_symbol = "$([char]0xE0B4)"; foreground = $bg; background = $cyan; background_templates = @("{{ if or (.Working.Changed) (.Staging.Changed) }}$yellow{{ end }}"); properties = [ordered]@{ fetch_status = $true }; template = " {{ .HEAD }} " }
                (& $statSeg $purple "$([char]0x276F) ")
            )
        }
        'avit' {
            # Port of oh-my-posh's avit: path + branch, then a colored arrow line.
            (& $line @(
                (& $pathSeg $fg '{{ .Path }} ')
                (& $gitSeg  $yellow '{{ .HEAD }} ')
                (& $statSeg $red '{{ if gt .Code 0 }}x{{ reason .Code }} {{ end }}')
            ))
            (& $line @((& $textSeg $blue "$([char]0x279C) ")) $true)   # arrow
        }
        'darkblood' {
            # Port of oh-my-posh's darkblood: box-drawing frame, accent brackets.
            (& $line @(
                [ordered]@{ type = 'session'; style = 'plain'; foreground = $fg; template = "<$red>$([char]0x250F)[</>{{ .UserName }}<$red>]</>" }
                [ordered]@{ type = 'git'; style = 'plain'; foreground = $fg; properties = [ordered]@{ fetch_status = $true; branch_icon = '' }; template = " <$red>[</>{{ .HEAD }}<$red>]</>" }
                [ordered]@{ type = 'status'; style = 'plain'; foreground = $fg; properties = [ordered]@{ always_enabled = $true }; template = "{{ if gt .Code 0 }} <$red>[</>x{{ reason .Code }}<$red>]</>{{ end }}" }
            ))
            (& $line @(
                [ordered]@{ type = 'path'; style = 'plain'; foreground = $fg; properties = [ordered]@{ style = 'folder' }; template = "<$red>$([char]0x2517)[</>{{ .Path }}<$red>]></> " }
            ) $true)
        }
        'tokyonight' {
            # Port of oh-my-posh's tokyonight_storm: arrow + path + branch, language
            # versions on the right, a triangle prompt on the next line.
            (& $line @(
                (& $textSeg $blue "$([char]0x279C) ")                 # ➜
                (& $pathSeg $purple '{{ .Path }} ')
                (& $textSeg $cyan "$([char]0x26A1) ")                 # ⚡
                (& $gitSeg  $cyan '({{ .HEAD }})')
                (& $statSeg $red "{{ if gt .Code 0 }} $([char]0x2717){{ end }}")  # ✗
            ))
            [ordered]@{ type = 'rprompt'; alignment = 'right'; segments = @(
                [ordered]@{ type = 'node'; style = 'plain'; foreground = $green; properties = [ordered]@{ fetch_version = $true }; template = "$([char]0xE718) {{ .Full }} " }
                [ordered]@{ type = 'go'; style = 'plain'; foreground = $cyan; properties = [ordered]@{ fetch_version = $true }; template = "$([char]0xE626) {{ .Full }} " }
                [ordered]@{ type = 'python'; style = 'plain'; foreground = $yellow; properties = [ordered]@{ fetch_version = $true }; template = "$([char]0xE235) {{ .Full }}" }
            ) }
            (& $line @((& $textSeg $green "$([char]0x25B6) ")) $true)  # ▶
        }
        'dracula' {
            # Port of oh-my-posh's dracula: a powerline chain with an aws cap. Segment
            # fills come from -Gradient (a designed ramp) when given, else scheme accents.
            $grad = if ($Gradient -and $Gradient.Count -ge 5) { $Gradient } else { @($blue, $purple, $red, $cyan, $yellow) }
            $pl = "$([char]0xE0B0)"
            (& $line @(
                [ordered]@{ type = 'session'; style = 'diamond'; leading_diamond = "$([char]0xE0B6)"; foreground = $black; background = $grad[0]; template = '{{ .UserName }} ' }
                [ordered]@{ type = 'path'; style = 'powerline'; powerline_symbol = $pl; foreground = $black; background = $grad[1]; properties = [ordered]@{ style = 'folder' }; template = ' {{ .Path }} ' }
                [ordered]@{ type = 'git'; style = 'powerline'; powerline_symbol = $pl; foreground = $black; background = $grad[2]; properties = [ordered]@{ fetch_status = $true; branch_icon = "$([char]0xE725) " }; template = ' {{ .HEAD }} ' }
                [ordered]@{ type = 'node'; style = 'powerline'; powerline_symbol = $pl; foreground = $black; background = $grad[3]; properties = [ordered]@{ fetch_version = $true }; template = " $([char]0xE718) {{ .Full }} " }
                [ordered]@{ type = 'time'; style = 'diamond'; trailing_diamond = "$pl"; foreground = $black; background = $grad[4]; properties = [ordered]@{ time_format = '15:04' }; template = " $([char]0x2665) {{ .CurrentDate | date .Format }} " }
            ))
            [ordered]@{ type = 'rprompt'; alignment = 'right'; segments = @(
                [ordered]@{ type = 'aws'; style = 'diamond'; leading_diamond = "$([char]0xE0B6)"; trailing_diamond = "$([char]0xE0B4)"; foreground = $black; background = $grad[4]; template = " $([char]0xE7AD) {{ .Profile }}{{ if .Region }}@{{ .Region }}{{ end }} " }
            ) }
        }
        '1_shell' {
            # Faithful port of oh-my-posh's 1_shell theme (colored text, no fills).
            [ordered]@{ type = 'prompt'; alignment = 'left'; newline = $true; segments = @(
                [ordered]@{ type = 'session'; style = 'diamond'; foreground = $red; leading_diamond = "<$purple> $([char]0xE200) </>"; template = "{{ .UserName }} <$fg>on</>" }
                [ordered]@{ type = 'time'; style = 'diamond'; foreground = $purple; properties = [ordered]@{ time_format = "Monday <$fg>at</> 3:04 PM" }; template = ' {{ .CurrentDate | date .Format }} ' }
                [ordered]@{ type = 'git'; style = 'diamond'; foreground = $cyan; properties = [ordered]@{ branch_icon = "$([char]0xE725) "; fetch_status = $true; fetch_upstream_icon = $true }; template = " $gitFull " }
            ) }
            [ordered]@{ type = 'prompt'; alignment = 'right'; segments = @(
                [ordered]@{ type = 'text'; style = 'plain'; foreground = $green }
                [ordered]@{ type = 'executiontime'; style = 'diamond'; foreground = $green; properties = [ordered]@{ style = 'dallas'; threshold = 0 }; template = " {{ .FormattedMs }}s <$fg>$([char]0xE601)</>" }
                [ordered]@{ type = 'root'; style = 'diamond'; properties = [ordered]@{ root_icon = "$([char]0xF292) " }; template = " $([char]0xF0E7) " }
                [ordered]@{ type = 'sysinfo'; style = 'diamond'; foreground = $green; template = " <$fg>MEM:</> {{ round .PhysicalPercentUsed .Precision }}% ({{ (div ((sub .PhysicalTotalMemory .PhysicalAvailableMemory)|float64) 1073741824.0) }}/{{ (div .PhysicalTotalMemory 1073741824.0) }}GB)" }
            ) }
            [ordered]@{ type = 'prompt'; alignment = 'left'; newline = $true; segments = @(
                [ordered]@{ type = 'path'; style = 'diamond'; foreground = $cyan; leading_diamond = "<$blue> $([char]0xE285) </><$cyan>{</>"; trailing_diamond = "<$cyan>}</>"; properties = [ordered]@{ folder_icon = "$([char]0xF07B)"; folder_separator_icon = " $([char]0xEBCB) "; home_icon = 'home'; style = 'agnoster_full' }; template = " $([char]0xE5FF) {{ .Path }} " }
                [ordered]@{ type = 'status'; style = 'plain'; foreground = $green; foreground_templates = @("{{ if gt .Code 0 }}$red{{ end }}"); properties = [ordered]@{ always_enabled = $true }; template = " $([char]0xE286) " }
            ) }
        }
        'cert' {
            # Faithful port of oh-my-posh's cert theme: one connected diamond chain.
            [ordered]@{ type = 'prompt'; alignment = 'left'; segments = @(
                [ordered]@{ type = 'session'; style = 'diamond'; foreground = $bg; background = $red; leading_diamond = "$([char]0xE0B6)"; trailing_diamond = "$([char]0xE0C6)"; template = '{{ .UserName }} ' }
                [ordered]@{ type = 'path'; style = 'diamond'; foreground = $bg; background = $green; leading_diamond = "$([char]0xE0C7)"; trailing_diamond = "$([char]0xE0C6)"; properties = [ordered]@{ style = 'folder' }; template = ' {{ .Path }} ' }
                [ordered]@{ type = 'git'; style = 'diamond'; foreground = $bg; background = $cyan; leading_diamond = "$([char]0xE0C7)"; trailing_diamond = "$([char]0xE0C6)"; properties = [ordered]@{ branch_icon = '' }; template = ' git({{ .HEAD }}) ' }
                [ordered]@{ type = 'time'; style = 'diamond'; foreground = $bg; background = $purple; leading_diamond = "$([char]0xE0C7)"; trailing_diamond = "$([char]0xE0C6)"; properties = [ordered]@{ time_format = '15:04' }; template = ' {{ .CurrentDate | date .Format }} ' }
            ) }
        }
        'clean-detailed' {
            # Faithful port of oh-my-posh's clean-detailed theme.
            [ordered]@{ type = 'prompt'; alignment = 'left'; newline = $true; segments = @(
                [ordered]@{ type = 'os'; style = 'diamond'; foreground = $bg; background = $fg; leading_diamond = "$([char]0xE0B2)"; trailing_diamond = "<transparent,$fg>$([char]0xE0B2)</>"; properties = [ordered]@{ macos = "$([char]0xF179) "; ubuntu = "$([char]0xF31B) "; windows = "$([char]0xE62A) " }; template = " {{ if .WSL }}WSL at {{ end }}{{.Icon}}" }
                [ordered]@{ type = 'shell'; style = 'diamond'; foreground = $bg; background = $fg; leading_diamond = "$([char]0xE0B2)"; trailing_diamond = "<transparent,$fg>$([char]0xE0B2)</>"; template = "$([char]0xF489) {{ .Name }}" }
                [ordered]@{ type = 'sysinfo'; style = 'diamond'; foreground = $bg; background = $blue; leading_diamond = "$([char]0xE0B2)"; trailing_diamond = "<transparent,$blue>$([char]0xE0B2)</>"; template = "$([char]0xE266) MEM: {{ round .PhysicalPercentUsed .Precision }}% | {{ (div ((sub .PhysicalTotalMemory .PhysicalAvailableMemory)|float64) 1073741824.0) }}/{{ (div .PhysicalTotalMemory 1073741824.0) }}GB $([char]0xE266) " }
                [ordered]@{ type = 'executiontime'; style = 'diamond'; foreground = $bg; background = $purple; leading_diamond = "$([char]0xE0B2)"; trailing_diamond = "$([char]0xE0B0)"; properties = [ordered]@{ style = 'roundrock'; threshold = 0 }; template = ' {{ .FormattedMs }} ' }
            ) }
            [ordered]@{ type = 'prompt'; alignment = 'right'; segments = @(
                [ordered]@{ type = 'git'; style = 'diamond'; foreground = $bg; background = $green; leading_diamond = "$([char]0xE0B2)"; trailing_diamond = "$([char]0xE0B0)"; properties = [ordered]@{ branch_icon = "$([char]0xE725) "; fetch_status = $true; fetch_upstream_icon = $true }; template = " $gitFull " }
            ) }
            [ordered]@{ type = 'prompt'; alignment = 'left'; newline = $true; segments = @(
                [ordered]@{ type = 'text'; style = 'plain'; foreground = $cyan; template = "$([char]0x256D)$([char]0x2500)" }
                [ordered]@{ type = 'time'; style = 'plain'; foreground = $yellow; properties = [ordered]@{ time_format = '15:04' }; template = " $([char]0x2665) {{ .CurrentDate | date .Format }} |" }
                [ordered]@{ type = 'root'; style = 'plain'; foreground = $red; template = " $([char]0xF292) " }
                [ordered]@{ type = 'path'; style = 'plain'; foreground = $blue; properties = [ordered]@{ folder_icon = "$([char]0xF07B) "; folder_separator_icon = " $([char]0xF061) "; home_icon = "$([char]0xEB06) " }; template = ' {{ .Path }} ' }
            ) }
            [ordered]@{ type = 'prompt'; alignment = 'left'; newline = $true; segments = @(
                [ordered]@{ type = 'status'; style = 'plain'; foreground = $purple; foreground_templates = @("{{ if gt .Code 0 }}$red{{ end }}"); properties = [ordered]@{ always_enabled = $true }; template = "$([char]0x2570)$([char]0x2500) " }
            ) }
        }
        'velvet' {
            # Faithful port of oh-my-posh's velvet theme.
            [ordered]@{ type = 'prompt'; alignment = 'left'; segments = @(
                [ordered]@{ type = 'os'; style = 'diamond'; foreground = $bg; background = $purple; properties = [ordered]@{ macos = "$([char]0xF179)"; windows = "$([char]0xF17A)"; linux = "$([char]0xF17C)"; ubuntu = "$([char]0xF31B)"; arch = "$([char]0xF303)"; debian = "$([char]0xF306)"; fedora = "$([char]0xF30A)"; manjaro = "$([char]0xF312)"; opensuse = "$([char]0xF314)" }; template = ' {{ if .WSL }}WSL at {{ end }}{{.Icon}} ' }
                [ordered]@{ type = 'path'; style = 'powerline'; powerline_symbol = "$([char]0xE0B4)"; foreground = $bg; background = $blue; properties = [ordered]@{ style = 'agnoster_short'; max_depth = 3; folder_icon = '...'; folder_separator_icon = '/'; home_icon = '~' }; template = ' {{ .Path }} ' }
                [ordered]@{ type = 'git'; style = 'powerline'; powerline_symbol = "$([char]0xE0B4)"; foreground = $bg; background = $cyan; properties = [ordered]@{ fetch_status = $true; fetch_upstream_icon = $true; branch_template = '{{ trunc 25 .Branch }}' }; template = " $gitFull " }
                [ordered]@{ type = 'executiontime'; style = 'powerline'; powerline_symbol = "$([char]0xE0B4)"; foreground = $bg; background = $yellow; properties = [ordered]@{ always_enabled = $true }; template = ' {{ .FormattedMs }} ' }
                [ordered]@{ type = 'status'; style = 'diamond'; trailing_diamond = "$([char]0xE0B4)"; foreground = $bg; background = $green; foreground_templates = @("{{ if gt .Code 0 }}$red{{ end }}"); properties = [ordered]@{ always_enabled = $true }; template = " $([char]0xF08A){{ if gt .Code 0 }} {{.Code}}{{ end }} " }
            ) }
            [ordered]@{ type = 'rprompt'; alignment = 'right'; segments = @(
                [ordered]@{ type = 'python'; style = 'diamond'; foreground = $yellow; background = $purple; leading_diamond = " $([char]0xE0B6)"; trailing_diamond = "$([char]0xE0B4)"; properties = [ordered]@{ fetch_version = $false }; template = "$([char]0xE235){{ if .Error }}{{ .Error }}{{ else }}{{ if .Venv }}{{ .Venv }} {{ end }}{{ .Full }}{{ end }}" }
                [ordered]@{ type = 'go'; style = 'diamond'; foreground = $cyan; background = $purple; leading_diamond = " $([char]0xE0B6)"; trailing_diamond = "$([char]0xE0B4)"; properties = [ordered]@{ fetch_version = $false }; template = "$([char]0xE626){{ if .Error }}{{ .Error }}{{ else }}{{ .Full }}{{ end }}" }
                [ordered]@{ type = 'node'; style = 'diamond'; foreground = $green; background = $purple; leading_diamond = " $([char]0xE0B6)"; trailing_diamond = "$([char]0xE0B4)"; properties = [ordered]@{ fetch_version = $false }; template = "$([char]0xE718){{ if .PackageManagerIcon }}{{ .PackageManagerIcon }} {{ end }}{{ .Full }}" }
                [ordered]@{ type = 'ruby'; style = 'diamond'; foreground = $red; background = $purple; leading_diamond = " $([char]0xE0B6)"; trailing_diamond = "$([char]0xE0B4)"; properties = [ordered]@{ fetch_version = $false }; template = "$([char]0xE791){{ if .Error }}{{ .Error }}{{ else }}{{ .Full }}{{ end }}" }
                [ordered]@{ type = 'java'; style = 'diamond'; foreground = $red; background = $purple; leading_diamond = " $([char]0xE0B6)"; trailing_diamond = "$([char]0xE0B4)"; properties = [ordered]@{ fetch_version = $false }; template = "$([char]0xE738){{ if .Error }}{{ .Error }}{{ else }}{{ .Full }}{{ end }}" }
            ) }
            [ordered]@{ type = 'prompt'; alignment = 'left'; newline = $true; segments = @(
                [ordered]@{ type = 'time'; style = 'diamond'; foreground = $bg; background = $purple; trailing_diamond = "$([char]0xE0B4)"; properties = [ordered]@{ time_format = '15:04:05' }; template = ' {{ .CurrentDate | date .Format }} ' }
            ) }
        }
        'pure' {
            (& $line @((& $pathSeg $blue '{{ .Path }}')))
            (& $line @((& $statSeg $purple '❯ ')) $true)
        }
        default {  # classic
            & $line @(
                (& $pathSeg $blue ' {{ .Path }} ')
                [ordered]@{ type = 'git'; style = 'plain'; foreground = $green; properties = [ordered]@{ fetch_status = $true }; template = '{{ .HEAD }}{{ if or (.Working.Changed) (.Staging.Changed) }}*{{ end }} ' }
                (& $statSeg $purple '❯ ')
            )
        }
    })

    $config = [ordered]@{
        '$schema'   = 'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json'
        version     = 4
        final_space = $true
        blocks      = @($blocks)
    }

    # Top-level extras carried by the ported themes (console title + transient prompt).
    switch ($Style) {
        '1_shell' {
            $config['console_title_template'] = '{{ .Folder }}'
            $config['transient_prompt'] = [ordered]@{ background = 'transparent'; foreground = $fg; template = "$([char]0xE285) " }
        }
        'clean-detailed' {
            $config['console_title_template'] = '{{ .Folder }}'
            $config['transient_prompt'] = [ordered]@{ background = 'transparent'; foreground = $fg; template = "$([char]0xE285) " }
        }
        'velvet' { $config['console_title_template'] = '{{ .Shell }} - {{ .Folder }}' }
    }
    $config
}

# Write a generated config to the PoshPalette-managed prompt dir; return its path.
function Save-PoshPalettePrompt {
    param([Parameter(Mandatory)] $Config, [string] $Name = 'auto')
    $dir = Join-Path $HOME '.poshpalette/prompts'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $path = Join-Path $dir "$Name.omp.json"
    Set-Content -Path $path -Value ($Config | ConvertTo-Json -Depth 32) -Encoding utf8
    $path
}
