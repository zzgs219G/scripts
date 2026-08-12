#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  《焚诀·Git 工作流》 安装 / 迁移脚本
#  用法:  bash fz-tools/install.sh
# ════════════════════════════════════════════════════════════
#  功能：
#    1. 备份 ~/.bashrc → ~/.bashrc.bak
#    2. 提取旧版注入块中的 AI Key 并迁移到新主入口（如有）
#    3. 移除旧版注入块（# --- AI_GIT_WORKFLOW --- ... # --- END ---）
#       及旧的 source <(curl ...) 注入行
#    4. 移除旧的 source 行与标记（任意克隆目录名，保证幂等）
#    5. 追加 source <仓库>/fz-tools/fzgit.sh
#    6. 重新加载 ~/.bashrc
# ════════════════════════════════════════════════════════════

# 定位仓库根目录（本脚本位于 <仓库>/fz-tools/install.sh）
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${INSTALL_DIR}/.." && pwd)"
MAIN_FILE="${INSTALL_DIR}/fzgit.sh"

if [ ! -f "${MAIN_FILE}" ]; then
    echo -e "\033[31m❌ 未找到主入口: ${MAIN_FILE}\033[0m"
    exit 1
fi
if [ ! -f "${HOME}/.bashrc" ]; then
    echo -e "\033[33m⚠️  ~/.bashrc 不存在，将自动创建\033[0m"
    touch "${HOME}/.bashrc"
fi

# 1. 备份
cp "${HOME}/.bashrc" "${HOME}/.bashrc.bak" 2>/dev/null && \
    echo -e "\033[90m💾 已备份 ~/.bashrc → ~/.bashrc.bak\033[0m"

# 2. 迁移旧注入块中的 AI Key（如有）
OLD_KEY=$(awk '/# --- AI_GIT_WORKFLOW ---/,/# --- END ---/' "${HOME}/.bashrc" | sed -n 's/.*export FZ_AI_KEY="\([^"]*\)".*/\1/p' | tail -1)
if [ -n "$OLD_KEY" ]; then
    if grep -q 'export FZ_AI_KEY=""' "${MAIN_FILE}"; then
        ESCAPED_KEY=$(printf '%s' "$OLD_KEY" | sed 's/[\/&]/\\&/g')
        sed -i "s|export FZ_AI_KEY=\"\"|export FZ_AI_KEY=\"${ESCAPED_KEY}\"|" "${MAIN_FILE}"
        echo -e "\033[32m🔑 已迁移旧版 AI Key 到新主入口\033[0m"
    else
        echo -e "\033[33m⚠️  新主入口已配置 Key，跳过迁移\033[0m"
    fi
fi

# 3. 移除旧注入块与旧 source 注入行
sed -i '/# --- AI_GIT_WORKFLOW ---/,/# --- END ---/d' "${HOME}/.bashrc"
sed -i '\#zzgs219G/scripts#d' "${HOME}/.bashrc"

# 4. 移除旧的 source 行与标记（任意克隆目录名均可，幂等可重跑）
sed -i '\#^source .*fzgit\.sh#d' "${HOME}/.bashrc"
sed -i '/# --- FZ-TOOLS: 焚诀入口 ---/d' "${HOME}/.bashrc"

# 5. 追加新加载行
printf '\n# --- FZ-TOOLS: 焚诀入口 ---\nsource '\''%s'\''\n' "${MAIN_FILE}" >> "${HOME}/.bashrc"

# 6. 生效
source "${HOME}/.bashrc"

# 7. 完成提示
echo -e "\n\033[1;32m╔══════════════════════════════════╗"
echo -e "║  焚诀·v${FZ_VERSION} 安装成功！        ║"
echo -e "╚══════════════════════════════════╝\033[0m"
echo -e "\n  执行 \033[36mh\033[0m 查看全部指令"
echo -e "  执行 \033[36msetup\033[0m 初始化环境"
echo -e "  执行 \033[36maikey\033[0m 配置AI commit（可选）\n"
