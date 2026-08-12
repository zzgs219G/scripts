#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — env.sh（环境模块）
#  职责：环境初始化 / GitHub 登录与远程仓库 / 目录信任 /
#        AI Key 配置 / 自更新（git pull 版）
#  包含函数：_setup_env  _github_login  _create_repo  _remote_mgr
#            _trust_dir  _ai_setup  _update_script  _fz_ver_gt
#  对应别名：setup  login  repo  remote  trust  aikey  up
#  说明：_create_repo / _remote_mgr 属 GitHub 环境相关，计划书
#        未单列，按就近原则归入本模块。
#  ⚠️ v4.0 加固：_github_login 增加非交互终端检测，避免管道
#     环境下 gh auth login 阻塞轮询
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

# 版本号比较（支持 v1.2.3 / 4.0 格式），a>b 返回 0
_fz_ver_gt() {
    local a="${1:-}" b="${2:-}"
    a="${a#v}"; b="${b#v}"
    local ia ib
    IFS='.' read -ra ia <<< "$a"
    IFS='.' read -ra ib <<< "$b"
    local i
    for (( i=0; i<${#ia[@]} || i<${#ib[@]}; i++ )); do
        local na="${ia[$i]:-0}" nb="${ib[$i]:-0}"
        [ "$na" -gt "$nb" ] && return 0
        [ "$na" -lt "$nb" ] && return 1
    done
    return 1
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

    # v5.0：书签初始化（若书签为空，引导创建 / 迁移旧 FZ_BASE）
    echo ""
    _bm_init

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

    # v4.0 加固：非交互环境（管道/脚本）下 gh 交互流程会阻塞，提前退出
    if [ ! -t 0 ]; then
        echo -e "\033[31m❌ login 需要交互终端，请直接在终端中执行\033[0m"
        return 1
    fi

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
#  🤖  AI 配置向导（aikey）
#  ⚠️ v4.0 起 Key 持久化到主入口文件（FZ_MAIN），
#     不再写入 ~/.bashrc（旧注入块已随迁移移除）
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
        local escaped_key
        escaped_key=$(printf '%s' "$input_key" | sed 's/[\/&]/\\&/g')
        if [ -n "$FZ_MAIN" ] && [ -f "$FZ_MAIN" ]; then
            sed -i "s|export FZ_AI_KEY=\".*\"|export FZ_AI_KEY=\"${escaped_key}\"|" "$FZ_MAIN"
        fi
        export FZ_AI_KEY="$input_key"
        echo -e "\033[32m✅ 已保存！下次 'p' 推送时将自动生成 commit message\033[0m\n"
    fi
}

# ══════════════════════════════════════════
#  🔄  自更新（up）
#  ⚠️ v4.0 起改为 git pull 更新整个仓库，
#     不再下载单文件注入（计划书 3.4 节）
# ══════════════════════════════════════════
_update_script() {
    echo -e "\033[34m🔄 检查更新中...\033[0m"

    local repo_root
    repo_root=$(git -C "${FZ_TOOLS_DIR}" rev-parse --show-toplevel 2>/dev/null)
    if [ -z "$repo_root" ] || [ ! -d "$repo_root/.git" ]; then
        echo -e "\033[31m❌ 无法定位《焚诀》所在仓库（请通过 git clone 安装）\033[0m"
        return 1
    fi

    if ! git -C "$repo_root" fetch --tags --quiet 2>/dev/null; then
        echo -e "\033[31m❌ 获取远程失败，请检查网络或代理设置\033[0m"
        return 1
    fi

    local default_br
    default_br=$(git -C "$repo_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's#refs/remotes/origin/##')
    [ -z "$default_br" ] && default_br="main"

    local remote_version
    remote_version=$(git -C "$repo_root" show "origin/${default_br}:fz-tools/fzgit.sh" 2>/dev/null | grep 'FZ_VERSION=' | head -1 | cut -d'"' -f2 | tr -d '\r')

    if [ -z "$remote_version" ]; then
        echo -e "\033[31m❌ 读取远程版本失败，请检查网络\033[0m"
        return 1
    fi

    echo -e "📦 当前版本: \033[33m$FZ_VERSION\033[0m"
    echo -e "🌐 最新版本: \033[33m$remote_version\033[0m"

    if ! _fz_ver_gt "$remote_version" "$FZ_VERSION"; then
        echo -e "\033[32m✅ 已是最新版本（v$FZ_VERSION），无需更新\033[0m"
        return 0
    fi

    read -p "发现新版本，是否升级？(y/n): " c
    [ "$c" != "y" ] && [ "$c" != "Y" ] && return 0

    echo -e "\033[33m⬆️ 开始拉取更新...\033[0m"

    if git -C "$repo_root" pull --quiet; then
        # 更新后重新加载（~/.bashrc 中已有 source 指向新主入口）
        source ~/.bashrc 2>/dev/null
        echo -e "\033[32m🎉 焚诀更新成功！当前版本已进化至 v$remote_version\033[0m"
        echo -e "\033[90m💡 若提示无变化，请手动执行: source ~/.bashrc\033[0m"
    else
        echo -e "\033[31m❌ 拉取更新失败，请检查本地 scripts 仓库是否有未提交改动\033[0m"
        return 1
    fi
}
