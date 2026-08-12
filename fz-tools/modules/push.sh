#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — push.sh（推送模块）
#  职责：自动暂存所有变更 / AI 生成 commit message / 推送远端
#  包含函数：_p_push  _ai_commit_msg
#  对应别名：p（支持 skip 跳过 CI）
#  ⚠️ v4.0 适配：scripts 仓库的版本号自增逻辑改为
#     定位 fz-tools/fzgit.sh（兼容旧根目录位置）
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

# ══════════════════════════════════════════
#  🤖  AI 生成 commit message
# ══════════════════════════════════════════
_ai_commit_msg() {
    [ -z "$FZ_AI_KEY" ] && return 1
    ! command -v curl &>/dev/null && return 1

    local diff_content=$(git diff --staged --stat 2>/dev/null)
    local diff_detail=$(git diff --staged 2>/dev/null | head -200)

    [ -z "$diff_content" ] && return 1

    echo -e "\033[90m🤖 AI 分析中...\033[0m" >&2

    local prompt="根据以下 git diff 内容，生成一条简洁的中文 commit message。
格式：<类型>: <简短描述>（不超过50字）
类型参考：feat/fix/refactor/style/docs/chore
只输出 commit message 本身，不要任何解释、引号或多余内容。

文件变更统计：
${diff_content}

代码差异（部分）：
${diff_detail}"

    local escaped_prompt
    escaped_prompt=$(_json_escape "$prompt")

    local response
    response=$(curl -s --max-time 15 "https://api.anthropic.com/v1/messages" \
        -H "x-api-key: ${FZ_AI_KEY}" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d "{
            \"model\": \"claude-haiku-4-5-20251001\",
            \"max_tokens\": 100,
            \"messages\": [{\"role\": \"user\", \"content\": ${escaped_prompt}}]
        }" 2>/dev/null)

    local msg=""
    if command -v python3 &>/dev/null; then
        msg=$(echo "$response" | python3 -c "
import json,sys
data=json.load(sys.stdin)
print(data['content'][0]['text'].strip())
" 2>/dev/null)
    elif command -v jq &>/dev/null; then
        msg=$(echo "$response" | jq -r '.content[0].text' 2>/dev/null)
    else
        msg=$(echo "$response" | grep -o '"text":"[^"]*"' | head -1 | sed 's/"text":"//;s/"$//')
    fi

    if [ -n "$msg" ] && [ "$msg" != "null" ]; then
        echo "$msg"
        return 0
    fi
    return 1
}

# ══════════════════════════════════════════
#  🚀  智能推送（p）
# ══════════════════════════════════════════
_p_push() {
    _check_git_repo || return 1

    # v5.0 前置检查：是否在书签项目内（计划书 6.2）
    if ! _bm_current >/dev/null; then
        echo -e "\033[33m⚠️ 当前目录不在任何书签项目内\033[0m"
        read -p "是否继续推送？(y/n): " _cont
        if [[ "$_cont" != "y" && "$_cont" != "Y" ]]; then
            echo -e "\033[90m已取消\033[0m"
            return 1
        fi
    fi

    _git_auto_ignore

    local b_name=$(git branch --show-current)

    echo -e "\033[36m📋 变更文件:\033[0m"
    git status -s

    local change_count
    change_count=$(git status -s 2>/dev/null | wc -l | tr -d ' ')

    if [ "$change_count" -eq 0 ]; then
        local ahead
        ahead=$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
        if [ "$ahead" -gt 0 ]; then
            echo -e "\033[33m📤 检测到 $ahead 个未推送的提交，直接推送...\033[0m"
            if git push origin "$b_name"; then
                echo -e "\033[32m✅ 已推送到远程仓库 [\033[1m$(git remote get-url origin 2>/dev/null || echo origin)\033[0m]\033[0m"
            fi
        else
            echo -e "\033[33m⚠️ 没有任何变更，无需推送\033[0m"
        fi
        return 0
    fi

    local remote_url=$(git remote get-url origin 2>/dev/null | tr '[:upper:]' '[:lower:]')
    local next_version="" next_sub_ver=0 fz_file=""

    # v4.0 重构后主入口位于 fz-tools/fzgit.sh（兼容旧位置）
    if [[ "$remote_url" == *"zzgs219g/scripts"* ]]; then
        for cand in fz-tools/fzgit.sh fzgit.sh; do
            [ -f "$cand" ] && fz_file="$cand" && break
        done
    fi

    if [ -n "$fz_file" ]; then
        local commit_count=$(git rev-list --count HEAD 2>/dev/null || echo 0)
        next_sub_ver=$((commit_count + 1))
        next_version="4.${next_sub_ver}"
        sed -i "s/FZ_VERSION=\"[^\"]*\"/FZ_VERSION=\"${next_version}\"/g" "$fz_file"
        echo -e "\033[35m✨ [焚诀算法阵] 历史提交 ${commit_count} 次，正在以 v${next_version} 准备上架...\033[0m"
    fi

    git add .

    local skip_ci_flag=""

    # 如果第一个参数输入的是 skip，就做好标记，并把变量换成第 2 个参数
    if [ "${1:-}" = "skip" ]; then
        skip_ci_flag=" [skip ci]"
        set -- "${2:-}"
    fi

    local msg=""
    if [ -n "${1:-}" ]; then
        msg="${1:-}"
    elif [ -n "$FZ_AI_KEY" ] && command -v curl &>/dev/null; then
        msg=$(_ai_commit_msg)
        if [ -n "$msg" ]; then
            echo -e "\033[90m💡 AI建议: \033[0m\033[1m${msg}\033[0m"
            read -p "使用此备注？(回车确认 / 输入自定义): " custom_msg
            [ -n "$custom_msg" ] && msg="$custom_msg"
        fi
    fi

    [ -z "$msg" ] && msg="⚡ update: $(date '+%m-%d %H:%M')"

    echo -e "\033[34m\n🚀 推送至 \033[1m${b_name}\033[0m\033[34m | 备注: ${msg}${skip_ci_flag}\033[0m"

    git commit -m "${msg}${skip_ci_flag}" 2>/dev/null || {
        echo -e "\033[33m⚠️ commit 无新变化，尝试直接推送\033[0m"
    }

    local push_ok=0
    if ! git push origin "${b_name}" 2>/dev/null; then
        echo -e "\033[33m🔧 尝试设置上游分支...\033[0m"
        git push -u origin "${b_name}" && push_ok=1
    else
        push_ok=1
    fi

    if [ "$push_ok" -eq 1 ]; then
        local remote_name
        remote_name=$(git remote get-url origin 2>/dev/null || echo "origin")
        echo -e "\033[32m✅ 已推送到远程仓库 [\033[1m${remote_name}\033[0m\033[32m] | ${change_count} 个文件变更\033[0m"
        if [ -n "$fz_file" ]; then
            echo -e "\033[35m💡 远程已更新至 v${next_version}，执行 \033[1mup\033[0m\033[35m 可更新本地环境\033[0m"
        fi
    else
        echo -e "\033[31m❌ 推送失败！\033[0m"
    fi
}
