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

    # v5.2 防冲突检测（计划书 9.x）：fetch 为只读操作，只获取远程
    #     信息，绝不触碰本地代码与未提交改动
    local _fz_force_push=0
    local upstream_ref
    upstream_ref=$(git rev-parse --abbrev-ref "@{u}" 2>/dev/null)
    if [ -n "$upstream_ref" ] && git fetch --quiet 2>/dev/null; then
        local behind
        behind=$(git rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)
        if [ "$behind" -gt 0 ]; then
            echo -e "\n\033[1;33m⚠️  本地落后远程 ${behind} 个提交（远程可能有流水线/定时任务自动提交）\033[0m"
            echo -e "\n\033[1;36m  📜 远程新增提交:\033[0m"
            git --no-pager log "HEAD..@{u}" --format="    %h %s" 2>/dev/null | head -10
            [ "$behind" -gt 10 ] && echo -e "    \033[90m... 其余 $((behind - 10)) 条省略\033[0m"
            echo -e "\n\033[1;36m  📄 这些提交涉及的文件:\033[0m"
            git diff --name-status "HEAD" "@{u}" 2>/dev/null | head -15 | sed 's/^/    /'
            git diff --stat "HEAD" "@{u}" 2>/dev/null | tail -n 1 | sed 's/^/    /'
            local local_dirty
            local_dirty=$(git status -s 2>/dev/null | wc -l | tr -d ' ')
            if [ "$local_dirty" -gt 0 ]; then
                echo -e "\n  \033[33m💡 你本地还有 ${local_dirty} 个文件的未提交改动（未 commit，不包含在上面的对比里）\033[0m"
            fi
            echo -e "\n  \033[33m[1]\033[0m 先拉取合并再推送（推荐，走智能 pull 保护流程）"
            echo -e "  \033[33m[2]\033[0m 强制推送（以本地为准覆盖远程，安全模式 --force-with-lease）"
            echo -e "  \033[33m[3]\033[0m 取消，我自己处理"
            read -p "请选择 (回车=1): " _sync_choice
            case "${_sync_choice:-1}" in
                1)
                    if _pull_now; then
                        echo -e "\033[32m✅ 已同步远程，继续推送流程\033[0m"
                    else
                        echo -e "\033[33m💡 同步未完成（可能有冲突），执行 \033[36mfix\033[0m 可引导解决；解决后重新执行 \033[36mp\033[0m\033[0m"
                        return 1
                    fi
                    ;;
                2)
                    read -p "⚠️ 强推将以本地为准覆盖远程，远程上那 ${behind} 个新提交会被覆盖，确认？(y/n): " _fconfirm
                    if [[ "$_fconfirm" == "y" || "$_fconfirm" == "Y" ]]; then
                        _fz_force_push=1
                    else
                        echo -e "\033[90m已取消\033[0m"
                        return 1
                    fi
                    ;;
                *)
                    echo -e "\033[90m已取消，可先执行 \033[36mst\033[0m 查看状态、\033[36minfo\033[0m 查看详情\033[0m"
                    return 1
                    ;;
            esac
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
        # v5.1：基于当前 FZ_VERSION 主版本递增（修复 v5.0 下写死 4. 的降级 bug）
        local cur_ver="${FZ_VERSION:-5.0}"
        local major_ver="${cur_ver%%.*}"
        major_ver="${major_ver:-5}"
        local commit_count=$(git rev-list --count HEAD 2>/dev/null || echo 0)
        next_sub_ver=$((commit_count + 1))
        next_version="${major_ver}.${next_sub_ver}"
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

    # v5.1：无参数时提供默认备注确认，避免"⚡ update"直接提交不可改
    if [ -z "$msg" ]; then
        local def_msg="⚡ update: $(date '+%m-%d %H:%M')"
        read -p "备注（回车使用默认: ${def_msg}）: " custom_msg
        msg="${custom_msg:-$def_msg}"
    fi

    echo -e "\033[34m\n🚀 推送至 \033[1m${b_name}\033[0m\033[34m | 备注: ${msg}${skip_ci_flag}\033[0m"

    git commit -m "${msg}${skip_ci_flag}" 2>/dev/null || {
        echo -e "\033[33m⚠️ commit 无新变化，尝试直接推送\033[0m"
    }

    local push_ok=0
    local -a _push_args=(origin "${b_name}")
    [ "$_fz_force_push" -eq 1 ] && _push_args+=("--force-with-lease")
    if ! git push "${_push_args[@]}" 2>/dev/null; then
        echo -e "\033[33m🔧 尝试设置上游分支...\033[0m"
        git push -u origin "${b_name}" && push_ok=1
    else
        push_ok=1
    fi

    if [ "$push_ok" -eq 0 ]; then
        echo -e "\033[31m❌ 推送被远程拒绝！\033[0m"
        echo -e "\033[33m💡 常见原因：远程有你没有的新提交（如流水线自动任务）\033[0m"
        echo -e "   👉 执行 \033[36mpull\033[0m 拉取合并后重新 \033[36mp\033[0m，或 \033[36mst\033[0m 查看状态"
        return 1
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
