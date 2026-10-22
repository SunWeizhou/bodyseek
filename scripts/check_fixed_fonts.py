#!/usr/bin/env python3
"""Dynamic Type 固定字号扫描（审计 H1 长期治理）。

报告 VelaApp 中仍使用 .system(size:) 的固定字号（默认不失败）；
CI 接线为 report-only，用来追踪清理进度与防止回归到无约束状态。

用法：
  python3 scripts/check_fixed_fonts.py            # 报告
  python3 scripts/check_fixed_fonts.py --strict  # 超过阈值时失败（清理完成后启用）
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "VelaApp"
THRESHOLD = 216  # --strict 时的当前存量上限。新增固定字号会超过它。

pat = re.compile(r'\.font\(\.system\(size:\s*(\d+)([^a-zA-Z][^)]*)\)\)')

print("剩余固定字号 .system(size:) 站点：")
total = 0
by_file = []
for swift in sorted(ROOT.rglob("*.swift")):
    text = swift.read_text(encoding="utf-8")
    count = len(pat.findall(text))
    if count:
        by_file.append((count, str(swift.relative_to(ROOT.parent))))
        total += count
for count, path in by_file[:25]:
    print(f"  {count:4d}  {path}")
if len(by_file) > 25:
    print(f"  ... 以及另外 {len(by_file) - 25} 个文件")
print(f"合计：{total} 处（图标/显示级字号属设计决策，清理目标为文字档位）")

if "--strict" in sys.argv:
    print(f"阈值：{THRESHOLD}")
    return_code = 0 if total <= THRESHOLD else 1
else:
    return_code = 0
sys.exit(return_code)
