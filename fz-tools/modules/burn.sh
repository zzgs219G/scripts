#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — burn.sh（炼化模块）v6.0
#  职责：把项目源码按规则过滤后拼接为一个 txt 文件，
#        供用户复制给对话框 AI 做全项目分析 / 生成计划书
#  用法：
#    f               全量模式：打包全部源码（滤掉矢量图/密钥/缓存/锁文件/资源 json-xml）
#    f -d / --diff   增量模式：只打包未提交的改动 + 未跟踪的新文件
#    f <关键词>      定向模式：只打包路径包含关键词的文件（如 f nav）
#    f -h / --help   帮助
#  ⚠️ 大文件（>64KB）不丢弃，照常完整打包，并在注释中标注路径与大小
#  🧹 kotlin(.kt/.kts) 文件自动过滤：注释（行/块/KDoc）+ import 导包
#     被过滤的 import 去重为「依赖清单」附在打包末尾（仅影响打包 txt，源文件不受任何修改）
#  输出路径：当前 Git 项目根目录的上一级 > 第一个书签目录 > FZ_BASE > HOME
#  包含函数：_f_burn  _f_burn_help  _f_burn_tree  _f_burn_clip  _f_burn_scan  _f_burn_strip_kt_comments
#  对应别名：f
#  由 fz-tools/fzgit.sh 自动加载
# ════════════════════════════════════════════════════════════

# ── 允许打包的源码扩展名（白名单）──
_F_BURN_EXT='html|htm|js|jsx|ts|tsx|vue|astro|svelte|css|scss|sass|less|json|md|kt|kts|java|xml|py|rb|go|rs|swift|dart|yaml|yml|sh|bash|php|c|cpp|h|hpp|cs|lua|pl|pm|tcl|sql|ps1|bat|r|m|mm|proto|toml|gradle|properties|conf|cfg|ini'

# ── 必须排除的垃圾文件（黑名单）──
#  构建/依赖目录: .git/ .gradle/ .idea/ build/ node_modules/ dist/ bin/ out/
#  锁与压缩产物:   *lock*  *.min.js  *.min.css
#  敏感凭据:       release.properties *.keystore *.jks *.key *.pem google-services.json
#  资源文件瘦身:   res/ 与 assets/ 目录下所有 json/xml 不打包（Android 资源/矢量图/离线数据）
#                  AndroidManifest.xml 位于 res/ 之外，不受影响，正常保留
_F_BURN_BLACK='(^|/)(\.git|\.gradle|\.idea|build|node_modules|dist|bin|out)/|.*lock.*|\.min\.(js|css)$|release\.properties$|\.(keystore|jks|key|pem)$|google-services\.json$|(^|/)res/.*\.(json|xml)$|(^|/)assets/.*\.(json|xml)$'

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

    local count=0 big_count=0 import_n=0
    local IMPORT_LOG
    IMPORT_LOG=$(mktemp "${HOME}/fz_burn_imports_XXXXXX.txt")

    while IFS= read -r file; do
        [ -f "$file" ] || continue

        local size
        size=$(wc -c < "$file" 2>/dev/null || echo 0)

        printf "\n// 📄 [%s]\n" "$file" >> "$TMP_FILE"
        if [ "$size" -gt $((_F_BURN_BIG_KB * 1024)) ]; then
            printf "// ⚠️ 大文件: %d KB（已完整打包）\n" "$((size/1024))" >> "$TMP_FILE"
            big_count=$((big_count + 1))
        fi

        case "$file" in
            *.kt|*.kts)
                # kotlin 文件：过滤注释（行注释/块注释/KDoc）+ 过滤 import（写入依赖清单），其余语言原样打包
                _f_burn_strip_kt_comments "$IMPORT_LOG" < "$file" >> "$TMP_FILE"
                ;;
            *)
                sed -e 's/^[[:space:]]*//' \
                    -e 's/[[:space:]]*$//' \
                    -e '/^[[:space:]]*$/d' \
                    "$file" >> "$TMP_FILE"
                ;;
        esac

        count=$((count + 1))
        printf "\r  \033[33m处理: %d 文件...\033[0m" "$count" >&2

    done < <(_f_burn_scan "$MODE" "$MODULE")

    # ── 追加 Kotlin 依赖汇总：被过滤的 import 去重后附在末尾，供 AI 参考 ──
    if [ -s "$IMPORT_LOG" ]; then
        {
            printf "\n/* ── 依赖汇总：以下 Kotlin import 已从正文过滤，仅作依赖参考 ── */\n"
            sort -u "$IMPORT_LOG" | sed 's|^|// |'
        } >> "$TMP_FILE"
        import_n=$(sort -u "$IMPORT_LOG" | wc -l | tr -d '[:space:]')
    fi

    cp "$TMP_FILE" "$OUT_FILE"
    rm -f "$TMP_FILE" "$IMPORT_LOG"

    local out_kb out_lines
    out_kb=$(( $(wc -c < "$OUT_FILE" 2>/dev/null || echo 0) / 1024 ))
    out_lines=$(wc -l < "$OUT_FILE" 2>/dev/null || echo 0)

    echo -e "\r\033[32m✨ 炼化完成！\033[0m"
    echo -e "  📄 已处理 : \033[33m${count}\033[0m 个文件"
    echo -e "  📏 行数   : \033[33m${out_lines}\033[0m 行"
    [ "$big_count" -gt 0 ] && echo -e "  ⚠️  大文件 : \033[33m${big_count}\033[0m 个（>${_F_BURN_BIG_KB}KB，已完整打包并标注）"
    [ "$import_n" -gt 0 ] && echo -e "  🔗 依赖清单 : \033[33m${import_n}\033[0m 条 import（已过滤，附在末尾）"
    echo -e "  📦 大小   : \033[33m${out_kb} KB\033[0m"
    echo -e "  📍 路径   : \033[36m${OUT_FILE}\033[0m"

    if _f_burn_clip "$OUT_FILE"; then
        echo -e "  📋 路径已复制到剪贴板"
    fi
}

