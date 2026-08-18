#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — view.sh（查看模块）
#  职责：日志 / 差异 / 仓库信息 / 远程仓库文件列表
#  包含函数：_log_pretty  _diff_view  _repo_info  _rls_remote
#  对应别名：lg  d  info  rls
#  ⚠️ v4.0 加固：_repo_info 的 git shortlog 增加 </dev/null，
#     避免 stdin 为管道（非交互/脚本环境）时 pager 挂起
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

# ══════════════════════════════════════════
#  📜  漂亮日志（lg）
# ══════════════════════════════════════════
_log_pretty() {
    _check_git_repo || return 1
    local n="${1:-15}"
    echo -e "\033[1;36m📜 最近 ${n} 条提交:\033[0m\n"
    git log --oneline --graph --decorate --color "-${n}"
    echo -e "\n\033[90m用法: lg <条数>\033[0m"
}

# ══════════════════════════════════════════
#  🔍  查看差异（d）
# ══════════════════════════════════════════
_diff_view() {
    _check_git_repo || return 1
    if [ -z "${1:-}" ]; then
        local changed=$(git diff --stat 2>/dev/null)
        if [ -z "$changed" ]; then
            echo -e "\033[32m✅ 工作区无未暂存的变更\033[0m"
        else
            echo -e "\033[36m📊 未暂存的变更:\033[0m"
            git diff --stat
        fi
    elif [ "${1:-}" = "s" ] || [ "${1:-}" = "staged" ]; then
        echo -e "\033[36m📊 已暂存的变更:\033[0m"
        git diff --staged --stat
    else
        echo -e "\033[36m📊 与 $1 的差异:\033[0m"
        git diff "${1:-}" --stat
    fi
}

# ══════════════════════════════════════════
#  📊  仓库信息总览（info）
# ══════════════════════════════════════════
_repo_info() {
    _check_git_repo || return 1
    echo -e "\n\033[1;35m📊 仓库信息\033[0m"
    echo -e "  ─────────────────────────────────"
    echo -e "  🌿 分支   : \033[33m$(git branch --show-current)\033[0m"
    echo -e "  🔗 远程   : \033[36m$(git remote get-url origin 2>/dev/null || echo '未设置')\033[0m"
    echo -e "  📜 提交数 : \033[33m$(git rev-list --count HEAD 2>/dev/null || echo 0)\033[0m 次"
    echo -e "  📁 追踪数 : \033[33m$(git ls-files 2>/dev/null | wc -l | tr -d ' ')\033[0m 个文件"
    echo -e "  ⏰ 最近   : $(git log -1 --format='%s (%cr)' 2>/dev/null || echo '无')"
    echo -e "  🏷️  标签   : $(git tag | wc -l | tr -d ' ') 个"

    local ahead behind
    ahead=$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
    behind=$(git rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)
    [ "$ahead" -gt 0 ] && echo -e "  📤 领先   : \033[33m${ahead}\033[0m 个提交（未推送）"
    [ "$behind" -gt 0 ] && echo -e "  📥 落后   : \033[31m${behind}\033[0m 个提交（需拉取）"

    echo -e "  ─────────────────────────────────"
    echo -e "  \033[90m贡献者:\033[0m"
    git shortlog -sn </dev/null 2>/dev/null | head -5 | awk '{print "    "$0}'
    echo ""
}

# ══════════════════════════════════════════
#  🌐  查看远程仓库文件（rls）
# ══════════════════════════════════════════
_rls_remote() {
    if [ -z "${1:-}" ]; then
        echo -e "\033[31m❌ 用法: rls 用户名/仓库名\033[0m"
        return 1
    fi

    if ! command -v gh &>/dev/null; then
        echo -e "\033[31m❌ 需要 gh CLI，先执行 setup\033[0m"
        return 1
    fi

    local repo="${1:-}"
    echo -e "\033[1;36m🌐 仓库: $repo\033[0m\n"

    gh api "repos/$repo/contents" \
        --jq '.[] | "📄 \(.name)\t\(.type)"' 2>/dev/null || {
        echo -e "\033[31m❌ 获取失败（仓库不存在或未登录）\033[0m"
    }
}
