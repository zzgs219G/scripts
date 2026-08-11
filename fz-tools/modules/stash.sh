#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — stash.sh（暂存模块）
#  职责：暂存当前工作区变更 / 恢复指定暂存项
#  包含函数：_stash_save  _stash_pop
#  对应别名：save  pop
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

# ══════════════════════════════════════════
#  🧊  暂存工作区（save）
# ══════════════════════════════════════════
_stash_save() {
    _check_git_repo || return 1
    local msg="${1:-临时保存_$(date '+%m%d_%H%M')}"
    git stash push -m "$msg"
    echo -e "\033[32m🧊 已暂存: $msg\033[0m"
    git stash list | head -5
}

# ══════════════════════════════════════════
#  📦  恢复暂存（pop）
# ══════════════════════════════════════════
_stash_pop() {
    _check_git_repo || return 1
    local list=$(git stash list)
    if [ -z "$list" ]; then
        echo -e "\033[33m📦 暂存区为空\033[0m"; return 0
    fi
    echo -e "\033[36m📦 暂存列表:\033[0m"
    git stash list
    if [ -z "$1" ]; then
        git stash pop && echo -e "\033[32m✅ 已恢复最近暂存\033[0m"
    else
        git stash pop "stash@{$1}" && echo -e "\033[32m✅ 已恢复暂存 [$1]\033[0m"
    fi
}
