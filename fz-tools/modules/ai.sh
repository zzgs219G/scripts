#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 — ai.sh（可选：AI 生成 commit message）
#
#  默认关闭。未配置时 `p` 完全走本地流程，零网络请求、零费用。
#
#  为什么用「OpenAI 兼容接口」而不是绑定某一家：
#    兼容 /v1/chat/completions 的服务太多了（NVIDIA NIM、DeepSeek、
#    本地 Ollama、LM Studio、各家代理），绑定任何一家都会过时。
#    用户只需给三样东西：base URL、模型名、Key。
#
#  配置文件：${HOME}/.fz_ai.conf（权限 600），格式 key=value
#    FZ_AI_BASE_URL=https://integrate.api.nvidia.com/v1
#    FZ_AI_MODEL=z-ai/glm-5.3-flash
#    FZ_AI_KEY=nvapi-xxxxx
#
#  ⚠️ 数据流向必须让用户知情：
#    启用后本工具会把 `git diff` 的统计与**前 200 行差异**发到你配置的
#    第三方服务。NVIDIA 免费层明确声明会记录输入输出用于模型改进。
#    不想外发就别配这个功能——`p` 的默认备注已经够用。
# ════════════════════════════════════════════════════════════

# ── 配置读取 ──
# 输出到全局变量，返回 1 表示未配置完整（调用方据此跳过 AI）
_fz_ai_load_conf() {
    FZ_AI_BASE_URL="${FZ_AI_BASE_URL:-}"
    FZ_AI_MODEL="${FZ_AI_MODEL:-}"
    FZ_AI_KEY="${FZ_AI_KEY:-}"
    FZ_AI_CONF_FILE="${FZ_AI_CONF_FILE:-${HOME}/.fz_ai.conf}"

    if [ -r "$FZ_AI_CONF_FILE" ]; then
        local _k _v
        while IFS='=' read -r _k _v || [ -n "$_k" ]; do
            case "$_k" in
                ''|\#*) continue ;;
                FZ_AI_BASE_URL) FZ_AI_BASE_URL="$_v" ;;
                FZ_AI_MODEL)    FZ_AI_MODEL="$_v" ;;
                FZ_AI_KEY)      FZ_AI_KEY="$_v" ;;
            esac
        done < "$FZ_AI_CONF_FILE"
    fi

    # 兼容旧版：只有 ~/.fz_ai_key（Anthropic）时不做任何事，
    # 因为协议不同。旧 Key 保留在盘上，但需要用户重新配置才能用。
    [ -z "$FZ_AI_BASE_URL" ] && return 1
    [ -z "$FZ_AI_MODEL" ] && return 1
    [ -z "$FZ_AI_KEY" ] && return 1
    return 0
}

# AI 功能是否可用（配置完整 + curl 存在）
_fz_ai_ready() {
    _fz_ai_load_conf || return 1
    command -v curl >/dev/null 2>&1
}

