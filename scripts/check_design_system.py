#!/usr/bin/env python3
"""BodySeek 设计系统门禁（只用标准库）。

依据 docs/design/design-system.md §10.3 与 docs/design/dataviz.md §8，扫描：
  - BodySeekKit/Sources/BodySeekFeatures        （通用规则）
  - BodySeekKit/Sources/BodySeekDesign/Charts   （通用规则 + 图表专项规则）
排除 BodySeekKit/Sources/BodySeekDesign/Tokens（令牌本身允许出现数字）。

默认只报告，退出码为 0。加 --strict <路径前缀>（相对仓库根目录，可重复）后，
该前缀下只要还有违例就以退出码 1 结束，用于以后逐页切换为阻断。
前缀不存在时以退出码 2 结束，避免拼写错误导致门禁悄悄失效。

用法：
  python3 scripts/check_design_system.py
  python3 scripts/check_design_system.py --strict BodySeekKit/Sources/BodySeekFeatures/Views/Today
  python3 scripts/check_design_system.py --markdown      # 输出 Markdown 表格（用于写基线文档）
  python3 scripts/check_design_system.py --details       # 列出每一处违例的行号
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
FEATURES = "BodySeekKit/Sources/BodySeekFeatures"
CHARTS = "BodySeekKit/Sources/BodySeekDesign/Charts"
TOKENS = "BodySeekKit/Sources/BodySeekDesign/Tokens"


@dataclass(frozen=True)
class Rule:
    key: str
    title: str
    pattern: re.Pattern[str]
    charts_only: bool = False
    # frame 规则需要先取出整个 .frame(...) 调用再检查参数，其他规则直接匹配全文。
    frame_call: bool = False


def _re(pattern: str) -> re.Pattern[str]:
    return re.compile(pattern)


RULES: list[Rule] = [
    Rule("padding", ".padding(数字)", _re(r"\.padding\(\s*(?:\.[A-Za-z]+\s*,\s*)?[0-9]")),
    Rule("spacing", "spacing: 数字", _re(r"\bspacing\s*:\s*[0-9]")),
    Rule("corner-radius", "cornerRadius: 数字", _re(r"\bcornerRadius\s*:\s*[0-9]")),
    Rule("opacity", ".opacity(0.xx)", _re(r"\.opacity\(\s*[0-9]*\.[0-9]")),
    Rule("frame", ".frame(width/height: 数字)", _re(r"\b(?:width|height)\s*:\s*[0-9]"), frame_call=True),
    Rule("hex-color", 'adaptive("# / Color(red:', _re(r'\badaptive\(\s*"#|\bColor\(\s*red\s*:')),
    Rule("fixed-font", ".font(.system(size:", _re(r"\.font\(\s*\.system\(\s*size\s*:")),
    Rule("shadow", ".shadow(", _re(r"\.shadow\(")),
    Rule("gradient", "Gradient", _re(r"Gradient")),
    Rule("plain-button", ".buttonStyle(.plain)", _re(r"\.buttonStyle\(\s*\.plain\s*\)")),
    Rule("fixed-curve", ".easeInOut( / .easeOut( / .linear(", _re(r"\.(?:easeInOut|easeOut|linear)\(")),
    Rule("damping", "dampingFraction / dampingRatio（BSMotion 之外）", _re(r"\b(?:dampingFraction|dampingRatio)\b")),
    Rule("kerning", ".kerning( / .tracking(", _re(r"\.(?:kerning|tracking)\(")),
    Rule("chart-linear-gradient", "[Charts] LinearGradient", _re(r"\bLinearGradient\b"), charts_only=True),
    Rule("chart-line-width", "[Charts] lineWidth: 数字", _re(r"\blineWidth\s*:\s*[0-9]"), charts_only=True),
    Rule("chart-dash", "[Charts] dash: [", _re(r"\bdash\s*:\s*\["), charts_only=True),
]

FRAME_CALL = re.compile(r"\.frame\(((?:[^()]|\([^()]*\))*)\)")


def strip_comments(source: str) -> str:
    """把注释替换为空格（保留换行以维持行号），字符串内容原样保留。"""
    out: list[str] = []
    i, n = 0, len(source)
    block_depth = 0
    while i < n:
        two = source[i : i + 2]
        ch = source[i]
        if block_depth:
            if two == "/*":
                block_depth += 1
                out.append("  ")
                i += 2
            elif two == "*/":
                block_depth -= 1
                out.append("  ")
                i += 2
            else:
                out.append("\n" if ch == "\n" else " ")
                i += 1
            continue
        if two == "//":
            while i < n and source[i] != "\n":
                out.append(" ")
                i += 1
            continue
        if two == "/*":
            block_depth = 1
            out.append("  ")
            i += 2
            continue
        if source.startswith('"""', i):
            end = source.find('"""', i + 3)
            end = n if end == -1 else end + 3
            out.append(source[i:end])
            i = end
            continue
        if ch == '"':
            j = i + 1
            while j < n and source[j] != "\n":
                if source[j] == "\\":
                    j += 2
                    continue
                if source[j] == '"':
                    j += 1
                    break
                j += 1
            out.append(source[i:j])
            i = j
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def scan_file(path: Path, rel: str, in_charts: bool) -> list[tuple[str, int]]:
    """返回 [(规则 key, 行号)]。"""
    try:
        text = strip_comments(path.read_text(encoding="utf-8"))
    except UnicodeDecodeError:
        print(f"警告：无法按 UTF-8 读取 {rel}，已跳过", file=sys.stderr)
        return []
    hits: list[tuple[str, int]] = []
    for rule in RULES:
        if rule.charts_only and not in_charts:
            continue
        if rule.frame_call:
            for m in FRAME_CALL.finditer(text):
                if rule.pattern.search(m.group(1)):
                    hits.append((rule.key, line_of(text, m.start())))
            continue
        for m in rule.pattern.finditer(text):
            hits.append((rule.key, line_of(text, m.start())))
    return hits


