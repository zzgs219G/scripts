#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — push.sh（推送模块）
#  职责：自动暂存所有变更 / AI 生成 commit message / 推送远端
#  包含函数：_p_push  _ai_commit_msg  _fz_parse_push_args
#            _fz_ensure_upstream  _fz_other_remotes_hint  _fz_push_rejected_guide
#  对应别名：p（支持 skip 跳过 CI / 远程名 / "备注"）
#  ⚠️ v5.100 核心修复（多远程假"无需推送"）：
#     判断基准从 @{u}（当前分支上游）改为「本次目标远程 $_fz_remote/$b_name」。
#     旧版当上游指向另一个远程（如 cnb）时，ahead 恒为 0 → 假报
#     "没有任何变更，无需推送"并直接 return，git push origin 从未执行，
#     GitHub 永远停在旧版。
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
#  🧩  p 参数解析（v5.100 修复 p "备注" 失效）
#  支持顺序自由组合：
#    p                  p cnb            p "备注"
#    p skip             p cnb skip       p skip "备注"
#    p -r cnb -m "备注"
#  规则：第一个非选项参数 —— 是已绑定远程名 → 视为远程，否则视为 commit 备注。
#       （"origin" 例外：即使未绑定也按远程处理，好给出明确报错）
#  输出：FZ_PARSE_REMOTE / FZ_PARSE_MSG / FZ_PARSE_SKIP / FZ_PARSE_REMOTE_MISSING
# ══════════════════════════════════════════
_fz_parse_push_args() {
    FZ_PARSE_REMOTE="origin"
    FZ_PARSE_MSG=""
    FZ_PARSE_SKIP=0
    FZ_PARSE_REMOTE_MISSING=0
    local explicit_r="" want_msg=""
    local expect_r=0 expect_m=0 arg
    for arg in "$@"; do
        [ -z "$arg" ] && continue
        if [ "$expect_r" -eq 1 ]; then explicit_r="$arg"; expect_r=0; continue; fi
        if [ "$expect_m" -eq 1 ]; then want_msg="$arg";    expect_m=0; continue; fi
        case "$arg" in
            -r|--remote) expect_r=1 ;;
            -m|--msg)    expect_m=1 ;;
            skip)        FZ_PARSE_SKIP=1 ;;
            -*)          ;;   # 未知选项忽略，保持向后兼容
            *)
                if git remote get-url "$arg" >/dev/null 2>&1 || [ "$arg" = "origin" ]; then
                    [ -z "$explicit_r" ] && explicit_r="$arg"
                elif [ -z "$want_msg" ]; then
                    want_msg="$arg"     # 不是已绑定远程 → 当作 commit 备注
                fi
                ;;
        esac
    done
    FZ_PARSE_MSG="$want_msg"
    if [ -n "$explicit_r" ]; then
        FZ_PARSE_REMOTE="$explicit_r"
        git remote get-url "$explicit_r" >/dev/null 2>&1 || FZ_PARSE_REMOTE_MISSING=1
    fi
    return 0
}

