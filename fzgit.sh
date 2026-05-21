#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║          焚诀·究极进化版  Git Workflow System               ║
# ║          v3.1 全面修复版                                    ║
# ╚══════════════════════════════════════════════════════════════╝
#
# 安装方法：
#   bash git_workflow_ultimate.sh
#
# 或手动注入：
#   cat git_workflow_ultimate.sh >> ~/.bashrc && source ~/.bashrc

# ============================================================
# 清理旧版本
# ============================================================
sed -i '/AI_GIT_WORKFLOW/,/END/d' ~/.bashrc

# ============================================================
# 注入新版本
# ============================================================
cat << 'INNER_EOF' >> ~/.bashrc
# --- AI_GIT_WORKFLOW ---

# ══════════════════════════════════════════
#  📁  基础配置
# ══════════════════════════════════════════
if [ -d "/storage/emulated/0/常用" ]; then
    _FOUND_PATH=$(find /storage/emulated/0/常用/ -maxdepth 2 -type d -name "*克隆仓库*" 2>/dev/null | head -n 1)
    export FZ_BASE="${_FOUND_PATH:-/storage/emulated/0/常用/工作台😡/克隆仓库}"
else
    export FZ_BASE="${HOME}/repos"
fi
mkdir -p "${FZ_BASE}"
unset _FOUND_PATH

# AI commit message 功能开关（填入 key 后自动开启）
# 获取方式：https://console.anthropic.com/
export FZ_AI_KEY=""   # 填入你的 Anthropic API Key

# ══════════════════════════════════════════
#  🛡️  内部工具函数
# ══════════════════════════════════════════

# 检查是否在 Git 仓库内
_check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "\033[31m❌ 当前目录不是 Git 仓库！\033[0m"
        return 1
    fi
}

# 自动护法（.gitignore）
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

# JSON 转义（兼容无 python3 环境）
# 修复：原版依赖 python3，Termux 上可能不存在
_json_escape() {
    local s="$1"
    # 优先用 python3，没有则用 sed 手动转义
    if command -v python3 &>/dev/null; then
        printf '%s' "$s" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null
    else
        # 手动转义：反斜杠、双引号、换行、制表符
        s="${s//\\/\\\\}"
        s="${s//\"/\\\"}"
        s="${s//$'\n'/\\n}"
        s="${s//$'\t'/\\t}"
        printf '"%s"' "$s"
    fi
}

# ══════════════════════════════════════════
#  🔧  环境配置（setup）
# ══════════════════════════════════════════
_setup_env() {
    echo -e "\n\033[1;35m🔧 Git 环境初始化向导\033[0m\n"

    if ! command -v git &>/dev/null; then
        echo -e "\033[31m❌ Git 未安装！\033[0m"
        echo -e "Termux:        \033[33mpkg install git\033[0m"
        echo -e "Ubuntu/Debian: \033[33msudo apt install git\033[0m"
        return 1
    fi
    echo -e "\033[32m✅ Git: $(git --version)\033[0m"

    if command -v gh &>/dev/null; then
        echo -e "\033[32m✅ GitHub CLI: $(gh --version | head -1)\033[0m"
    else
        echo -e "\033[33m⚠️  GitHub CLI 未安装（创建远程仓库需要）\033[0m"
        echo -e "Termux:        \033[33mpkg install gh\033[0m"
        echo -e "Ubuntu/Debian: \033[33msudo apt install gh\033[0m"
    fi

    if command -v curl &>/dev/null; then
        echo -e "\033[32m✅ curl 已安装\033[0m"
    else
        echo -e "\033[33m⚠️  curl 未安装（AI commit 需要）\033[0m"
        echo -e "Termux: \033[33mpkg install curl\033[0m"
    fi

    echo ""

    local cur_name=$(git config --global user.name)
    if [ -z "$cur_name" ]; then
        read -p "📛 输入你的 Git 用户名: " git_name
        [ -n "$git_name" ] && git config --global user.name "$git_name"
    else
        echo -e "👤 用户名: \033[33m$cur_name\033[0m"
    fi

    local cur_email=$(git config --global user.email)
    if [ -z "$cur_email" ]; then
        read -p "📧 输入你的 Git 邮箱: " git_email
        [ -n "$git_email" ] && git config --global user.email "$git_email"
    else
        echo -e "📧 邮箱: \033[33m$cur_email\033[0m"
    fi

    git config --global core.editor        "nano"
    git config --global pull.rebase        false
    git config --global core.bigFileThreshold "50m"
    git config --global core.quotepath     false
    git config --global init.defaultBranch main
    git config --global merge.conflictstyle diff3
    git config --global color.ui           auto

    echo -e "\n\033[32m✨ 环境配置完成！\033[0m"
    echo -e "  下一步: \033[36mlogin\033[0m 登录 GitHub"
    echo -e "  AI commit: 执行 \033[36maikey\033[0m 配置\n"
}

