#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — core.sh（内部工具模块）
#  职责：基础环境校验 / JSON 转义 / 自动生成 .gitignore
#  包含函数：_check_git_repo  _git_auto_ignore  _json_escape
#  由 fz-tools/fzgit.sh 自动加载，请勿单独 source
# ════════════════════════════════════════════════════════════

# 校验当前目录是否为 Git 仓库
_check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "\033[31m❌ 当前目录不是 Git 仓库！\033[0m"
        return 1
    fi
}

# 当前 Git 状态摘要（分支 / 变更数 / 领先落后 / 最近提交）
# 供 c 进入项目、b 切换分支等场景复用（v5.1 新增）
_git_status_summary() {
    local b_name changes ahead behind
    b_name=$(git branch --show-current 2>/dev/null)
    changes=$(git status -s 2>/dev/null | wc -l | tr -d ' ')
    ahead=$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
    behind=$(git rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)

    local sum="  🌿 分支: \033[1;33m${b_name:-?}\033[0m | 变更: \033[33m${changes}\033[0m 个文件"
    if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
        sum+=" | 📤${ahead} 📥${behind} \033[1;34m🔵分叉\033[0m"
    elif [ "$ahead" -gt 0 ]; then
        sum+=" | \033[33m📤 领先 ${ahead}\033[0m"
    elif [ "$behind" -gt 0 ]; then
        sum+=" | \033[31m📥 落后 ${behind}\033[0m"
    fi
    echo -e "$sum"

    local last_commit
    last_commit=$(git log -1 --format="%s (%cr)" 2>/dev/null)
    [ -n "$last_commit" ] && echo -e "  \033[90m📌 ${last_commit}\033[0m"
}

# 自动生成 / 补全 .gitignore 护法阵
_git_auto_ignore() {
    local items="build/\n.gradle/\n.idea/\nlocal.properties\n*.log\n.DS_Store\n__pycache__/\n*.pyc\nnode_modules/\ndist/\n.env\n*.class\n*.apk\n*.ipa"
    if [ ! -f .gitignore ]; then
        printf "%b" "$items" > .gitignore
        echo -e "\033[32m🛡️ 已创建 .gitignore 护法阵\033[0m"
    elif ! grep -q "build/" .gitignore 2>/dev/null; then
        printf "\n%b" "$items" >> .gitignore
        echo -e "\033[32m🛡️ 已补全 .gitignore 护法阵\033[0m"
    fi
}

# JSON 转义（优先 python3，退化到纯 bash）
_json_escape() {
    local s="${1:-}"
    if command -v python3 &>/dev/null; then
        printf '%s' "$s" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null
    else
        s="${s//\\/\\\\}"
        s="${s//\"/\\\"}"
        s="${s//$'\n'/\\n}"
        s="${s//$'\t'/\\t}"
        printf '"%s"' "$s"
    fi
}
