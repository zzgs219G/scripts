#!/usr/bin/env bash
#  ════════════════════════════════════════════════════════════
#  《焚诀·Git 工作流》 主入口  v5.0（智能书签·零硬编码版）
# ════════════════════════════════════════════════════════════
#  安装（新方式，克隆后写入 ~/.bashrc）：
#     git clone https://github.com/zzgs219G/scripts.git
#     echo 'source /<仓库路径>/fz-tools/fzgit.sh' >> ~/.bashrc
#  迁移（旧版 curl 注入用户）：
#     bash /<仓库路径>/fz-tools/install.sh
# ════════════════════════════════════════════════════════════
#  本文件只负责四件事：
#    1. 环境变量（FZ_VERSION / FZ_BASE / FZ_AI_KEY / FZ_MAIN / FZ_TOOLS_DIR）
#    2. 路径自适应 + 模块加载（core.sh + modules/*.sh）
#    3. 全部别名注册
#    4. 帮助菜单
#  功能函数已拆分至各模块文件，请勿在本文件新增函数。
#  ⚠️ v5.0 迁移策略：FZ_BASE 仅保留用于 burn.sh 输出备用，
#     导航/克隆/拉取全部改为书签系统（~/.fz_bookmarks）。
# ════════════════════════════════════════════════════════════

# ── 版本号（v5.100 修复：p 以「目标远程」而非 @{u} 判断是否推送）──
FZ_VERSION="5.109"

# ── FZ_BASE：仅作 burn.sh 输出备用（v5.0 不再参与导航）──
#     v5.2 跨平台化：Termux 保留原探测，电脑端自动用 ~/repos
if [ -d "/storage/emulated/0" ] 2>/dev/null; then
    _FOUND_PATH=$(find /storage/emulated/0/常用/ -maxdepth 2 -type d -name "*克隆仓库*" 2>/dev/null | head -n 1)
    export FZ_BASE="${_FOUND_PATH:-/storage/emulated/0/常用/工作台😡/克隆仓库}"
else
    export FZ_BASE="${HOME}/repos"
fi
mkdir -p "${FZ_BASE}" 2>/dev/null
unset _FOUND_PATH

# AI commit message 功能开关（aikey 配置后自动开启并持久化到本文件）
export FZ_AI_KEY=""

# ── 路径自适应：无论从何处 source，都能定位自身与模块目录 ──
_FZ_SRC="${BASH_SOURCE[0]}"
_FZ_DIR="$(cd "$(dirname "${_FZ_SRC}")" && pwd)"
export FZ_MAIN="${_FZ_DIR}/fzgit.sh"      # 主入口绝对路径（aikey 持久化用）
export FZ_TOOLS_DIR="${_FZ_DIR}"          # 工具目录绝对路径（自更新用）

# ── 加载 core（工具目录顶层）+ 全部功能模块（modules/ 下）──
if [ -f "${_FZ_DIR}/core.sh" ]; then
    source "${_FZ_DIR}/core.sh"
else
    echo -e "\033[31m❌ [焚诀] 缺少文件: ${_FZ_DIR}/core.sh\033[0m" >&2
fi

for _fz_mod in env bookmark nav branch push merge view stash fix tag burn clone pullall reasonix; do
    _fz_mod_file="${_FZ_DIR}/modules/${_fz_mod}.sh"
    if [ -f "${_fz_mod_file}" ]; then
        source "${_fz_mod_file}"
    else
        echo -e "\033[31m❌ [焚诀] 缺少模块文件: ${_fz_mod_file}\033[0m" >&2
    fi
done
unset _fz_mod _fz_mod_file _FZ_SRC _FZ_DIR

# ══════════════════════════════════════════
#  🔤  别名注册（v5.0）
# ══════════════════════════════════════════
alias up='_update_script'
alias init='_fz_init'
alias setup='_setup_env'
alias login='_github_login'
alias repo='_create_repo'
alias remote='_remote_mgr'
alias trust='_trust_dir'
alias aikey='_ai_setup'
alias bookmark='_bookmark_mgr'
alias c='_c_jump'
alias lsp='_ls_projects'
alias b='_branch_mgr'
alias rn='_rename_branch'
alias bclean='_clean_branches'
alias gsync='_sync_branch'
alias p='_p_push'
alias ok='_ok_merge'
alias no='_no_revert'
alias gomain='_main_branch'
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
alias st='_st_status'
alias pull='_pull_now'
alias rsx='_rsx_install'
alias h='_fz_help'
alias undo='git restore . && echo -e "\033[33m↩️ 已撤销工作区所有未提交修改\033[0m"'
alias unstage='git restore --staged . && echo -e "\033[33m↩️ 已取消所有暂存\033[0m"'

# ══════════════════════════════════════════
#  💡 直接执行时给出提示（正常用法是 source）
# ══════════════════════════════════════════
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo -e "\n\033[1;33m📖 焚诀 v${FZ_VERSION} 已加载到当前会话\033[0m"
    echo -e "   执行 \033[36mh\033[0m 查看全部指令"
    echo -e "   若需全局生效，请将下面这行追加到 ~/.bashrc："
    echo -e "   \033[32msource ${FZ_MAIN}\033[0m\n"
fi
