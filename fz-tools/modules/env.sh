#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — env.sh（环境模块）
#  职责：环境初始化 / GitHub 登录与远程仓库 / 目录信任 /
#        AI Key 配置 / 自更新（git pull 版）
#  包含函数：_setup_env  _github_login  _create_repo  _remote_mgr
#            _trust_dir  _ai_setup  _update_script  _fz_ver_gt
#            _fz_token  _fz_token_help
#  对应别名：setup  ghlogin(login)  repo  remote  trust  aikey  up  token
#  说明：_create_repo / _remote_mgr 属 GitHub 环境相关，计划书
#        未单列，按就近原则归入本模块。
#  ⚠️ _github_login 有非交互终端检测，避免管道
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
        if _gh_ensure_credential; then
            echo -e "\033[32m🔑 git 凭据已配置，GitHub 操作无需再登录\033[0m"
        fi
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

    local cur_name
    cur_name=$(git config --global user.name)
    if [ -z "$cur_name" ]; then
        read -rp "📛 输入你的 Git 用户名: " git_name
        [ -n "$git_name" ] && git config --global user.name "$git_name"
    else
        echo -e "👤 用户名: \033[33m$cur_name\033[0m"
    fi

    local cur_email
    cur_email=$(git config --global user.email)
    if [ -z "$cur_email" ]; then
        read -rp "📧 输入你的 Git 邮箱: " git_email
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

    # 书签初始化（为空时引导创建，或迁移用户显式设置过的旧 FZ_BASE）
    echo ""
    _bm_init

    echo -e "  下一步: \033[36mghlogin\033[0m 登录 GitHub"
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
#  🔑  确保 git 走 HTTPS 时自动复用 gh 凭据（幂等，可重复调用）
#      修复：login 在“已登录 + 选不重登”时提前 return，会跳过
#      gh auth setup-git，导致 git push/pull/fetch/clone 仍需输入用户名密码。
# ══════════════════════════════════════════
_gh_ensure_credential() {
    command -v gh &>/dev/null || return 1
    gh auth status &>/dev/null || return 1
    gh auth setup-git
}

# ══════════════════════════════════════════
#  🔐  HTTPS 令牌管理（token）
#  为什么需要这个指令：credential.helper=store 会把令牌明文缓存进
#  ~/.git-credentials，此后 git 不再向用户索要凭据。令牌轮换后 git 只会
#  反复报 401，而用户并不知道凭据被缓存在哪个文件、以什么格式存的。
#  这里统一走 git credential 协议（先 reject 再 approve），对 store /
#  cache / keychain / gh 各类 helper 都成立 —— 不需要知道令牌存在哪。
#  平台与令牌入口来自 _fz_platforms（单一真相源），此处不另建表。
# ══════════════════════════════════════════

# 把用户输入归一成 host；未知返回空
# 接受：英文简称（cnb）、主机名（cnb.cool）、表中显示名（腾讯云 CNB）
# ⚠️ 不能只靠「主机名首段」推简称：CODING 的主机是 e.coding.net，
#    首段是 "e"，用户会敲 coding。这类平台必须有显式别名。
_fz_token_host_of() {
    local want="${1:-}" name _url host _token
    # 显式别名优先（简称与主机首段不一致的平台放这里）
    case "$want" in
        coding|coding.net) want="e.coding.net" ;;
        gl)                want="gitlab.com" ;;
        gh)                want="github.com" ;;
    esac
    # 含点的一律当主机名直通（x.com 这类自定义平台无须入表）
    case "$want" in
        *.*) echo "$want"; return 0 ;;
    esac
    while IFS='|' read -r name _url host _token; do
        [ -z "$host" ] && continue
        [ "$want" = "${host%%.*}" ] && { echo "$host"; return 0; }
        [ "$want" = "$name" ] && { echo "$host"; return 0; }
    done < <(_fz_platforms)
    return 0
}