# ══════════════════════════════════════════
#  🔑  信任当前目录（trust）
# ══════════════════════════════════════════
_trust_dir() {
    local target="${1:-$(pwd)}"
    git config --global --add safe.directory "$target"
    echo -e "\033[32m✅ 已信任目录: $target\033[0m"
}

# ══════════════════════════════════════════
#  🔑  GitHub 登录（login）
# ══════════════════════════════════════════
_github_login() {
    echo -e "\n\033[1;35m🔑 GitHub 登录向导\033[0m\n"

    if ! command -v gh &>/dev/null; then
        echo -e "\033[31m❌ 需要先安装 GitHub CLI，执行 'setup'\033[0m"
        return 1
    fi

    if gh auth status &>/dev/null; then
        echo -e "\033[32m✅ 当前登录状态:\033[0m"
        gh auth status
        echo ""
        read -p "重新登录？(y/n): " relogin
        [[ "$relogin" != "y" && "$relogin" != "Y" ]] && return 0
    fi

    echo -e "\033[36m选择登录方式:\033[0m"
    echo -e "  \033[33m1\033[0m. 浏览器授权（推荐）"
    echo -e "  \033[33m2\033[0m. Token 登录"
    read -p "请选择 (1/2): " choice

    if [ "$choice" = "2" ]; then
        echo -e "\nGitHub → Settings → Developer settings → Personal access tokens"
        echo -e "需要权限: \033[33mrepo, workflow, read:org\033[0m\n"
        gh auth login --with-token
    else
        gh auth login --web -h github.com
    fi

    gh auth setup-git
    echo -e "\n\033[32m✅ 登录成功！用 'repo' 创建远程仓库\033[0m\n"
}

# ══════════════════════════════════════════
#  🏗️  创建远程仓库（repo）
# ══════════════════════════════════════════
_create_repo() {
    echo -e "\n\033[1;35m🏗️ 创建 GitHub 远程仓库\033[0m\n"

    if ! command -v gh &>/dev/null; then
        echo -e "\033[31m❌ 需要先安装 GitHub CLI，执行 'setup'\033[0m"; return 1
    fi
    if ! gh auth status &>/dev/null; then
        echo -e "\033[31m❌ 尚未登录 GitHub，执行 'login'\033[0m"; return 1
    fi

    local default_name=$(basename "$PWD")
    read -p "📦 仓库名 (回车默认: ${default_name}): " repo_name
    repo_name="${repo_name:-$default_name}"

    read -p "📝 仓库描述 (可选): " repo_desc

    echo -e "\033[36m仓库类型:\033[0m  \033[33m1\033[0m. 公开  \033[33m2\033[0m. 私有（默认）"
    read -p "请选择 (1/2): " vis_choice
    local visibility="--private"
    [ "$vis_choice" = "1" ] && visibility="--public"

    local push_current="n"
    if git rev-parse --git-dir > /dev/null 2>&1; then
        read -p "将当前目录推送到新仓库？(y/n): " push_current
    fi

    if [ "$push_current" = "y" ] || [ "$push_current" = "Y" ]; then
        git remote remove origin 2>/dev/null
    fi

    if [ -n "$repo_desc" ]; then
        gh repo create "$repo_name" $visibility --description "$repo_desc"
    else
        gh repo create "$repo_name" $visibility
    fi

    [ $? -ne 0 ] && echo -e "\033[31m❌ 仓库创建失败！\033[0m" && return 1
    echo -e "\033[32m✅ 仓库创建成功！\033[0m"

    if [[ "$push_current" == "y" || "$push_current" == "Y" ]]; then
        local username=$(gh api user --jq '.login')
        local remote_url="https://github.com/${username}/${repo_name}.git"
        git remote add origin "$remote_url"
        _git_auto_ignore
        git add .
        git commit -m "🎉 init: 项目初始化" 2>/dev/null || true
        git branch -M main
        git push -u origin main
        echo -e "\033[32m🚀 已推送至 ${remote_url}\033[0m\n"
    fi
}

