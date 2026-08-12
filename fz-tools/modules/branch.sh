#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — branch.sh（分支模块）
#  职责：分支列表/切换/创建/删除、重命名（含远程同步）、
#        清理已合并分支、安全同步、快速回主线
#  包含函数：_branch_mgr  _rename_branch  _clean_branches
#            _sync_branch  _main_branch
#  对应别名：b  rn  bclean  gsync  gomain
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

# ══════════════════════════════════════════
#  🌿  分支管理（b）
# ══════════════════════════════════════════
_branch_mgr() {
    _check_git_repo || return 1

    # v5.0：增加当前所在书签/项目路径提示（计划书 6.1）
    local _bm_cur
    _bm_cur=$(_bm_current)
    if [ -n "$_bm_cur" ]; then
        echo -e "\033[90m📍 书签: \033[36m${_bm_cur}\033[0m\033[90m | 路径: $(pwd)\033[0m"
    else
        echo -e "\033[90m📍 路径: $(pwd)\033[0m"
    fi

    if [ "${1:-}" = "ql" ] || [ "${1:-}" = "clean" ]; then
        echo -e "\033[34m🧹 正在同步远程并清理无效分支缓存（联网中）...\033[0m"
        if git fetch -p; then
            git remote prune origin >/dev/null 2>&1
            echo -e "\033[32m✅ 远程分支缓存清理完毕！本地视界已净化。\033[0m"
        else
            echo -e "\033[31m❌ 联网失败，请检查网络或代理设置\033[0m"
        fi
        return 0
    fi

    if [ "${1:-}" = "all" ]; then
        echo -e "\033[34m📥 正在打捞所有远程分支实体...\033[0m"
        git fetch --all --prune 2>/dev/null

        local n=0
        while IFS= read -r r_br; do
            [ -z "$r_br" ] && continue
            local l_br="${r_br#origin/}"
            if ! git rev-parse --verify "$l_br" >/dev/null 2>&1; then
                git branch --track "$l_br" "origin/$l_br" 2>/dev/null && \
                    echo -e "  \033[32m✔ 已同步镜像:\033[0m $l_br" && \
                    n=$((n + 1))
            fi
        done < <(git branch -r 2>/dev/null | sed 's/^[[:space:]]*//' | grep '^origin/' | grep -v 'origin/HEAD')

        echo -e "\n\033[32m✨ 镜像完成！本地新增 \033[1m${n}\033[0m\033[32m 个分支\033[0m"
        echo -e "💡 用 \033[36mb <名字>\033[0m 切换分支"
        return 0
    fi

    if [ -z "${1:-}" ]; then
        echo -e "\033[1;36m🌿 分支列表:\033[0m"
        local branches=()
        while IFS= read -r line; do
            branches+=("$line")
        done < <(git branch | sed 's/[* ]*//')

        local i=1
        for br in "${branches[@]}"; do
            local cur=$(git branch --show-current)
            if [ "$br" = "$cur" ]; then
                echo -e "  \033[33m$i\033[0m. \033[32m* $br\033[0m \033[90m← 当前\033[0m"
            else
                echo -e "  \033[33m$i\033[0m. $br"
            fi
            i=$((i+1))
        done

        echo -e "  \033[33m${i}\033[0m. \033[36m+ 创建新分支\033[0m"
        echo -e "  \033[33mq\033[0m. 取消\n"
        read -p "选择编号 (回车默认进 dev): " choice

        if [ -z "$choice" ]; then
            git checkout dev 2>/dev/null || git checkout -b dev origin/dev 2>/dev/null || git checkout -b dev
            git branch --set-upstream-to=origin/dev dev &>/dev/null
            echo -e "\033[32m✨ 已进入 dev 实验室\033[0m"
        elif [ "$choice" = "q" ]; then
            return 0
        elif [ "$choice" = "$i" ]; then
            read -p "新分支名: " new_br
            [ -n "$new_br" ] && git checkout -b "$new_br" && \
                echo -e "\033[32m✨ 已创建并进入: $new_br\033[0m"
        else
            if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
                echo -e "\033[31m❌ 请输入有效数字\033[0m"
                return 1
            fi
            local target_br="${branches[$((choice-1))]}"
            if [ -n "$target_br" ]; then
                git checkout "$target_br"
                echo -e "\033[32m✨ 已切换到: $target_br\033[0m"
            else
                echo -e "\033[31m❌ 编号无效\033[0m"
            fi
        fi

    elif [ "${1:-}" = "-l" ] || [ "${1:-}" = "list" ]; then
        echo -e "\033[1;36m🌿 所有分支（含远程）:\033[0m"
        git branch -a --color

    elif [ "${1:-}" = "-d" ] || [ "${1:-}" = "del" ]; then
        local b_del="${2}"
        [ -z "$b_del" ] && read -p "要删除的分支名: " b_del
        read -p "确认删除本地分支 '$b_del'？(y/n): " confirm
        [[ "$confirm" == "y" || "$confirm" == "Y" ]] && \
            git branch -d "$b_del" && \
            echo -e "\033[32m🗑️ 已删除本地分支: $b_del\033[0m"

    elif [ "${1:-}" = "-dr" ] || [ "${1:-}" = "delremote" ]; then
        local b_del="${2}"
        [ -z "$b_del" ] && read -p "要删除的远程分支名: " b_del
        read -p "确认删除远程分支 'origin/$b_del'？(y/n): " confirm
        [[ "$confirm" == "y" || "$confirm" == "Y" ]] && \
            git push origin --delete "$b_del" && \
            echo -e "\033[32m🗑️ 已删除远程分支: $b_del\033[0m"

    else
        git checkout -b "${1:-}" 2>/dev/null || git checkout "${1:-}"
        echo -e "\033[32m✨ 已进入分支: $1\033[0m"
    fi
}

