"""Palette-aware oh-my-posh prompt generation - a 1:1 port of src/Prompt.ps1.

Each style builds the same blocks/segments/templates as New-PoshPaletteOmpConfig
with the scheme's colors swapped in, so a prompt looks identical whether it was
applied from pwsh or from bash/zsh/fish. tests/test_prompt_parity.py diffs the
two generators whenever pwsh is on PATH.
"""

import json

STYLES = ("classic", "minimal", "powerline", "robby", "twoline", "arrow", "lambda", "pure",
          "spaceship", "atomic", "smoothie", "1_shell", "cert", "clean-detailed", "velvet",
          "avit", "darkblood", "tokyonight", "dracula", "bong")

SCHEMA = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json"


def new_omp_config(colors, style="classic", gradient=None):
    if style not in STYLES:
        raise ValueError(f"Unknown prompt style '{style}'. Known: {', '.join(STYLES)}")

    def get(name, fallback):
        v = colors.get(name)
        return fallback if v is None or not str(v).strip() else v

    bg = get("background", "#1A1B26")
    black = get("black", "#15161E")
    blue = get("blue", "#7AA2F7")
    green = get("green", "#9ECE6A")
    red = get("red", "#F7768E")
    purple = get("purple", "#BB9AF7")
    cyan = get("cyan", "#7DCFFF")
    yellow = get("yellow", "#E0AF68")
    fg = get("foreground", "#C0CAF5")
    chg = f"{{{{ if or (.Working.Changed) (.Staging.Changed) }}}}{red}{{{{ end }}}}"
    git_full = ("{{ .UpstreamIcon }}{{ .HEAD }}{{if .BranchStatus }} {{ .BranchStatus }}{{ end }}"
                "{{ if .Working.Changed }}  {{ .Working.String }}{{ end }}"
                "{{ if and (.Working.Changed) (.Staging.Changed) }} |{{ end }}"
                "{{ if .Staging.Changed }}  {{ .Staging.String }}{{ end }}"
                "{{ if gt .StashCount 0 }}  {{ .StashCount }}{{ end }}")

    def path_seg(f, tpl):
        return {"type": "path", "style": "plain", "foreground": f, "properties": {"style": "folder"}, "template": tpl}

    def git_seg(f, tpl):
        return {"type": "git", "style": "plain", "foreground": f, "foreground_templates": [chg],
                "properties": {"fetch_status": True, "branch_icon": ""}, "template": tpl}

    def time_seg(f):
        return {"type": "time", "style": "plain", "foreground": f, "template": '{{ .CurrentDate | date "15:04" }} '}

    def stat_seg(f, tpl):
        return {"type": "status", "style": "plain", "foreground": f,
                "foreground_templates": [f"{{{{ if gt .Code 0 }}}}{red}{{{{ end }}}}"],
                "properties": {"always_enabled": True}, "template": tpl}

    def text_seg(f, tpl):
        return {"type": "text", "style": "plain", "foreground": f, "template": tpl}

    def line(segs, nl=False):
        b = {"type": "prompt", "alignment": "left", "segments": list(segs)}
        if nl:
            b["newline"] = True
        return b

    def pl_seg(type_, sym, bg_, tpl, props=None, bg_tpl=None):
        s = {"type": type_, "style": "powerline", "powerline_symbol": sym, "foreground": bg, "background": bg_}
        if bg_tpl:
            s["background_templates"] = [bg_tpl]
        if props is not None:
            s["properties"] = props
        s["template"] = tpl
        return s

    PL, ROUND = "", ""

    if style == "robby":
        blocks = [line([text_seg(cyan, "❯❯"), path_seg(blue, " {{ .Path }} "),
                        git_seg(green, "git:({{ .HEAD }}) "), time_seg(yellow)])]
    elif style == "minimal":
        blocks = [line([stat_seg(purple, "❯ ")])]
    elif style == "powerline":
        blocks = [line([
            pl_seg("path", PL, blue, " {{ .Path }} ", {"style": "folder"}),
            pl_seg("git", PL, green, "  {{ .HEAD }} ", {"fetch_status": True, "branch_icon": ""},
                   f"{{{{ if or (.Working.Changed) (.Staging.Changed) }}}}{purple}{{{{ end }}}}"),
            pl_seg("status", PL, cyan, " {{ if gt .Code 0 }}✗{{ else }}✓{{ end }} ", {"always_enabled": True},
                   f"{{{{ if gt .Code 0 }}}}{red}{{{{ end }}}}"),
        ])]
    elif style == "twoline":
        blocks = [
            line([text_seg(cyan, "╭─ "), path_seg(blue, "{{ .Path }} "), git_seg(green, "● {{ .HEAD }} "), time_seg(yellow)]),
            line([text_seg(cyan, "╰─"), stat_seg(purple, "❯ ")], True),
        ]
    elif style == "arrow":
        blocks = [line([path_seg(blue, "{{ .Path }} "), text_seg(cyan, "on "), git_seg(green, "● {{ .HEAD }} "),
                        time_seg(yellow), stat_seg(purple, "❯ ")])]
    elif style == "lambda":
        blocks = [line([text_seg(purple, "λ "), path_seg(blue, "{{ .Path }} "), text_seg(green, "→ ")])]
    elif style == "spaceship":
        blocks = [line([path_seg(blue, "{{ .Path }} "), text_seg(cyan, "on "), git_seg(purple, "⎇ {{ .HEAD }} "),
                        time_seg(yellow), stat_seg(green, "➜ ")])]
    elif style == "atomic":
        blocks = [line([
            text_seg(purple, "⚡ "),
            pl_seg("path", PL, blue, " {{ .Path }} ", {"style": "folder"}),
            pl_seg("git", PL, green, "  {{ .HEAD }} ", {"fetch_status": True, "branch_icon": ""},
                   f"{{{{ if or (.Working.Changed) (.Staging.Changed) }}}}{red}{{{{ end }}}}"),
            stat_seg(purple, "❯ "),
        ])]
    elif style == "smoothie":
        blocks = [line([
            {"type": "path", "style": "powerline", "powerline_symbol": ROUND, "foreground": bg, "background": purple,
             "properties": {"style": "folder"}, "template": " {{ .Path }} "},
            {"type": "git", "style": "powerline", "powerline_symbol": ROUND, "foreground": bg, "background": cyan,
             "background_templates": [f"{{{{ if or (.Working.Changed) (.Staging.Changed) }}}}{yellow}{{{{ end }}}}"],
             "properties": {"fetch_status": True}, "template": " {{ .HEAD }} "},
            stat_seg(purple, "❯ "),
        ])]
    elif style == "avit":
        blocks = [
            line([path_seg(fg, "{{ .Path }} "), git_seg(yellow, "{{ .HEAD }} "),
                  stat_seg(red, "{{ if gt .Code 0 }}x{{ reason .Code }} {{ end }}")]),
            line([text_seg(blue, "➜ ")], True),
        ]
    elif style == "darkblood":
        blocks = [
            line([
                {"type": "session", "style": "plain", "foreground": fg, "template": f"<{red}>┏[</>{{{{ .UserName }}}}<{red}>]</>"},
                {"type": "git", "style": "plain", "foreground": fg, "properties": {"fetch_status": False, "branch_icon": ""},
                 "template": f" <{red}>[</>{{{{ .HEAD }}}}<{red}>]</>"},
                {"type": "status", "style": "plain", "foreground": fg, "properties": {"always_enabled": True},
                 "template": f"{{{{ if gt .Code 0 }}}} <{red}>[</>x{{{{ reason .Code }}}}<{red}>]</>{{{{ end }}}}"},
            ]),
            line([{"type": "path", "style": "plain", "foreground": fg, "properties": {"style": "folder"},
                   "template": f"<{red}>┗[</>{{{{ .Path }}}}<{red}>]></> "}], True),
        ]
    elif style == "tokyonight":
        blocks = [
            line([text_seg(blue, "➜ "), path_seg(purple, "{{ .Path }} "), text_seg(cyan, "⚡ "),
                  git_seg(cyan, "({{ .HEAD }})"), stat_seg(red, "{{ if gt .Code 0 }} ✗{{ end }}")]),
            {"type": "rprompt", "alignment": "right", "segments": [
                {"type": "node", "style": "plain", "foreground": green, "properties": {"fetch_version": True}, "template": " {{ .Full }} "},
                {"type": "go", "style": "plain", "foreground": cyan, "properties": {"fetch_version": True}, "template": " {{ .Full }} "},
                {"type": "python", "style": "plain", "foreground": yellow, "properties": {"fetch_version": True}, "template": " {{ .Full }}"},
            ]},
            line([text_seg(green, "▶ ")], True),
        ]
    elif style == "dracula":
        grad = list(gradient) if gradient and len(gradient) >= 5 else [blue, purple, red, cyan, yellow]
        blocks = [
            line([
                {"type": "session", "style": "diamond", "leading_diamond": "", "foreground": black, "background": grad[0], "template": "{{ .UserName }} "},
                {"type": "path", "style": "powerline", "powerline_symbol": PL, "foreground": black, "background": grad[1],
                 "properties": {"style": "folder"}, "template": " {{ .Path }} "},
                {"type": "git", "style": "powerline", "powerline_symbol": PL, "foreground": black, "background": grad[2],
                 "properties": {"fetch_status": False, "branch_icon": " "}, "template": " {{ .HEAD }} "},
                {"type": "node", "style": "powerline", "powerline_symbol": PL, "foreground": black, "background": grad[3],
                 "properties": {"fetch_version": True}, "template": "  {{ .Full }} "},
                {"type": "time", "style": "diamond", "trailing_diamond": PL, "foreground": black, "background": grad[4],
                 "properties": {"time_format": "15:04"}, "template": " ♥ {{ .CurrentDate | date .Format }} "},
            ]),
            {"type": "rprompt", "alignment": "right", "segments": [
                {"type": "aws", "style": "diamond", "leading_diamond": "", "trailing_diamond": "", "foreground": black,
                 "background": grad[4], "template": "  {{ .Profile }}{{ if .Region }}@{{ .Region }}{{ end }} "},
            ]},
        ]
    elif style == "1_shell":
        blocks = [
            {"type": "prompt", "alignment": "left", "newline": True, "segments": [
                {"type": "session", "style": "diamond", "foreground": red, "leading_diamond": f"<{purple}>  </>",
                 "template": f"{{{{ .UserName }}}} <{fg}>on</>"},
                {"type": "time", "style": "diamond", "foreground": purple,
                 "properties": {"time_format": f"Monday <{fg}>at</> 3:04 PM"}, "template": " {{ .CurrentDate | date .Format }} "},
                {"type": "git", "style": "diamond", "foreground": cyan,
                 "properties": {"branch_icon": " ", "fetch_status": True, "fetch_upstream_icon": True}, "template": f" {git_full} "},
            ]},
            {"type": "prompt", "alignment": "right", "segments": [
                {"type": "text", "style": "plain", "foreground": green},
                {"type": "executiontime", "style": "diamond", "foreground": green, "properties": {"style": "dallas", "threshold": 0},
                 "template": f" {{{{ .FormattedMs }}}}s <{fg}></>"},
                {"type": "root", "style": "diamond", "properties": {"root_icon": " "}, "template": "  "},
                {"type": "sysinfo", "style": "diamond", "foreground": green,
                 "template": f" <{fg}>MEM:</> {{{{ round .PhysicalPercentUsed .Precision }}}}% ({{{{ (div ((sub .PhysicalTotalMemory .PhysicalAvailableMemory)|float64) 1073741824.0) }}}}/{{{{ (div .PhysicalTotalMemory 1073741824.0) }}}}GB)"},
            ]},
            {"type": "prompt", "alignment": "left", "newline": True, "segments": [
                {"type": "path", "style": "diamond", "foreground": cyan, "leading_diamond": f"<{blue}>  </><{cyan}>{{</>",
                 "trailing_diamond": f"<{cyan}>}}</>",
                 "properties": {"folder_icon": "", "folder_separator_icon": "  ", "home_icon": "home", "style": "agnoster_full"},
                 "template": "  {{ .Path }} "},
                {"type": "status", "style": "plain", "foreground": green,
                 "foreground_templates": [f"{{{{ if gt .Code 0 }}}}{red}{{{{ end }}}}"],
                 "properties": {"always_enabled": True}, "template": "  "},
            ]},
        ]
    elif style == "cert":
        def cert(type_, b, tpl, props=None):
            s = {"type": type_, "style": "diamond", "foreground": bg, "background": b,
                 "leading_diamond": "" if type_ == "session" else "", "trailing_diamond": ""}
            if props is not None:
                s["properties"] = props
            s["template"] = tpl
            return s
        blocks = [{"type": "prompt", "alignment": "left", "segments": [
            cert("session", red, "{{ .UserName }} "),
            cert("path", green, " {{ .Path }} ", {"style": "folder"}),
            cert("git", cyan, " git({{ .HEAD }}) ", {"branch_icon": ""}),
            cert("time", purple, " {{ .CurrentDate | date .Format }} ", {"time_format": "15:04"}),
        ]}]
    elif style == "clean-detailed":
        def cd(type_, f, b, trail, tpl, props=None):
            s = {"type": type_, "style": "diamond", "foreground": f, "background": b,
                 "leading_diamond": "", "trailing_diamond": trail}
            if props is not None:
                s["properties"] = props
            s["template"] = tpl
            return s
        blocks = [
            {"type": "prompt", "alignment": "left", "newline": True, "segments": [
                cd("os", bg, fg, f"<transparent,{fg}></>", " {{ if .WSL }}WSL at {{ end }}{{.Icon}}",
                   {"macos": " ", "ubuntu": " ", "windows": " "}),
                cd("shell", bg, fg, f"<transparent,{fg}></>", " {{ .Name }}"),
                cd("sysinfo", bg, blue, f"<transparent,{blue}></>",
                   " MEM: {{ round .PhysicalPercentUsed .Precision }}% | {{ (div ((sub .PhysicalTotalMemory .PhysicalAvailableMemory)|float64) 1073741824.0) }}/{{ (div .PhysicalTotalMemory 1073741824.0) }}GB  "),
                cd("executiontime", bg, purple, "", " {{ .FormattedMs }} ", {"style": "roundrock", "threshold": 0}),
            ]},
            {"type": "prompt", "alignment": "right", "segments": [
                cd("git", bg, green, "", f" {git_full} ",
                   {"branch_icon": " ", "fetch_status": True, "fetch_upstream_icon": True}),
            ]},
            {"type": "prompt", "alignment": "left", "newline": True, "segments": [
                {"type": "text", "style": "plain", "foreground": cyan, "template": "╭─"},
                {"type": "time", "style": "plain", "foreground": yellow, "properties": {"time_format": "15:04"},
                 "template": " ♥ {{ .CurrentDate | date .Format }} |"},
                {"type": "root", "style": "plain", "foreground": red, "template": "  "},
                {"type": "path", "style": "plain", "foreground": blue,
                 "properties": {"folder_icon": " ", "folder_separator_icon": "  ", "home_icon": " "},
                 "template": " {{ .Path }} "},
            ]},
            {"type": "prompt", "alignment": "left", "newline": True, "segments": [
                {"type": "status", "style": "plain", "foreground": purple,
                 "foreground_templates": [f"{{{{ if gt .Code 0 }}}}{red}{{{{ end }}}}"],
                 "properties": {"always_enabled": True}, "template": "╰─ "},
            ]},
        ]
    elif style == "velvet":
        def lang(type_, f, tpl):
            return {"type": type_, "style": "diamond", "foreground": f, "background": purple,
                    "leading_diamond": " ", "trailing_diamond": "",
                    "properties": {"fetch_version": False}, "template": tpl}
        blocks = [
            {"type": "prompt", "alignment": "left", "segments": [
                {"type": "os", "style": "diamond", "foreground": bg, "background": purple, "properties": {
                    "macos": "", "windows": "", "linux": "", "ubuntu": "", "arch": "",
                    "debian": "", "fedora": "", "manjaro": "", "opensuse": ""},
                 "template": " {{ if .WSL }}WSL at {{ end }}{{.Icon}} "},
                {"type": "path", "style": "powerline", "powerline_symbol": ROUND, "foreground": bg, "background": blue,
                 "properties": {"style": "agnoster_short", "max_depth": 3, "folder_icon": "...", "folder_separator_icon": "/", "home_icon": "~"},
                 "template": " {{ .Path }} "},
                {"type": "git", "style": "powerline", "powerline_symbol": ROUND, "foreground": bg, "background": cyan,
                 "properties": {"fetch_status": True, "fetch_upstream_icon": True, "branch_template": "{{ trunc 25 .Branch }}"},
                 "template": f" {git_full} "},
                {"type": "executiontime", "style": "powerline", "powerline_symbol": ROUND, "foreground": bg, "background": yellow,
                 "properties": {"always_enabled": True}, "template": " {{ .FormattedMs }} "},
                {"type": "status", "style": "diamond", "trailing_diamond": ROUND, "foreground": bg, "background": green,
                 "foreground_templates": [f"{{{{ if gt .Code 0 }}}}{red}{{{{ end }}}}"], "properties": {"always_enabled": True},
                 "template": " {{ if gt .Code 0 }} {{.Code}}{{ end }} "},
            ]},
            {"type": "rprompt", "alignment": "right", "segments": [
                lang("python", yellow, "{{ if .Error }}{{ .Error }}{{ else }}{{ if .Venv }}{{ .Venv }} {{ end }}{{ .Full }}{{ end }}"),
                lang("go", cyan, "{{ if .Error }}{{ .Error }}{{ else }}{{ .Full }}{{ end }}"),
                lang("node", green, "{{ if .PackageManagerIcon }}{{ .PackageManagerIcon }} {{ end }}{{ .Full }}"),
                lang("ruby", red, "{{ if .Error }}{{ .Error }}{{ else }}{{ .Full }}{{ end }}"),
                lang("java", red, "{{ if .Error }}{{ .Error }}{{ else }}{{ .Full }}{{ end }}"),
            ]},
            {"type": "prompt", "alignment": "left", "newline": True, "segments": [
                {"type": "time", "style": "diamond", "foreground": bg, "background": purple, "trailing_diamond": ROUND,
                 "properties": {"time_format": "15:04:05"}, "template": " {{ .CurrentDate | date .Format }} "},
            ]},
        ]
    elif style == "pure":
        blocks = [line([path_seg(blue, "{{ .Path }}")]), line([stat_seg(purple, "❯ ")], True)]
    elif style == "bong":
        cloud, dog, bone = "", "", ""
        blocks = [
            line([
                text_seg(yellow, f"{cloud}  "),
                {"type": "time", "style": "plain", "foreground": fg, "properties": {"time_format": "02/01/2006 Monday 03:04 PM"},
                 "template": "{{ .CurrentDate | date .Format }}"},
                text_seg(fg, " | "),
                {"type": "path", "style": "plain", "foreground": yellow,
                 "properties": {"style": "agnoster_short", "max_depth": 3, "folder_separator_icon": "\\", "folder_icon": ".."},
                 "template": "{{ .Path }}"},
                {"type": "git", "style": "plain", "foreground": purple, "properties": {"fetch_status": False, "branch_icon": " "},
                 "template": " {{ .HEAD }}"},
            ]),
            line([stat_seg(yellow, f"{dog} {bone} ")], True),
        ]
    else:  # classic
        blocks = [line([
            path_seg(blue, " {{ .Path }} "),
            {"type": "git", "style": "plain", "foreground": green, "properties": {"fetch_status": True},
             "template": "{{ .HEAD }}{{ if or (.Working.Changed) (.Staging.Changed) }}*{{ end }} "},
            stat_seg(purple, "❯ "),
        ])]

    config = {"$schema": SCHEMA, "version": 4, "final_space": True, "blocks": blocks}

    if style in ("1_shell", "clean-detailed"):
        config["console_title_template"] = "{{ .Folder }}"
        config["transient_prompt"] = {"background": "transparent", "foreground": fg, "template": " "}
    elif style == "velvet":
        config["console_title_template"] = "{{ .Shell }} - {{ .Folder }}"
    elif style == "bong":
        config["console_title_template"] = "{{ .Folder }}"
        config["transient_prompt"] = {"background": "transparent", "foreground": yellow, "template": "  "}
    return config


def save_prompt(config, name="auto"):
    """Write a generated config to ~/.poshpalette/prompts/<name>.omp.json."""
    from .catalog import user_root
    d = user_root() / "prompts"
    d.mkdir(parents=True, exist_ok=True)
    p = d / f"{name}.omp.json"
    p.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return p
