#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — nav.sh（导航模块）v5.0 完全重写
#  职责：c 命令三阶段状态机（书签选择→项目列表→项目操作）、
#        书签项目总览、当前状态显示（含书签上下文）
#  包含函数：_c_jump  _c_project_menu  _c_project_ops
#            _bm_move_copy  _ls_projects  _st_status
#  对应别名：c  lsp  st
#  ⚠️ v5.0 起：
#     - _clone_repo 已迁移至 clone.sh
#     - _pull_all   已迁移至 pullall.sh
#     - 全部 FZ_BASE 依赖移除，改为书签系统
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

# ══════════════════════════════════════════
#  🧭  通用选择器 _fz_picker（v5.3 融合版）
#  渲染：编号直接印在每行前缀上（如 "❯ 1 项目A"），一套菜单同时
#        提供 ↑/↓ 指示器与数字直选，调用方不再自行打印编号列表
#  交互：↑/↓（或 j/k）移动指示器 → 回车确认；数字 1-9 直接跳选；
#        其余单字符（q/b/0 等）作为快捷键透传给调用方
#  退化：stdin 非终端（管道/脚本，如 smoke-test）时自动降级为
#        数字输入模式，保证自动化测试与脚本调用兼容
#  用法：_fz_picker "提示语" item1 item2 ...；返回值：
#        0=回车/数字选定（全局 FZ_PICK_RET=序号，1 起）
#        1=用户按了快捷键（FZ_PICK_RET=该字符）
#  渲染：指示器行用反色（\033[7m），项内容支持内嵌 ANSI 码
# ══════════════════════════════════════════
_fz_picker() {
    FZ_PICK_RET=""
    _FZ_PICK_DRAWN=0
    local prompt="${1:-}"; shift
    local -a items=("$@")
    local n=${#items[@]}
    [ "$n" -eq 0 ] && return 1

    # 非交互环境：退化为数字输入（管道喂入兼容）
    if [ ! -t 0 ]; then
        local sel
        read -r sel || sel=""
        if [ -z "$sel" ]; then
            sel="${FZ_PICK_DEFAULT:-1}"      # 空行 = 默认项（阶段3 回车默认）
        fi
        if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "$n" ]; then
            FZ_PICK_RET="$sel"
            return 0
        fi
        FZ_PICK_RET="$sel"
        return 1
    fi

    local cur=1 i key seq
    while true; do
        # 重绘：光标上移清屏（首轮不跳）
        if [ "${_FZ_PICK_DRAWN:-0}" -eq 1 ]; then
            printf '\033[%dA\033[J' "$((n + 1))"
        fi
        echo -e "${prompt}"
        for ((i = 1; i <= n; i++)); do
            if [ "$i" -eq "$cur" ]; then
                echo -e "  \033[7m ❯ ${i}. ${items[$((i - 1))]} \033[0m"
            else
                echo -e "    \033[33m${i}.\033[0m ${items[$((i - 1))]}"
            fi
        done
        echo -e "  \033[90m↑/↓ 或数字选择 · 回车确认 · q 退出\033[0m"
        _FZ_PICK_DRAWN=1

        # 逐键读取；ESC 开头的转义序列再补读 2 字节
        IFS= read -rsn1 key || { FZ_PICK_RET="q"; return 1; }
        if [ "$key" = $'\x1b' ]; then
            IFS= read -rsn2 -t 0.05 seq || seq=""
            case "$seq" in
                '[A') cur=$((cur > 1 ? cur - 1 : n)) ;;
                '[B') cur=$((cur < n ? cur + 1 : 1)) ;;
                *)    FZ_PICK_RET="q"; return 1 ;;   # 其他 ESC 序列当作退出
            esac
            continue
        fi
        case "$key" in
            '') FZ_PICK_RET="$cur"; return 0 ;;                     # 回车确认
            j)  cur=$((cur < n ? cur + 1 : 1)) ;;                   # j=下（vim 惯例）
            k)  cur=$((cur > 1 ? cur - 1 : n)) ;;                   # k=上（vim 惯例）
            [1-9])
                if [ "$key" -le "$n" ]; then
                    FZ_PICK_RET="$key"; return 0                    # 数字直选
                fi
                ;;
            *)  FZ_PICK_RET="$key"; return 1 ;;                     # q/b/0 等透传
        esac
    done
}

