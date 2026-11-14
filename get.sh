#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  《焚诀·Git 工作流》一行安装入口
#
#  安装：
#    curl -fsSL https://raw.githubusercontent.com/zzgs219G/scripts/main/get.sh | bash
#
#  卸载：
#    bash ~/.local/share/fz/fz-tools/install.sh --uninstall
#    # 或再取一次本脚本：curl -fsSL <同上> | bash -s -- --uninstall
#
#  可用环境变量：
#    FZ_HOME      安装目录（默认 ~/.local/share/fz）
#    FZ_REPO_URL  仓库地址（默认官方仓库，便于 fork 自用）
#    FZ_BRANCH    分支（默认 main）
#    FZ_RC        要写入的启动文件（默认 ~/.bashrc）
# ════════════════════════════════════════════════════════════
#  设计说明（为什么是「clone」而不是「下载单文件」）：
#    `c` 需要在当前 shell 里 cd，而 POSIX 不允许子进程改父进程 cwd，
#    因此本工具只能以「被 source 的函数库」形态存在——必然是本地文件。
#    这与 nvm / asdf / oh-my-zsh 的形态一致，不是不规范。
#    本脚本只是把「手动 clone + 手动改 .bashrc」这一步自动化。
# ════════════════════════════════════════════════════════════

set -uo pipefail

FZ_HOME="${FZ_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/fz}"
FZ_REPO_URL="${FZ_REPO_URL:-https://github.com/zzgs219G/scripts.git}"
FZ_BRANCH="${FZ_BRANCH:-main}"
FZ_RC="${FZ_RC:-$HOME/.bashrc}"
FZ_MARKER="# --- FZ-TOOLS: 焚诀入口 ---"

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'
CYN=$'\033[36m'; DIM=$'\033[90m'; BLD=$'\033[1m'; RST=$'\033[0m'

say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✅ %s%s\n' "$GRN" "$*" "$RST"; }
warn() { printf '%s⚠️  %s%s\n' "$YEL" "$*" "$RST"; }
err()  { printf '%s❌ %s%s\n' "$RED" "$*" "$RST" >&2; }
dim()  { printf '%s   %s%s\n' "$DIM" "$*" "$RST"; }

# ── stdin 处理 ──
# `curl ... | bash` 时脚本自身的 stdin 是管道，交互式 read 会立刻读到 EOF。
# 有终端时把 stdin 切回终端；没有终端（CI）则全部走非交互路径。
# ⚠️ 不能写 `exec < /dev/tty 2>/dev/null`：失败时 stdin 已被关闭，
#    后续任何 read 都只能读到 EOF，导致「确认」类交互永远被当作取消。
HAVE_TTY=0
if [ -t 0 ]; then
    HAVE_TTY=1
elif ( : < /dev/tty ) 2>/dev/null; then
    # 先探测可读，再切换；探测失败则保持原 stdin 不动
    if exec < /dev/tty 2>/dev/null; then HAVE_TTY=1; fi
fi

