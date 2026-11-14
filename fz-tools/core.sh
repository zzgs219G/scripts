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
# 供 c 进入项目、b 切换分支等场景复用
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

# 凭据护栏：`p` 前检查暂存区，命中疑似凭据的文件就拦下来
# 为什么需要：`p` 会执行 `git add .`，若某处代码把 Key 写进受追踪的文件
# （历史上 aikey 就曾 sed 进 fz-tools/fzgit.sh），一次推送即公开泄漏。
# 这里只做「已暂存内容」的只读扫描，不改任何文件。
#
# 设计取舍：宁可漏报也不误报。
#   漏报代价 = 回到修复前（本来就无保护）；
#   误报代价 = 用户被拦在门口，最后学会无视这条警告。
# 因此三层过滤：
#   ① 正则先粗筛已知前缀与长度；
#   ② 跳过注释行（文档举例不算）；
#   ③ 熵校验：必须同时含大小写与数字，且不是全同一字符
#      —— 这能放过 sk-ant-placeholder / ghp_xxxxxxx 这类占位符。
# 返回 0 = 未发现; 1 = 发现疑似凭据（已打印命中位置）
_SECRET_PATTERN='(sk-ant-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,}|AIza[A-Za-z0-9_-]{35}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)'

# 熵校验：候选串是否像真实凭据（而非占位符/文档示例）
_fz_looks_like_secret() {
    local tok="$1" body="$1"
    case "$tok" in
        sk-ant-*)    body="${tok#sk-ant-}" ;;
        gh[pousr]_*) body="${tok#*_}" ;;
        github_pat_*) body="${tok#github_pat_}" ;;
        AIza*)       body="${tok#AIza}" ;;
        xox*)        body="${tok#*-}" ;;
        -----*)      return 0 ;;   # 私钥头本身即高危，不做熵校验
    esac
    [ -z "$body" ] && return 1
    # 全同一字符（如 ghp_xxxxxxxx）→ 占位符
    local uniq
    uniq=$(printf '%s' "$body" | fold -w1 2>/dev/null | sort -u 2>/dev/null | wc -l | tr -d ' ')
    [ "${uniq:-0}" -le 2 ] && return 1
    # 真实 token 同时含大写/小写/数字
    printf '%s' "$body" | grep -q '[0-9]' || return 1
    printf '%s' "$body" | grep -q '[A-Z]' || return 1
    printf '%s' "$body" | grep -q '[a-z]' || return 1
    return 0
}

_fz_guard_staged_secrets() {
    git rev-parse --git-dir >/dev/null 2>&1 || return 0

    local hits="" f
    # 逐文件扫描暂存内容，便于报出文件名（git diff --cached 不直接带路径）
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        local cand found=""
        while IFS= read -r cand; do
            [ -z "$cand" ] && continue
            if _fz_looks_like_secret "$cand"; then
                found="$cand"
                break
            fi
        done < <(git diff --cached -U0 -- "$f" 2>/dev/null \
                   | grep -E '^\+' \
                   | grep -vE '^\+\s*#' \
                   | grep -oE "$_SECRET_PATTERN" 2>/dev/null)
        [ -n "$found" ] && hits+="   ${f}  →  ${found:0:12}..."$'\n'
    done < <(git diff --cached --name-only 2>/dev/null)

    if [ -n "$hits" ]; then
        echo -e "\033[31m⛔ 暂存区中发现疑似凭据，已中止推送：\033[0m" >&2
        printf '%s' "$hits" | head -5 >&2
        echo -e "\033[90m   修复：把密钥移出仓库（aikey 现在写入 ~/.fz_ai_key）\033[0m" >&2
        echo -e "\033[90m   若确属误报，可手动 git add + git commit 绕过本检查；\033[0m" >&2
        echo -e "\033[90m   若该 Key 已推送过，请立刻到平台后台轮换。\033[0m" >&2
        return 1
    fi
    return 0
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