_c_jump() {
    _bm_init
    _bm_load
    if [ ${#FZ_BOOKMARKS[@]} -eq 0 ]; then
        echo -e "\033[33m📌 暂无书签，请先执行 \033[1mbookmark\033[0m 添加\033[0m"
        return 1
    fi

    local keyword="${1:-}"

    # ── 带参数：书签名直达阶段2 / 项目名模糊直达 ──
    if [ -n "$keyword" ]; then
        local kw_path
        kw_path=$(_bm_get_path "$keyword")
        if [ -n "$kw_path" ]; then
            _c_project_menu "$keyword" "$kw_path"
            return $?
        fi
        for entry in "${FZ_BOOKMARKS[@]}"; do
            local bp="${entry#*|}"
            [ -d "$bp" ] || continue
            for d in "$bp"/*/; do
                [ -d "$d" ] || continue
                local dn
                dn=$(basename "$d")
                if [[ "${dn,,}" == *"${keyword,,}"* ]]; then
                    cd "$d" || return 1
                    echo -e "\033[32m🚀 瞬移成功: \033[1m${dn}\033[0m \033[90m(${d})\033[0m"
                    _git_status_summary
                    return 0
                fi
            done
        done
        echo -e "\033[31m❌ 未找到匹配 \"${keyword}\" 的书签或项目\033[0m"
        return 1
    fi

    # ── 阶段1：书签选择（v5.3：编号前缀融合渲染，不再手工打印菜单）──
    while true; do
        local -a bm_items=()
        local entry
        for entry in "${FZ_BOOKMARKS[@]}"; do
            local bn="${entry%%|*}" bpth="${entry#*|}"
            local bm_mark=""
            [ ! -d "$bpth" ] && bm_mark=" \033[31m[失效]\033[0m"
            bm_items+=("📁 \033[1m${bn}\033[0m \033[90m(${bpth})\033[0m${bm_mark}")
        done
        bm_items+=("➕ 添加新书签")

        echo -e "\n\033[1;36m📂 工作台书签（可用 bookmark 管理）：\033[0m"
        _fz_picker "请选择（↑/↓+回车，或输入编号 / + / q）: " "${bm_items[@]}"
        local choice="$FZ_PICK_RET"

        case "$choice" in
            q|Q)
                return 0
                ;;
            +|add|new)
                _c_add_bookmark
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]]; then
                    if [ "$choice" -eq ${#bm_items[@]} ]; then
                        _c_add_bookmark
                    elif _c_enter_bookmark "$choice"; then
                        return 0
                    fi
                else
                    echo -e "\033[31m❌ 无效输入，请输入编号、+ 或 q\033[0m"
                fi
                ;;
        esac
    done
}

# 阶段1内部：添加书签
_c_add_bookmark() {
    read -p "书签名称: " nb
    [ -z "$nb" ] && { echo -e "\033[33m已取消\033[0m"; return 1; }
    read -p "书签路径: " np
    [ -z "$np" ] && { echo -e "\033[33m已取消\033[0m"; return 1; }
    _bm_add "$nb" "$np"
}

# 阶段1内部：进入某编号书签（含失效处理）
_c_enter_bookmark() {
    local sel="${1:-}"
    local idx=$((sel - 1))
    if [ $idx -lt 0 ] || [ $idx -ge ${#FZ_BOOKMARKS[@]} ]; then
        echo -e "\033[31m❌ 编号 ${sel} 超出范围！\033[0m"
        return 1
    fi
    local sel_bm="${FZ_BOOKMARKS[$idx]%%|*}"
    local sel_path="${FZ_BOOKMARKS[$idx]#*|}"

    # 失效书签处理（计划书 8.1）
    if [ ! -d "$sel_path" ]; then
        echo -e "\033[31m⚠️ 书签 \"${sel_bm}\" 指向的目录已失效: ${sel_path}\033[0m"
        read -p "是否移除该书签？(y/n): " rm_bm
        if [[ "$rm_bm" == "y" || "$rm_bm" == "Y" ]]; then
            _bm_remove "$sel_bm"
        fi
        return 1
    fi

    _c_project_menu "$sel_bm" "$sel_path"
    local ret=$?
    # 0 = 已 cd 结束命令；2 = 返回书签选择；1 = 出错
    [ "$ret" -ne 2 ] && return "$ret"
    return 1
}

# ══════════════════════════════════════════
#  📁  阶段2：项目列表
#  [0]/q → cd 书签根目录并结束（计划书强调的需求）
#  [b]   → 返回书签选择（重绘菜单，pwd 保留在书签根目录）
# ══════════════════════════════════════════
_c_project_menu() {
    local bm_name="${1:-}" bm_path="${2:-}"
    cd "$bm_path" 2>/dev/null || {
        echo -e "\033[31m❌ 无法进入目录: $bm_path\033[0m"
        return 1
    }

    while true; do
        local dirs=()
        local _nav_d
        while IFS= read -r _nav_d; do
            [ -n "$_nav_d" ] && dirs+=("$_nav_d")
        done < <(command ls -d */ 2>/dev/null | sed 's#/$##')

        echo -e "\n\033[1;36m📁 当前目录：\033[1m${bm_name}\033[0m \033[90m(${bm_path})\033[0m"

        # v5.3 编号前缀融合渲染：首项=进入书签根目录（原[0]），末项=返回书签
        local -a pj_items=("📂 进入此目录（书签根目录，原[0]）")
        local d mark
        for d in "${dirs[@]}"; do
            mark=""
            [ -d "${d}/.git" ] && mark=" \033[32m✓\033[0m"
            pj_items+=("${d}${mark}")
        done
        pj_items+=("↩ 返回书签选择（原[b]）")

        _fz_picker "请选择（↑/↓+回车 / 编号 / 0 / b / q）: " "${pj_items[@]}"
        local sel="$FZ_PICK_RET"

        case "$sel" in
            q|Q|0)
                cd "$bm_path" || return 1
                echo -e "\033[32m📂 已进入: \033[1m${bm_path}\033[0m"
                return 0
                ;;
            b|B)
                return 2
                ;;
            *)
                if [[ "$sel" =~ ^[0-9]+$ ]]; then
                    if [ "$sel" -eq ${#pj_items[@]} ]; then
                        return 2
                    fi
                    local idx=$((sel - 1))   # 项目在 dirs 中从 0 起（pj_items 首项占 1）
                    if [ $idx -ge 0 ] && [ $idx -lt ${#dirs[@]} ]; then
                        local proj="${dirs[$idx]}"
                        _c_project_ops "$bm_name" "$bm_path" "$proj"
                        [ $? -eq 0 ] && return 0
                    else
                        echo -e "\033[31m❌ 编号无效\033[0m"
                    fi
                else
                    echo -e "\033[31m❌ 无效输入，请输入编号、b 或 q\033[0m"
                fi
                ;;
        esac
    done
}

# ══════════════════════════════════════════
#  🎯  阶段3：项目操作菜单
#  1 进入 / 2 移动 / 3 复制 / q 取消
#  返回 0 = 已 cd（结束整个 c 命令）；1 = 取消/复制未进入
# ══════════════════════════════════════════
_c_project_ops() {
    local bm_name="${1:-}" bm_path="${2:-}" proj="${3:-}"
    local proj_path="${bm_path}/${proj}"

    while true; do
        echo -e "\n\033[1;36m选中项目：\033[1m${proj}\033[0m"

        # v5.3 编号前缀融合渲染：回车默认第一项（进入项目）
        local -a ops_items=("🚀 进入该项目（回车默认）"
                            "📦 移动本项目到其他书签（剪切）"
                            "📋 复制本项目到其他书签（保留原件）")
        FZ_PICK_DEFAULT=1
        _fz_picker "请选择（↑/↓+回车 / 编号 / q）: " "${ops_items[@]}"
        local op="$FZ_PICK_RET"

        case "$op" in
            1|""|" ")
                cd "$proj_path" || { echo -e "\033[31m❌ 无法进入: $proj_path\033[0m"; return 1; }
                echo -e "\033[32m🚀 已进入项目: \033[1m${proj}\033[0m"
                _git_status_summary
                return 0
                ;;
            2)
                _bm_move_copy "$bm_name" "$proj_path" "move"
                return $?
                ;;
            3)
                _bm_move_copy "$bm_name" "$proj_path" "copy"
                return $?
                ;;
            q|Q)
                return 1
                ;;
            *)
                echo -e "\033[31m❌ 无效选项\033[0m"
                ;;
        esac
    done
}

