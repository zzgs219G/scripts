#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — push.sh（推送模块）
#  职责：智能推送（防冲突检测 / 多远程 / AI 备注 / 统一失败引导）
#  包含函数：_fz_parse_push_args  _p_push  _fz_ensure_upstream
#            _fz_other_remotes_hint  _fz_push_rejected_guide
#  对应别名：p
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

# ══════════════════════════════════════════
#  🧩  p 参数解析
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

    # ── 前置检查：Git 作者身份 ──
    #  gh login（认证/推送权限）≠ setup（署名），是两套独立配置。
    #  缺署名时 commit 必然失败，若等到 commit 阶段才发现，报错会埋在
    #  git 输出里；这里前置拦截，给出可直接照做的引导。
    if [ -z "$(git config user.name 2>/dev/null)" ] || [ -z "$(git config user.email 2>/dev/null)" ]; then
        echo -e "\033[31m❌ Git 作者身份未配置（user.name / user.email），无法提交\033[0m"
        echo -e "\033[90m💡 已 gh login ≠ 已配置署名。执行 \033[36msetup\033[0m\033[90m 一键配置即可\033[0m"
        return 1
    fi

    _fz_parse_push_args "$@"
    if [ "$FZ_PARSE_REMOTE_MISSING" -eq 1 ]; then
        echo -e "\033[31m❌ 远程 \"${FZ_PARSE_REMOTE}\" 未绑定，执行 \033[1mremote\033[0m\033[31m 可绑定\033[0m"
        return 1
    fi
    local _fz_remote="$FZ_PARSE_REMOTE"
    local _fz_msg_arg="$FZ_PARSE_MSG"
    local skip_ci_flag=""
    [ "$FZ_PARSE_SKIP" -eq 1 ] && skip_ci_flag=" [skip ci]"

    # 指定远程时明示目标（p cnb / p gitee）；不带参数走 origin
    if [ "$_fz_remote" != "origin" ]; then
        echo -e "\033[36m🎯 本次推送到远程: \033[1m${_fz_remote}\033[0m \033[90m($(git remote get-url "$_fz_remote"))\033[0m"
    fi

    # 不在书签项目内时先确认（避免误推到家目录等非项目位置）
    if ! _bm_current >/dev/null; then
        echo -e "\033[33m⚠️ 当前目录不在任何书签项目内\033[0m"
        read -rp "是否继续推送？(y/n): " _cont
        if [[ "$_cont" != "y" && "$_cont" != "Y" ]]; then
            echo -e "\033[90m已取消\033[0m"
            return 1
        fi
    fi

    local b_name
    b_name=$(git branch --show-current)

    # ── 防冲突检测的基准必须是「本次目标远程」，不能是 @{u} ──
    #  一个项目可能同时绑多个远程（如 origin=GitHub、cnb=CNB），而分支的
    #  上游只指向其中一个。若用 @{u} 判断，就会对另一个远程看错对象：
    #  落后检测、『是否需要推送』全都基于错误的分支，结果是对 GitHub
    #  假报『没有变更，无需推送』并直接返回——代码永远推不上去。
    #  fetch 是只读操作，只取远程信息，不碰本地代码与未提交改动。
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
            read -rp "请选择 (回车=1): " _sync_choice
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
                    read -rp "⚠️ 强推将以本地为准覆盖远程，远程上那 ${behind} 个新提交会被覆盖，确认？(y/n): " _fconfirm
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

    # 判定「要不要推」同样只看目标远程（理由见上方基准说明）：
    #   目标远程尚无该分支 → 首推；目标远程落后 → 存在未推送提交。
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

    # ⚠️ 版本号不在这里改写。发版请用 `bash version.sh bump`。
    #   在推送流程里用 commit count 覆盖 FZ_VERSION 会带来三个问题：
    #   每次推送必然多一次「版本号变动」提交、版本号与内容脱钩、
    #   多分支并行时这行 sed 是固定冲突源。

    git add .

    # 凭据护栏：暂存区里若出现疑似 Key 立即中止（见 core.sh 说明）
    # 中止时撤销本次暂存，避免明文凭据留在索引里被随手 git commit 带走。
    if ! _fz_guard_staged_secrets; then
        if git rev-parse HEAD >/dev/null 2>&1; then
            git reset -q 2>/dev/null
        else
            git rm -r --cached -q . >/dev/null 2>&1   # 空仓库无 HEAD，reset 不可用
        fi
        echo -e "\033[90m已撤销本次暂存，文件内容未改动\033[0m"
        return 1
    fi

    local msg=""
    if [ -n "${_fz_msg_arg:-}" ]; then
        msg="${_fz_msg_arg}"
    elif _fz_ai_ready; then
        # AI 备注是可选项：只在配置完整时才发请求（见 ai.sh 的数据流向说明）
        msg=$(_fz_ai_commit_msg)
        if [ -n "$msg" ]; then
            echo -e "\033[90m💡 AI建议: \033[0m\033[1m${msg}\033[0m"
            read -rp "使用此备注？(回车确认 / 输入自定义): " custom_msg
            [ -n "$custom_msg" ] && msg="$custom_msg"
        fi
    fi

    # 无备注参数时给默认值并允许修改，不静默提交固定文案
    if [ -z "$msg" ]; then
        local def_msg
        def_msg="⚡ update: $(date '+%m-%d %H:%M')"
        read -rp "备注（回车使用默认: ${def_msg}）: " custom_msg
        msg="${custom_msg:-$def_msg}"
    fi

    echo -e "\033[34m\n🚀 推送至 \033[1m${b_name}\033[0m\033[34m | 备注: ${msg}${skip_ci_flag}\033[0m"

    # ── 提交失败必须如实报告 ──
    #  `git commit` 的 stderr 不能丢掉：像 user.name/email 缺失这类硬失败
    #  会被误当成『无变更』继续推送，最后假报『推送成功』而代码根本没进提交。
    #  这里区分两种情况：真无变更 vs 真失败。
    local _commit_out
    if ! _commit_out=$(git commit -m "${msg}${skip_ci_flag}" 2>&1); then
        if echo "$_commit_out" | grep -qiE "nothing to commit|no changes added to commit"; then
            echo -e "\033[33m⚠️ 无新变更，尝试直接推送\033[0m"
        else
            echo -e "\033[31m❌ 提交失败（代码未进入任何提交）：\033[0m"
            echo "$_commit_out" | head -5 | sed 's/^/  \033[90m/'
            echo -e "\033[0m"
            return 1
        fi
    fi

    local -a _push_args=("$_fz_remote" "$b_name")
    [ "$_fz_force_push" -eq 1 ] && _push_args+=("--force-with-lease")
    # ── 推送只尝试一次，失败即进入统一诊断 ──
    #  不做 `git push -u` 重试：那会把当前分支的上游静默改成本次远程，
    #  多远程项目下会造成『上游漂移』。上游由 _fz_ensure_upstream 收敛为
    #  『仅当尚无上游时才建立跟踪』。
    #  也不做『--amend 补 [skip ci] 后重试』：那会擅自改写用户提交，
    #  HEAD 是 merge 提交时更会破坏其父节点，风险远大于收益。
    #  首推场景 `git push <远程> <分支>` 本身即可创建远程分支，无需 -u。
    if ! git push "${_push_args[@]}" 2>/dev/null; then
        _fz_push_rejected_guide "$_fz_remote" "$b_name"
        return 1
    fi

    # 推送成功且当前分支尚无上游时才建立跟踪；已有上游绝不改写
    _fz_ensure_upstream "$_fz_remote" "$b_name"

    local remote_name
    remote_name=$(git remote get-url "$_fz_remote" 2>/dev/null || echo "$_fz_remote")
    echo -e "\033[32m✅ 已推送到远程仓库 [\033[1m${remote_name}\033[0m\033[32m] | ${change_count} 个文件变更\033[0m"
    _fz_other_remotes_hint "$_fz_remote" "$b_name"
}

