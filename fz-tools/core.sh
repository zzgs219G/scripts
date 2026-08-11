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
    local s="$1"
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
