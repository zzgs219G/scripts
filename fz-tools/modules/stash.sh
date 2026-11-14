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

    # 未跟踪文件默认不在 stash 范围内。用户说「暂存工作区」时通常
    # 期望新增文件也被一起收走，否则 save 后工作区仍脏、后续 checkout
    # 会失败。这里显式带上 -u，并在无任何改动时给出明确提示。
    if [ -z "$(git status -s 2>/dev/null)" ]; then
        echo -e "\033[33m🧊 工作区没有需要暂存的改动\033[0m"
        return 0
    fi

    local untracked=0
    [ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ] && untracked=1

    if git stash push -u -m "$msg" >/dev/null 2>&1; then
        echo -e "\033[32m🧊 已暂存: $msg\033[0m"
        [ "$untracked" -eq 1 ] && echo -e "\033[90m   含未跟踪的新文件（恢复时一并回来）\033[0m"
    else
        # 兼容极老版本 git（无 -u 支持）
        git stash push -m "$msg" || {
            echo -e "\033[31m❌ 暂存失败\033[0m"
            return 1
        }
        echo -e "\033[32m🧊 已暂存: $msg\033[0m"
        echo -e "\033[33m   ⚠️ 未跟踪的新文件未被包含（当前 git 版本不支持 -u）\033[0m"
    fi
    git stash list | head -5
}

# ══════════════════════════════════════════
#  📦  恢复暂存（pop）
# ══════════════════════════════════════════
_stash_pop() {
    _check_git_repo || return 1
    local list
    list=$(git stash list)
    if [ -z "$list" ]; then
        echo -e "\033[33m📦 暂存区为空\033[0m"; return 0
    fi
    echo -e "\033[36m📦 暂存列表:\033[0m"
    git stash list
    if [ -z "${1:-}" ]; then
        git stash pop && echo -e "\033[32m✅ 已恢复最近暂存\033[0m"
    else
        git stash pop "stash@{$1}" && echo -e "\033[32m✅ 已恢复暂存 [$1]\033[0m"
    fi
}
