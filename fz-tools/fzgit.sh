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

# ── 版本号（v5.1 智能迭代：体验增强 + P0 修复）──
FZ_VERSION="5.91"

# ── FZ_BASE：仅作 burn.sh 输出备用（v5.0 不再参与导航）──
#     首次 setup/c 时自动导入为默认书签（见 modules/bookmark.sh _bm_init）
if [ -d "/storage/emulated/0/常用" ]; then
    _FOUND_PATH=$(find /storage/emulated/0/常用/ -maxdepth 2 -type d -name "*克隆仓库*" 2>/dev/null | head -n 1)
    export FZ_BASE="${_FOUND_PATH:-/storage/emulated/0/常用/工作台😡/克隆仓库}"
else
    export FZ_BASE="${HOME}/repos"
fi
mkdir -p "${FZ_BASE}"
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

for _fz_mod in env bookmark nav branch push merge view stash fix tag burn clone pullall; do
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
alias undo='git restore . && echo -e "\033[33m↩️ 已撤销工作区所有未提交修改\033[0m"'
alias unstage='git restore --staged . && echo -e "\033[33m↩️ 已取消所有暂存\033[0m"'

# ══════════════════════════════════════════
#  📖  帮助菜单（与原版完全一致）
# ══════════════════════════════════════════
alias h='echo -e "\033[1;36m
╔══════════════════════════════════════════╗
║      焚诀·Git 工作流  v${FZ_VERSION}              ║
╚══════════════════════════════════════════╝\033[0m

\033[33m⚠️ 首次使用请先安装依赖：\033[0m

  \033[36mpkg install git curl gh\033[0m
\033[90m（Ubuntu/Debian: sudo apt install git curl gh）\033[0m

\033[33m📌 安装后执行：\033[0m  \033[36msetup\033[0m  →  \033[36mlogin\033[0m  →  \033[36maikey\033[0m（可选）

\033[1;35m╔══════════════════════════════════════════╗
║      指令秘籍                            ║
╚══════════════════════════════════════════╝\033[0m
\033[1;33m── 🔧检查更新 ───────────────────────\033[0m
  \033[36mup\033[0m         一键检查更新/自动升级《焚诀》
\033[1;33m── 🔧 初始化 ────────────────────────────\033[0m
  \033[36msetup\033[0m    检查环境 + 配置 Git 全局信息
  \033[36mlogin\033[0m    登录 GitHub（浏览器/Token）
  \033[36mrepo\033[0m     创建远程仓库
  \033[36mremote\033[0m   管理远程地址（增删改查）
  \033[36mtrust\033[0m    信任当前目录（safe.directory）
  \033[36maikey\033[0m    配置 AI commit key（Anthropic）

\033[1;33m── 📂 项目导航（书签制）──────────────────\033[0m
  \033[36mbookmark\033[0m  管理书签（增删改查）
  \033[36mlsp\033[0m       所有书签项目状态总览
  \033[36mc\033[0m         书签→项目→操作 交互导航
  \033[36mc <名字>\033[0m   书签/项目关键字直达
  \033[36mcl\033[0m         交互式克隆（gh 仓库列表选择）
  \033[36mcl <仓库>\033[0m  直接克隆到当前目录/指定书签
  \033[36mpullall\033[0m   批量拉取所有书签项目
  \033[36mpullall <书签>\033[0m 只更新指定书签

\033[1;33m── 🌿 分支操作 ──────────────────────────\033[0m
  \033[36mb all\033[0m      打捞全部远程分支并本地镜像
  \033[36mb\033[0m          列出分支 → 选编号切换
  \033[36mb <名字>\033[0m   直接切换/创建分支
  \033[36mb -l\033[0m       显示所有分支（含远程）
  \033[36mb ql\033[0m       清理分支缓存
  \033[36mb -d <名>\033[0m   删除本地分支
  \033[36mb -dr <名>\033[0m  删除远程分支
  \033[36mgomain\033[0m     回到 main/master
  \033[36mrn\033[0m         重命名当前分支（本地+远程）
  \033[36mbclean\033[0m     清理已合并的本地分支

\033[1;33m── 🚀 推送 & 发布 ───────────────────────\033[0m
  \033[36mp\033[0m          推送，p skip可跳过CI构建
  \033[36mp \"备注\"\033[0m   指定备注推送
  \033[36mgsync\033[0m      安全同步远程（fetch+rebase）
  \033[36mpull\033[0m       拉取最新代码
  \033[36mok\033[0m         合并 dev→main 发布
  \033[36mok dev main skip\033[0m  合并 跳过 CI 构建
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
  \033[36mf\033[0m          全量打包源码（滤掉垃圾，喂给AI）
  \033[36mf <模块>\033[0m    只打包指定模块
  \033[36mf -d\033[0m       只打包未提交的改动
  \033[36mundo\033[0m       撤销工作区所有修改 ⚠️
  \033[36munstage\033[0m    取消所有暂存
  \033[36mh\033[0m          显示此菜单"'

# ══════════════════════════════════════════
#  💡 直接执行时给出提示（正常用法是 source）
# ══════════════════════════════════════════
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo -e "\n\033[1;33m📖 焚诀 v${FZ_VERSION} 已加载到当前会话\033[0m"
    echo -e "   执行 \033[36mh\033[0m 查看全部指令"
    echo -e "   若需全局生效，请将下面这行追加到 ~/.bashrc："
    echo -e "   \033[32msource ${FZ_MAIN}\033[0m\n"
fi
