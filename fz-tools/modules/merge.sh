#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — merge.sh（合并发布模块）
#  职责：合并发布（默认 dev→main）/ 撤回最后一次提交
#  包含函数：_ok_merge  _no_revert
#  对应别名：ok  no
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

# ══════════════════════════════════════════
#  ✅  发布转正（ok）
# ══════════════════════════════════════════
_ok_merge() {
    _check_git_repo || return 1
    local src="${1:-dev}"
    local dst="${2:-main}"
    local opt="${3}"

    if ! git rev-parse --verify "$src" >/dev/null 2>&1; then
        echo -e "\033[31m❌ 分支 '$src' 不存在！\033[0m"
        return 1
    fi

    local msg="🔀 merge: ${src} → ${dst}"
    if [ "$opt" = "skip" ]; then
        msg="🔀 merge: ${src} → ${dst} [skip ci]"
        echo -e "\033[33m🛡️ 已启用免构建锁（将跳过 CI 构建）\033[0m"
    fi

    echo -e "\033[33m⚠️ 准备将 \033[1m${src}\033[0m\033[33m → \033[1m${dst}\033[0m\033[33m 合并发布\033[0m"
    echo -e "\033[36m\n待合并的提交:\033[0m"
    git log "${dst}..${src}" --oneline 2>/dev/null | head -10 | awk '{print "  " $0}'

    local count
    count=$(git rev-list "${dst}..${src}" --count 2>/dev/null)
    echo -e "\n\033[90m共 $count 个提交待合并\033[0m"
    read -p "确认合并发布？(y/n): " confirm

    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        _git_auto_ignore
        git checkout "$dst" && \
        git merge "$src" --no-ff -m "${msg}" && \
        git push origin "$dst"

        if [ $? -eq 0 ]; then
            echo -e "\033[32m✅ 功德圆满！已发布至 ${dst}\033[0m"
            git checkout "$src"
            read -p "顺手打版本标签？(如 v1.0.0，回车跳过): " tag_ver
            [ -n "$tag_ver" ] && _tag_mgr "$tag_ver" "release $tag_ver"
        else
            echo -e "\033[31m❌ 合并失败！执行 'fix' 查看冲突\033[0m"
            git checkout "$src"
        fi
    else
        echo -e "\033[31m⛔ 已取消\033[0m"
    fi
}

# ══════════════════════════════════════════
#  💊  后悔药（no）
# ══════════════════════════════════════════
_no_revert() {
    _check_git_repo || return 1
    local target="${1:-main}"
    local cur=$(git branch --show-current)

    echo -e "\033[1;31m💀 警告：将撤回 ${target} 分支的最后一次提交！\033[0m"
    echo -e "\033[33m最近提交:\033[0m"
    git log "$target" --oneline -5 2>/dev/null | awk '{print "  "$0}'
    echo ""

    read -p "确定吃后悔药？(y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        if git checkout "$target" && \
           git reset --hard HEAD~1 && \
           git push origin "$target" --force; then
            echo -e "\033[32m♻️ 撤回成功！\033[0m"
        else
            echo -e "\033[31m❌ 撤回失败，请手动检查状态！\033[0m"
        fi
        git checkout "$cur"
    else
        echo -e "\033[32m💨 已取消\033[0m"
    fi
}
