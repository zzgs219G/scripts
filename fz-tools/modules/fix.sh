#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — fix.sh（冲突解决模块）
#  职责：检测冲突文件、列出清单并引导用编辑器解决
#  包含函数：_fix_conflict
#  对应别名：fix
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

# ══════════════════════════════════════════
#  🔧  冲突解决引导（fix）
# ══════════════════════════════════════════
_fix_conflict() {
    _check_git_repo || return 1
    local conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null)

    if [ -z "$conflicts" ]; then
        echo -e "\033[32m✅ 无冲突文件！\033[0m"
        return 0
    fi

    echo -e "\033[1;31m⚔️ 发现冲突文件:\033[0m"
    echo "$conflicts" | awk '{print "  \033[33m"NR"\033[0m. "$0}'

    echo -e "\n\033[36m解决步骤:\033[0m"
    echo -e "  1. 打开冲突文件，找到 \033[31m<<<<<<< HEAD\033[0m 标记"
    echo -e "  2. 保留需要的代码，删除 <<<<< ===== >>>>> 标记行"
    echo -e "  3. 执行 \033[33mgit add <文件>\033[0m"
    echo -e "  4. 执行 \033[33mgit commit\033[0m\n"

    local first=$(echo "$conflicts" | head -1)
    read -p "用 nano 打开 '$first'？(y/n): " open_it
    [[ "$open_it" == "y" || "$open_it" == "Y" ]] && nano "$first"
}
