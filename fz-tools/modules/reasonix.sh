#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — reasonix.sh（应用安装模块）
#  职责：一键安装 / 升级 Reasonix CLI
#        （拉源码 → 编译 → 装到 PATH → 关闭 bash 沙箱限制 → 验证）
#  包含函数：_rsx_install  _rsx_fix_cfg
#  对应别名：rsx
#  由 fz-tools/fzgit.sh 自动加载
#  ⚠️ 与独立脚本（docs/文档.md 的 rsx-install.sh）的关键差异：
#     本函数运行在用户交互 shell 内，绝不能用 set -e
#     （会让整个终端会话出错即退出），所有错误一律显式 return 1。
# ════════════════════════════════════════════════════════════

# 可被用户覆盖的变量：先赋值再用，避免重复 source 时被重置
: "${RSX_REPO_URL:=https://github.com/esengine/DeepSeek-Reasonix.git}"
: "${RSX_SRC_DIR:=${HOME}/DeepSeek-Reasonix}"
: "${RSX_BRANCH:=studio}"

# ══════════════════════════════════════════
#  ⚙️  关闭 bash 沙箱限制（bash = "enforce" → "off"）
#  不关闭则 CLI 无权限执行本地命令
#  参数：$1 = 刚安装的 reasonix 可执行文件路径（用于触发默认配置生成）
# ══════════════════════════════════════════
_rsx_fix_cfg() {
    local bin="${1:-}"
    local c1="${HOME}/.reasonix/config.toml"
    local c2="${HOME}/.config/reasonix/config.toml"
    local line='bash = "off"'
    local found=0

    # 首次安装时配置往往还不存在：先跑一次二进制，让它自己生成默认配置
    if [ ! -f "$c1" ] && [ ! -f "$c2" ] && [ -n "$bin" ] && [ -x "$bin" ]; then
        "$bin" --version >/dev/null 2>&1 || true
    fi

    local cfg
    for cfg in "$c1" "$c2"; do
        [ -f "$cfg" ] || continue
        found=1

        if grep -qE '^[[:space:]]*bash[[:space:]]*=[[:space:]]*"enforce"' "$cfg"; then
            sed -i 's/^[[:space:]]*bash[[:space:]]*=[[:space:]]*"enforce"/bash = "off"/' "$cfg" \
                && echo -e "\033[32m⚙️  已关闭 bash 沙箱限制: ${cfg}\033[0m"
        elif grep -qE '^[[:space:]]*bash[[:space:]]*=' "$cfg"; then
            echo -e "\033[90m⚙️  ${cfg} 中 bash 已非 enforce，无需修改\033[0m"
        else
            # 顶层键必须位于所有 [section] 之前，所以插入文件头而非追加到末尾
            local tmp="${cfg}.fz$$"
            if { printf '%s\n' "$line"; cat "$cfg"; } > "$tmp" 2>/dev/null && mv "$tmp" "$cfg"; then
                echo -e "\033[32m⚙️  已写入 bash = \"off\": ${cfg}\033[0m"
            else
                rm -f "$tmp" 2>/dev/null
                echo -e "\033[31m❌ 写入失败: ${cfg}\033[0m"
            fi
        fi
    done

    if [ "$found" -eq 0 ]; then
        # 两个候选都不存在：按文档约定创建 ~/.reasonix/config.toml
        if mkdir -p "${HOME}/.reasonix" 2>/dev/null && printf '%s\n' "$line" > "$c1"; then
            echo -e "\033[32m⚙️  已创建 ${c1}（bash = \"off\"）\033[0m"
        else
            echo -e "\033[31m❌ 无法创建 ${c1}\033[0m"
            return 1
        fi
    fi
    return 0
}

