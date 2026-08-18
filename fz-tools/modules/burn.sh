#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — burn.sh（炼化模块）v6.0
#  职责：把项目源码按规则过滤后拼接为一个 txt 文件，
#        供用户复制给对话框 AI 做全项目分析 / 生成计划书
#  用法：
#    f               全量模式：打包全部源码（滤掉矢量图/密钥/缓存/锁文件）
#    f -d / --diff   增量模式：只打包未提交的改动 + 未跟踪的新文件
#    f <关键词>      定向模式：只打包路径包含关键词的文件（如 f nav）
#    f -h / --help   帮助
#  ⚠️ 大文件（>64KB）不丢弃，照常完整打包，并在注释中标注路径与大小
#  输出路径：当前 Git 项目根目录的上一级 > 第一个书签目录 > FZ_BASE > HOME
#  包含函数：_f_burn  _f_burn_help  _f_burn_tree  _f_burn_clip  _f_burn_scan
#  对应别名：f
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

# ── 允许打包的源码扩展名（白名单）──
_F_BURN_EXT='html|htm|js|jsx|ts|tsx|vue|astro|svelte|css|scss|sass|less|json|md|kt|kts|java|xml|py|rb|go|rs|swift|dart|yaml|yml|sh|bash|php|c|cpp|h|hpp|cs|lua|pl|pm|tcl|sql|ps1|bat|r|m|mm|proto|toml|gradle|properties|conf|cfg|ini'

# ── 必须排除的垃圾文件（黑名单）──
#  构建/依赖目录: .git/ .gradle/ .idea/ build/ node_modules/ dist/ bin/ out/
#  锁与压缩产物:   *lock*  *.min.js  *.min.css
#  敏感凭据:       release.properties *.keystore *.jks *.key *.pem google-services.json
#  体积杀手:       res/drawable*/*.xml（矢量图坐标） res/mipmap*/（图标）
#                  assets/*.json|bin|dat|wasm|txt（大配置/字库/离线包）
_F_BURN_BLACK='(^|/)(\.git|\.gradle|\.idea|build|node_modules|dist|bin|out)/|.*lock.*|\.min\.(js|css)$|release\.properties$|\.(keystore|jks|key|pem)$|google-services\.json$|(^|/)res/drawable[^/]*/.*\.xml$|(^|/)res/mipmap[^/]*/|(^|/)assets/.*\.(json|bin|dat|wasm|txt)$'

# 大文件阈值（KB）——超过则在注释里标注大小，但照常完整打包
_F_BURN_BIG_KB=64

# ══════════════════════════════════════════
#  ⚡ 炼化引擎（f）
# ══════════════════════════════════════════
_f_burn() {
    # ── 参数解析：模式 + 模块（支持 f -d nav 组合）──
    local MODE="FULL"
    local MODULE=""
    local arg
    for arg in "$@"; do
        case "$arg" in
            -d|--diff) MODE="DIFF" ;;
            -h|--help) _f_burn_help; return 0 ;;
            -s|--skeleton)
                echo -e "\033[33mℹ️ 骨架模式已并入全量模式：直接运行 f 即打包全部源码（含结构信息）\033[0m" ;;
            -*) echo -e "\033[31m❌ 未知选项: $arg（运行 f -h 查看用法）\033[0m" >&2; return 1 ;;
            *)  MODULE="$arg" ;;
        esac
    done

    local TMP_FILE
    TMP_FILE=$(mktemp "${HOME}/fz_burn_tmp_XXXXXX.txt")
    local PROJECT_NAME
    PROJECT_NAME=$(basename "$PWD")
    local MODE_TAG=""
    [ "$MODE" = "DIFF" ] && MODE_TAG="_diff"

    # ── 输出路径：当前 Git 项目根目录的上一级 > 第一个书签目录 > FZ_BASE > HOME ──
    local OUT_DIR=""
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        OUT_DIR=$(git rev-parse --show-toplevel 2>/dev/null)
        OUT_DIR=$(dirname "$OUT_DIR")
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

    local OUT_NAME="code_${PROJECT_NAME}${MODE_TAG}${MODULE:+_${MODULE}}.txt"
    local OUT_FILE="${OUT_DIR}/${OUT_NAME}"

    echo -e "\033[33m⚡ 炼化启动...\033[0m"
    echo -e "\033[90m📁 项目: $(basename "$PWD") | 模式: ${MODE}${MODULE:+ | 模块: ${MODULE}}\033[0m"
    echo -e "\033[90m📂 输出目录: ${OUT_DIR}\033[0m"

    # ── 头部元数据 + 目录树注入 ──
    {
        printf '/*\n * Project : %s\n * Mode    : %s\n * Module  : %s\n * Author  : %s\n * Date    : %s\n * Branch  : %s\n */\n\n' \
            "$PROJECT_NAME" "$MODE" "${MODULE:-ALL}" \
            "$(git config user.name 2>/dev/null || echo unknown)" \
            "$(date '+%Y-%m-%d %H:%M')" \
            "$(git branch --show-current 2>/dev/null || echo unknown)"
        echo "/* ── 目录概览（3 层）── */"
        _f_burn_tree
        echo
    } > "$TMP_FILE"

    local count=0 big_count=0

    while IFS= read -r file; do
        [ -f "$file" ] || continue

        local size
        size=$(wc -c < "$file" 2>/dev/null || echo 0)

        printf "\n// ━━━━━━━━━━━━━━━━━━━━━━━━\n" >> "$TMP_FILE"
        printf "// 📄 [%s]\n" "$file" >> "$TMP_FILE"
        if [ "$size" -gt $((_F_BURN_BIG_KB * 1024)) ]; then
            printf "// ⚠️ 大文件: %d KB（已完整打包）\n" "$((size/1024))" >> "$TMP_FILE"
            big_count=$((big_count + 1))
        fi
        printf "// ━━━━━━━━━━━━━━━━━━━━━━━━\n" >> "$TMP_FILE"

        sed -e 's/^[[:space:]]*//' \
            -e 's/[[:space:]]*$//' \
            -e '/^[[:space:]]*$/d' \
            "$file" >> "$TMP_FILE"

        count=$((count + 1))
        printf "\r  \033[33m处理: %d 文件...\033[0m" "$count" >&2

    done < <(_f_burn_scan "$MODE" "$MODULE")

    cp "$TMP_FILE" "$OUT_FILE"
    rm -f "$TMP_FILE"

    local out_kb out_lines
    out_kb=$(( $(wc -c < "$OUT_FILE" 2>/dev/null || echo 0) / 1024 ))
    out_lines=$(wc -l < "$OUT_FILE" 2>/dev/null || echo 0)

    echo -e "\r\033[32m✨ 炼化完成！\033[0m"
    echo -e "  📄 已处理 : \033[33m${count}\033[0m 个文件"
    echo -e "  📏 行数   : \033[33m${out_lines}\033[0m 行"
    [ "$big_count" -gt 0 ] && echo -e "  ⚠️  大文件 : \033[33m${big_count}\033[0m 个（>${_F_BURN_BIG_KB}KB，已完整打包并标注）"
    echo -e "  📦 大小   : \033[33m${out_kb} KB\033[0m"
    echo -e "  📍 路径   : \033[36m${OUT_FILE}\033[0m"

    if _f_burn_clip "$OUT_FILE"; then
        echo -e "  📋 路径已复制到剪贴板"
    fi
}

