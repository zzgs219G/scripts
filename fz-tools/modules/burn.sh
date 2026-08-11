#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — burn.sh（炼化模块）
#  职责：遍历项目源码文件，按规则过滤并拼接为单一文本，
#        同时复制到工作台与剪贴板（termux-clipboard-set）
#  包含函数：_f_burn
#  对应别名：f
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

# ══════════════════════════════════════════
#  ⚡  炼化引擎（f）
# ══════════════════════════════════════════
_f_burn() {
    local MODULE="$1"

    local TMP_FILE
    TMP_FILE=$(mktemp "${HOME}/fz_burn_tmp_XXXXXX.txt")
    local PROJECT_NAME
PROJECT_NAME=$(basename "$PWD")

local OUT_NAME="code_${PROJECT_NAME}${MODULE:+_${MODULE}}.txt"
    local OUT_FILE="${HOME}/${OUT_NAME}"

    echo -e "\033[33m⚡ 炼化启动...\033[0m"
    echo -e "\033[90m📁 项目: $(basename "$PWD") | 过滤模块: ${MODULE:-无}\033[0m"

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

    if [ -d "${FZ_BASE}" ] && cp "$OUT_FILE" "${FZ_BASE}/${OUT_NAME}" 2>/dev/null; then
        echo -e "  📂 工作台 : \033[36m${FZ_BASE}/${OUT_NAME}\033[0m"
    fi

    if command -v termux-clipboard-set &>/dev/null; then
        echo "$OUT_FILE" | termux-clipboard-set
        echo -e "  📋 路径已复制到剪贴板"
    fi
}
