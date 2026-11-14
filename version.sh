#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·版本号管理
#  用法:
#    bash version.sh            # 显示当前版本
#    bash version.sh bump       # 次版本 +1（5.109 → 5.110）
#    bash version.sh bump major # 主版本 +1（5.109 → 6.0）
#    bash version.sh set 5.120  # 直接指定
# ════════════════════════════════════════════════════════════
#  为什么独立成脚本：
#   旧实现在 `p` 里用 commit count 覆盖 FZ_VERSION，导致每次推送
#   都必然产生一次「版本号变动」提交，版本号与语义完全脱钩，
#   且多分支并行时该 sed 是固定冲突源。现改为发版时显式递增。
# ════════════════════════════════════════════════════════════

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_FILE="${SCRIPT_DIR}/fz-tools/fzgit.sh"

if [ ! -f "$MAIN_FILE" ]; then
    echo "❌ 未找到主入口: $MAIN_FILE" >&2
    exit 1
fi

current=$(grep -m1 '^FZ_VERSION=' "$MAIN_FILE" | cut -d'"' -f2)
if [ -z "$current" ]; then
    echo "❌ 无法读取当前版本号" >&2
    exit 1
fi

action="${1:-show}"

case "$action" in
    show)
        echo "$current"
        exit 0
        ;;
    bump)
        if [ "${2:-minor}" = "major" ]; then
            next="$(( ${current%%.*} + 1 )).0"
        else
            major="${current%%.*}"
            minor="${current#*.}"
            minor="${minor%%.*}"
            next="${major}.$(( minor + 1 ))"
        fi
        ;;
    set)
        next="${2:-}"
        if ! [[ "$next" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
            echo "❌ 版本号格式无效: ${next}（示例: 5.120 / 6.0）" >&2
            exit 1
        fi
        ;;
    -h|--help|help)
        sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^#  \{0,2\}//'
        exit 0
        ;;
    *)
        echo "❌ 未知动作: $action（可用: show / bump / bump major / set <版本>）" >&2
        exit 1
        ;;
esac

sed -i "s/^FZ_VERSION=\".*\"$/FZ_VERSION=\"${next}\"/" "$MAIN_FILE"

# 校验写入结果，避免 sed 未命中却静默成功
written=$(grep -m1 '^FZ_VERSION=' "$MAIN_FILE" | cut -d'"' -f2)
if [ "$written" != "$next" ]; then
    echo "❌ 写入失败（当前仍为 ${written}）" >&2
    exit 1
fi

echo "v${current} → v${next}"
echo "提示: 需要重新加载 shell 才会生效 —— source ~/.bashrc"