# ── 文件扫描引擎：按模式产出待打包文件列表（含白名单/黑名单/模块过滤）──
_f_burn_scan() {
    local mode="$1" module="$2"

    if [ "$mode" = "DIFF" ]; then
        # 增量：未提交改动（工作区+暂存区）+ 未跟踪新文件
        if git rev-parse --is-inside-work-tree &>/dev/null; then
            { git diff --name-only HEAD 2>/dev/null
              git ls-files --others --exclude-standard 2>/dev/null; } | sort -u
        else
            # 非 git 仓库：-d 语义失效，回退为全量 find
            find . -type f ! -path "*/.git/*" ! -path "*/node_modules/*"
        fi
    elif git rev-parse --is-inside-work-tree &>/dev/null; then
        # 全量（git 仓库）：已跟踪文件 + 未跟踪文件
        git ls-files -c -o --exclude-standard 2>/dev/null || true
    else
        # 全量（非 git）：find 兜底
        find . -type f ! -path "*/.git/*" ! -path "*/node_modules/*"
    fi |
    # ① 白名单：只留源码扩展名
    grep -iE "\.(${_F_BURN_EXT})$" |
    # ② 黑名单：排除垃圾 / 敏感 / 体积杀手
    grep -vE "${_F_BURN_BLACK}" |
    # ③ 定向模块：可选，按路径关键词过滤（固定字符串，避免正则误伤）
    { [ -n "$module" ] && grep -iF "$module" || cat; } |
    sort
}

# ── 目录树注入（3 层，排除噪音目录，截断防爆）──
_f_burn_tree() {
    if command -v find >/dev/null 2>&1; then
        find . -maxdepth 3 \
            \( -path '*/.git' -o -path '*/node_modules' -o -path '*/build' -o -path '*/.gradle' -o -path '*/dist' -o -path '*/out' -o -path '*/.idea' \) -prune -o -print 2>/dev/null \
        | sort | sed 's|^\./||' | head -300
    fi
}

# ── 剪贴板：复制路径（多平台兜底，失败静默）──
_f_burn_clip() {
    local target="$1"
    if command -v termux-clipboard-set &>/dev/null; then
        printf '%s' "$target" | termux-clipboard-set 2>/dev/null && return 0
    fi
    for c in xclip wl-copy pbcopy; do
        if command -v "$c" &>/dev/null; then
            printf '%s' "$target" | "$c" 2>/dev/null && return 0
        fi
    done
    return 1
}

# ── 帮助 ──
_f_burn_help() {
    echo -e "\033[1;36m
 焚诀·炼化引擎 f — 用法
────────────────────────────────────────
 f              全量打包：滤掉矢量图/密钥/缓存/锁文件，其余全部打包
 f -d           增量打包：只打包未提交的改动 + 新文件
 f <关键词>     定向打包：只打包路径含关键词的文件（如 f nav）
 f -h           显示本帮助
────────────────────────────────────────
 大文件（>${_F_BURN_BIG_KB}KB）不丢弃，会完整打包并标注路径与大小
 输出路径: 项目上一级 > 第一个书签 > FZ_BASE > HOME
\033[0m"
}
