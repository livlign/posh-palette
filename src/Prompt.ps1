# Prompt.ps1 - palette-aware oh-my-posh prompt generation.
#
# Most oh-my-posh themes hardcode their own colors, so swapping the prompt while
# keeping a scheme leaves the prompt clashing with everything else. The 'auto'
# prompt sidesteps that: it generates a clean oh-my-posh config whose segment
# colors are pulled straight from the active scheme, so the prompt always matches.

# Build an oh-my-posh config (v2) from a scheme's colors. -Style picks the layout:
#   classic   - path · git · ❯ (plain, no background fills)
#   minimal   - just a colored ❯ that turns red on a non-zero exit
#   powerline - filled powerline segments (needs a nerd font for the separators)
#   robby     - robbyrussell-style: ❯❯ folder git:(branch) time (no glyphs needed)
function New-PoshPaletteOmpConfig {
    param(
        [Parameter(Mandatory)] $Colors,
        [ValidateSet('classic','minimal','powerline','robby')] [string] $Style = 'classic'
    )

    $get = {
        param($name, $fallback)
        $v = $Colors.$name
        if ([string]::IsNullOrWhiteSpace($v)) { $fallback } else { $v }
    }
    $bg     = & $get 'background' '#1A1B26'
    $blue   = & $get 'blue'   '#7AA2F7'
    $green  = & $get 'green'  '#9ECE6A'
    $red    = & $get 'red'    '#F7768E'
    $purple = & $get 'purple' '#BB9AF7'
    $cyan   = & $get 'cyan'   '#7DCFFF'
    $yellow = & $get 'yellow' '#E0AF68'
    $fg     = & $get 'foreground' '#C0CAF5'

    $segments = @(switch ($Style) {
        'robby' {
            @(
                [ordered]@{ type = 'text'; style = 'plain'; foreground = $cyan; template = '❯❯' }
                [ordered]@{ type = 'path'; style = 'plain'; foreground = $blue;
                    properties = [ordered]@{ style = 'folder' }; template = ' {{ .Path }} ' }
                [ordered]@{ type = 'git'; style = 'plain'; foreground = $green;
                    foreground_templates = @("{{ if or (.Working.Changed) (.Staging.Changed) }}$red{{ end }}");
                    properties = [ordered]@{ fetch_status = $true; branch_icon = '' };
                    template = 'git:({{ .HEAD }}) ' }
                [ordered]@{ type = 'time'; style = 'plain'; foreground = $yellow;
                    template = '{{ .CurrentDate | date "15:04" }} ' }
            )
        }
        'minimal' {
            @(
                [ordered]@{ type = 'status'; style = 'plain'; foreground = $purple;
                    foreground_templates = @("{{ if gt .Code 0 }}$red{{ end }}");
                    properties = [ordered]@{ always_enabled = $true }; template = '❯ ' }
            )
        }
        'powerline' {
            @(
                [ordered]@{ type = 'path'; style = 'powerline'; powerline_symbol = "$([char]0xE0B0)";
                    foreground = $bg; background = $blue; properties = [ordered]@{ style = 'folder' };
                    template = ' {{ .Path }} ' }
                [ordered]@{ type = 'git'; style = 'powerline'; powerline_symbol = "$([char]0xE0B0)";
                    foreground = $bg; background = $green;
                    background_templates = @("{{ if or (.Working.Changed) (.Staging.Changed) }}$purple{{ end }}");
                    properties = [ordered]@{ fetch_status = $true };
                    template = " $([char]0xE0A0) {{ .HEAD }} " }
                [ordered]@{ type = 'status'; style = 'powerline'; powerline_symbol = "$([char]0xE0B0)";
                    foreground = $bg; background = $cyan;
                    background_templates = @("{{ if gt .Code 0 }}$red{{ end }}");
                    properties = [ordered]@{ always_enabled = $true };
                    template = ' {{ if gt .Code 0 }}✗{{ else }}✓{{ end }} ' }
            )
        }
        default {  # classic
            @(
                [ordered]@{ type = 'path'; style = 'plain'; foreground = $blue;
                    properties = [ordered]@{ style = 'folder' }; template = ' {{ .Path }} ' }
                [ordered]@{ type = 'git'; style = 'plain'; foreground = $green;
                    properties = [ordered]@{ fetch_status = $true };
                    template = '{{ .HEAD }}{{ if or (.Working.Changed) (.Staging.Changed) }}*{{ end }} ' }
                [ordered]@{ type = 'status'; style = 'plain'; foreground = $purple;
                    foreground_templates = @("{{ if gt .Code 0 }}$red{{ end }}");
                    properties = [ordered]@{ always_enabled = $true }; template = '❯ ' }
            )
        }
    })

    [ordered]@{
        '$schema'   = 'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json'
        version     = 2
        final_space = $true
        blocks      = @(
            [ordered]@{ type = 'prompt'; alignment = 'left'; segments = $segments }
        )
    }
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
