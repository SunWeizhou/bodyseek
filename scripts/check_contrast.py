#!/usr/bin/env python3
"""BodySeek BevelTheme 对比度守卫。

规则：
  1. 硬性门禁：正文与交互文字 token（ink / inkSecondary / deviationInk / brand）
     对画布 BevelTheme.canvas，在浅色与深色外观下都必须 >=4.5:1（WCAG AA 正文）。
  2. 报告项：其余文字语义 token 若低于 3:1 打印警告，不阻断
     （图标/装饰色按 3:1 图形目标；如需收紧请提升到规则 1）。

用法：
  python3 scripts/check_contrast.py            # CI/本地门禁
  python3 scripts/check_contrast.py --report   # 只出报告（不失败）
"""

import re
import sys
from pathlib import Path

THEME = (
    Path(__file__).resolve().parent.parent
    / "BodySeekKit"
    / "Sources"
    / "BodySeekDesign"
    / "Tokens"
    / "BevelTheme.swift"
)
TEXT_MIN = 4.5
TEXT_TOKENS = ("ink", "inkSecondary", "deviationInk", "brand")


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
        r'(?://[^\n]*)?\n\s*(?:public\s+|internal\s+)?static let\s+(\w+)\s*=.*?'
        r'adaptive\("#([0-9A-Fa-f]{6})",\s*"#([0-9A-Fa-f]{6})"\)',
        text,
    ):
        pairs.append((m.group(1), "#" + m.group(2).upper(), "#" + m.group(3).upper()))
    return pairs


def main():
    report_only = "--report" in sys.argv
    source = THEME.read_text(encoding="utf-8")
    pairs = parse_adaptive_pairs(source)
    by_name = {name: (light, dark) for name, light, dark in pairs}

    canvas = by_name.get("canvas")
    if canvas is None:
        print("FAIL: canvas 自适应画布颜色未找到", file=sys.stderr)
        return 1
    light_canvas, dark_canvas = canvas
    print(f"Canvas: {light_canvas} / {dark_canvas}")

    failures = []
    for token in TEXT_TOKENS:
        pair = by_name.get(token)
        if pair is None:
            failures.append(f"  text token {token} missing")
            continue
        light, dark = pair
        for mode, value, canvas_hex in (
            ("light", light, light_canvas),
            ("dark", dark, dark_canvas),
        ):
            ratio = contrast(value, canvas_hex)
            print(f"{token} {mode} {value} on {canvas_hex} = {ratio:.2f}:1")
            if ratio < TEXT_MIN:
                failures.append(
                    f"  {token} {value} on {canvas_hex} = {ratio:.2f}:1 (< {TEXT_MIN})"
                )

    # 报告项：其余文字语义色 <3:1 只提示（图标/装饰色按图形目标 3:1）。
    text_like = re.compile(
        r"(accent|brand|state|system|info|strain|energy|stress|sleep|recovery|meta|ink|fg|Text|poor|moderate|good|danger)",
        re.I,
    )
    warnings = []
    for name, light, dark in pairs:
        if name in TEXT_TOKENS or not text_like.search(name):
            continue
        if name.startswith("on") or name.endswith(("Soft", "Track", "Band")):
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
        print("FAIL (text tokens WCAG AA >=4.5:1):")
        print("\n".join(failures))
        if report_only:
            return 0
        return 1

    print(f"contrast OK: text tokens {', '.join(TEXT_TOKENS)} all >= {TEXT_MIN}:1")
    return 0


if __name__ == "__main__":
    sys.exit(main())