# ══════════════════════════════════════════
#  🔗  远程仓库管理（remote）
# ══════════════════════════════════════════
_remote_mgr() {
    _check_git_repo || return 1
    echo -e "\n\033[1;35m🔗 远程仓库管理\033[0m\n"
    echo -e "\033[36m当前远程地址:\033[0m"
    git remote -v

    echo -e "\n  \033[33m1\033[0m. 设置/修改 origin"
    echo -e "  \033[33m2\033[0m. 添加新的远程"
    echo -e "  \033[33m3\033[0m. 删除远程"
    echo -e "  \033[33m4\033[0m. 查看远程详情"
    echo -e "  \033[33mq\033[0m. 退出"
    read -p "请选择: " op

    case "$op" in
        1) read -p "新的 origin URL: " new_url
           git remote set-url origin "$new_url" 2>/dev/null || \
           git remote add origin "$new_url"
           echo -e "\033[32m✅ 已更新 origin\033[0m" ;;
        2) read -p "远程名称: " r_name; read -p "远程 URL: " r_url
           git remote add "$r_name" "$r_url" && echo -e "\033[32m✅ 已添加 $r_name\033[0m" ;;
        3) read -p "要删除的远程名称: " r_del
           git remote remove "$r_del" && echo -e "\033[32m✅ 已删除 $r_del\033[0m" ;;
        4) git remote show origin ;;
        *) return 0 ;;
    esac
}

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
#  📊  工作台总览（lsp）新增
# ══════════════════════════════════════════
_ls_projects() {
    if [ ! -d "${FZ_BASE}" ]; then
        echo -e "\033[31m❌ 工作台路径不存在: ${FZ_BASE}\033[0m"
        return 1
    fi

    echo -e "\n\033[1;36m📊 工作台项目总览\033[0m\n"
    printf "  \033[90m%-28s %-14s %-8s %s\033[0m\n" "项目名" "分支" "变更" "最近提交"
    echo -e "  \033[90m──────────────────────────────────────────────────────────\033[0m"

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

            local branch_color="\033[32m"
            [ "$branch" = "main" ] || [ "$branch" = "master" ] && branch_color="\033[33m"

            local changes_display="-"
            local changes_color="\033[90m"
            [ "$changes" -gt 0 ] && changes_display="${changes}个" && changes_color="\033[31m"

            printf "  %-28s ${branch_color}%-14s\033[0m ${changes_color}%-6s\033[0m \033[90m%s\033[0m\n" \
                "$name" "$branch" "$changes_display" "$commit"
        else
            printf "  %-28s \033[90m%-14s\033[0m\n" "$name" "(非Git仓库)"
        fi
    done

    echo -e "\n\033[90m  共 $count 个项目 | FZ_BASE: ${FZ_BASE}\033[0m\n"
}

# ══════════════════════════════════════════
#  🌿  分支管理（b）
# ══════════════════════════════════════════
_branch_mgr() {
    _check_git_repo || return 1

    # b all：打捞所有远程分支
    # 修复：原版 grep 管道在某些环境下对带空格行处理不稳定，改用更健壮的写法
    if [ "$1" = "all" ]; then
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

    # 无参数：列出 + 选编号切换
    if [ -z "$1" ]; then
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

    elif [ "$1" = "-l" ] || [ "$1" = "list" ]; then
        echo -e "\033[1;36m🌿 所有分支（含远程）:\033[0m"
        git branch -a --color

    elif [ "$1" = "-d" ] || [ "$1" = "del" ]; then
        local b_del="${2}"
        [ -z "$b_del" ] && read -p "要删除的分支名: " b_del
        read -p "确认删除本地分支 '$b_del'？(y/n): " confirm
        [[ "$confirm" == "y" || "$confirm" == "Y" ]] && \
            git branch -d "$b_del" && \
            echo -e "\033[32m🗑️ 已删除本地分支: $b_del\033[0m"

    elif [ "$1" = "-dr" ] || [ "$1" = "delremote" ]; then
        local b_del="${2}"
        [ -z "$b_del" ] && read -p "要删除的远程分支名: " b_del
        read -p "确认删除远程分支 'origin/$b_del'？(y/n): " confirm
        [[ "$confirm" == "y" || "$confirm" == "Y" ]] && \
            git push origin --delete "$b_del" && \
            echo -e "\033[32m🗑️ 已删除远程分支: $b_del\033[0m"

    else
        git checkout -b "$1" 2>/dev/null || git checkout "$1"
        echo -e "\033[32m✨ 已进入分支: $1\033[0m"
    fi
}