# ── kotlin 注释 + import 过滤（仅 .kt/.kts 使用，源文件不落盘、不修改）──
# 逐字符状态机：过滤行注释 //（含行内）、块注释 /* */（含嵌套与 KDoc），
# 但字符串（双引号/单引号/三引号原始字符串）内的 //、/* 原样保留，不误伤 URL。
# 注释过滤后，行首为 "import" 的顶层语句一并过滤，写入依赖清单（参数 $1，可选）。
# 输出行为与原 sed 对齐：去首尾空白 + 删空行。
# 状态: 0=代码 1=双引号串 2=单引号字符 3=三引号串 4=块注释(depth 计嵌套)
_f_burn_strip_kt_comments() {
    local log="${1:-}"
    awk -v logfile="$log" '
    BEGIN { state = 0; depth = 0 }
    {
        out = ""
        n = length($0)
        i = 1
        while (i <= n) {
            c = substr($0, i, 1)
            if (state == 0) {
                if (c == "/" && i < n) {
                    nxt = substr($0, i + 1, 1)
                    if (nxt == "/") break
                    if (nxt == "*") { state = 4; depth = 1; i += 2; continue }
                }
                if (c == "\"") {
                    # 三引号原始字符串必须连续三个引号，空字符串 "" 不算
                    if (i + 2 <= n && substr($0, i, 3) == "\"\"\"") {
                        out = out "\"\"\""; i += 3; state = 3; continue
                    }
                    state = 1
                } else if (c == "\047") {
                    state = 2
                }
                out = out c; i++
            } else if (state == 1) {
                out = out c
                if (c == "\\" && i < n) { i++; out = out substr($0, i, 1); i++; continue }
                if (c == "\"") state = 0
                i++
            } else if (state == 2) {
                out = out c
                if (c == "\\" && i < n) { i++; out = out substr($0, i, 1); i++; continue }
                if (c == "\047") state = 0
                i++
            } else if (state == 3) {
                out = out c
                if (c == "\"" && i + 2 <= n && substr($0, i + 1, 2) == "\"\"") {
                    out = out "\"\""; i += 3; state = 0; continue
                }
                i++
            } else if (state == 4) {
                if (c == "/" && i < n && substr($0, i + 1, 1) == "*") { depth++; i += 2; continue }
                if (c == "*" && i < n && substr($0, i + 1, 1) == "/") {
                    depth--; i += 2
                    if (depth <= 0) state = 0
                    continue
                }
                i++
            }
        }
        gsub(/^[ \t]+|[ \t]+$/, "", out)
        if (out == "") next
        # import 过滤：Kotlin 的 import 只能出现在顶层，且 import 是保留关键字，
        # 行首 "import" + 空白 即为 import 语句（含 import a.b.* / import a as b）。
        # 多行 import 在 Kotlin 规范上不允许，按单行处理即可。
        if (out ~ /^import([ \t]+|$)/) {
            if (logfile != "") print out >> logfile
            next
        }
        print out
    }'
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
 f              全量打包：滤掉矢量图/密钥/缓存/锁文件/资源目录下 json-xml
 f -d           增量打包：只打包未提交的改动 + 新文件
 f <关键词>     定向打包：只打包路径含关键词的文件（如 f nav）
 f -h           显示本帮助
────────────────────────────────────────
 🧹 kotlin(.kt/.kts) 注释自动过滤（含行内注释，字符串/URL 不误伤）
 🧹 kotlin(.kt/.kts) import 自动过滤，去重「依赖清单」附在打包末尾（AI 参考）
 📄 文件头只保留 // 📄 [路径]（大文件另标注大小）
 大文件（>${_F_BURN_BIG_KB}KB）不丢弃，会完整打包并标注路径与大小
 输出路径: 项目上一级 > 第一个书签 > FZ_BASE > HOME
\033[0m"
}
