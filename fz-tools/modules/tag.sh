#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — tag.sh（标签模块）
#  职责：查看标签 / 创建带注释标签 / 删除本地及远程标签
#  包含函数：_tag_mgr
#  对应别名：tag
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

# ══════════════════════════════════════════
#  🏷️  版本标签（tag）
# ══════════════════════════════════════════
_tag_mgr() {
    _check_git_repo || return 1

    if [ -z "$1" ]; then
        echo -e "\033[1;36m🏷️ 版本标签:\033[0m"
        git tag -l --sort=-version:refname | head -20
        echo -e "\n\033[90m用法:\033[0m"
        echo -e "  \033[36mtag v1.0.0\033[0m        发布标签"
        echo -e "  \033[36mtag v1.0.0 \"描述\"\033[0m 带描述发布"
        echo -e "  \033[36mtag -d v1.0.0\033[0m     删除标签"
    elif [ "$1" = "-d" ]; then
        local t="${2}"
        [ -z "$t" ] && read -p "要删除的标签: " t
        git tag -d "$t"
        git push origin --delete "$t" 2>/dev/null
        echo -e "\033[32m🗑️ 已删除标签 $t\033[0m"
    else
        local ver="$1"
        local msg="${2:-release $ver}"
        git tag -a "$ver" -m "$msg"
        git push origin "$ver"
        echo -e "\033[32m🏷️ 标签 $ver 已推送！\033[0m"
    fi
}