# ask <提示> [默认答案]
#   有终端：读用户输入；直接回车 → 用默认答案
#   无终端：不阻塞，直接采用默认答案（CI/管道场景）
# 返回值：0=确认执行, 1=放弃
ask_confirm() {
    local prompt="$1" def="${2:-n}" reply=""
    if [ "$HAVE_TTY" -eq 1 ]; then
        printf '%s%s%s ' "$CYN" "$prompt" "$RST"
        IFS= read -r reply || reply=""
        [ -z "$reply" ] && reply="$def"
    else
        reply="$def"
        dim "非交互环境，默认回答: ${def}"
    fi
    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

# ── 卸载 ──
do_uninstall() {
    local assume_yes="${1:-0}"
    say ""
    say "${BLD}🗑️  卸载《焚诀》${RST}"
    say ""
    if [ ! -d "$FZ_HOME" ]; then
        warn "未在 ${FZ_HOME} 找到安装"
        dim "若从别处 clone，请直接删掉那个目录，并手动移除 .bashrc 中的 source 行"
        return 0
    fi
    say "将执行："
    dim "1. 从 ${FZ_RC} 移除 source 行"
    dim "2. 删除 ${FZ_HOME}（含仓库）"
    dim "3. 保留 ${HOME}/.fz_bookmarks（你的书签）与 ${HOME}/.fz_ai_key（你的 Key）"
    say ""
    # 无终端时必须显式 --yes：破坏性操作不接受「默认同意」
    if [ "$assume_yes" -eq 1 ]; then
        dim "（--yes 已指定，跳过确认）"
    elif [ "$HAVE_TTY" -ne 1 ]; then
        err "非交互环境下卸载需要显式确认"
        dim "用法: ... | bash -s -- --uninstall --yes"
        return 1
    elif ! ask_confirm "确认卸载？(y/N)" "n"; then
        say "已取消"
        return 0
    fi

    if [ -f "$FZ_RC" ]; then
        cp "$FZ_RC" "${FZ_RC}.bak.fz.$(date +%s)" 2>/dev/null || true
        # 同时清掉旧的注入块与任意 fz-tools 的 source 行
        grep -v 'fz-tools/fzgit\.sh' "$FZ_RC" | grep -vF "$FZ_MARKER" > "${FZ_RC}.tmp.$$" \
            && mv "${FZ_RC}.tmp.$$" "$FZ_RC"
        ok "已从 ${FZ_RC} 移除加载行（已备份）"
    fi

    rm -rf "$FZ_HOME"
    ok "已删除 ${FZ_HOME}"
    say ""
    say "书签与 Key 已保留："
    dim "${HOME}/.fz_bookmarks"
    dim "${HOME}/.fz_ai_key"
    dim "如需一并删除：rm -f ${HOME}/.fz_bookmarks ${HOME}/.fz_ai_key"
    say ""
    say "当前 shell 里的别名仍然有效，退出重开即可清除。"
}

# ── 依赖检查 ──
need_git() {
    command -v git >/dev/null 2>&1 && return 0
    err "未安装 git"
    if command -v pkg >/dev/null 2>&1; then
        dim "Termux: pkg install git"
    elif command -v brew >/dev/null 2>&1; then
        dim "macOS:  brew install git"
    else
        dim "Debian/Ubuntu: sudo apt install git"
    fi
    return 1
}

# ── 主流程 ──
main() {
    say ""
    say "${BLD}🔥 《焚诀·Git 工作流》安装${RST}"
    say ""

    need_git || exit 1

    # 1) 取到代码（幂等）
    if [ -d "$FZ_HOME/.git" ]; then
        say "📦 已存在安装目录：${FZ_HOME}"
        local cur_url
        cur_url=$(git -C "$FZ_HOME" remote get-url origin 2>/dev/null || echo "?")
        dim "origin = ${cur_url}"
        if [ -n "$(git -C "$FZ_HOME" status --porcelain 2>/dev/null)" ]; then
            warn "该目录有未提交改动，跳过更新"
            dim "如需更新：cd ${FZ_HOME} && git stash && git pull"
        else
            say "🔄 拉取最新代码..."
            if git -C "$FZ_HOME" fetch --quiet origin "$FZ_BRANCH" 2>/dev/null \
               && git -C "$FZ_HOME" merge --ff-only FETCH_HEAD >/dev/null 2>&1; then
                ok "已更新到最新"
            else
                warn "更新失败（可能已是最新或存在分叉），继续使用当前版本"
            fi
        fi
    else
        say "📥 克隆到 ${FZ_HOME}"
        mkdir -p "$(dirname "$FZ_HOME")" || { err "无法创建目录 $FZ_HOME"; exit 1; }
        # 目标已存在但不是 git 仓库 → 不覆盖，避免吃掉用户数据
        if [ -e "$FZ_HOME" ] && [ ! -d "$FZ_HOME/.git" ]; then
            err "${FZ_HOME} 已存在且不是 git 仓库，拒绝覆盖"
            dim "请先移除该目录，或用 FZ_HOME=... 指定其它位置"
            exit 1
        fi
        if ! git clone --quiet --branch "$FZ_BRANCH" --depth 1 "$FZ_REPO_URL" "$FZ_HOME"; then
            err "克隆失败"
            dim "检查网络，或用 FZ_REPO_URL 指定镜像"
            exit 1
        fi
        ok "克隆完成"
    fi

    # 2) 校验结构（避免 clone 到一半或仓库结构变化后写坏 .bashrc）
    local main_file="${FZ_HOME}/fz-tools/fzgit.sh"
    if [ ! -f "$main_file" ]; then
        err "仓库结构异常：缺少 ${main_file}"
        dim "可能仓库结构已变更，或分支 ${FZ_BRANCH} 不存在"
        exit 1
    fi

    # 3) 写启动文件（幂等）
    [ -f "$FZ_RC" ] || touch "$FZ_RC" 2>/dev/null || {
        err "无法创建 ${FZ_RC}"; exit 1; }

    cp "$FZ_RC" "${FZ_RC}.bak.fz.$(date +%s)" 2>/dev/null || true
    # 移除本工具的既有加载行与旧注入块（任意安装路径都能被替换掉）
    if grep -q 'fz-tools/fzgit\.sh' "$FZ_RC" 2>/dev/null; then
        grep -v 'fz-tools/fzgit\.sh' "$FZ_RC" > "${FZ_RC}.tmp.$$" && mv "${FZ_RC}.tmp.$$" "$FZ_RC"
    fi
    grep -vF "$FZ_MARKER" "$FZ_RC" > "${FZ_RC}.tmp.$$" 2>/dev/null && mv "${FZ_RC}.tmp.$$" "$FZ_RC"
    # 旧版 curl 注入块的清理（历史遗留）
    sed -i.bak '/# --- AI_GIT_WORKFLOW ---/,/# --- END ---/d' "$FZ_RC" 2>/dev/null || true
    rm -f "${FZ_RC}.bak" 2>/dev/null || true

    printf '\n%s\nsource "%s"\n' "$FZ_MARKER" "$main_file" >> "$FZ_RC"
    ok "已写入 ${FZ_RC}"

    # 4) 在当前进程加载一次，跑环境初始化
    # shellcheck source=/dev/null
    source "$main_file"

    say ""
    say "${BLD}🎉 安装完成${RST}（v${FZ_VERSION:-?}）"
    say ""
    dim "安装目录: ${FZ_HOME}"
    dim "加载文件: ${FZ_RC}"
    dim "重新打开终端，或执行： source ${FZ_RC}"
    say ""
    say "下一步："
    dim "  setup     检查环境 + 配置 Git 身份 + 创建书签"
    dim "  c         书签 → 项目 → 进入（最常用）"
    dim "  h         查看全部指令"
    dim "  aikey     配置 AI 自动生成 commit 说明（可选）"
    say ""

    # 5) 首次安装时直接进入初始化向导
    if [ "$HAVE_TTY" -eq 1 ]; then
        if ask_confirm "现在运行 setup 初始化环境？(Y/n)" "y"; then
            _setup_env || warn "setup 未完成，可稍后重跑"
        else
            say "已跳过。随时执行 setup"
        fi
    else
        dim "非交互环境，跳过 setup。请稍后手动执行 setup"
    fi
}

# 参数解析：支持 --uninstall --yes 任意顺序
UNINSTALL=0; ASSUME_YES=0
for _a in "$@"; do
    case "$_a" in
        --uninstall|uninstall|-u) UNINSTALL=1 ;;
        --yes|-y)                 ASSUME_YES=1 ;;
        -h|--help|help)           SHOW_HELP=1 ;;
        "")                       ;;
        *) err "未知参数: $_a（可用: --uninstall / --yes / --help）"; exit 1 ;;
    esac
done

if [ "${SHOW_HELP:-0}" -eq 1 ]; then
    say "用法："
    say "  安装:   curl -fsSL <url> | bash"
    say "  卸载:   curl -fsSL <url> | bash -s -- --uninstall --yes"
    say ""
    say "环境变量："
    say "  FZ_HOME      安装目录（默认 \${XDG_DATA_HOME:-~/.local/share}/fz）"
    say "  FZ_REPO_URL  仓库地址（默认官方仓库，便于 fork 自用）"
    say "  FZ_BRANCH    分支（默认 main）"
    say "  FZ_RC        启动文件（默认 ~/.bashrc）"
    exit 0
fi

if [ "$UNINSTALL" -eq 1 ]; then
    do_uninstall "$ASSUME_YES"
    exit $?
fi

main