# ══════════════════════════════════════════
#  🌿  按需建立上游跟踪
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
#  📡  多远程未同步提示
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
#  🧭  推送被拒统一引导
#  push 失败时自动诊断原因，最常见的是「本地新项目 vs 远程已有内容」
#  （unrelated histories）——旧版只会让用户去 pull，而 pull 对这种
#  情况同样被拒，用户（不会 git 指令）就彻底卡死。现在自动修复。
# ══════════════════════════════════════════
_fz_push_rejected_guide() {
    local _fz_remote="${1:-origin}" b_name="${2:-$(git branch --show-current)}"
    local r_url
    r_url=$(git remote get-url "$_fz_remote" 2>/dev/null || echo "$_fz_remote")

    echo -e "\n\033[31m❌ 推送到 $r_url 被拒绝\033[0m"

    # ── 先确认能否连上远程，再谈诊断 ──
    #  fetch 失败（网络/SSL/凭据）时，本地的 $remote/$branch 只是过期快照，
    #  基于它判断『落后 / 无共同历史』必然误判——一次网络抖动就曾被误报成
    #  『无共同历史』并触发自动 merge。连不上就明确报告并终止，
    #  绝不进入依赖远程信息的诊断分支。
    if ! git fetch --quiet "$_fz_remote" 2>/dev/null; then
        echo -e "\033[1;33m诊断结果：无法连接远程（网络不通 / SSL 中断 / 凭据失效）\033[0m"
        echo -e "  · 先检查网络，恢复后重试 \033[36mp\033[0m"
        echo -e "  · 网络正常仍失败 → 令牌可能过期，重新 \033[36mlogin\033[0m"
        return 1
    fi

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