# ══════════════════════════════════════════
#  🧩  安装 / 升级 Reasonix CLI（rsx）
# ══════════════════════════════════════════
_rsx_install() {
    echo -e "\n\033[1;35m🧩 Reasonix CLI 安装 / 升级\033[0m\n"

    # ── 1. 编译依赖 ──
    local -a need=()
    command -v git  >/dev/null 2>&1 || need+=(git)
    command -v make >/dev/null 2>&1 || need+=(make)
    command -v go   >/dev/null 2>&1 || need+=(golang)

    if [ ${#need[@]} -gt 0 ]; then
        if command -v pkg >/dev/null 2>&1; then
            echo -e "\033[33m📦 安装编译依赖: ${need[*]}\033[0m"
            if ! pkg install -y "${need[@]}"; then
                echo -e "\033[31m❌ 依赖安装失败\033[0m"
                return 1
            fi
        else
            echo -e "\033[31m❌ 缺少依赖: ${need[*]}\033[0m"
            echo -e "   \033[90m非 Termux 环境请手动安装（如 apt install git make golang）\033[0m"
            return 1
        fi
    fi

    # ── 2. 准备源码 ──
    if [ -d "${RSX_SRC_DIR}/.git" ]; then
        echo -e "\033[36m📂 复用已有仓库: ${RSX_SRC_DIR}\033[0m"
        local cur_br
        cur_br=$(git -C "$RSX_SRC_DIR" branch --show-current 2>/dev/null)
        if [ "$cur_br" != "$RSX_BRANCH" ]; then
            echo -e "\033[33m🔀 切换分支: ${cur_br:-（游离 HEAD）} → ${RSX_BRANCH}\033[0m"
            if ! git -C "$RSX_SRC_DIR" switch "$RSX_BRANCH"; then
                echo -e "\033[31m❌ 无法切换到 ${RSX_BRANCH} 分支\033[0m"
                return 1
            fi
        fi
        # 先 fetch 再 ff-only 合并：区分「网络/远端不可达」与「本地脏改动」
        if ! git -C "$RSX_SRC_DIR" fetch --quiet 2>/dev/null; then
            echo -e "\033[31m❌ 获取远程失败，请检查网络或代理设置\033[0m"
            return 1
        fi
        if ! git -C "$RSX_SRC_DIR" merge --ff-only FETCH_HEAD >/dev/null 2>&1; then
            echo -e "\033[31m❌ 合并失败：源码目录有本地改动或与远端已分叉\033[0m"
            echo -e "   \033[90m处理后再执行 rsx：cd ${RSX_SRC_DIR} && git status\033[0m"
            return 1
        fi
    else
        echo -e "\033[36m⬇️  克隆源码: ${RSX_REPO_URL}\033[0m"
        if ! git clone "$RSX_REPO_URL" "$RSX_SRC_DIR"; then
            echo -e "\033[31m❌ 克隆失败，请检查网络\033[0m"
            return 1
        fi
        if ! git -C "$RSX_SRC_DIR" switch "$RSX_BRANCH"; then
            echo -e "\033[31m❌ 仓库中没有 ${RSX_BRANCH} 分支（2.x CLI 所在分支）\033[0m"
            return 1
        fi
    fi

    # ── 3. 编译 ──
    echo -e "\033[36m🔨 编译中（首次较慢）...\033[0m"
    if ! make -C "$RSX_SRC_DIR" build; then
        echo -e "\033[31m❌ 编译失败\033[0m"
        echo -e "   \033[90m排查：cd ${RSX_SRC_DIR} && make build\033[0m"
        return 1
    fi

    local bin="${RSX_SRC_DIR}/bin/reasonix"
    if [ ! -f "$bin" ]; then
        echo -e "\033[31m❌ 编译产物不存在: ${bin}\033[0m"
        return 1
    fi

    # ── 4. 安装到 PATH ──
    # Termux 用 $PREFIX/bin；其他环境（$PREFIX 为空）回退 ~/.local/bin，
    # 避免文档脚本里 `cp ... $PREFIX/bin/` 在非 Termux 下写到 /bin 的隐患
    local dest
    if [ -n "${PREFIX:-}" ] && [ -d "${PREFIX}/bin" ]; then
        dest="${PREFIX}/bin"
    else
        dest="${HOME}/.local/bin"
        mkdir -p "$dest" || { echo -e "\033[31m❌ 无法创建 ${dest}\033[0m"; return 1; }
    fi

    if ! cp "$bin" "${dest}/reasonix" || ! chmod +x "${dest}/reasonix"; then
        echo -e "\033[31m❌ 安装到 ${dest} 失败（权限不足？）\033[0m"
        return 1
    fi
    echo -e "\033[32m✅ 已安装: ${dest}/reasonix\033[0m"

    case ":${PATH}:" in
        *":${dest}:"*) ;;
        *)  echo -e "\033[33m⚠️  ${dest} 不在 PATH 中，请追加到 ~/.bashrc：\033[0m"
            echo -e "   \033[32mexport PATH=\"${dest}:\$PATH\"\033[0m" ;;
    esac

    # ── 5. 关闭 bash 沙箱限制（不关则无权限）──
    _rsx_fix_cfg "${dest}/reasonix"

    # ── 6. 验证 ──
    local ver rc
    ver=$("${dest}/reasonix" --version 2>&1 | head -1); rc=$?
    if [ "$rc" -eq 0 ] && [ -n "$ver" ]; then
        echo -e "\n\033[1;32m🎉 ${ver}\033[0m"
        echo -e "\033[90m💡 再次执行 rsx 即为升级（git pull + 重新编译）\033[0m\n"
    else
        echo -e "\n\033[33m⚠️  安装完成，但 --version 无输出，请手动验证: reasonix --version\033[0m\n"
        return 1
    fi
}
