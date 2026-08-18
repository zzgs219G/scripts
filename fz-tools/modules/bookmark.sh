#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — bookmark.sh（书签模块）v5.0 新增
#  职责：书签的增删改查 / 首次使用引导 / 旧 FZ_BASE 迁移 /
#        失效标记 / 当前书签识别
#  包含函数：_bm_init  _bm_load  _bm_list  _bm_add  _bm_remove
#            _bm_get_path  _bm_rename  _bookmark_mgr  _bm_current
#  对应别名：bookmark
#  存储文件：~/.fz_bookmarks（每行 名称|绝对路径）
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

FZ_BOOKMARKS_FILE="${HOME}/.fz_bookmarks"

# ══════════════════════════════════════════
#  📌  书签文件初始化（_bm_init）
#  首次使用：引导创建第一个书签
#  旧用户迁移：FZ_BASE 自动导入为默认书签
# ══════════════════════════════════════════
_bm_init() {
    if [ -f "$FZ_BOOKMARKS_FILE" ] && [ -s "$FZ_BOOKMARKS_FILE" ]; then
        return 0
    fi

    # 迁移策略：书签为空且旧 FZ_BASE 存在 → 导入为默认书签
    if [ -n "$FZ_BASE" ] && [ -d "$FZ_BASE" ]; then
        echo -e "\033[1;35m📌 检测到旧版工作台（FZ_BASE），正在导入为书签...\033[0m"
        read -p "书签名称（回车默认: 工作台）: " bm_name
        bm_name="${bm_name:-工作台}"
        if _bm_add "$bm_name" "$FZ_BASE"; then
            echo -e "\033[32m✅ 已导入书签: \033[1m${bm_name}\033[0m → ${FZ_BASE}"
            echo -e "\033[90m💡 以后可用 bookmark 命令管理书签\033[0m"
        fi
        return 0
    fi

    # 全新安装：引导创建第一个书签
    echo -e "\n\033[1;35m📌 欢迎使用《焚诀》v5.0！先创建一个书签吧\033[0m"
    echo -e "\033[90m书签 = 一个顶层目录，里面的每个子文件夹都会被当作一个项目\033[0m"
    read -p "书签名称（回车默认: 工作台）: " bm_name
    bm_name="${bm_name:-工作台}"
    read -p "书签路径（如 ${HOME}/repos）: " bm_path
    if [ -z "$bm_path" ]; then
        bm_path="${HOME}/repos"
        echo -e "\033[90m已使用默认路径: ${bm_path}\033[0m"
    fi
    mkdir -p "$bm_path" 2>/dev/null
    if _bm_add "$bm_name" "$bm_path"; then
        echo -e "\033[32m✅ 书签创建成功！执行 \033[1mc\033[0m\033[32m 开始使用\033[0m"
    fi
}

# ══════════════════════════════════════════
#  📖  加载书签到全局数组（_bm_load）
#  每项格式: 名称|绝对路径
#  ⚠️ 内部 read 变量必须用 _bm_ 前缀，
#     避免覆盖调用方同名 local（bash 局部变量对调用链可见）
# ══════════════════════════════════════════
_bm_load() {
    FZ_BOOKMARKS=()
    [ -f "$FZ_BOOKMARKS_FILE" ] || return 0
    local _bm_n _bm_p
    while IFS='|' read -r _bm_n _bm_p; do
        [ -z "$_bm_n" ] && continue
        FZ_BOOKMARKS+=("${_bm_n}|${_bm_p}")
    done < "$FZ_BOOKMARKS_FILE"
}

