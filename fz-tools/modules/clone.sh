#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — clone.sh（克隆模块）v5.0 新增
#  职责：交互式克隆（gh 仓库列表选择）/ 直连克隆 / 自动书签注册
#  包含函数：_clone_repo  _clone_interactive  _clone_direct
#  对应别名：cl
#  ⚠️ v5.0 起自 nav.sh 迁移至此，nav.sh 中仅保留兼容说明
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

# ══════════════════════════════════════════
#  📥  克隆主入口（cl）
#  cl                    → 交互式选择 gh 仓库
#  cl <仓库名或URL>      → 直接克隆到当前目录
#  cl <仓库名或URL> <书签名> → 直接克隆到指定书签目录
# ══════════════════════════════════════════
_clone_repo() {
    if [ -z "${1:-}" ]; then
        _clone_interactive
        return $?
    fi
    _clone_direct "${1:-}" "${2:-}"
}

# ══════════════════════════════════════════
#  🎛️  交互式克隆（cl 无参数）
#  流程：gh 仓库列表 → 选仓库 → 选目标目录 →
#        克隆 → 自动识别/注册书签 → 询问是否进入
# ══════════════════════════════════════════
_clone_interactive() {
    if ! command -v gh &>/dev/null; then
        echo -e "\033[31m❌ 交互式克隆需要 GitHub CLI（gh）\033[0m"
        echo -e "   Termux:        \033[33mpkg install gh\033[0m"
        echo -e "   Ubuntu/Debian: \033[33msudo apt install gh\033[0m"
        echo -e "\033[90m💡 或降级使用: cl <仓库名或URL>\033[0m"
        return 1
    fi
    if ! gh auth status &>/dev/null; then
        echo -e "\033[31m❌ 尚未登录 GitHub，请先执行 \033[1mlogin\033[0m"
        return 1
    fi

    echo -e "\033[34m📥 正在获取你的 GitHub 仓库列表...\033[0m"
    local repos=()
    local _c_rn _c_ru
    while IFS='|' read -r _c_rn _c_ru; do
        [ -z "$_c_rn" ] && continue
        repos+=("${_c_rn}|${_c_ru}")
    done < <(gh repo list --limit 100 --json name,url --jq '.[] | "\(.name)|\(.url)"' 2>/dev/null)

    if [ ${#repos[@]} -eq 0 ]; then
        echo -e "\033[33m⚠️ 获取仓库列表失败或没有可克隆的仓库\033[0m"
        return 1
    fi

    echo -e "\n\033[1;36m📦 你的 GitHub 仓库:\033[0m"
    local i=1
    for r in "${repos[@]}"; do
        echo -e "  \033[33m[$i]\033[0m ${r%%|*}"
        i=$((i + 1))
    done
    echo -e "  \033[33m[q]\033[0m 取消"
    read -p "请选择仓库编号: " sel

    if [[ "$sel" == "q" || "$sel" == "Q" ]]; then
        echo -e "\033[90m已取消\033[0m"
        return 1
    fi
    if [[ ! "$sel" =~ ^[0-9]+$ ]]; then
        echo -e "\033[31m❌ 请输入编号或 q 取消\033[0m"
        return 1
    fi
    local idx=$((sel - 1))
    if [ $idx -lt 0 ] || [ $idx -ge ${#repos[@]} ]; then
        echo -e "\033[31m❌ 编号无效\033[0m"
        return 1
    fi
    local rname="${repos[$idx]%%|*}"
    local rurl="${repos[$idx]#*|}"

    # ── 目标目录选择 ──
    local target_dir="" reg_bm=""
    echo -e "\n\033[36m选择克隆目标位置:\033[0m"
    echo -e "  \033[33m[1]\033[0m 当前目录 \033[90m($(pwd))\033[0m"
    echo -e "  \033[33m[2]\033[0m 选择书签目录"
    echo -e "  \033[33m[q]\033[0m 取消"
    read -p "请选择: " loc

    case "$loc" in
        1)
            target_dir="$(pwd)"
            ;;
        2)
            _bm_load
            if [ ${#FZ_BOOKMARKS[@]} -eq 0 ]; then
                echo -e "\033[33m📌 暂无书签，请先用 bookmark 添加\033[0m"
                return 1
            fi
            echo -e "\n\033[36m选择书签:\033[0m"
            local j=1
            for e in "${FZ_BOOKMARKS[@]}"; do
                echo -e "  \033[33m[$j]\033[0m ${e%%|*} \033[90m(${e#*|})\033[0m"
                j=$((j + 1))
            done
            read -p "请选择书签编号: " bsel
            if [[ "$bsel" == "q" || "$bsel" == "Q" ]]; then
                echo -e "\033[90m已取消\033[0m"
                return 1
            fi
            if [[ ! "$bsel" =~ ^[0-9]+$ ]]; then
                echo -e "\033[31m❌ 请输入编号或 q 取消\033[0m"
                return 1
            fi
            local bidx=$((bsel - 1))
            if [ $bidx -lt 0 ] || [ $bidx -ge ${#FZ_BOOKMARKS[@]} ]; then
                echo -e "\033[31m❌ 编号无效\033[0m"
                return 1
            fi
            target_dir="${FZ_BOOKMARKS[$bidx]#*|}"
            reg_bm="${FZ_BOOKMARKS[$bidx]%%|*}"
            ;;
        q|Q) return 1 ;;
        *) echo -e "\033[31m❌ 无效选项\033[0m"; return 1 ;;
    esac

    _clone_exec "$rname" "$rurl" "$target_dir" "$reg_bm"
}

# ══════════════════════════════════════════
#  ⚡  直连克隆（cl <仓库名或URL> [书签名]）
# ══════════════════════════════════════════
_clone_direct() {
    local input="${1:-}" reg_bm="${2:-}"
    local url="$input"

    # 短格式补全：cl 用户名/仓库名 或 cl 仓库名 → https://github.com/...
    # 本地路径 / file:// 等真实源地址原样透传，不做补全
    if [[ "$url" != http* && "$url" != git@* && "$url" != file://* && ! -e "$url" ]]; then
        url="https://github.com/${url}.git"
    fi

    local rname
    rname=$(basename "$url" .git)
    rname="${rname##*:}"

    # 指定书签目录
    local target_dir="$(pwd)"
    if [ -n "$reg_bm" ]; then
        local bm_path
        bm_path=$(_bm_get_path "$reg_bm") || { echo -e "\033[31m❌ 未找到书签: $reg_bm\033[0m"; return 1; }
        target_dir="$bm_path"
    fi

    _clone_exec "$rname" "$url" "$target_dir" "$reg_bm"
}

# ══════════════════════════════════════════
#  🛠️  克隆执行 + 书签注册（内部共用）
# ══════════════════════════════════════════
_clone_exec() {
    local rname="${1:-}" rurl="${2:-}" target_dir="${3:-}" reg_bm="${4:-}"

    if [ ! -d "$target_dir" ]; then
        echo -e "\033[31m❌ 目标目录不存在: $target_dir\033[0m"
        return 1
    fi
    if [ -e "${target_dir}/${rname}" ]; then
        echo -e "\033[31m❌ 目标已存在同名目录: ${target_dir}/${rname}\033[0m"
        return 1
    fi

    echo -e "\033[34m📥 克隆中: \033[1m${rname}\033[0m → ${target_dir}"
    if ! (cd "$target_dir" && git clone "$rurl" "$rname" 2>&1); then
        echo -e "\033[31m❌ 克隆失败！\033[0m"
        return 1
    fi

    local cloned_path="${target_dir}/${rname}"
    echo -e "\033[32m✅ 克隆完成: \033[1m${cloned_path}\033[0m"

    # ── 自动识别书签：克隆在书签目录下则自动关联；否则询问 ──
    if [ -z "$reg_bm" ]; then
        _bm_load
        for e in "${FZ_BOOKMARKS[@]}"; do
            local bp="${e#*|}"
            case "$cloned_path" in
                "$bp"|"$bp"/*) reg_bm="${e%%|*}"; break ;;
            esac
        done
    fi

    if [ -n "$reg_bm" ]; then
        echo -e "\033[32m📌 已自动识别书签: \033[1m${reg_bm}\033[0m"
    else
        read -p "将 ${rname} 加入书签？(y/n): " addbm
        if [[ "$addbm" == "y" || "$addbm" == "Y" ]]; then
            read -p "书签名称（回车默认: 工作台）: " nb
            nb="${nb:-工作台}"
            _bm_add "$nb" "$target_dir"
            echo -e "\033[32m📌 已加入书签: ${nb}\033[0m"
        fi
    fi

    # ── 询问是否立即进入 ──
    read -p "是否立即进入该项目？(y/n): " go
    if [[ "$go" == "y" || "$go" == "Y" ]]; then
        cd "$cloned_path"
        echo -e "\033[32m🚀 已进入: \033[1m${rname}\033[0m"
        local cur_br
        cur_br=$(git branch --show-current 2>/dev/null)
        [ -n "$cur_br" ] && echo -e "  🌿 当前分支: \033[33m${cur_br}\033[0m"
    fi
    return 0
}