# ══════════════════════════════════════════
#  🚀  智能推送（p）
# ══════════════════════════════════════════
_p_push() {
    _check_git_repo || return 1

    # v5.100：参数解析接入（修复 p "备注" 被误判为远程名而报错）
    _fz_parse_push_args "$@"
    if [ "$FZ_PARSE_REMOTE_MISSING" -eq 1 ]; then
        echo -e "\033[31m❌ 远程 \"${FZ_PARSE_REMOTE}\" 未绑定，执行 \033[1mremote\033[0m\033[31m 可绑定\033[0m"
        return 1
    fi
    local _fz_remote="$FZ_PARSE_REMOTE"
    local _fz_msg_arg="$FZ_PARSE_MSG"
    local skip_ci_flag=""
    [ "$FZ_PARSE_SKIP" -eq 1 ] && skip_ci_flag=" [skip ci]"

    # v5.97：p 远程名 —— 一键推送到指定远程（如 p cnb / p gitee）
    # 不带参数 = 走 origin（默认行为不变）
    if [ "$_fz_remote" != "origin" ]; then
        echo -e "\033[36m🎯 本次推送到远程: \033[1m${_fz_remote}\033[0m \033[90m($(git remote get-url "$_fz_remote"))\033[0m"
    fi

    # v5.0 前置检查：是否在书签项目内（计划书 6.2）
    if ! _bm_current >/dev/null; then
        echo -e "\033[33m⚠️ 当前目录不在任何书签项目内\033[0m"
        read -p "是否继续推送？(y/n): " _cont
        if [[ "$_cont" != "y" && "$_cont" != "Y" ]]; then
            echo -e "\033[90m已取消\033[0m"
            return 1
        fi
    fi

    local b_name
    b_name=$(git branch --show-current)

    # v5.100 核心修复：防冲突检测改为以「本次推送的目标远程」为基准
    #  旧版用 @{u}（当前分支上游）：当上游指向另一个远程（如 cnb）时，
    #  落后检测与"是否需要推送"全都看错了对象，导致 p origin 假报
    #  "没有任何变更，无需推送"并直接返回，git push origin 从未执行。
    #  fetch 仍为只读操作，只获取远程信息，绝不触碰本地代码与未提交改动。
    local _fz_force_push=0
    local _fz_target_ref="$_fz_remote/$b_name"
    local _fz_have_target=0
    if git fetch --quiet "$_fz_remote" 2>/dev/null; then
        git rev-parse --verify --quiet "$_fz_target_ref" >/dev/null 2>&1 && _fz_have_target=1
    fi
    if [ "$_fz_have_target" -eq 1 ]; then
        local behind
        behind=$(git rev-list --count "HEAD..$_fz_target_ref" 2>/dev/null || echo 0)
        if [ "$behind" -gt 0 ]; then
            echo -e "\n\033[1;33m⚠️  本地落后远程 [${_fz_remote}] ${behind} 个提交（远程可能有流水线/定时任务自动提交）\033[0m"
            echo -e "\n\033[1;36m  📜 远程新增提交:\033[0m"
            git --no-pager log "HEAD..$_fz_target_ref" --format="    %h %s" 2>/dev/null | head -10
            [ "$behind" -gt 10 ] && echo -e "    \033[90m... 其余 $((behind - 10)) 条省略\033[0m"
            echo -e "\n\033[1;36m  📄 这些提交涉及的文件:\033[0m"
            git diff --name-status "HEAD" "$_fz_target_ref" 2>/dev/null | head -15 | sed 's/^/    /'
            git diff --stat "HEAD" "$_fz_target_ref" 2>/dev/null | tail -n 1 | sed 's/^/    /'
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
                    if _pull_now "$_fz_remote"; then
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

    echo -e "\033[36m📋 变更文件:\033[0m"
    git status -s

    local change_count
    change_count=$(git status -s 2>/dev/null | wc -l | tr -d ' ')

    # v5.100 核心修复：判定基准从 @{u} 改为「本次目标远程 $_fz_target_ref」
    #   · 目标远程尚无该分支 → 首推，必须推
    #   · 目标远程落后 → 存在未推送提交，必须推
    #  （旧版看 @{u}：上游指向 cnb 时此处恒为 0，于是假报"无需推送"直接 return）
    local _fz_ahead=0
    if [ "$_fz_have_target" -eq 1 ]; then
        _fz_ahead=$(git rev-list --count "$_fz_target_ref..HEAD" 2>/dev/null || echo 0)
    fi

    if [ "$change_count" -eq 0 ]; then
        if ! git remote get-url "$_fz_remote" >/dev/null 2>&1; then
            echo -e "\033[33m⚠️ 没有本地变更，且远程 [${_fz_remote}] 未绑定，无需推送\033[0m"
            echo -e "\033[90m💡 执行 \033[36mremote\033[0m\033[90m 绑定远程后再推送\033[0m"
            return 0
        elif [ "$_fz_have_target" -eq 0 ]; then
            echo -e "\033[33m📤 远程 [${_fz_remote}] 还没有 ${b_name} 分支，执行首次推送...\033[0m"
            if git push -u "$_fz_remote" "$b_name"; then
                echo -e "\033[32m✅ 已推送到远程仓库 [\033[1m$(git remote get-url "$_fz_remote" 2>/dev/null || echo "$_fz_remote")\033[0m]\033[0m"
            else
                _fz_push_rejected_guide "$_fz_remote" "$b_name"
                return 1
            fi
        elif [ "$_fz_ahead" -gt 0 ]; then
            echo -e "\033[33m📤 检测到 ${_fz_ahead} 个未推送的提交，直接推送...\033[0m"
            local -a _fz_fast_args=("$_fz_remote" "$b_name")
            [ "$_fz_force_push" -eq 1 ] && _fz_fast_args+=("--force-with-lease")
            if git push "${_fz_fast_args[@]}"; then
                echo -e "\033[32m✅ 已推送到远程仓库 [\033[1m$(git remote get-url "$_fz_remote" 2>/dev/null || echo "$_fz_remote")\033[0m]\033[0m"
            else
                _fz_push_rejected_guide "$_fz_remote" "$b_name"
                return 1
            fi
        else
            echo -e "\033[32m✅ 已是最新：远程 [${_fz_remote}] 的 ${b_name} 与本地一致，无需推送\033[0m"
        fi
        _fz_other_remotes_hint "$_fz_remote" "$b_name"
        return 0
    fi

    local remote_url=$(git remote get-url "$_fz_remote" 2>/dev/null | tr '[:upper:]' '[:lower:]')
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

    local msg=""
    if [ -n "${_fz_msg_arg:-}" ]; then
        msg="${_fz_msg_arg}"
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

    local -a _push_args=("$_fz_remote" "$b_name")
    [ "$_fz_force_push" -eq 1 ] && _push_args+=("--force-with-lease")
    # v5.100：push 只尝试一次，失败即进入统一诊断。
    #   旧版此处会再 `git push -u` 重试——那会把当前分支的上游静默改写成本次
    #   远程（缺陷 1 的成因之一）；现由 _fz_ensure_upstream 收敛为
    #   「仅当尚无上游时才建立跟踪」。
    #   另：不再做「--amend 补 [skip ci] 后重试」——那会擅自改写用户的提交
    #   （HEAD 为 merge 提交时更会破坏其父节点），风险远大于收益。
    #   首推场景 `git push <远程> <分支>` 本身即可创建远程分支，无需 -u。
    if ! git push "${_push_args[@]}" 2>/dev/null; then
        # v5.99：被拒不再甩一句"去 pull"就结束，进入统一引导
        _fz_push_rejected_guide "$_fz_remote" "$b_name"
        return 1
    fi

    # v5.100：推送成功且当前分支尚无上游时才建立跟踪；已有上游绝不改写
    _fz_ensure_upstream "$_fz_remote" "$b_name"

    local remote_name
    remote_name=$(git remote get-url "$_fz_remote" 2>/dev/null || echo "$_fz_remote")
    echo -e "\033[32m✅ 已推送到远程仓库 [\033[1m${remote_name}\033[0m\033[32m] | ${change_count} 个文件变更\033[0m"
    if [ -n "$fz_file" ]; then
        echo -e "\033[35m💡 远程已更新至 v${next_version}，执行 \033[1mup\033[0m\033[35m 可更新本地环境\033[0m"
    fi
    _fz_other_remotes_hint "$_fz_remote" "$b_name"
}