def collect_files(root: Path) -> list[tuple[Path, str, bool]]:
    files: list[tuple[Path, str, bool]] = []
    for base, in_charts in ((FEATURES, False), (CHARTS, True)):
        base_path = root / base
        if not base_path.is_dir():
            print(f"警告：目录不存在 {base}", file=sys.stderr)
            continue
        for path in sorted(base_path.rglob("*.swift")):
            rel = path.relative_to(root).as_posix()
            if rel.startswith(TOKENS + "/"):
                continue
            files.append((path, rel, in_charts))
    return files


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="BodySeek 设计系统门禁（默认只报告）")
    parser.add_argument("--strict", action="append", default=[], metavar="路径前缀",
                        help="对该前缀（相对仓库根目录）下的违例以退出码 1 结束；可重复")
    parser.add_argument("--root", default=str(REPO_ROOT), help="仓库根目录（默认取脚本所在仓库）")
    parser.add_argument("--top", type=int, default=10, help="列出违例最多的文件数（默认 10）")
    parser.add_argument("--markdown", action="store_true", help="以 Markdown 表格输出")
    parser.add_argument("--details", action="store_true", help="列出每个文件每条规则的行号")
    args = parser.parse_args(argv)

    root = Path(args.root).resolve()
    files = collect_files(root)

    for prefix in args.strict:
        if not (root / prefix).exists():
            print(f"错误：--strict 路径不存在：{prefix}", file=sys.stderr)
            return 2

    per_file: dict[str, Counter[str]] = {}
    lines: dict[str, list[tuple[str, int]]] = {}
    totals_features: Counter[str] = Counter()
    totals_charts: Counter[str] = Counter()
    for path, rel, in_charts in files:
        hits = scan_file(path, rel, in_charts)
        counter: Counter[str] = Counter(key for key, _ in hits)
        per_file[rel] = counter
        lines[rel] = hits
        (totals_charts if in_charts else totals_features).update(counter)

    def row_total(key: str) -> int:
        return totals_features[key] + totals_charts[key]

    general = [r for r in RULES if not r.charts_only]
    chart_only = [r for r in RULES if r.charts_only]
    general_sum = sum(row_total(r.key) for r in general)
    chart_sum = sum(row_total(r.key) for r in chart_only)

    md = args.markdown
    print("## 设计系统门禁报告" if md else "设计系统门禁报告")
    print(f"扫描 {len(files)} 个 Swift 文件（BodySeekFeatures + BodySeekDesign/Charts，排除 Tokens）")
    print()
    if md:
        print("| 规则 | Features | Charts | 合计 |")
        print("| :--- | ---: | ---: | ---: |")
        for r in RULES:
            print(f"| `{r.key}` {r.title} | {totals_features[r.key]} | {totals_charts[r.key]} | {row_total(r.key)} |")
        print(f"| **通用规则合计** |  |  | **{general_sum}** |")
        print(f"| **图表专项合计（与通用规则可能重叠）** |  |  | **{chart_sum}** |")
    else:
        width = max(len(r.key) for r in RULES)
        print(f"{'规则':<{width}}  {'Features':>8}  {'Charts':>6}  {'合计':>5}  说明")
        for r in RULES:
            print(f"{r.key:<{width}}  {totals_features[r.key]:>8}  {totals_charts[r.key]:>6}  {row_total(r.key):>5}  {r.title}")
        print(f"{'通用规则合计':<{width}}  {'':>8}  {'':>6}  {general_sum:>5}")
        print(f"{'图表专项合计':<{width}}  {'':>8}  {'':>6}  {chart_sum:>5}  （LinearGradient 与 gradient 规则重叠）")
    print()

    ranked = sorted(((sum(c.values()), rel) for rel, c in per_file.items() if c), reverse=True)
    print(f"### 违例最多的 {args.top} 个文件" if md else f"违例最多的 {args.top} 个文件")
    if md:
        print("| # | 文件 | 违例数 | 主要规则 |")
        print("| ---: | :--- | ---: | :--- |")
    for idx, (count, rel) in enumerate(ranked[: args.top], start=1):
        top_rules = ", ".join(f"{k}×{v}" for k, v in per_file[rel].most_common(3))
        if md:
            print(f"| {idx} | `{rel}` | {count} | {top_rules} |")
        else:
            print(f"{idx:>2}. {count:>4}  {rel}  ({top_rules})")
    if not ranked:
        print("（无违例）")
    print()

    if args.details:
        for count, rel in ranked:
            print(f"{rel}")
            for key, line in sorted(lines[rel], key=lambda x: (x[1], x[0])):
                print(f"  L{line}: {key}")
        print()

    strict_hits: list[tuple[str, int]] = []
    for rel, counter in per_file.items():
        total = sum(counter.values())
        if total and any(rel == p.rstrip("/") or rel.startswith(p.rstrip("/") + "/") or rel.startswith(p)
                         for p in args.strict):
            strict_hits.append((rel, total))
    if args.strict:
        if strict_hits:
            print("严格模式失败：以下文件仍有违例")
            for rel, total in sorted(strict_hits):
                print(f"  {total:>4}  {rel}")
            return 1
        print("严格模式通过：指定前缀下没有违例")
    else:
        print("模式：只报告（退出码 0）。要把某个页面切换为阻断，加 --strict <路径前缀>。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