# ══════════════════════════════════════════
#  📦  移动/复制项目到其他书签（_bm_move_copy）
#  冲突处理：覆盖 / 重命名(_副本) / 取消
#  移动前二次确认；自动 safe.directory；移动后进入
# ══════════════════════════════════════════
_bm_move_copy() {
    local cur_bm="${1:-}" src="${2:-}" mode="${3:-}"
    local proj_name
    proj_name=$(basename "$src")

    _bm_load
    local targets=()
    for entry in "${FZ_BOOKMARKS[@]}"; do
        [ "${entry%%|*}" = "$cur_bm" ] && continue
        targets+=("$entry")
    done
    if [ ${#targets[@]} -eq 0 ]; then
        echo -e "\033[33m⚠️ 没有其他书签可用，请先用 \033[1mbookmark\033[0m 添加\033[0m"
        return 1
    fi

    # v5.3：目标书签也用编号前缀融合渲染（手工列表已并入 picker）
    echo -e "\n\033[36m选择目标书签：\033[0m"
    local -a tgt_items=()
    local entry
    for entry in "${targets[@]}"; do
        local tmark=""
        [ ! -d "${entry#*|}" ] && tmark=" \033[31m[失效]\033[0m"
        tgt_items+=("📁 \033[1m${entry%%|*}\033[0m \033[90m(${entry#*|})\033[0m${tmark}")
    done
    _fz_picker "选择目标书签（↑/↓+回车 / 编号 / q 取消）: " "${tgt_items[@]}"
    local tsel="$FZ_PICK_RET"

    if [[ ! "$tsel" =~ ^[0-9]+$ ]]; then
        echo -e "\033[90m已取消\033[0m"
        return 1
    fi
    local tidx=$((tsel - 1))
    if [ $tidx -lt 0 ] || [ $tidx -ge ${#targets[@]} ]; then
        echo -e "\033[31m❌ 编号无效\033[0m"
        return 1
    fi
    local dst_bm="${targets[$tidx]%%|*}"
    local dst_root="${targets[$tidx]#*|}"
    if [ ! -d "$dst_root" ]; then
        echo -e "\033[31m❌ 目标书签目录不存在: $dst_root\033[0m"
        return 1
    fi
    local dst="${dst_root}/${proj_name}"

    # ── 冲突处理（计划书 3.2）──
    if [ -e "$dst" ]; then
        echo -e "\n\033[33m⚠️ 目标位置已存在同名目录: \033[1m${dst}\033[0m"
        echo -e "  \033[33m[1]\033[0m 覆盖"
        echo -e "  \033[33m[2]\033[0m 重命名（加 _副本）"
        echo -e "  \033[33m[3]\033[0m 取消"
        read -p "请选择: " cop
        case "$cop" in
            1)
                read -p "⚠️ 覆盖将删除目标目录，确认？(y/n): " ov
                if [[ "$ov" == "y" || "$ov" == "Y" ]]; then
                    rm -rf "$dst" || { echo -e "\033[31m❌ 删除目标失败\033[0m"; return 1; }
                else
                    echo -e "\033[90m已取消\033[0m"
                    return 1
                fi
                ;;
            2) dst="${dst}_副本" ;;
            *) echo -e "\033[90m已取消\033[0m"; return 1 ;;
        esac
    fi

    # ── 移动前二次确认（计划书 8.1 防误删）──
    if [ "$mode" = "move" ]; then
        read -p "确认将 \033[1m${proj_name}\033[0m 移动到书签 \033[1m${dst_bm}\033[0m？(y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo -e "\033[90m已取消\033[0m"
            return 1
        fi
    fi

    # ── 执行移动/复制 ──
    if [ "$mode" = "move" ]; then
        if ! mv "$src" "$dst" 2>&1; then
            echo -e "\033[31m❌ 移动失败！\033[0m"
            return 1
        fi
    else
        if ! cp -r "$src" "$dst" 2>&1; then
            echo -e "\033[31m❌ 复制失败！\033[0m"
            return 1
        fi
    fi

    # ── 自动修复 Git 安全权限（计划书 3.2）──
    git config --global --add safe.directory "$dst" 2>/dev/null

    if [ "$mode" = "move" ]; then
        echo -e "\033[32m✅ 已移动: \033[1m${proj_name}\033[0m → ${dst_bm}"
        cd "$dst" || return 1
        echo -e "\033[32m🚀 已进入: \033[1m${dst}\033[0m"
        return 0
    else
        echo -e "\033[32m✅ 已复制: \033[1m${proj_name}\033[0m → ${dst_bm}（原件保留）"
        read -p "是否进入副本？(y/n): " go
        if [[ "$go" == "y" || "$go" == "Y" ]]; then
            cd "$dst" || return 1
            echo -e "\033[32m🚀 已进入副本: \033[1m${dst}\033[0m"
            return 0
        fi
        return 1
    fi
}

# ══════════════════════════════════════════
#  📊  书签项目总览（lsp）
#  v5.0 起基于书签统计，不再依赖 FZ_BASE
# ══════════════════════════════════════════
_ls_projects() {
    _bm_init
    _bm_load
    if [ ${#FZ_BOOKMARKS[@]} -eq 0 ]; then
        echo -e "\033[33m📌 暂无书签，请先执行 \033[1mbookmark\033[0m 添加\033[0m"
        return 1
    fi

    echo -e "\n\033[1;36m📊 工作台项目总览\033[0m\n"
    local total=0
    for entry in "${FZ_BOOKMARKS[@]}"; do
        local bm_name="${entry%%|*}"
        local bm_path="${entry#*|}"
        echo -e "\n\033[1;35m📁 书签: ${bm_name} \033[90m(${bm_path})\033[0m"
        if [ ! -d "$bm_path" ]; then
            echo -e "  \033[31m[失效] 目录不存在\033[0m"
            continue
        fi
        printf "  \033[90m%-22s %-10s %-10s %-8s %s\033[0m\n" "项目名" "状态" "分支" "变更" "最近提交"
        echo -e "  \033[90m────────────────────────────────────────────────────────────\033[0m"
        local count=0
        for dir in "$bm_path"/*/; do
            [ -d "$dir" ] || continue
            local name
            name=$(basename "$dir")
            count=$((count + 1))
            total=$((total + 1))

            if [ -d "$dir/.git" ]; then
                local branch commit changes
                branch=$(cd "$dir" && git branch --show-current 2>/dev/null || echo "?")
                commit=$(cd "$dir" && git log -1 --format="%s" 2>/dev/null | cut -c1-30 || echo "-")
                changes=$(cd "$dir" && git status -s 2>/dev/null | wc -l | tr -d ' ')

                local ahead behind sync_status
                ahead=$(cd "$dir" && git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
                behind=$(cd "$dir" && git rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)

                if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
                    sync_status="🔵分叉"
                elif [ "$ahead" -gt 0 ]; then
                    sync_status="🟡领先"
                elif [ "$behind" -gt 0 ]; then
                    sync_status="🔴落后"
                else
                    sync_status="🟢同步"
                fi

                local changes_display="-"
                [ "$changes" -gt 0 ] && changes_display="${changes}个"

                printf "  %-22s %-10s %-10s %-8s \033[90m%s\033[0m\n" \
                    "$name" "$sync_status" "$branch" "$changes_display" "$commit"
            else
                printf "  %-22s \033[90m%-10s\033[0m\n" "$name" "(非Git)"
            fi
        done
        echo -e "\033[90m  ── 该书签共 ${count} 个项目\033[0m"
    done
    echo -e "\n\033[90m  共 ${total} 个项目\033[0m\n"
}

# ══════════════════════════════════════════
#  📍  当前状态（st）
#  v5.0 起增加当前书签名称显示（计划书 6.5）
# ══════════════════════════════════════════
_st_status() {
    local bm_name
    bm_name=$(_bm_current)
    local cur changes
    cur=$(git branch --show-current 2>/dev/null)
    changes=$(git status -s 2>/dev/null | wc -l | tr -d ' ')

    local line="📍 "
    if [ -n "$bm_name" ]; then
        line+="书签: \033[1;36m${bm_name}\033[0m | "
    fi
    if [ -n "$cur" ]; then
        line+="分支: \033[1;33m${cur}\033[0m | 变更: \033[33m${changes}\033[0m 个文件"
    else
        line+="分支: \033[1;33m非Git目录\033[0m"
        echo -e "$line"
        return 0
    fi

    # v5.1：增加领先/落后同步状态（计划书 6.5 增强）
    local ahead behind
    ahead=$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
    behind=$(git rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)
    if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
        line+=" | 📤${ahead} 📥${behind} \033[1;34m🔵分叉\033[0m"
    elif [ "$ahead" -gt 0 ]; then
        line+=" | 📤 领先 \033[33m${ahead}\033[0m 个提交"
    elif [ "$behind" -gt 0 ]; then
        line+=" | 📥 落后 \033[31m${behind}\033[0m 个提交"
    fi
    echo -e "$line"

    local last_commit
    last_commit=$(git log -1 --format="%s (%cr)" 2>/dev/null)
    [ -n "$last_commit" ] && echo -e "  \033[90m📌 ${last_commit}\033[0m"
}