# ══════════════════════════════════════════
#  ✂️  重命名分支（rn）新增
# ══════════════════════════════════════════
_rename_branch() {
    _check_git_repo || return 1
    local old_br=$(git branch --show-current)
    local new_br="$1"

    if [ -z "$new_br" ]; then
        echo -e "\033[36m当前分支: \033[1m$old_br\033[0m"
        read -p "新分支名: " new_br
    fi
    [ -z "$new_br" ] && return 1

    # 本地重命名
    git branch -m "$old_br" "$new_br"

    # 同步远程
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
#  🧹  清理已合并分支（bclean）新增
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
#  🔄  安全同步（gsync）新增
# ══════════════════════════════════════════
_sync_branch() {
    _check_git_repo || return 1
    local cur_br=$(git branch --show-current)

    echo -e "\033[34m🔄 同步分支: \033[1m$cur_br\033[0m"

    # 检查有无未提交变更
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

    # 恢复暂存
    if [ "${stashed}" = "1" ]; then
        echo -e "\033[34m📦 恢复暂存的变更...\033[0m"
        git stash pop
    fi

    echo -e "\033[32m✅ 同步完成\033[0m"
}

# ══════════════════════════════════════════
#  🤖  AI 生成 commit message
# ══════════════════════════════════════════
# 修复：移除 python3 依赖，改用内置 _json_escape 函数
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
# 修复：change_count 统计逻辑，以及 ahead 判断的嵌套问题
_p_push() {
    _check_git_repo || return 1
    _git_auto_ignore

    local b_name=$(git branch --show-current)

    echo -e "\033[36m📋 变更文件:\033[0m"
    git status -s

    local change_count
    change_count=$(git status -s 2>/dev/null | wc -l | tr -d ' ')

    if [ "$change_count" -eq 0 ]; then
        # 没有工作区变更，但可能有未推送的 commit
        local ahead
        ahead=$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
        if [ "$ahead" -gt 0 ]; then
            echo -e "\033[33m📤 检测到 $ahead 个未推送的提交，直接推送...\033[0m"
            git push origin "$b_name"
        else
            echo -e "\033[33m⚠️ 没有任何变更，无需推送\033[0m"
        fi
        return 0
    fi

    git add .

    local msg=""
    if [ -n "$1" ]; then
        msg="$1"
    elif [ -n "$FZ_AI_KEY" ] && command -v curl &>/dev/null; then
        msg=$(_ai_commit_msg)
        if [ -n "$msg" ]; then
            echo -e "\033[90m💡 AI建议: \033[0m\033[1m${msg}\033[0m"
            read -p "使用此备注？(回车确认 / 输入自定义): " custom_msg
            [ -n "$custom_msg" ] && msg="$custom_msg"
        fi
    fi

    [ -z "$msg" ] && msg="⚡ update: $(date '+%m-%d %H:%M')"

    echo -e "\033[34m\n🚀 推送至 \033[1m${b_name}\033[0m\033[34m | 备注: ${msg}\033[0m"

    git commit -m "${msg}" 2>/dev/null || {
        echo -e "\033[33m⚠️ commit 无新变化，尝试直接推送\033[0m"
    }

    # 自动处理首次推送（无上游分支）
    local push_ok=0
    if ! git push origin "${b_name}" 2>/dev/null; then
        echo -e "\033[33m🔧 尝试设置上游分支...\033[0m"
        git push -u origin "${b_name}" && push_ok=1
    else
        push_ok=1
    fi

    if [ "$push_ok" -eq 1 ]; then
        echo -e "\033[32m✅ 推送成功！${change_count} 个文件变更\033[0m"
    else
        echo -e "\033[31m❌ 推送失败！可能需要先执行 'gsync' 同步\033[0m"
    fi
}

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
    # 修复：统一支持 noci / no-ci / [no ci] 三种写法
    if [ "$opt" = "noci" ] || [ "$opt" = "no-ci" ] || [ "$opt" = "[no ci]" ]; then
        msg="🔀 merge: ${src} → ${dst} [no ci]"
        echo -e "\033[33m🛡️ 已启用免构建锁（Cloudflare/CI 将跳过本次构建）\033[0m"
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

# ══════════════════════════════════════════
#  📜  漂亮日志（lg）
# ══════════════════════════════════════════
_log_pretty() {
    _check_git_repo || return 1
    local n="${1:-15}"
    echo -e "\033[1;36m📜 最近 ${n} 条提交:\033[0m\n"
    git log --oneline --graph --decorate --color "-${n}"
    echo -e "\n\033[90m用法: lg <条数>\033[0m"
}

# ══════════════════════════════════════════
#  🔍  查看差异（d）
# ══════════════════════════════════════════
_diff_view() {
    _check_git_repo || return 1
    if [ -z "$1" ]; then
        local changed=$(git diff --stat 2>/dev/null)
        if [ -z "$changed" ]; then
            echo -e "\033[32m✅ 工作区无未暂存的变更\033[0m"
        else
            echo -e "\033[36m📊 未暂存的变更:\033[0m"
            git diff --stat
        fi
    elif [ "$1" = "s" ] || [ "$1" = "staged" ]; then
        echo -e "\033[36m📊 已暂存的变更:\033[0m"
        git diff --staged --stat
    else
        echo -e "\033[36m📊 与 $1 的差异:\033[0m"
        git diff "$1" --stat
    fi
}

# ══════════════════════════════════════════
#  🧊  暂存工作区（save / pop）
# ══════════════════════════════════════════
_stash_save() {
    _check_git_repo || return 1
    local msg="${1:-临时保存_$(date '+%m%d_%H%M')}"
    git stash push -m "$msg"
    echo -e "\033[32m🧊 已暂存: $msg\033[0m"
    git stash list | head -5
}

_stash_pop() {
    _check_git_repo || return 1
    local list=$(git stash list)
    if [ -z "$list" ]; then
        echo -e "\033[33m📦 暂存区为空\033[0m"; return 0
    fi
    echo -e "\033[36m📦 暂存列表:\033[0m"
    git stash list
    if [ -z "$1" ]; then
        git stash pop && echo -e "\033[32m✅ 已恢复最近暂存\033[0m"
    else
        git stash pop "stash@{$1}" && echo -e "\033[32m✅ 已恢复暂存 [$1]\033[0m"
    fi
}

# ══════════════════════════════════════════
#  🔧  冲突解决引导（fix）
# ══════════════════════════════════════════
_fix_conflict() {
    _check_git_repo || return 1
    local conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null)

    if [ -z "$conflicts" ]; then
        echo -e "\033[32m✅ 无冲突文件！\033[0m"
        return 0
    fi

    echo -e "\033[1;31m⚔️ 发现冲突文件:\033[0m"
    echo "$conflicts" | awk '{print "  \033[33m"NR"\033[0m. "$0}'

    echo -e "\n\033[36m解决步骤:\033[0m"
    echo -e "  1. 打开冲突文件，找到 \033[31m<<<<<<< HEAD\033[0m 标记"
    echo -e "  2. 保留需要的代码，删除 <<<<< ===== >>>>> 标记行"
    echo -e "  3. 执行 \033[33mgit add <文件>\033[0m"
    echo -e "  4. 执行 \033[33mgit commit\033[0m\n"

    local first=$(echo "$conflicts" | head -1)
    read -p "用 nano 打开 '$first'？(y/n): " open_it
    [[ "$open_it" == "y" || "$open_it" == "Y" ]] && nano "$first"
}

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