# ══════════════════════════════════════════
#  ✂️  重命名分支（rn）
# ══════════════════════════════════════════
_rename_branch() {
    _check_git_repo || return 1
    local old_br=$(git branch --show-current)
    local new_br="${1:-}"

    if [ -z "$new_br" ]; then
        echo -e "\033[36m当前分支: \033[1m$old_br\033[0m"
        read -p "新分支名: " new_br
    fi
    [ -z "$new_br" ] && return 1

    git branch -m "$old_br" "$new_br"

    if git remote get-url origin &>/dev/null; then
        read -p "同步删除远程旧分支并推送新分支？(y/n): " sync_remote
        if [[ "$sync_remote" == "y" || "$sync_remote" == "Y" ]]; then
            git push origin --delete "$old_br" 2>/dev/null
            git push -u origin "$new_br"
            echo -e "\033[32m✅ 远程分支已同步: $old_br → $new_br\033[0m"
        fi
    fi
    echo -e "\033[32m✨ 分支重命名: \033[1m$old_br → $new_br\033[0m"
}

# ══════════════════════════════════════════
#  🧹  清理已合并分支（bclean）
# ══════════════════════════════════════════
_clean_branches() {
    _check_git_repo || return 1
    echo -e "\033[34m🔍 检查已合并到 main/master 的分支...\033[0m"

    local base_br="main"
    git rev-parse --verify main >/dev/null 2>&1 || base_br="master"

    local merged=()
    while IFS= read -r br; do
        [ -z "$br" ] && continue
        [[ "$br" == "main" || "$br" == "master" || "$br" == "dev" ]] && continue
        merged+=("$br")
    done < <(git branch --merged "$base_br" 2>/dev/null | sed 's/[* ]*//' | grep -v "^$")

    if [ ${#merged[@]} -eq 0 ]; then
        echo -e "\033[32m✅ 没有可清理的已合并分支\033[0m"
        return 0
    fi

    echo -e "\033[33m以下分支已合并到 $base_br，可以删除:\033[0m"
    for br in "${merged[@]}"; do
        echo -e "  \033[31m- $br\033[0m"
    done

    read -p "确认删除这 ${#merged[@]} 个分支？(y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        for br in "${merged[@]}"; do
            git branch -d "$br" && echo -e "  \033[32m🗑️ 已删除: $br\033[0m"
        done
    else
        echo -e "\033[90m已取消\033[0m"
    fi
}

# ══════════════════════════════════════════
#  🔄  安全同步（gsync）
# ══════════════════════════════════════════
_sync_branch() {
    _check_git_repo || return 1
    local cur_br=$(git branch --show-current)

    echo -e "\033[34m🔄 同步分支: \033[1m$cur_br\033[0m"

    if [ -n "$(git status -s 2>/dev/null)" ]; then
        echo -e "\033[33m⚠️ 存在未提交变更，先暂存...\033[0m"
        git stash push -m "sync_auto_stash_$(date '+%m%d_%H%M')"
        local stashed=1
    fi

    git fetch origin 2>/dev/null
    git rebase "origin/$cur_br" 2>/dev/null || {
        echo -e "\033[33m⚠️ rebase 遇到冲突，回退为 merge...\033[0m"
        git rebase --abort 2>/dev/null
        git merge "origin/$cur_br"
    }

    if [ "${stashed}" = "1" ]; then
        echo -e "\033[34m📦 恢复暂存的变更...\033[0m"
        git stash pop
    fi

    echo -e "\033[32m✅ 同步完成\033[0m"
}

# ══════════════════════════════════════════
#  🏠  回主线（gomain）
# ══════════════════════════════════════════
_main_branch() {
    _check_git_repo || return 1
    if git rev-parse --verify main >/dev/null 2>&1; then
        git checkout main && echo -e "\033[32m🏠 已回到 main\033[0m"
    elif git rev-parse --verify master >/dev/null 2>&1; then
        git checkout master && echo -e "\033[32m🏠 已回到 master\033[0m"
    else
        echo -e "\033[31m❌ 没有 main/master 分支\033[0m"
    fi
}
