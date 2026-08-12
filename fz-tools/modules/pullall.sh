#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — pullall.sh（批量拉取模块）v5.0 新增
#  职责：遍历书签下所有一级子目录（含 .git 的项目）批量拉取
#  包含函数：_pull_all
#  对应别名：pullall
#  pullall             → 更新所有书签下的项目
#  pullall <书签名>    → 只更新指定书签下的项目
#  ⚠️ v5.0 起自 nav.sh 迁移至此，nav.sh 中仅保留兼容说明
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

# ══════════════════════════════════════════
#  🔄  批量拉取（pullall）
#  执行前确认书签列表；逐项目 git pull --quiet；
#  统计成功/失败，最后显示失败列表
# ══════════════════════════════════════════
_pull_all() {
    _bm_load
    if [ ${#FZ_BOOKMARKS[@]} -eq 0 ]; then
        echo -e "\033[33m📌 暂无书签，请先执行 \033[1mbookmark\033[0m 添加\033[0m"
        return 1
    fi

    # ── 确定本次要更新的书签 ──
    local targets=()
    if [ -n "${1:-}" ]; then
        local tpath
        tpath=$(_bm_get_path "${1:-}") || { echo -e "\033[31m❌ 未找到书签: $1\033[0m"; return 1; }
        targets=("$1|$tpath")
    else
        targets=("${FZ_BOOKMARKS[@]}")
    fi

    # ── 收集所有 Git 项目（一级子目录含 .git）──
    local projects=()   # 每项: 书签名|项目绝对路径
    local invalid=0
    for entry in "${targets[@]}"; do
        local bm_name="${entry%%|*}"
        local bm_path="${entry#*|}"
        if [ ! -d "$bm_path" ]; then
            echo -e "  \033[31m[失效]\033[0m 书签 \033[1m${bm_name}\033[0m 目录不存在: ${bm_path}"
            invalid=$((invalid + 1))
            continue
        fi
        for d in "$bm_path"/*/; do
            [ -d "$d/.git" ] || continue
            projects+=("${bm_name}|${d%/}")
        done
    done

    if [ ${#projects[@]} -eq 0 ]; then
        echo -e "\033[33m⚠️ 没有找到任何 Git 项目（${invalid} 个书签失效）\033[0m"
        return 1
    fi

    # ── 执行前确认（计划书 5.2）──
    echo -e "\n\033[1;35m🔄 批量拉取预览\033[0m"
    echo -e "\033[90m将更新以下书签下的所有项目:\033[0m"
    for entry in "${targets[@]}"; do
        local mark=""
        [ ! -d "${entry#*|}" ] && mark=" \033[31m[失效]\033[0m"
        echo -e "  \033[33m•\033[0m ${entry%%|*}${mark}"
    done
    echo -e "\033[90m共 ${#projects[@]} 个 Git 项目\033[0m"
    read -p "确认开始批量拉取？(y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "\033[90m已取消\033[0m"
        return 0
    fi

    # ── 逐项目拉取 ──
    echo ""
    local success=0 fail=0
    local fail_list=()
    for entry in "${projects[@]}"; do
        local bm_name="${entry%%|*}"
        local pdir="${entry#*|}"
        local pname
        pname=$(basename "$pdir")
        printf "  [%s] %-24s" "$bm_name" "$pname"
        local result
        result=$(cd "$pdir" && git pull --quiet 2>&1)
        if [ $? -eq 0 ]; then
            echo -e "\033[32m✅\033[0m"
            success=$((success + 1))
        else
            echo -e "\033[31m❌\033[0m"
            fail_list+=("${bm_name}/${pname}: $(echo "$result" | head -2 | tr '\n' ' ')")
            fail=$((fail + 1))
        fi
    done

    echo -e "\n\033[1;32m完成: ${success} 成功 | ${fail} 失败\033[0m"
    if [ "$fail" -gt 0 ]; then
        echo -e "\n\033[31m📋 失败项目列表:\033[0m"
        for f in "${fail_list[@]}"; do
            echo -e "  \033[31m•\033[0m $f"
        done
    fi
    return 0
}

# ══════════════════════════════════════════
#  📥  单仓库智能拉取（pull）v5.1 新增
#  由 fzgit.sh 的 pull 别名调用（原为 echo + git pull 简单别名）
#  特性：显示分支 → 检查上游跟踪 → 脏工作区确认 →
#        pull 后显示新增提交 / 失败提示 fix
# ══════════════════════════════════════════
_pull_now() {
    _check_git_repo || return 1
    local b_name
    b_name=$(git branch --show-current 2>/dev/null)
    local upstream
    upstream=$(git rev-parse --abbrev-ref "@{u}" 2>/dev/null)

    echo -e "\033[34m📥 正在同步分支: \033[1m${b_name}\033[0m"
    if [ -z "$upstream" ]; then
        echo -e "\033[33m⚠️ 当前分支没有上游（remote）跟踪，无法直接 pull\033[0m"
        echo -e "   💡 用 \033[36mp\033[0m 推送一次即可建立跟踪，或执行 \033[36mgsync\033[0m 安全同步"
        return 1
    fi

    if [ -n "$(git status -s 2>/dev/null)" ]; then
        echo -e "\033[33m⚠️ 存在未提交变更，pull 前建议先 \033[36msave\033[0m 暂存\033[0m"
        read -p "仍要继续 pull？(y/n): " cont
        if [[ "$cont" != "y" && "$cont" != "Y" ]]; then
            echo -e "\033[90m已取消\033[0m"
            return 1
        fi
    fi

    local before after
    before=$(git rev-list --count HEAD 2>/dev/null || echo 0)
    if ! git pull --quiet 2>&1; then
        echo -e "\033[31m❌ 拉取失败！可能有冲突，执行 \033[36mfix\033[0m 引导解决\033[0m"
        return 1
    fi
    after=$(git rev-list --count HEAD 2>/dev/null || echo 0)
    local got=$((after - before))
    if [ "$got" -gt 0 ]; then
        echo -e "\033[32m✅ 拉取完成，新增 \033[1m${got}\033[0m 个提交\033[0m"
        git log --oneline "-${got}" 2>/dev/null | sed 's/^/   /'
    else
        echo -e "\033[32m✅ 已是最新\033[0m"
    fi
    return 0
}