# ── 请求 ──
# 成功时把 message 打印到 stdout 并返回 0；失败返回 1（静默）
_fz_ai_commit_msg() {
    _fz_ai_ready || return 1

    local stat detail
    stat=$(git diff --staged --stat 2>/dev/null)
    detail=$(git diff --staged 2>/dev/null | head -200)
    [ -z "$stat" ] && return 1

    echo -e "\033[90m🤖 AI 生成备注中...\033[0m" >&2

    local prompt="根据以下 git diff 生成一条简洁的中文 commit message。
格式：<类型>: <简短描述>（不超过50字，不要英文句号）
类型：feat/fix/refactor/style/docs/chore/test/ci
只输出 commit message 本身，不要解释、不要引号、不要代码块。

文件变更统计：
${stat}

代码差异（部分）：
${detail}"

    local esc_prompt esc_model
    esc_prompt=$(_json_escape "$prompt")
    esc_model=$(_json_escape "$FZ_AI_MODEL")

    local payload
    payload=$(printf '{"model":%s,"messages":[{"role":"user","content":%s}],"max_tokens":120,"temperature":0.3,"stream":false}' \
        "$esc_model" "$esc_prompt")

    local response
    response=$(curl -sS --max-time 25 "${FZ_AI_BASE_URL%/}/chat/completions" \
        -H "Authorization: Bearer ${FZ_AI_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)

    [ -z "$response" ] && { echo -e "\033[90m   （AI 无响应，改用默认备注）\033[0m" >&2; return 1; }

    _fz_ai_extract_content "$response"
}

# 从 OpenAI 兼容响应中取出 message.content
# 优先 python3/jq，退化到 sed/grep（只处理非流式、单行 JSON 的常见形态）
_fz_ai_extract_content() {
    local response="$1" msg=""

    if command -v python3 >/dev/null 2>&1; then
        msg=$(printf '%s' "$response" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    c=d["choices"][0]["message"]["content"]
    print((c or "").strip())
except Exception:
    pass
' 2>/dev/null)
    elif command -v jq >/dev/null 2>&1; then
        msg=$(printf '%s' "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    else
        msg=$(printf '%s' "$response" \
            | tr '\n' ' ' \
            | sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            | head -1)
    fi

    # 清理：去掉代码块标记、首尾空白、包裹引号，只留第一行有效内容
    msg=$(printf '%s\n' "$msg" \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        | grep -v '^```' \
        | grep -v '^$' \
        | head -1)
    # 去掉包裹的引号
    msg=$(printf '%s' "$msg" | sed -e 's/^["'\'']//' -e 's/["'\'']$//')

    [ -n "$msg" ] || return 1
    printf '%s\n' "$msg"
    return 0
}

# ── 配置向导（aikey）──
_fz_ai_setup() {
    echo -e "\n\033[1;35m🤖 AI 生成 commit 备注（可选）\033[0m\n"

    if _fz_ai_ready; then
        echo -e "\033[32m✅ 已启用\033[0m"
        echo -e "\033[90m   地址: ${FZ_AI_BASE_URL}\033[0m"
        echo -e "\033[90m   模型: ${FZ_AI_MODEL}\033[0m"
        echo -e "\033[90m   配置文件: ${FZ_AI_CONF_FILE}\033[0m"
        read -rp "重新配置？(y/N) " a
        case "$a" in y|Y) ;; *) return 0 ;; esac
    else
        echo -e "\033[90m这是可选功能。不配置时 p 用默认备注（⚡ update: 日期），\033[0m"
        echo -e "\033[90m零网络请求、零费用。\033[0m"
    fi

    echo ""
    echo -e "\033[33m⚠️  启用后会把 git diff 的前 200 行发送到下面配置的服务。\033[0m"
    echo -e "\033[33m   若该服务的数据政策不明（尤其免费层），请先确认再启用。\033[0m"
    echo ""
    echo -e "\033[1;36m常用免费/自建端点（OpenAI 兼容）：\033[0m"
    echo -e "  \033[36m1)\033[0m NVIDIA NIM    \033[90mhttps://integrate.api.nvidia.com/v1\033[0m"
    echo -e "     \033[90m免费、无需信用卡；官方声明会记录输入输出用于改进模型\033[0m"
    echo -e "     \033[90mKey: https://build.nvidia.com/settings/api-keys （nvapi- 前缀）\033[0m"
    echo -e "  \033[36m2)\033[0m DeepSeek       \033[90mhttps://api.deepseek.com/v1\033[0m"
    echo -e "     \033[90m按量付费，价格低；Key: https://platform.deepseek.com\033[0m"
    echo -e "  \033[36m3)\033[0m Ollama（本机） \033[90mhttp://localhost:11434/v1\033[0m"
    echo -e "     \033[90m完全本地、不外发；需先 ollama pull 一个模型\033[0m"
    echo -e "  \033[36m4)\033[0m 其他自定义     \033[90m任何兼容 /v1/chat/completions 的地址\033[0m"
    echo ""

    read -rp "Base URL（回车=NVIDIA）: " in_url
    in_url="${in_url:-https://integrate.api.nvidia.com/v1}"

    read -rp "模型名（回车=z-ai/glm-5.3-flash）: " in_model
    in_model="${in_model:-z-ai/glm-5.3-flash}"

    read -rp "API Key: " in_key
    if [ -z "$in_key" ]; then
        echo -e "\033[90m已取消（未改动配置）\033[0m"
        return 0
    fi

    local conf="${FZ_AI_CONF_FILE:-${HOME}/.fz_ai.conf}"
    if ! ( umask 077
           {
             printf 'FZ_AI_BASE_URL=%s\n' "$in_url"
             printf 'FZ_AI_MODEL=%s\n'    "$in_model"
             printf 'FZ_AI_KEY=%s\n'      "$in_key"
           } > "$conf" ); then
        echo -e "\033[31m❌ 写入 ${conf} 失败\033[0m"
        return 1
    fi
    chmod 600 "$conf" 2>/dev/null

    FZ_AI_BASE_URL="$in_url"
    FZ_AI_MODEL="$in_model"
    FZ_AI_KEY="$in_key"
    FZ_AI_CONF_FILE="$conf"

    echo ""
    echo -e "\033[32m✅ 已保存到 ${conf}（权限 600，不在仓库内）\033[0m"
    echo -e "\033[90m   关闭方式: rm ${conf}\033[0m"

    # 立刻试一次，让用户确认能通（失败不影响配置）
    read -rp "现在测试一次连通性？(Y/n) " t
    case "$t" in n|N) return 0 ;; esac
    echo -e "\033[90m🤖 正在测试...\033[0m"
    local probe
    probe=$(_fz_ai_extract_content "$(curl -sS --max-time 20 "${FZ_AI_BASE_URL%/}/chat/completions" \
        -H "Authorization: Bearer ${FZ_AI_KEY}" \
        -H "Content-Type: application/json" \
        -d '{"model":"'"$FZ_AI_MODEL"'","messages":[{"role":"user","content":"只回复两个字：可用"}],"max_tokens":20,"stream":false}' \
        2>/dev/null)")
    if [ -n "$probe" ]; then
        echo -e "\033[32m✅ 连通正常，模型回复: ${probe}\033[0m"
    else
        echo -e "\033[33m⚠️  测试未通过（可能是模型名不对 / Key 无效 / 网络问题）\033[0m"
        echo -e "\033[90m   配置已保存，可稍后重试 aikey 调整\033[0m"
    fi
}

# ── 关闭 ──
_fz_ai_off() {
    local conf="${FZ_AI_CONF_FILE:-${HOME}/.fz_ai.conf}"
    if [ -f "$conf" ]; then
        rm -f "$conf" && echo -e "\033[32m✅ 已关闭 AI 备注\033[0m（删除 ${conf}）"
    else
        # 旧版 Anthropic Key 也一并清理
        if [ -f "${HOME}/.fz_ai_key" ]; then
            rm -f "${HOME}/.fz_ai_key"
            echo -e "\033[32m✅ 已删除旧版 Anthropic Key\033[0m"
        else
            echo -e "\033[90m本来就未启用\033[0m"
        fi
    fi
    FZ_AI_KEY=""; FZ_AI_BASE_URL=""; FZ_AI_MODEL=""
}
