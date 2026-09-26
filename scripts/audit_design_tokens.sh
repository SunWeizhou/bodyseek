#!/bin/bash
# Vela 设计 Token 审计 —— 零依赖,现在即可运行。
#
# 目的:让"不允许在视图层硬编码颜色/字号/圆角"这条设计系统宪法**可见、可执行**,
# 而不是停留在 docs/VELA_DESIGN_LANGUAGE.md 纸面上。Token 只在 Core/Theme 与 Core/DesignSystem 定义,
# 其余视图文件一律应引用 VelaTheme / VelaDesignSystem。
#
# 用法:
#   scripts/audit_design_tokens.sh           # 报告模式(默认,exit 0)
#   scripts/audit_design_tokens.sh --strict  # 严格模式,发现违规 exit 1(可挂 CI)
#
# 说明:.system(size:) 对**图标**是合法的(图标不参与 Dynamic Type),脚本无法
# 100% 区分文本与图标,故默认仅报告不拦截;人工判断收敛即可。

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

STRICT="${1:-}"

# Token 定义处(豁免)
EXEMPT='VelaApp/Core/Theme|VelaApp/Core/DesignSystem'

# 承载视图的源码目录
SEARCH_DIRS="VelaApp/Features VelaApp/Journal VelaApp/TrainingIntelligence VelaApp/Health VelaApp/AI VelaApp/App"

total=0
report() {
  local label="$1" pattern="$2"
  local matches count
  matches=$(grep -rnE "$pattern" $SEARCH_DIRS --include='*.swift' 2>/dev/null | grep -vE "$EXEMPT" || true)
  count=$(printf '%s' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')
  if [ "$count" -gt 0 ]; then
    echo ""
    echo "❌ ${label} — ${count} 处"
    printf '%s\n' "$matches" | head -12
    if [ "$count" -gt 12 ]; then
      echo "   … 以及 $((count-12)) 处更多(完整列表用 grep 自行查看)"
    fi
  else
    echo ""
    echo "✅ ${label} — 0 处"
  fi
  total=$((total+count))
}

echo "==================================="
echo "  Vela 设计 Token 审计"
echo "==================================="

report '硬编码颜色 Color(hex:)'            'Color\(hex:'
report '硬编码字号 .font(.system(size:))'  '\.font\(\s*\.system\(size:'
report '直写系统语义色 Color.red/green/…'  'Color\.(red|green|orange|yellow|pink|purple)\b'
report '内联 RoundedRectangle(cornerRadius:' 'RoundedRectangle\(cornerRadius:'

echo ""
echo "==================================="
echo "  合计 ${total} 处硬编码"
echo "==================================="

if [ "$STRICT" = "--strict" ] && [ "$total" -gt 0 ]; then
  echo "严格模式:存在违规,exit 1"
  exit 1
fi
exit 0