# ══════════════════════════════════════════
#  🌿  按需建立上游跟踪（v5.100 新增）
#  仅当当前分支还没有上游时设置；已有上游绝不改写，
#  避免把 origin 静默换成 cnb（旧版 git push -u 的副作用）
# ══════════════════════════════════════════
_fz_ensure_upstream() {
    local r="${1:-origin}" b="${2:-$(git branch --show-current)}"
    git rev-parse --abbrev-ref "@{u}" >/dev/null 2>&1 && return 0
    git branch --set-upstream-to="${r}/${b}" "$b" >/dev/null 2>&1 \
        && echo -e "\033[90m🔗 已建立跟踪: ${b} → ${r}/${b}\033[0m"
    return 0
}

# ══════════════════════════════════════════
#  📡  多远程未同步提示（v5.100 新增）
#  推完目标远程后，若其他远程该分支仍落后 / 尚无该分支，仅提示不自动推，
#  避免用户以为"推了一次就全平台同步"（本次 bug 的认知来源）
# ══════════════════════════════════════════
_fz_other_remotes_hint() {
    local target="$1" b="${2:-$(git branch --show-current)}" r
    for r in $(git remote 2>/dev/null); do
        [ "$r" = "$target" ] && continue
        if ! git rev-parse --verify --quiet "$r/$b" >/dev/null 2>&1; then
            # 本地无该远程记录时不断言"没有"，只提示可能未同步
            # （该远程可能尚未 fetch，避免误报）
            echo -e "\033[90m📡 远程 [${r}] 未同步（本地无记录），如需推送: \033[36mp ${r}\033[0m"
        elif ! git merge-base --is-ancestor HEAD "$r/$b" 2>/dev/null; then
            local n
            n=$(git rev-list --count "$r/$b..HEAD" 2>/dev/null || echo 0)
            [ "$n" -gt 0 ] && echo -e "\033[90m📡 远程 [${r}] 还落后 ${n} 个提交，如需同步: \033[36mp ${r}\033[0m"
        fi
    done
    return 0
}

