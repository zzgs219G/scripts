#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — nav.sh（导航模块）
#  职责：工作台项目列表 / 模糊跳转 / 克隆 / 批量拉取
#  包含函数：_c_jump  _ls_projects  _clone_repo  _pull_all
#  对应别名：c  lsp  cl  pullall
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

# ══════════════════════════════════════════
#  📂  瞬移引擎（c）
# ══════════════════════════════════════════
_c_jump() {
    if [ ! -d "${FZ_BASE}" ]; then
        echo -e "\033[31m❌ 工作台路径不存在: ${FZ_BASE}\033[0m"
        return 1
    fi

    local dirs=()
    while IFS= read -r line; do
        [ -n "$line" ] && dirs+=("$line")
    done < <(cd "${FZ_BASE}" && command ls -d */ 2>/dev/null | sed 's/\///g' | sort)

    if [ ${#dirs[@]} -eq 0 ]; then
        echo -e "\033[90m(工作台空空如也，快用 cl 克隆一个吧)\033[0m"
        return 0
    fi

    local input="$1"

    if [ -z "$input" ]; then
        echo -e "\033[1;36m📂 工作台项目列表:\033[0m"
        local i=1
        for d in "${dirs[@]}"; do
            echo -e "  \033[33m$i\033[0m. $d"
            i=$((i+1))
        done
        echo ""
        read -p "🚀 输入编号或项目名直达 (q退出): " input
        [ -z "$input" ] || [ "$input" = "q" ] && return 0
    fi

    local target=""

    if [[ "$input" =~ ^[0-9]+$ ]]; then
        local idx=$(( input - 1 ))
        if [ $idx -ge 0 ] && [ $idx -lt ${#dirs[@]} ]; then
            target="${dirs[$idx]}"
        else
            echo -e "\033[31m❌ 编号 $input 超出范围！\033[0m"
            return 1
        fi
    else
        for d in "${dirs[@]}"; do
            if [[ "${d,,}" == *"${input,,}"* ]]; then
                target="$d"
                break
            fi
        done
    fi

    if [ -n "$target" ]; then
        cd "${FZ_BASE}/$target" || return 1
        echo -e "🚀 瞬移成功: \033[1;32m${target}\033[0m"
        if git rev-parse --is-inside-work-tree &>/dev/null; then
            local cur_br=$(git branch --show-current)
            echo -e "  🌿 当前分支: \033[33m${cur_br}\033[0m"
        fi
    else
        echo -e "\033[31m❌ 未找到匹配 \"$input\" 的项目！\033[0m"
        return 1
    fi
}

# ══════════════════════════════════════════
#  📊  工作台总览（lsp）
# ══════════════════════════════════════════
_ls_projects() {
    if [ ! -d "${FZ_BASE}" ]; then
        echo -e "\033[31m❌ 工作台路径不存在: ${FZ_BASE}\033[0m"
        return 1
    fi

    echo -e "\n\033[1;36m📊 工作台项目总览\033[0m\n"
    printf "  \033[90m%-22s %-10s %-10s %-8s %s\033[0m\n" "项目名" "状态" "分支" "变更" "最近提交"
    echo -e "  \033[90m────────────────────────────────────────────────────────────\033[0m"

    local count=0
    for dir in "${FZ_BASE}"/*/; do
        [ -d "$dir" ] || continue
        local name=$(basename "$dir")
        count=$((count+1))

        if [ -d "$dir/.git" ]; then
            local branch commit changes
            branch=$(cd "$dir" && git branch --show-current 2>/dev/null || echo "?")
            commit=$(cd "$dir" && git log -1 --format="%s" 2>/dev/null | cut -c1-30 || echo "-")
            changes=$(cd "$dir" && git status -s 2>/dev/null | wc -l | tr -d ' ')

            local ahead behind sync_status
            ahead=$(cd "$dir" && git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
            behind=$(cd "$dir" && git rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)

            if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
                sync_status="🔵分叉"
            elif [ "$ahead" -gt 0 ]; then
                sync_status="🟡领先"
            elif [ "$behind" -gt 0 ]; then
                sync_status="🔴落后"
            else
                sync_status="🟢同步"
            fi

            local changes_display="-"
            [ "$changes" -gt 0 ] && changes_display="${changes}个"

            printf "  %-22s %-10s %-10s %-8s \033[90m%s\033[0m\n" \
                "$name" "$sync_status" "$branch" "$changes_display" "$commit"
        else
            printf "  %-22s \033[90m%-10s\033[0m\n" "$name" "(非Git)"
        fi
    done

    echo -e "\n\033[90m  共 $count 个项目 | FZ_BASE: ${FZ_BASE}\033[0m\n"
}

# ══════════════════════════════════════════
#  📥  克隆增强（cl）
# ══════════════════════════════════════════
_clone_repo() {
    if [ -z "$1" ]; then
        echo -e "\033[36m用法:\033[0m"
        echo -e "  \033[33mcl <URL>\033[0m           完整地址克隆"
        echo -e "  \033[33mcl 用户名/仓库名\033[0m   GitHub 短格式"
        return 0
    fi

    local url="$1"
    if [[ "$url" != http* && "$url" != git@* ]]; then
        url="https://github.com/${url}.git"
        echo -e "\033[36m🔗 GitHub 地址: $url\033[0m"
    fi

    cd "${FZ_BASE}" || return
    git clone "$url"

    local repo_name
    repo_name=$(basename "$url" .git)
    repo_name="${repo_name##*:}"

    if [ -d "$repo_name" ]; then
        cd "$repo_name"
        echo -e "\033[32m✅ 克隆完成，已进入: \033[1m$repo_name\033[0m\033[0m"
        git log --oneline -3 2>/dev/null | awk '{print "  \033[90m"$0"\033[0m"}'
    fi
}

# ══════════════════════════════════════════
#  🔄  批量拉取（pullall）
# ══════════════════════════════════════════
_pull_all() {
    echo -e "\033[1;35m🔄 批量同步所有项目...\033[0m\n"
    local success=0 fail=0
    for dir in "${FZ_BASE}"/*/; do
        [ -d "$dir/.git" ] || continue
        local name=$(basename "$dir")
        printf "  %-28s" "$name"
        local result
        result=$(cd "$dir" && git pull --quiet 2>&1)
        if [ $? -eq 0 ]; then
            echo -e "\033[32m✅\033[0m"
            success=$((success+1))
        else
            echo -e "\033[31m❌\033[0m  $result"
            fail=$((fail+1))
        fi
    done
    echo -e "\n\033[32m完成: ${success} 成功 | ${fail} 失败\033[0m"
}
