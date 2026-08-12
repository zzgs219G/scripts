#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — burn.sh（炼化模块）v5.0
#  职责：遍历项目源码文件，按规则过滤并拼接为单一文本，
#        复制到剪贴板（termux-clipboard-set）
#  ⚠️ v5.0 输出路径：当前 Git 项目根目录；否则第一个书签目录；
#     兜底 FZ_BASE / HOME（计划书 6.4）
#  包含函数：_f_burn
#  对应别名：f
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

# ══════════════════════════════════════════
#  ⚡  炼化引擎（f）
# ══════════════════════════════════════════
_f_burn() {
    local MODULE="${1:-}"

    local TMP_FILE
    TMP_FILE=$(mktemp "${HOME}/fz_burn_tmp_XXXXXX.txt")
    local PROJECT_NAME
    PROJECT_NAME=$(basename "$PWD")

    # ── v5.0 输出路径：当前 Git 项目根 > 第一个书签目录 > FZ_BASE > HOME ──
    local OUT_DIR=""
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        OUT_DIR=$(git rev-parse --show-toplevel 2>/dev/null)
    fi
    if [ -z "$OUT_DIR" ]; then
        _bm_load
        if [ ${#FZ_BOOKMARKS[@]} -gt 0 ]; then
            OUT_DIR="${FZ_BOOKMARKS[0]#*|}"
        fi
    fi
    if [ -z "$OUT_DIR" ] || [ ! -d "$OUT_DIR" ]; then
        OUT_DIR="${FZ_BASE:-${HOME}}"
    fi

    local OUT_NAME="code_${PROJECT_NAME}${MODULE:+_${MODULE}}.txt"
    local OUT_FILE="${OUT_DIR}/${OUT_NAME}"

    echo -e "\033[33m⚡ 炼化启动...\033[0m"
    echo -e "\033[90m📁 项目: $(basename "$PWD") | 过滤模块: ${MODULE:-无}\033[0m"
    echo -e "\033[90m📂 输出目录: ${OUT_DIR}\033[0m"

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
        # 仅仅在这里加上了 astro|svelte，其余字符、变量、逻辑一个字都没动
        grep -iE "\.(html|htm|js|jsx|ts|tsx|vue|astro|svelte|css|scss|sass|less|json|md|kt|kts|java|xml|py|rb|go|rs|swift|dart|yaml|yml|sh|bash|php|c|cpp|h|hpp|cs|lua|pl|pm|tcl|sql|ps1|bat|r|m|mm|proto|toml|gradle|properties|conf|cfg|ini)$" | \
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

    if command -v termux-clipboard-set &>/dev/null; then
        echo "$OUT_FILE" | termux-clipboard-set
        echo -e "  📋 路径已复制到剪贴板"
    fi
}