# ══════════════════════════════════════════
#  🧭  推送被拒统一引导（v5.99 新增，报错记录核心 bug）
#  push 失败时自动诊断原因，最常见的是「本地新项目 vs 远程已有内容」
#  （unrelated histories）——旧版只会让用户去 pull，而 pull 对这种
#  情况同样被拒，用户（不会 git 指令）就彻底卡死。现在自动修复。
# ══════════════════════════════════════════
_fz_push_rejected_guide() {
    local _fz_remote="${1:-origin}" b_name="${2:-$(git branch --show-current)}"
    local r_url
    r_url=$(git remote get-url "$_fz_remote" 2>/dev/null || echo "$_fz_remote")

    echo -e "\n\033[31m❌ 推送到 $r_url 被拒绝\033[0m"
    git fetch --quiet "$_fz_remote" 2>/dev/null

    # 诊断 1：远程分支存在但与本地无共同祖先（首推撞上自动生成 README 等）
    if git rev-parse --verify --quiet "$_fz_remote/$b_name" >/dev/null 2>&1 \
        && ! git merge-base --quiet HEAD "$_fz_remote/$b_name" 2>/dev/null; then
        echo -e "\033[1;33m诊断结果：远程已有内容，但与本地没有任何共同历史\033[0m"
        _fz_unrelated_history_guide "$b_name" "$_fz_remote"
        return
    fi

    # 诊断 2：本地落后远程（正常 fetch first 场景）→ 走既有智能拉取
    local behind
    behind=$(git rev-list --count "HEAD..$_fz_remote/$b_name" 2>/dev/null || echo 0)
    if [ "$behind" -gt 0 ]; then
        echo -e "\033[1;33m诊断结果：本地落后远程 $behind 个提交\033[0m"
        echo -e "\033[36m👉 自动执行安全拉取（pull 保护流程）...\033[0m"
        if _pull_now "$_fz_remote"; then
            echo -e "\033[36m👉 已同步，重新推送...\033[0m"
            git push "$_fz_remote" "$b_name" \
                && echo -e "\033[32m✅ 推送成功\033[0m" \
                || echo -e "\033[31m❌ 仍失败，执行 \033[36mfix\033[0m 排查\033[0m"
        fi
        return
    fi

    # 诊断 3：兜底（凭据/网络/分支保护等）
    echo -e "\033[1;33m诊断结果：非历史冲突类问题，常见原因：\033[0m"
    echo -e "  · 凭据失效（HTTPS 令牌过期）→ 重新 \033[36mlogin\033[0m"
    echo -e "  · 分支保护规则（远程禁 push）→ 检查平台仓库设置"
    echo -e "  · 网络不通 → \033[36mst\033[0m 看状态后重试"
}
