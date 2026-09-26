#!/usr/bin/env python3
"""Vela 主题色对比度守卫（审计 H6）。

规则：
  1. 硬性门禁：VelaTheme.textColor(for:) 的文字色（light/dark）对画布
     VelaTheme.rhythmCanvas 必须 ≥4.5:1（WCAG AA 正文）。新增/修改文字色须通过。
  2. 报告项：全部 adaptive 色板里 light <3:1 或 dark <3:1 的条目打印警告
     不阻断（图形/装饰色按 3:1 图形目标；如需收紧请提升到规则 1）。

用法：
  python3 scripts/check_contrast.py            # CI/本地门禁
  python3 scripts/check_contrast.py --report   # 只出报告（不失败）
"""

import re
import sys
from pathlib import Path

THEME = Path(__file__).resolve().parent.parent / "VelaApp" / "Core" / "Theme" / "VelaTheme.swift"
TEXT_MIN = 4.5


def luminance(hex_color):
    values = hex_color.lstrip("#")
    r, g, b = (int(values[i:i + 2], 16) / 255 for i in (0, 2, 4))

    def linear(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def parse_adaptive_pairs(text):
    """提取所有 adaptive("#LIGHT", "#DARK") 对（含命名注释）。"""
    pairs = []
    for m in re.finditer(
        r'(?://[^\n]*)?\n\s*static let\s+(\w+)\s*=.*?adaptive\("#([0-9A-Fa-f]{6})",\s*"#([0-9A-Fa-f]{6})"\)',
        text,
    ):
        pairs.append((m.group(1), "#" + m.group(2).upper(), "#" + m.group(3).upper()))
    return pairs


def main():
    report_only = "--report" in sys.argv
    source = THEME.read_text(encoding="utf-8")
    canvas = next(((light, dark) for name, light, dark in parse_adaptive_pairs(source)
                   if name == "rhythmCanvas"), None)
    if canvas is None:
        print("FAIL: rhythmCanvas 自适应画布颜色未找到", file=sys.stderr)
        return 1
    light_canvas, dark_canvas = canvas
    print(f"Canvas: {light_canvas} / {dark_canvas}")

    # 规则 1：textColor(for:) 的六个值
    block = re.search(r"static func textColor\(for[\s\S]*?\n    \}", source)
    if not block:
        print("FAIL: textColor(for:) 未找到", file=sys.stderr)
        return 1
    hexes = re.findall(r'adaptive\("#([0-9A-Fa-f]{6})",\s*"#([0-9A-Fa-f]{6})"\)', block.group(0))
    failures = []
    for light, dark in hexes:
        l = "#" + light.upper()
        d = "#" + dark.upper()
        cl = contrast(l, light_canvas)
        cd = contrast(d, dark_canvas)
        for mode, value, canvas, ratio in (("light", l, light_canvas, cl), ("dark", d, dark_canvas, cd)):
            if ratio < TEXT_MIN:
                failures.append(f"  textColor {value} on {canvas} = {ratio:.2f}:1 (< {TEXT_MIN})")

    # 规则 2：全色板报告（仅扫描「前景语义色」，表面/描边/渐变类低对比是设计预期）
    text_like = re.compile(
        r"(accent|brand|state|system|info|strain|energy|stress|sleep|recovery|meta|ink|fg|Text|poor|moderate|good)",
        re.I,
    )
    warnings = []
    for name, light, dark in parse_adaptive_pairs(source):
        if not text_like.search(name):
            continue
        cl = contrast(light, light_canvas)
        cd = contrast(dark, dark_canvas)
        if cl < 3.0:
            warnings.append(f"  {name} {light} on {light_canvas} = {cl:.2f}:1")
        if cd < 3.0:
            warnings.append(f"  {name} {dark} on {dark_canvas} = {cd:.2f}:1")

    if warnings:
        print("WARN (graphic palette <3:1, informational):")
        print("\n".join(warnings))

    if failures:
        print("FAIL (textColor WCAG AA >=4.5:1):")
        print("\n".join(failures))
        print("文字色请在浅色模式下加深，如 #0C7A44 / #8A5F14 / #B0405C。")
        return 1

    print(f"contrast OK: textColor(for:) all >= {TEXT_MIN}:1")
    return 0


if __name__ == "__main__":
    sys.exit(main())