# ══════════════════════════════════════════
#  ⚡  炼化引擎（f）
# ══════════════════════════════════════════
# 修复：
# 1. TMP_FILE 改到 HOME 目录，避免 emoji 路径导致 cp/cat 炸裂
# 2. OUT_FILE 先输出到 HOME，成功后再尝试复制到 FZ_BASE
# 3. 所有路径变量全部加双引号
_f_burn() {
    local MODULE="$1"
    local TIMESTAMP
    TIMESTAMP=$(date '+%m%d_%H%M')

    # 修复核心：TMP 和 OUT 都先放 HOME，绝对安全
    local TMP_FILE
    TMP_FILE=$(mktemp "${HOME}/fz_burn_tmp_XXXXXX.txt")
    local OUT_NAME="ai_code_${MODULE:-all}_${TIMESTAMP}.txt"
    local OUT_FILE="${HOME}/${OUT_NAME}"

    echo -e "\033[33m⚡ 炼化启动...\033[0m"
    echo -e "\033[90m📁 项目: $(basename "$PWD") | 过滤模块: ${MODULE:-无}\033[0m"

    # 文件头
    printf "/*\n * Project : %s\n * Module  : %s\n * Author  : %s\n * Date    : %s\n * Branch  : %s\n */\n\n" \
        "$(basename "$PWD")" \
        "${MODULE:-ALL}" \
        "$(git config user.name 2>/dev/null || echo 'unknown')" \
        "$(date '+%Y-%m-%d %H:%M')" \
        "$(git branch --show-current 2>/dev/null || echo 'unknown')" > "$TMP_FILE"

    local count=0
    local skip_count=0

    while IFS= read -r file; do
        [ -f "$file" ] || continue

        local size
        size=$(wc -c < "$file" 2>/dev/null || echo 0)

        if [ "$size" -gt 102400 ]; then
            printf "\n// [SKIP 过大: %s — %dKB]\n" "$file" "$((size/1024))" >> "$TMP_FILE"
            skip_count=$((skip_count + 1))
            continue
        fi

        printf "\n// ━━━━━━━━━━━━━━━━━━━━━━━━\n" >> "$TMP_FILE"
        printf "// [%s]\n" "$file" >> "$TMP_FILE"
        printf "// ━━━━━━━━━━━━━━━━━━━━━━━━\n" >> "$TMP_FILE"
        sed -e 's/^[[:space:]]*//' \
            -e 's/[[:space:]]*$//' \
            -e '/^[[:space:]]*$/d' \
            "$file" >> "$TMP_FILE"

        count=$((count + 1))
        printf "\r  \033[33m处理: %d 文件...\033[0m" "$count" >&2

    done < <(
        { git ls-files -c -o --exclude-standard 2>/dev/null || \
          find . -type f ! -path "*/\.git/*" ! -path "*/node_modules/*"; } | \
        grep -iE "\.(html|htm|js|jsx|ts|tsx|vue|css|scss|sass|less|json|md|kt|kts|java|xml|py|rb|go|rs|swift|dart|yaml|yml|sh|bash)$" | \
        grep -vE "(^|/)\.|(package-lock|yarn\.lock|pnpm-lock|\.min\.(js|css)|assets/(vue_global_prod|tailwindcss|remixicon)\.)" | \
        { [ -n "$MODULE" ] && grep -i "$MODULE" || cat; } | \
        sort
    )

    cp "$TMP_FILE" "$OUT_FILE"
    rm -f "$TMP_FILE"

    local out_kb
    out_kb=$(( $(wc -c < "$OUT_FILE" 2>/dev/null || echo 0) / 1024 ))

    echo -e "\r\033[32m✨ 炼化完成！\033[0m"
    echo -e "  📄 已处理 : \033[33m${count}\033[0m 个文件"
    [ "$skip_count" -gt 0 ] && echo -e "  ⏭️  跳过   : \033[90m${skip_count} 个过大文件\033[0m"
    echo -e "  📦 大小   : \033[33m${out_kb} KB\033[0m"
    echo -e "  📍 路径   : \033[36m${OUT_FILE}\033[0m"

    # 尝试额外复制到工作台目录（失败不影响主流程）
    if [ -d "${FZ_BASE}" ] && cp "$OUT_FILE" "${FZ_BASE}/${OUT_NAME}" 2>/dev/null; then
        echo -e "  📂 工作台 : \033[36m${FZ_BASE}/${OUT_NAME}\033[0m"
    fi

    # 自动复制路径到剪贴板（Termux）
    if command -v termux-clipboard-set &>/dev/null; then
        echo "$OUT_FILE" | termux-clipboard-set
        echo -e "  📋 路径已复制到剪贴板"
    fi
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
    # 修复：处理 SSH 格式中的冒号（git@host:user/repo）
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

# ══════════════════════════════════════════
#  📊  仓库信息总览（info）
# ══════════════════════════════════════════
_repo_info() {
    _check_git_repo || return 1
    echo -e "\n\033[1;35m📊 仓库信息\033[0m"
    echo -e "  ─────────────────────────────────"
    echo -e "  🌿 分支   : \033[33m$(git branch --show-current)\033[0m"
    echo -e "  🔗 远程   : \033[36m$(git remote get-url origin 2>/dev/null || echo '未设置')\033[0m"
    echo -e "  📜 提交数 : \033[33m$(git rev-list --count HEAD 2>/dev/null || echo 0)\033[0m 次"
    echo -e "  📁 追踪数 : \033[33m$(git ls-files 2>/dev/null | wc -l | tr -d ' ')\033[0m 个文件"
    echo -e "  ⏰ 最近   : $(git log -1 --format='%s (%cr)' 2>/dev/null || echo '无')"
    echo -e "  🏷️  标签   : $(git tag | wc -l | tr -d ' ') 个"

    # 新增：显示本地领先/落后远程的提交数
    local ahead behind
    ahead=$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
    behind=$(git rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)
    [ "$ahead" -gt 0 ] && echo -e "  📤 领先   : \033[33m${ahead}\033[0m 个提交（未推送）"
    [ "$behind" -gt 0 ] && echo -e "  📥 落后   : \033[31m${behind}\033[0m 个提交（需拉取）"

    echo -e "  ─────────────────────────────────"
    echo -e "  \033[90m贡献者:\033[0m"
    git shortlog -sn 2>/dev/null | head -5 | awk '{print "    "$0}'
    echo ""
}

# ══════════════════════════════════════════
#  🤖  AI 配置向导（aikey）
# ══════════════════════════════════════════
_ai_setup() {
    echo -e "\n\033[1;35m🤖 AI commit 配置\033[0m\n"
    echo -e "获取 API Key: \033[36mhttps://console.anthropic.com/\033[0m\n"

    if [ -n "$FZ_AI_KEY" ]; then
        echo -e "\033[32m✅ 已配置 API Key\033[0m（${FZ_AI_KEY:0:8}...）"
        read -p "重新配置？(y/n): " reconf
        [[ "$reconf" != "y" && "$reconf" != "Y" ]] && return 0
    fi

    read -p "输入你的 Anthropic API Key (sk-ant-...): " input_key
    if [ -n "$input_key" ]; then
        # 修复：转义 sed 特殊字符，避免 ~/.bashrc 损坏
        local escaped_key
        escaped_key=$(printf '%s' "$input_key" | sed 's/[\/&]/\\&/g')
        sed -i "s|export FZ_AI_KEY=\".*\"|export FZ_AI_KEY=\"${escaped_key}\"|" ~/.bashrc
        export FZ_AI_KEY="$input_key"
        echo -e "\033[32m✅ 已保存！下次 'p' 推送时将自动生成 commit message\033[0m\n"
    fi
}

# ══════════════════════════════════════════
#  🌐  查看远程仓库文件（rls）
# ══════════════════════════════════════════
_rls_remote() {
    if [ -z "$1" ]; then
        echo -e "\033[31m❌ 用法: rls 用户名/仓库名\033[0m"
        return 1
    fi

    if ! command -v gh &>/dev/null; then
        echo -e "\033[31m❌ 需要 gh CLI，先执行 setup\033[0m"
        return 1
    fi

    local repo="$1"
    echo -e "\033[1;36m🌐 仓库: $repo\033[0m\n"

    gh api "repos/$repo/contents" \
        --jq '.[] | "📄 \(.name)\t\(.type)"' 2>/dev/null || {
        echo -e "\033[31m❌ 获取失败（仓库不存在或未登录）\033[0m"
    }
}

# ══════════════════════════════════════════
#  🔤  别名注册
# ══════════════════════════════════════════
alias setup='_setup_env'
alias login='_github_login'
alias repo='_create_repo'
alias remote='_remote_mgr'
alias trust='_trust_dir'
alias aikey='_ai_setup'
alias c='_c_jump'
alias lsp='_ls_projects'       # 修复：避免覆盖系统 ls 命令
alias b='_branch_mgr'
alias rn='_rename_branch'      # 新增：重命名分支
alias bclean='_clean_branches' # 修复：避免覆盖系统/常用 clean 命令
alias gsync='_sync_branch'     # 修复：避免覆盖系统 sync 命令
alias p='_p_push'
alias ok='_ok_merge'
alias no='_no_revert'
alias gomain='_main_branch'    # 修复：避免与常见可执行文件名冲突
alias f='_f_burn'
alias lg='_log_pretty'
alias d='_diff_view'
alias save='_stash_save'
alias pop='_stash_pop'
alias fix='_fix_conflict'
alias tag='_tag_mgr'
alias cl='_clone_repo'
alias pullall='_pull_all'
alias info='_repo_info'
alias rls='_rls_remote'
alias st='echo -e "📍 分支: \033[1;33m$(git branch --show-current 2>/dev/null || echo "非Git目录")\033[0m | 变更: \033[33m$(git status -s 2>/dev/null | wc -l | tr -d " ")\033[0m 个文件"'
alias pull='echo -e "\033[34m📥 同步中...\033[0m" && git pull'
alias undo='git restore . && echo -e "\033[33m↩️ 已撤销工作区所有未提交修改\033[0m"'
alias unstage='git restore --staged . && echo -e "\033[33m↩️ 已取消所有暂存\033[0m"'

# ══════════════════════════════════════════
#  📖  帮助菜单（h）
# ══════════════════════════════════════════
alias h='echo -e "

\033[1;36m
╔══════════════════════════════════════════╗
║      焚诀·Git 工作流  v3.1              ║
╚══════════════════════════════════════════╝
\033[0m

\033[33m⚠️ 首次使用请先安装依赖：\033[0m

  \033[36mpkg install git curl gh\033[0m
\033[90m（Ubuntu/Debian: sudo apt install git curl gh）\033[0m

\033[33m📌 安装后执行：\033[0m  \033[36msetup\033[0m  →  \033[36mlogin\033[0m  →  \033[36maikey\033[0m（可选）

\033[1;35m╔══════════════════════════════════════════╗
║      指令秘籍                            ║
╚══════════════════════════════════════════╝\033[0m

\033[1;33m── 🔧 初始化 ────────────────────────────\033[0m
  \033[36msetup\033[0m    检查环境 + 配置 Git 全局信息
  \033[36mlogin\033[0m    登录 GitHub（浏览器/Token）
  \033[36mrepo\033[0m     创建远程仓库
  \033[36mremote\033[0m   管理远程地址（增删改查）
  \033[36mtrust\033[0m    信任当前目录（safe.directory）
  \033[36maikey\033[0m    配置 AI commit key（Anthropic）

\033[1;33m── 📂 项目导航 ──────────────────────────\033[0m
  \033[36mlsp\033[0m       工作台所有项目状态总览     ✨新
  \033[36mc\033[0m         列表选择/编号瞬移
  \033[36mc <名字>\033[0m   关键字模糊直达
  \033[36mcl <url>\033[0m   克隆（支持 用户名/仓库名）
  \033[36mpullall\033[0m   一键拉取所有项目

\033[1;33m── 🌿 分支操作 ──────────────────────────\033[0m
  \033[36mb all\033[0m      打捞全部远程分支并本地镜像
  \033[36mb\033[0m          列出分支 → 选编号切换
  \033[36mb <名字>\033[0m   直接切换/创建分支
  \033[36mb -l\033[0m       显示所有分支（含远程）
  \033[36mb -d <名>\033[0m   删除本地分支
  \033[36mb -dr <名>\033[0m  删除远程分支
  \033[36mgomain\033[0m     回到 main/master
  \033[36mrn\033[0m         重命名当前分支（本地+远程）✨新
  \033[36mbclean\033[0m     清理已合并的本地分支       ✨新

\033[1;33m── 🚀 推送 & 发布 ───────────────────────\033[0m
  \033[36mp\033[0m          推送（AI key 自动生成备注）
  \033[36mp \"备注\"\033[0m   指定备注推送
  \033[36mgsync\033[0m      安全同步远程（fetch+rebase） ✨新
  \033[36mpull\033[0m       拉取最新代码
  \033[36mok\033[0m         合并 dev→main 发布
  \033[36mok dev main noci\033[0m  合并并跳过 CI 构建
  \033[31mno\033[0m         撤回最后一次发布 ⚠️ 危险

\033[1;33m── 📊 查看 & 对比 ───────────────────────\033[0m
  \033[36mst\033[0m         当前分支 + 变更文件数
  \033[36minfo\033[0m       仓库完整信息（含领先/落后）
  \033[36mrls 用户/仓库\033[0m 查看远程仓库文件列表
  \033[36mlg\033[0m         提交历史图（默认15条）
  \033[36mlg 30\033[0m      查看30条历史
  \033[36md\033[0m          查看未暂存的变更
  \033[36md s\033[0m        查看已暂存的变更

\033[1;33m── 🧰 实用工具 ──────────────────────────\033[0m
  \033[36msave\033[0m       暂存工作区
  \033[36mpop\033[0m        恢复暂存
  \033[36mfix\033[0m        冲突解决引导
  \033[36mtag\033[0m        查看所有标签
  \033[36mtag v1.0\033[0m   发布版本标签
  \033[36mf\033[0m          炼化全部源码（喂给AI）
  \033[36mf <模块>\033[0m    只炼化指定模块
  \033[36mundo\033[0m       撤销工作区所有修改 ⚠️
  \033[36munstage\033[0m    取消所有暂存
  \033[36mh\033[0m          显示此菜单
"'

# --- END ---
INNER_EOF


# ============================================================
# 生效
# ============================================================
source ~/.bashrc
echo -e "\n\033[1;32m╔══════════════════════════════════╗"
echo -e "║  焚诀·v3.1 注入成功！           ║"
echo -e "╚══════════════════════════════════╝\033[0m"
echo -e "\n  执行 \033[36mh\033[0m 查看全部指令"
echo -e "  执行 \033[36msetup\033[0m 初始化环境"
echo -e "  执行 \033[36maikey\033[0m 配置AI commit（可选）\n"