# ══════════════════════════════════════════
#  📋  显示书签列表（_bm_list）
#  显示编号/名称/路径，失效目录标记 [失效]
#  输出后调用方需自行 _bm_load 读取数组
# ══════════════════════════════════════════
_bm_list() {
    _bm_load
    if [ ${#FZ_BOOKMARKS[@]} -eq 0 ]; then
        echo -e "\033[33m📌 暂无书签，请先用 bookmark 添加\033[0m"
        return 1
    fi
    local i=1
    for entry in "${FZ_BOOKMARKS[@]}"; do
        local bm_name="${entry%%|*}"
        local bm_path="${entry#*|}"
        if [ -d "$bm_path" ]; then
            echo -e "  \033[33m[$i]\033[0m 📁 \033[1m${bm_name}\033[0m \033[90m(${bm_path})\033[0m"
        else
            echo -e "  \033[33m[$i]\033[0m 📁 \033[1m${bm_name}\033[0m \033[31m[失效]\033[0m \033[90m(${bm_path})\033[0m"
        fi
        i=$((i + 1))
    done
    return 0
}

# ══════════════════════════════════════════
#  ➕  添加书签（_bm_add <名称> <路径>）
#  同名 / 同路径去重，自动创建目录
# ══════════════════════════════════════════
_bm_add() {
    local bm_name="${1:-}" bm_path="${2:-}"
    if [ -z "$bm_name" ] || [ -z "$bm_path" ]; then
        echo -e "\033[31m❌ 用法: _bm_add <名称> <路径>\033[0m"
        return 1
    fi
    _bm_load
    for entry in "${FZ_BOOKMARKS[@]}"; do
        if [ "${entry%%|*}" = "$bm_name" ]; then
            echo -e "\033[31m❌ 书签 \"${bm_name}\" 已存在\033[0m"
            return 1
        fi
        if [ "${entry#*|}" = "$bm_path" ]; then
            echo -e "\033[31m❌ 路径已被书签 \"${entry%%|*}\" 使用\033[0m"
            return 1
        fi
    done
    mkdir -p "$bm_path" 2>/dev/null
    echo "${bm_name}|${bm_path}" >> "$FZ_BOOKMARKS_FILE"
    echo -e "\033[32m✅ 已添加书签: \033[1m${bm_name}\033[0m → ${bm_path}"
    return 0
}

# ══════════════════════════════════════════
#  🗑️  删除书签（_bm_remove <编号|名称>）
# ══════════════════════════════════════════
_bm_remove() {
    local key="${1:-}"
    [ -z "$key" ] && { echo -e "\033[31m❌ 用法: _bm_remove <编号|名称>\033[0m"; return 1; }
    _bm_load
    [ ${#FZ_BOOKMARKS[@]} -eq 0 ] && { echo -e "\033[33m📌 暂无书签\033[0m"; return 1; }

    local target=""
    if [[ "$key" =~ ^[0-9]+$ ]]; then
        local idx=$((key - 1))
        if [ $idx -ge 0 ] && [ $idx -lt ${#FZ_BOOKMARKS[@]} ]; then
            target="${FZ_BOOKMARKS[$idx]%%|*}"
        fi
    else
        target="$key"
    fi
    if [ -z "$target" ]; then
        echo -e "\033[31m❌ 未找到书签: $key\033[0m"
        return 1
    fi

    local tmp="${FZ_BOOKMARKS_FILE}.tmp"
    : > "$tmp"
    local found=0
    for entry in "${FZ_BOOKMARKS[@]}"; do
        if [ "${entry%%|*}" = "$target" ]; then
            found=1
            continue
        fi
        echo "$entry" >> "$tmp"
    done
    [ "$found" -eq 0 ] && { rm -f "$tmp"; echo -e "\033[31m❌ 未找到书签: $target\033[0m"; return 1; }
    mv "$tmp" "$FZ_BOOKMARKS_FILE"
    echo -e "\033[32m🗑️ 已删除书签: \033[1m$target\033[0m"
    return 0
}

# ══════════════════════════════════════════
#  🔍  获取书签路径（_bm_get_path <编号|名称>）
#  echo 输出路径，找不到返回 1
# ══════════════════════════════════════════
_bm_get_path() {
    local key="${1:-}"
    [ -z "$key" ] && return 1
    _bm_load
    if [[ "$key" =~ ^[0-9]+$ ]]; then
        local idx=$((key - 1))
        if [ $idx -ge 0 ] && [ $idx -lt ${#FZ_BOOKMARKS[@]} ]; then
            echo "${FZ_BOOKMARKS[$idx]#*|}"
            return 0
        fi
        return 1
    fi
    for entry in "${FZ_BOOKMARKS[@]}"; do
        if [ "${entry%%|*}" = "$key" ]; then
            echo "${entry#*|}"
            return 0
        fi
    done
    return 1
}

# ══════════════════════════════════════════
#  ✏️  重命名书签（_bm_rename <旧名> <新名>）
# ══════════════════════════════════════════
_bm_rename() {
    local old_name="${1:-}" new_name="${2:-}"
    if [ -z "$old_name" ] || [ -z "$new_name" ]; then
        echo -e "\033[31m❌ 用法: _bm_rename <旧名> <新名>\033[0m"
        return 1
    fi
    _bm_load
    for entry in "${FZ_BOOKMARKS[@]}"; do
        if [ "${entry%%|*}" = "$new_name" ]; then
            echo -e "\033[31m❌ 书签 \"${new_name}\" 已存在\033[0m"
            return 1
        fi
    done

    local tmp="${FZ_BOOKMARKS_FILE}.tmp"
    : > "$tmp"
    local found=0
    for entry in "${FZ_BOOKMARKS[@]}"; do
        if [ "${entry%%|*}" = "$old_name" ]; then
            found=1
            echo "${new_name}|${entry#*|}" >> "$tmp"
        else
            echo "$entry" >> "$tmp"
        fi
    done
    [ "$found" -eq 0 ] && { rm -f "$tmp"; echo -e "\033[31m❌ 未找到书签: $old_name\033[0m"; return 1; }
    mv "$tmp" "$FZ_BOOKMARKS_FILE"
    echo -e "\033[32m✏️  已重命名书签: \033[1m${old_name} → ${new_name}\033[0m"
    return 0
}

# ══════════════════════════════════════════
#  🏷️  识别当前所在书签（_bm_current）
#  若 pwd 位于某书签目录内，echo 书签名并返回 0
# ══════════════════════════════════════════
_bm_current() {
    _bm_load
    [ ${#FZ_BOOKMARKS[@]} -eq 0 ] && return 1
    local pwd_path
    pwd_path=$(pwd)
    for entry in "${FZ_BOOKMARKS[@]}"; do
        local bm_path="${entry#*|}"
        case "$pwd_path" in
            "$bm_path"|"$bm_path"/*)
                echo "${entry%%|*}"
                return 0
                ;;
        esac
    done
    return 1
}

# ══════════════════════════════════════════
#  📌  书签管理菜单（bookmark）
#  交互式增删改查
# ══════════════════════════════════════════
_bookmark_mgr() {
    _bm_init

    while true; do
        echo -e "\n\033[1;35m📌 书签管理\033[0m"
        _bm_list || { echo ""; }
        echo -e "\n  \033[33m[1]\033[0m ➕ 添加书签"
        echo -e "  \033[33m[2]\033[0m 🗑️  删除书签"
        echo -e "  \033[33m[3]\033[0m ✏️  重命名书签"
        echo -e "  \033[33m[q]\033[0m 退出"
        read -p "请选择操作: " op

        case "$op" in
            1)
                read -p "书签名称: " nb
                [ -z "$nb" ] && { echo -e "\033[33m已取消\033[0m"; continue; }
                read -p "书签路径: " np
                [ -z "$np" ] && { echo -e "\033[33m已取消\033[0m"; continue; }
                _bm_add "$nb" "$np"
                ;;
            2)
                read -p "输入编号或名称: " del_key
                [ -n "$del_key" ] && _bm_remove "$del_key"
                ;;
            3)
                read -p "输入要重命名的书签编号或名称: " old_key
                local old_name=""
                if [[ "$old_key" =~ ^[0-9]+$ ]]; then
                    _bm_load
                    local oidx=$((old_key - 1))
                    if [ $oidx -ge 0 ] && [ $oidx -lt ${#FZ_BOOKMARKS[@]} ]; then
                        old_name="${FZ_BOOKMARKS[$oidx]%%|*}"
                    fi
                else
                    old_name="$old_key"
                fi
                [ -z "$old_name" ] && { echo -e "\033[31m❌ 未找到书签\033[0m"; continue; }
                read -p "新名称: " new_name
                [ -n "$new_name" ] && _bm_rename "$old_name" "$new_name"
                ;;
            q|Q) return 0 ;;
            *) echo -e "\033[31m❌ 无效选项\033[0m" ;;
        esac
    done
}