# 读当前凭据：输出 "username<TAB>password"，未存储则输出空
# 必须 GIT_TERMINAL_PROMPT=0：否则 git 会在终端里主动索要凭据，
# 而本函数只用于「看一眼当前状态」，绝不能打断用户。
_fz_token_current() {
    local host="$1" out u="" p=""
    out=$(printf 'protocol=https\nhost=%s\n\n' "$host" \
          | GIT_TERMINAL_PROMPT=0 git credential fill 2>/dev/null) || return 0
    u=$(printf '%s\n' "$out" | sed -n 's/^username=//p' | head -1)
    p=$(printf '%s\n' "$out" | sed -n 's/^password=//p' | head -1)
    [ -n "$p" ] && printf '%s\t%s\n' "${u:-?}" "$p"
    return 0
}

# 令牌脱敏：只暴露长度与前 4 位，输出到 stdout
_fz_token_mask() {
    local t="${1:-}" n
    n=${#t}
    if [ "$n" -le 8 ]; then
        echo "****（${n} 位，偏短，可能不是有效令牌）"
    else
        echo "${t:0:4}****（共 ${n} 位）"
    fi
}

_fz_token_help() {
    echo -e "\033[1;36m🔐 token — 更换各平台 HTTPS 令牌\033[0m

  \033[36mtoken\033[0m             列出各平台令牌状态，选一个更换
  \033[36mtoken cnb\033[0m         直接更换 CNB 令牌
  \033[36mtoken github\033[0m      更换 GitHub 令牌（走 git 凭据，非 gh）
  \033[36mtoken gitlab\033[0m      / gitee / coding
  \033[36mtoken x.com\033[0m       任意主机（直接给域名）

\033[90m  管的是 git 推送用的 HTTPS 令牌，不是 gh CLI 的登录态；
  GitHub 若装了 gh，凭据由 gh 接管，请改用 ghlogin。\033[0m"
}

# ══════════════════════════════════════════
#  🔐  令牌更换主入口（token）
# ══════════════════════════════════════════
_fz_token() {
    local arg="${1:-}" user_arg="${2:-}"
    case "$arg" in
        -h|--help|help) _fz_token_help; return 0 ;;
    esac

    local host="" pick_name="" pick_url=""
    if [ -n "$arg" ]; then
        host=$(_fz_token_host_of "$arg")
        if [ -z "$host" ]; then
            echo -e "\033[31m❌ 不认识的平台: ${arg}\033[0m（可给域名，如 token cnb.cool）" >&2
            return 1
        fi
    fi

    echo -e "\n\033[1;35m🔐 HTTPS 令牌管理\033[0m\n"

    # ── 无参数：列状态 + 选择平台 ──
    if [ -z "$host" ]; then
        local -a names=() hosts=() urls=() labels=()
        local name h _url token cur u p label
        while IFS='|' read -r name _url h token; do
            [ -z "$h" ] && continue          # 跳过「自定义 URL」项
            names+=("$name"); hosts+=("$h"); urls+=("$token")
            cur=$(_fz_token_current "$h")
            if [ -n "$cur" ]; then
                u="${cur%%$'\t'*}"; p="${cur#*$'\t'}"
                label="${name}（${u} · $(_fz_token_mask "$p")）"
            else
                label="${name}（未存储令牌）"
            fi
            labels+=("$label")
        done < <(_fz_platforms)

        # 非交互环境下 picker 退化为数字输入，空行 = 第一项
        _fz_picker "更换哪个平台的令牌: " "${labels[@]}" || {
            echo -e "\033[90m已取消\033[0m"; return 0
        }
        local idx="$FZ_PICK_RET"
        [[ "$idx" =~ ^[0-9]+$ ]] || { echo -e "\033[90m已取消\033[0m"; return 0; }
        local i=$((idx - 1))
        host="${hosts[$i]}"; pick_name="${names[$i]}"; pick_url="${urls[$i]}"
    fi

    # ── 当前状态 ──
    local cur u="" old="" masked="无"
    cur=$(_fz_token_current "$host")
    if [ -n "$cur" ]; then
        u="${cur%%$'\t'*}"; old="${cur#*$'\t'}"
        masked=$(_fz_token_mask "$old")
    fi
    echo -e "  平台     : \033[36m${pick_name:-$host}\033[0m（${host}）"
    echo -e "  账号     : \033[33m${u:-（未知）}\033[0m"
    echo -e "  当前令牌 : \033[33m${masked}\033[0m"
    [ -n "$pick_url" ] && echo -e "  新令牌   : \033[90m${pick_url}\033[0m"

    # ── 平台专属凭据助手会覆盖 store，提前说清楚 ──
    local host_helper
    host_helper=$(git config --get-all "credential.https://${host}.helper" 2>/dev/null | tail -1)
    if [ -n "$host_helper" ]; then
        echo -e "\033[33m⚠️  ${host} 的凭据由专属助手接管：${host_helper}\033[0m"
        if [ "$host" = "github.com" ]; then
            echo -e "\033[33m    更换 GitHub 令牌请用 \033[36mghlogin\033[0m\033[33m（本指令写入的会被它覆盖）\033[0m"
        fi
    fi

    # ── 输入新令牌：TTY 用静默读取，管道则从 stdin 取一行 ──
    local tok=""
    if [ -t 0 ]; then
        read -rsp "粘贴新令牌（输入不回显，回车确认）: " tok
        echo ""
    else
        read -r tok || tok=""
    fi
    tok="${tok%$'\r'}"
    # 去掉误粘贴的空白与 URL 包装（用户常整行复制）
    tok="${tok#"${tok%%[![:space:]]*}"}"; tok="${tok%"${tok##*[![:space:]]}"}"
    if [ -z "$tok" ]; then
        echo -e "\033[90m未输入，已取消（令牌未改动）\033[0m"
        return 1
    fi

    # 用户名：优先命令行第二参数，其次沿用旧值，都没有才问
    if [ -n "$user_arg" ]; then
        u="$user_arg"
    elif [ -z "$u" ] || [ "$u" = "?" ]; then
        if [ -t 0 ]; then
            read -rp "该平台用户名: " u
        fi
        if [ -z "$u" ]; then
            echo -e "\033[31m❌ 缺少用户名，无法保存令牌\033[0m" >&2
            return 1
        fi
    fi

    # ── 先删旧再写新：store 助手是追加写，不删会留下两条 ──
    #  ⚠️ 不能靠 approve 的退出码判断成败：实测即使 helper 彻底失败
    #     （程序不存在 / 目标文件不可写），git credential approve 仍返回 0。
    #     唯一可靠的判据是写完回读。回滚也必须在回读失败时做 ——
    #     此时旧令牌已被 reject 删掉，不恢复用户就卡在「旧的没了、新的没成」。
    local had_old=0
    [ -n "$old" ] && had_old=1
    printf 'protocol=https\nhost=%s\n\n' "$host" \
        | GIT_TERMINAL_PROMPT=0 git credential reject 2>/dev/null

    printf 'protocol=https\nhost=%s\nusername=%s\npassword=%s\n\n' "$host" "$u" "$tok" \
        | GIT_TERMINAL_PROMPT=0 git credential approve >/dev/null 2>&1

    # ── 回读校验：确认这个 host 现在取到的就是新令牌 ──
    local after a_user a_pass
    after=$(_fz_token_current "$host")
    a_user="${after%%$'\t'*}"; a_pass="${after#*$'\t'}"
    if [ -z "$after" ] || [ "$a_pass" != "$tok" ]; then
        if [ "$had_old" -eq 1 ]; then
            printf 'protocol=https\nhost=%s\nusername=%s\npassword=%s\n\n' "$host" "$u" "$old" \
                | GIT_TERMINAL_PROMPT=0 git credential approve >/dev/null 2>&1
            echo -e "\033[31m❌ 令牌未能写入，已恢复原令牌\033[0m" >&2
        else
            echo -e "\033[31m❌ 令牌未能写入（该平台原本没有存储凭据）\033[0m" >&2
        fi
        echo -e "\033[90m   当前生效助手: $(git config --get credential.helper 2>/dev/null || echo 无)\033[0m" >&2
        echo -e "\033[90m💡 若 $host 由专属助手接管，请用该平台自己的登录方式\033[0m" >&2
        return 1
    fi

    echo -e "\n\033[32m✅ 已更换 ${host} 令牌\033[0m"
    echo -e "   账号 \033[33m${a_user}\033[0m · 令牌 $(_fz_token_mask "$a_pass")"
    echo -e "\033[90m   旧令牌立即失效；若平台后台仍保留旧令牌记录，可去后台吊销\033[0m"
    [ "$host" = "cnb.cool" ] && echo -e "\033[90m   验证：在 CNB 项目里执行 \033[36mp cnb\033[0m\033[0m"
    return 0
}

# ══════════════════════════════════════════
#  🔑  GitHub 登录（ghlogin / login 兼容）
# ══════════════════════════════════════════
_github_login() {
    echo -e "\n\033[1;35m🔑 GitHub 登录向导\033[0m\n"

    # 非交互环境（管道/脚本）下 gh 的交互流程会阻塞，必须提前退出
    if [ ! -t 0 ]; then
        echo -e "\033[31m❌ ghlogin 需要交互终端，请直接在终端中执行\033[0m"
        return 1
    fi

    if ! command -v gh &>/dev/null; then
        echo -e "\033[31m❌ 需要先安装 GitHub CLI，执行 'setup'\033[0m"
        return 1
    fi

    # 只要 gh 已登录，就先确保 git 全局凭据已配置（幂等），
    # 避免“已登录 + 选不重登”提前 return 跳过后面的 gh auth setup-git
    _gh_ensure_credential

    if gh auth status &>/dev/null; then
        echo -e "\033[32m✅ 当前登录状态:\033[0m"
        gh auth status
        echo ""
        read -rp "重新登录？(y/n): " relogin
        [[ "$relogin" != "y" && "$relogin" != "Y" ]] && return 0
    fi

    echo -e "\033[36m选择登录方式:\033[0m"
    echo -e "  \033[33m1\033[0m. 浏览器授权（推荐）"
    echo -e "  \033[33m2\033[0m. Token 登录"
    read -rp "请选择 (1/2): " choice

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
        echo -e "\033[31m❌ 尚未登录 GitHub，执行 \033[36mghlogin\033[0m\033[31m 登录\033[0m"; return 1
    fi

    local default_name
    default_name=$(basename "$PWD")
    read -rp "📦 仓库名 (回车默认: ${default_name}): " repo_name
    repo_name="${repo_name:-$default_name}"

    read -rp "📝 仓库描述 (可选): " repo_desc

    echo -e "\033[36m仓库类型:\033[0m  \033[33m1\033[0m. 公开  \033[33m2\033[0m. 私有（默认）"
    read -rp "请选择 (1/2): " vis_choice
    local visibility="--private"
    [ "$vis_choice" = "1" ] && visibility="--public"

    local push_current="n"
    if git rev-parse --git-dir > /dev/null 2>&1; then
        read -rp "将当前目录推送到新仓库？(y/n): " push_current
    fi

    if [ "$push_current" = "y" ] || [ "$push_current" = "Y" ]; then
        git remote remove origin 2>/dev/null
    fi

    local create_rc=0
    if [ -n "$repo_desc" ]; then
        gh repo create "$repo_name" $visibility --description "$repo_desc" || create_rc=$?
    else
        gh repo create "$repo_name" $visibility || create_rc=$?
    fi

    if [ "$create_rc" -ne 0 ]; then
        echo -e "\033[31m❌ 仓库创建失败！\033[0m"
        return 1
    fi
    echo -e "\033[32m✅ 仓库创建成功！\033[0m"

    if [[ "$push_current" == "y" || "$push_current" == "Y" ]]; then
        local username
        username=$(gh api user --jq '.login' 2>/dev/null)
        # gh 未登录/失败时 username 为空，拼出的 URL 会是 //repo.git（静默加错远程）
        if [ -z "$username" ]; then
            echo -e "\033[31m❌ 无法获取 GitHub 用户名（是否已 login？）\033[0m"
            echo -e "\033[90m💡 执行 \033[36mlogin\033[0m\033[90m 登录后再试\033[0m"
            return 1
        fi
        local remote_url="https://github.com/${username}/${repo_name}.git"
        git remote add origin "$remote_url"
        _git_auto_ignore
        git add .
        # 不能 `2>/dev/null || true`：缺身份时 git commit 返回 128，
        # 吞掉后仍会继续 push 并打印「已推送」，而代码根本没进任何提交。
        local commit_out
        if ! commit_out=$(git commit -m "🎉 init: 项目初始化" 2>&1); then
            if echo "$commit_out" | grep -qiE "nothing to commit|nothing added"; then
                :   # 真的没有可提交内容，继续推送
            else
                echo -e "\033[31m❌ 初始提交失败：\033[0m" >&2
                echo "$commit_out" | head -5 | sed 's/^/   /' >&2
                echo -e "\033[90m💡 若是身份未配置，执行 \033[36msetup\033[0m\033[90m 设置 user.name / user.email\033[0m" >&2
                return 1
            fi
        fi
        git branch -M main
        if ! git push -u origin main; then
            echo -e "\033[31m❌ 推送到 ${remote_url} 失败\033[0m" >&2
            echo -e "\033[90m💡 检查网络/凭据；CNB 等平台可先 \033[36mtoken <平台>\033[0m\033[90m 配置令牌\033[0m" >&2
            return 1
        fi
        echo -e "\033[32m🚀 已推送至 ${remote_url}\033[0m\n"
    fi
}

# ══════════════════════════════════════════
#  🌐  平台表（单一真相源）
#  一张表同时喂三处：remote 绑定拼 URL、token 换令牌、HTTPS 凭据提示。
#  拆成多张表的后果是新增平台要改好几处，总有一处会被忘记。
#  列：名称|URL模板|主机|令牌生成入口
#  {user}=用户名/组织 {repo}=仓库名；主机为空表示非固定模板（自定义 URL）
# ══════════════════════════════════════════
_fz_platforms() {
    cat <<'FZ_PLATFORM_EOF'
GitHub|https://github.com/{user}/{repo}.git|github.com|https://github.com/settings/tokens
GitLab|https://gitlab.com/{user}/{repo}.git|gitlab.com|GitLab → Settings → Access Tokens（勾选 write_repository）
Gitee（码云）|https://gitee.com/{user}/{repo}.git|gitee.com|Gitee → 设置 → 私人令牌
腾讯云 CNB|https://cnb.cool/{user}/{repo}.git|cnb.cool|CNB → 右上头像 → 个人设置 → 访问令牌
CODING（腾讯）|https://e.coding.net/{user}/{user}/{repo}.git|e.coding.net|CODING → 个人设置 → 访问令牌
自定义（直接输入完整 URL）|||
FZ_PLATFORM_EOF
}

# 平台凭据提示：从表中取令牌入口，不再另维护一份 case 分支
_fz_platform_hint() {
    local want="${1:-}" name _url host token
    while IFS='|' read -r name _url host token; do
        [ "$name" = "$want" ] || continue
        [ -z "$token" ] && return 0
        echo -e "  💡 HTTPS 推送需令牌: \033[36m${token}\033[0m"
        return 0
    done < <(_fz_platforms)
    return 0
}

# 按 URL 猜平台名（info/remote 展示用）
_fz_platform_of() {
    case "${1:-}" in
        *github.com*)   echo "GitHub" ;;
        *gitlab.com*)   echo "GitLab" ;;
        *gitee.com*)    echo "Gitee" ;;
        *cnb.cool*)     echo "腾讯云 CNB" ;;
        *coding.net*)   echo "CODING" ;;
        *)              echo "其他平台" ;;
    esac
}

# 交互式确定远程 URL（返回全局变量 FZ_REMOTE_URL，失败置空）
# 交互设计要点（平台选择要能退出、URL 要能直接粘贴）：
#   1. 旧版把 "$(_fz_platforms | cut -d'|' -f1)" 作为一个带引号参数传给
#      _fz_picker，6 个平台被压成 1 个含换行的条目 → picker n=1，
#      ↑/↓ 指示器永远不动（用户视角即"卡死"）。现改为逐行读入数组。
#   2. 第一推荐项改为"粘贴完整 URL"，任意平台通吃，粘贴后自动识别平台；
#      平台模板保留为快捷方式。
#   3. 模板模式下用户名默认取 gh 登录账号，仓库名默认取当前目录名，
#      回车即可，不再强制手打。
_fz_build_url() {
    FZ_REMOTE_URL=""
    local -a p_names=() p_tmpls=()
    while IFS='|' read -r name tmpl _rest; do
        p_names+=("$name")
        p_tmpls+=("$tmpl")
    done < <(_fz_platforms)

    # ── 二选一：URL 直粘 / 用户名+仓库名拼装 ──
    # 平台表只在"名字拼装"分支出现；URL 粘贴天然跨平台无需平台表
    _fz_picker "绑定方式: " \
        "📎 粘贴完整仓库 URL（任意平台，自动识别，推荐）" \
        "🔤 用 用户名/仓库名 + 平台 拼装"
    local mode="$FZ_PICK_RET"

    if [ "$mode" = "1" ]; then
        read -rp "粘贴完整远程 URL（https://... 或 git@...）: " FZ_REMOTE_URL
        [ -z "$FZ_REMOTE_URL" ] && return 1
        echo -e "\033[90m识别平台: $(_fz_platform_of "$FZ_REMOTE_URL")\033[0m"
        return 0
    fi
    [ "$mode" = "2" ] || return 1

    # ── 名字拼装分支：先选平台 ──
    _fz_picker "选择平台: " "${p_names[@]}"
    local pidx="$FZ_PICK_RET"
    [[ ! "$pidx" =~ ^[0-9]+$ ]] && return 1
    local i=$((pidx - 1))
    local plat="${p_names[$i]}" tmpl="${p_tmpls[$i]}"

    if [ -z "$tmpl" ]; then
        read -rp "输入完整远程 URL: " FZ_REMOTE_URL
        [ -n "$FZ_REMOTE_URL" ] || return 1
        return 0
    fi

    local p_user p_repo
    local gh_user=""
    if command -v gh &>/dev/null; then
        gh_user=$(gh api user --jq '.login' 2>/dev/null)
    fi
    if [ -n "$gh_user" ]; then
        read -rp "用户名/组织名（回车=${gh_user}）: " p_user
        p_user="${p_user:-$gh_user}"
    else
        read -rp "用户名/组织名: " p_user
    fi
    [ -z "$p_user" ] && return 1

    local def_repo
    def_repo=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
    read -rp "仓库名（回车=${def_repo}）: " p_repo
    p_repo="${p_repo:-$def_repo}"
    [ -z "$p_repo" ] && return 1

    FZ_REMOTE_URL="${tmpl//\{user\}/$p_user}"
    FZ_REMOTE_URL="${FZ_REMOTE_URL//\{repo\}/$p_repo}"
    _fz_platform_hint "$plat"
    return 0
}

# ══════════════════════════════════════════
#  🔗  远程仓库管理（remote）
#  设计原则：绑定一个新远程只该做一件事——选平台 → 填用户名/仓库名 → 完成，
#  不再弹"四项主菜单"绕路；默认直接引导绑定/切换 origin（p 的默认远程），
#  绑定非 origin 远程时提示后续用 p 远程名 推送。
# ══════════════════════════════════════════
_remote_mgr() {
    _check_git_repo || return 1
    echo -e "\n\033[1;35m🔗 绑定远程仓库\033[0m\n"
    echo -e "\033[36m当前远程地址:\033[0m"
    git remote -v
    local cur_url
    cur_url=$(git remote get-url origin 2>/dev/null)
    [ -n "$cur_url" ] && echo -e "\033[90m识别平台: $(_fz_platform_of "$cur_url")（执行 p 默认推送到 origin）\033[0m"

    # 先定目标远程（回车默认 origin），决定后续操作作用于哪个远程
    _fz_picker "绑定到哪个远程（回车=origin）: " \
        "origin（p 默认推送目标）" \
        "新建远程（如 cnb / gitee，之后用 p 远程名 推送）" \
        "删除某个远程" \
        "查看远程详情"
    local op="$FZ_PICK_RET"
    local target="origin"
    case "$op" in
        2)
            local r_name
            read -rp "远程名称（如 cnb / gitee / upstream）: " r_name
            r_name="${r_name:-cnb}"
            target="$r_name" ;;
        3)
            # 用 picker 选择而非手打名字：
            # 输错/输不存在时既不报错也不删除，表现为"删除不了"）
            local -a r_list=()
            while IFS= read -r r; do
                [ -n "$r" ] && r_list+=("$r → $(git remote get-url "$r" 2>/dev/null)")
            done < <(git remote)
            if [ ${#r_list[@]} -eq 0 ]; then
                echo -e "\033[33m⚠️ 当前没有任何远程，无需删除\033[0m"
                return 0
            fi
            _fz_picker "删除哪个远程: " "${r_list[@]}"
            local r_sel="$FZ_PICK_RET"
            [[ ! "$r_sel" =~ ^[0-9]+$ ]] && { echo -e "\033[90m已取消\033[0m"; return 0; }
            local r_del="${r_list[$((r_sel - 1))]%% *}"
            read -rp "确认删除 ${r_del}？(y/n): " r_ok
            if [[ "$r_ok" == "y" || "$r_ok" == "Y" ]]; then
                git remote remove "$r_del" && echo -e "\033[32m✅ 已删除 $r_del\033[0m"
            else
                echo -e "\033[90m已取消\033[0m"
            fi
            return 0 ;;
        4)  git remote show origin; return 0 ;;
        *)  : ;;
    esac

    # 选平台 → 拼 URL（_fz_build_url 内部：picker 选平台 + 填用户名/仓库名）
    if _fz_build_url; then
        if git remote get-url "$target" >/dev/null 2>&1; then
            git remote set-url "$target" "$FZ_REMOTE_URL"
            echo -e "\033[32m✅ 已更新 $target → $FZ_REMOTE_URL\033[0m"
        else
            git remote add "$target" "$FZ_REMOTE_URL"
            echo -e "\033[32m✅ 已绑定 $target → $FZ_REMOTE_URL\033[0m"
        fi
        if [ "$target" != "origin" ]; then
            echo -e "\033[36m💡 之后执行 \033[1mp $target\033[0m \033[36m即可一键推送到该远程\033[0m"
        fi
    fi
}

# ══════════════════════════════════════════
#  🤖  AI 配置（转到 ai.sh）
#  保留此函数名以兼容 `setup` 等旧调用点。
# ══════════════════════════════════════════
_ai_setup() {
    _fz_ai_setup
}

# ══════════════════════════════════════════
#  🔄  自更新（up）
#  ⚠️ 更新方式是 git pull 整个仓库，
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

    read -rp "发现新版本，是否升级？(y/n): " c
    [ "$c" != "y" ] && [ "$c" != "Y" ] && return 0

    echo -e "\033[33m⬆️ 开始拉取更新...\033[0m"

    if git -C "$repo_root" pull --quiet; then
        # 更新后重新加载（~/.bashrc 中已有 source 指向新主入口）
        # shellcheck source=/dev/null  # 用户环境文件，静态分析不适用
        source ~/.bashrc 2>/dev/null
        echo -e "\033[32m🎉 焚诀更新成功！当前版本已进化至 v$remote_version\033[0m"
        echo -e "\033[90m💡 若提示无变化，请手动执行: source ~/.bashrc\033[0m"
    else
        echo -e "\033[31m❌ 拉取更新失败，请检查本地 scripts 仓库是否有未提交改动\033[0m"
        return 1
    fi
}

# ══════════════════════════════════════════
#  🎬  项目初始化（init）
#  空文件夹 → git init → 萌新引导链（绑远程 → 首次推送）
#  设计要点：
#   - 幂等：已是 git 仓库时提示后照常进入引导，不重复 init
#   - 初始化后先落一个 .gitignore 兜底 + 初始提交，保证分支存在
#   - 引导链每一步都可退出，退出不留脏状态
# ══════════════════════════════════════════
_fz_init() {
    echo -e "\n\033[1;35m🎬 项目初始化\033[0m\n"

    if git rev-parse --git-dir &>/dev/null; then
        echo -e "\033[33m⚠️ 当前目录已经是 git 仓库，无需重复初始化\033[0m"
    else
        git init || { echo -e "\033[31m❌ git init 失败\033[0m"; return 1; }
        echo -e "\033[32m✅ git 仓库已初始化\033[0m"
    fi

    # 主分支统一为 main（与 p / b 模块习惯一致）
    # ⚠️ 不能靠 `git symbolic-ref --short HEAD` 是否为空来判断：
    #    git init 之后 HEAD 已指向 refs/heads/master（分支尚未创建），
    #    该命令会返回 "master" 而不是空，导致改名逻辑被跳过。
    #    正确判断是「当前分支名不是 main」——此时若该分支还没有提交，
    #    直接改 HEAD 指向即可。
    local cur_branch
    cur_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    if [ -n "$cur_branch" ] && [ "$cur_branch" != "main" ]; then
        # 仅当该分支尚无提交时才改名（已有历史的分支不动，避免惊吓）
        if ! git rev-parse --verify --quiet "refs/heads/${cur_branch}" >/dev/null 2>&1; then
            git symbolic-ref HEAD refs/heads/main 2>/dev/null
            # 若 remote 已存在且默认分支是 master，同步过去更省事
            cur_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
        fi
    elif [ -z "$cur_branch" ]; then
        git symbolic-ref HEAD refs/heads/main 2>/dev/null
    fi

    # 初始提交：仅当仓库完全无提交时做（避免覆盖用户已有历史）
    if ! git rev-parse HEAD &>/dev/null; then
        [ -f .gitignore ] || printf '.DS_Store\n*.log\nnode_modules/\n__pycache__/\n' > .gitignore
        git add . 2>/dev/null
        git commit -m "🎉 init: 项目初始化" --allow-empty &>/dev/null
        echo -e "\033[32m✅ 初始提交已创建\033[0m"
    fi

    # ── 萌新引导链 ──
    # has_remote 决定默认选项：已绑远程时「试试推送」才有意义
    local has_remote
    has_remote=$(git remote | head -1)
    if [ -n "$has_remote" ]; then
        _fz_picker "下一步做什么: " \
            "🚀 直接试试推送 p（已绑定远程 [${has_remote}]）" \
            "🔗 管理远程仓库" \
            "✅ 暂时不用，我自己来（随时执行 h 查看全部指令）"
    else
        _fz_picker "下一步做什么: " \
            "🔗 绑定远程仓库（绑定后才能备份到云端）" \
            "🚀 直接试试推送 p（没绑远程会失败）" \
            "✅ 暂时不用，我自己来（随时执行 h 查看全部指令）"
    fi
    case "$FZ_PICK_RET" in
        1)
            if [ -n "$has_remote" ]; then
                _p_push
            else
                _remote_mgr
            fi
            ;;
        2)
            if [ -n "$has_remote" ]; then
                _remote_mgr
            else
                _p_push
            fi
            ;;
        *) echo -e "\033[90m💡 已初始化完成。常用: p=推送 · st=状态 · cl=克隆 · h=全部指令\033[0m" ;;
    esac
}
