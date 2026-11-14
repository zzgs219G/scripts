#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 v5.0 — 全套冒烟测试
#  用法: bash fz-tools/smoke-test.sh
#  特性:
#    · $TMPDIR 隔离环境（独立 HOME / GIT_CONFIG_GLOBAL）
#    · 本地 bare 仓库模拟远端，零网络依赖
#    · 交互流程全部自动应答（管道喂入）
#    · 结束自动清理全部临时文件（trap EXIT）
#  覆盖 T1-T12：核心功能回归 + 安全回归（凭据隔离 / 无副作用加载）
# ════════════════════════════════════════════════════════════

set -u

PASS=0
FAIL=0
FAIL_NAMES=()

# ── 断言工具：assert <描述> <命令...> ──
assert() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        echo "  ✅ $desc"
    else
        FAIL=$((FAIL + 1))
        FAIL_NAMES+=("$desc")
        echo "  ❌ $desc"
    fi
}

# ── 隔离环境 ──
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
mkdir -p "$HOME"

export GIT_CONFIG_GLOBAL="$TEST_ROOT/gitconfig"
: > "$GIT_CONFIG_GLOBAL"
git config --global user.name "冒烟测试"
git config --global user.email "smoke@test.local"
git config --global --add safe.directory "$TEST_ROOT"

export GIT_AUTHOR_NAME="冒烟测试"  GIT_AUTHOR_EMAIL="smoke@test.local"
export GIT_COMMITTER_NAME="冒烟测试" GIT_COMMITTER_EMAIL="smoke@test.local"

# ── 加载焚诀（fzgit.sh 自动加载 core + 全部模块）──
FZ_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${FZ_SRC_DIR}/fzgit.sh"

# ── 目录规划 ──
BM1="$TEST_ROOT/books/main"
BM2="$TEST_ROOT/books/backup"
REMOTE="$TEST_ROOT/remote/origin.git"
mkdir -p "$BM1" "$BM2" "$TEST_ROOT/remote"
git init -q --bare "$REMOTE"

# ══════════════════════════════════════════
echo ""
echo "══════════ T1 书签初始化向导（用例1）══════════"

# T1a 迁移分支：书签为空且旧 FZ_BASE 存在 → 自动导入为默认书签
rm -f "$HOME/.fz_bookmarks"
printf "工作台\n" | _bm_init >/dev/null 2>&1
assert "T1a 迁移：FZ_BASE 自动导入为书签" grep -q "^工作台|" "$HOME/.fz_bookmarks"

# T1b 全新安装向导：书签为空且无 FZ_BASE → 引导创建（v5.106 起先路径后名称）
rm -f "$HOME/.fz_bookmarks"
# shellcheck disable=SC2034  # 由 _bm_init 通过 export 读取，静态分析看不到
FZ_BASE=""
export FZ_BASE
printf "%s\n主工作台\n" "$BM1" | _bm_init >/dev/null 2>&1
assert "T1b 全新向导：创建书签文件" grep -q "^主工作台|${BM1}$" "$HOME/.fz_bookmarks"

# T1c 书签名留空 → 自动取路径末尾文件夹名（v5.106 新增）
rm -f "$HOME/.fz_bookmarks"
printf "%s\n\n" "$BM1" | _bm_init >/dev/null 2>&1
assert "T1c 书签名留空取文件夹名" grep -q "^main|${BM1}$" "$HOME/.fz_bookmarks"
# T1c 覆盖了书签文件，恢复 T2 及之后用例依赖的初始状态（主工作台|BM1）
rm -f "$HOME/.fz_bookmarks"
printf "%s\n主工作台\n" "$BM1" | _bm_init >/dev/null 2>&1

# ══════════════════════════════════════════
echo ""
echo "══════════ T2 书签增删改查（用例2）══════════"

_bm_add "备份" "$BM2" >/dev/null 2>&1
assert "T2a 添加第二个书签" grep -q "^备份|${BM2}$" "$HOME/.fz_bookmarks"

_bm_add "主工作台" "$BM2" >/dev/null 2>&1; rc=$?
assert "T2b 同名去重拒绝" [ "$rc" -ne 0 ]

_bm_add "重复路径" "$BM2" >/dev/null 2>&1; rc=$?
assert "T2c 同路径去重拒绝" [ "$rc" -ne 0 ]

_bm_load
assert "T2d 数组加载 2 条" [ "${#FZ_BOOKMARKS[@]}" -eq 2 ]

p=$(_bm_get_path "主工作台")
assert "T2e 按名称取路径" [ "$p" = "$BM1" ]
p=$(_bm_get_path 1)
assert "T2f 按编号取路径" [ "$p" = "$BM1" ]

_bm_rename "备份" "备书" >/dev/null 2>&1
assert "T2g 重命名书签" grep -q "^备书|${BM2}$" "$HOME/.fz_bookmarks"

_bm_remove "备书" >/dev/null 2>&1
assert "T2h 删除书签" [ "$(grep -c '^备书' "$HOME/.fz_bookmarks" 2>/dev/null)" -eq 0 ]

_bm_add "备份" "$BM2" >/dev/null 2>&1   # 恢复供后续用例使用

# ══════════════════════════════════════════
echo ""
echo "══════════ T3 导航三阶段状态机（用例3）══════════"

mkdir -p "$BM1/projA"
( cd "$BM1/projA" && git init -q && echo hello > a.txt && git add . && git commit -qm init )

cd "$TEST_ROOT" || exit 1
_c_jump <<< $'1\n0\n' >/dev/null 2>&1
assert "T3a 阶段1→2 [0] 进入书签根目录" [ "$PWD" = "$BM1" ]

# v5.95 编号语义修复后：阶段2 屏幕 1=进入书签根目录，2=第一个项目
_c_jump <<< $'1\n2\n1\n' >/dev/null 2>&1
assert "T3b 阶段3 [1] 进入项目" [ "$PWD" = "$BM1/projA" ]

_c_jump <<< $'1\n2\n\n' >/dev/null 2>&1
assert "T3f 阶段3 回车默认=1 进入项目" [ "$PWD" = "$BM1/projA" ]

_c_jump "主工作台" <<< $'0\n' >/dev/null 2>&1
assert "T3c 书签关键字直达阶段2" [ "$PWD" = "$BM1" ]

_c_jump "projA" >/dev/null 2>&1
assert "T3d 项目关键字模糊直达" [ "$PWD" = "$BM1/projA" ]

printf "1\nb\nq\n" | _c_jump >/dev/null 2>&1
assert "T3e [b] 返回书签选择后 [q] 退出" [ $? -eq 0 ]

# ── T3g 多位数编号（v5.101 回归：11 个目录时想输 11，旧版一敲 1 就进项目 1）──
# 构造 11 个项目，使菜单编号 ≥ 10 必然出现；菜单项为
#   1=进入书签根目录, 2..12=proj01..proj11, 13=返回书签选择
cd "$TEST_ROOT" || exit 1
for k in $(seq -w 1 11); do mkdir -p "$BM1/proj$k"; done
# 目标 = 菜单编号 12（= proj11）；期望 _c_jump 停在阶段3 而不是把 "1" 当成 proj01
proj_out=$(printf '1\n12\n' | _c_jump 2>&1)
assert "T3g 多位数编号：输入 1 不再立即跳转" grep -q "proj11" <<<"$proj_out"
# 单位数行为不变：3 项菜单输 1 依旧立即选中第 1 项。
# 注意：必须用 here-string(`<<<`) 而非 `|` 管道 —— 管道会让函数在子 shell
# 中执行，FZ_PICK_RET 赋值随子 shell 一起消失（bash 固有行为，与本改动无关）。
assert "T3g 单位数行为不变：1 仍选第一项" bash -c '
  source "'"$FZ_SRC_DIR"'/fzgit.sh" >/dev/null 2>&1
  a=(x y z)
  _fz_picker "t: " "${a[@]}" >/dev/null 2>&1 <<< "1"
  [ "$FZ_PICK_RET" = 1 ]'
# 交互路径（TTY 逐键）是本次修复的主战场，管道退化模式一次读整行、
# 本就支持多位，覆盖不到缓冲逻辑；该路径由 pty 探针实测验证。

# ══════════════════════════════════════════
echo ""
echo "══════════ T4 移动/复制 + safe.directory（用例6）══════════"

cd "$TEST_ROOT" || exit 1
printf "1\ny\n" | _bm_move_copy "主工作台" "$BM1/projA" "move" >/dev/null 2>&1
assert "T4a 移动成功" [ -d "$BM2/projA" ]
assert "T4b 原位置已移除" [ ! -d "$BM1/projA" ]
assert "T4c safe.directory 已记录" grep -q "directory = .*/projA" "$GIT_CONFIG_GLOBAL"

mkdir -p "$BM1/projB"
( cd "$BM1/projB" && git init -q && echo x > b.txt && printf 'build/\n' > .gitignore && git add . && git commit -qm init2 )
printf "1\nn\n" | _bm_move_copy "主工作台" "$BM1/projB" "copy" >/dev/null 2>&1
assert "T4d 复制成功" [ -d "$BM2/projB" ]
assert "T4e 复制后原件保留" [ -d "$BM1/projB" ]

# ══════════════════════════════════════════
echo ""
echo "══════════ T5 交互式克隆（用例4：gh 不可用时降级直连）══════════"

# T5a 书签目录内克隆 → 自动识别书签（无需询问）
cd "$BM1" || exit 1
printf "n\n" | _clone_direct "file://${REMOTE}" >/dev/null 2>&1
assert "T5a 克隆到书签目录" [ -d "$BM1/origin" ]

# T5b 非书签目录克隆 → 询问是否加入书签
mkdir -p "$TEST_ROOT/elsewhere"
cd "$TEST_ROOT/elsewhere" || exit 1
printf "y\n新书签\n" | _clone_direct "file://${REMOTE}" >/dev/null 2>&1
assert "T5b 克隆到非书签目录" [ -d "$TEST_ROOT/elsewhere/origin" ]
assert "T5c 询问后加入新书签" grep -q "^新书签|${TEST_ROOT}/elsewhere$" "$HOME/.fz_bookmarks"

# T5d 交互式克隆 gh 降级路径（仅当 gh 缺失时验证；已装则跳过避免网络依赖）
if command -v gh &>/dev/null; then
    echo "  ⏭️  gh 已安装，T5d 交互式列表依赖外部认证，跳过"
else
    _clone_interactive >/dev/null 2>&1; rc=$?
    assert "T5d gh 缺失时优雅提示并退出" [ "$rc" -eq 1 ]
fi

# ══════════════════════════════════════════
echo ""
echo "══════════ T6 批量拉取（用例5）══════════"

cd "$BM1" || exit 1
git clone -q "$REMOTE" remote_proj 2>/dev/null
( cd "$BM1/remote_proj" && echo update > u.txt && git add . && git commit -qm update && git push -q origin HEAD 2>&1 )

out=$(printf "y\n" | _pull_all "主工作台" 2>&1)
assert "T6a 批量拉取执行并统计" grep -qE "完成: [0-9]+ 成功" <<<"$out"

# 失败路径：把 origin 指向不存在的仓库
( cd "$BM1/remote_proj" && git remote set-url origin "file://${TEST_ROOT}/nonexistent.git" )
out=$(printf "y\n" | _pull_all "主工作台" 2>&1)
assert "T6b 拉取失败被记录" grep -q "失败项目列表" <<<"$out"
( cd "$BM1/remote_proj" && git remote set-url origin "$REMOTE" )

# ══════════════════════════════════════════
echo ""
echo "══════════ T7 炼化输出路径（计划书 6.4）══════════"

cd "$BM1/projB" || exit 1
_f_burn >/dev/null 2>&1
assert "T7a 炼化输出到项目上一级目录" [ -f "$BM1/code_projB.txt" ]

# ══════════════════════════════════════════
echo ""
echo "══════════ T8 上下文感知（计划书 6.2 / 6.5）══════════"

cd "$BM1/projB" || exit 1
bm=$(_bm_current)
assert "T8a 识别当前书签" [ "$bm" = "主工作台" ]

mkdir -p "$TEST_ROOT/outside/gitx"
( cd "$TEST_ROOT/outside/gitx" && git init -q && echo y > y.txt && printf 'build/\n' > .gitignore && git add . && git commit -qm c )
cd "$TEST_ROOT/outside/gitx" || exit 1
printf "n\n" | _p_push >/dev/null 2>&1; rc=$?
assert "T8b 非书签内推送前置检查拦截" [ "$rc" -ne 0 ]

cd "$BM1/projB" || exit 1
rm -f "$BM1/code_projB.txt"   # 清理 T7 炼化产物，恢复"无变更"场景
out=$(_p_push 2>&1)
# v5.100：文案从含糊的"没有任何变更"改为明确说明（projB 无远程 → 未绑定提示）
assert "T8c 书签内无变更时给出明确提示" grep -q "无需推送" <<<"$out"

# ══════════════════════════════════════════
echo ""
echo "══════════ T9 状态与总览（lsp / st）══════════"

cd "$BM1/projB" || exit 1
out=$(_st_status 2>&1)
assert "T9a st 显示书签上下文" grep -q "主工作台" <<<"$out"
out=$(_ls_projects 2>&1)
assert "T9b lsp 总览含项目" grep -q "projB" <<<"$out"

# T9c/T9d（v5.103）：st 合并 info 信息 + 列出变更文件清单
echo dirty >> "$BM1/projB/b.txt"
echo brand-new > "$BM1/projB/newfile.txt"
out=$(_st_status 2>&1)
assert "T9c st 列出变更文件名（不再只有个数）" grep -q "newfile.txt" <<<"$out"
assert "T9d st 含提交数与追踪文件数（合并 info）" grep -qE "次提交.*个追踪文件" <<<"$out"

# ══════════════════════════════════════════
echo ""
echo "══════════ T11 多远程推送基准（v5.100 核心回归）══════════"
# 场景（用户真实报告）：项目同时绑 GitHub(origin) 与 CNB(cnb)，
# 上游 @{u} 指向 cnb。本地在 cnb 已是最新、GitHub 还是旧版时按 p，
# 旧版用 @{u} 判断 → ahead 恒为 0 → 假报"没有任何变更，无需推送"并
# 直接 return，git push origin 从未执行，GitHub 永远停在旧版。

REMOTE_ORIGIN="$TEST_ROOT/remote/origin-github.git"
REMOTE_CNB="$TEST_ROOT/remote/cnb.git"
git init -q --bare "$REMOTE_ORIGIN"
git init -q --bare "$REMOTE_CNB"
( cd "$REMOTE_CNB" && git symbolic-ref HEAD refs/heads/main ) 2>/dev/null || true
( cd "$REMOTE_ORIGIN" && git symbolic-ref HEAD refs/heads/main ) 2>/dev/null || true

mkdir -p "$BM2/multi"
(
  cd "$BM2/multi" && git init -q && git symbolic-ref HEAD refs/heads/main &&
  git remote add cnb "$REMOTE_CNB" && git remote add origin "$REMOTE_ORIGIN" &&
  printf 'build/\n' > .gitignore && echo v1 > f.txt && git add . && git commit -qm init &&
  git push -q -u cnb main && git push -q origin main
) >/dev/null 2>&1

cd "$BM2/multi" || exit 1
assert "T11a 前置：上游指向 cnb（复现用户环境）" \
    [ "$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null)" = "cnb/main" ]

# 本地产生"最新版"提交，GitHub 仍是旧版 → 按 p（默认 origin）
echo v2 > f.txt && git add . && git commit -qm latest >/dev/null 2>&1
out=$(_p_push 2>&1)
assert "T11b 不再假报「没有任何变更，无需推送」" \
    bash -c '! grep -q "没有任何变更" <<<"$1"' _ "$out"
assert "T11c GitHub(origin) 已真正被推送到最新" \
    [ "$(git -C "$REMOTE_ORIGIN" rev-parse main 2>/dev/null)" = "$(git rev-parse HEAD)" ]
assert "T11d 未静默改写上游（仍是 cnb/main）" \
    [ "$(git rev-parse --abbrev-ref '@{u}')" = "cnb/main" ]
assert "T11e 提示 cnb 仍需同步" \
    bash -c 'grep -q "cnb" <<<"$1"' _ "$out"

# 文档承诺：p "备注" 指定 commit message（v5.97 曾回归为"远程未绑定"报错）
echo v3 > f.txt
out=$(_p_push "修复登录bug" 2>&1)
assert "T11f p \"备注\" 生效且不再报远程未绑定" \
    bash -c '[ "$(git -C "$1" log -1 --format=%s)" = "修复登录bug" ] && ! grep -q "未绑定" <<<"$2"' \
    _ "$BM2/multi" "$out"

# 无变更且确已同步 → 明确报"已是最新"（而非误导文案）
out=$(_p_push 2>&1)
assert "T11g 确无新内容时明确提示已是最新" grep -q "已是最新" <<<"$out"

# 上游为空场景（仅用 p cnb、从未建立跟踪）也须真推
git checkout -q -b feature/x >/dev/null 2>&1
echo n1 > n.txt && git add . && git commit -qm newbr >/dev/null 2>&1
out=$(_p_push cnb 2>&1)
assert "T11h 上游为空时首推新分支不假报" \
    [ "$(git -C "$REMOTE_CNB" rev-parse feature/x 2>/dev/null)" = "$(git rev-parse HEAD)" ]

# ══════════════════════════════════════════
echo ""
echo "══════════ T10 模块加载完整性 ══════════"

missing=0
for fn in _bm_init _bm_load _bm_add _bm_remove _bm_get_path _bm_rename _bm_current _bookmark_mgr \
          _c_jump _c_project_menu _bm_move_copy _ls_projects _st_status \
          _clone_repo _clone_direct _clone_interactive _pull_all \
          _f_burn _p_push _branch_mgr _ok_merge _tag_mgr _repo_info \
          _fz_parse_push_args _fz_ensure_upstream _fz_other_remotes_hint; do
    declare -F "$fn" >/dev/null 2>&1 || { echo "  ❌ 缺少函数: $fn"; missing=$((missing + 1)); }
done
if [ "$missing" -eq 0 ]; then
    PASS=$((PASS + 1)); echo "  ✅ 全部 27 个核心函数已加载"
else
    FAIL=$((FAIL + 1)); FAIL_NAMES+=("模块加载完整性（缺 $missing 个函数）")
fi

# ══════════════════════════════════════════
# T12 安全回归（P0：凭据不得进入仓库）
#  背景：aikey 曾把 Key 明文 sed 进被 git 追踪的 fz-tools/fzgit.sh，
#  而 p 会执行 git add . —— 配过 Key 后一次推送即公开泄漏。
#  以下用例锁死修复，防止被改回。
# ══════════════════════════════════════════
echo ""
echo "══════════ T12 安全回归（凭据隔离）══════════"

# T12a: source 主入口不得写磁盘（旧版会 mkdir -p 一个硬编码个人路径）
unset FZ_BASE FZ_BASE_USER_SET
_probe_home="$TEST_ROOT/t12_home"; mkdir -p "$_probe_home"
( HOME="$_probe_home"; unset FZ_BASE FZ_BASE_USER_SET
  source "${FZ_SRC_DIR}/fzgit.sh" >/dev/null 2>&1
  [ -d "${_probe_home}/repos" ] && exit 1 || exit 0 )
assert "T12a source 主入口不创建目录（不写磁盘）" [ $? -eq 0 ]

# T12b: 全新用户不应被误判为旧版（FZ_BASE_USER_SET 默认 0）
( HOME="$_probe_home"; unset FZ_BASE FZ_BASE_USER_SET
  source "${FZ_SRC_DIR}/fzgit.sh" >/dev/null 2>&1
  [ "$FZ_BASE_USER_SET" = "0" ] )
assert "T12b 新用户 FZ_BASE_USER_SET=0（不误判旧版）" [ $? -eq 0 ]

# T12c: 主入口源码中不得硬编码个人存储路径
if grep -q '工作台😡\|/storage/emulated/0/常用' "${FZ_SRC_DIR}/fzgit.sh" 2>/dev/null; then
    FAIL=$((FAIL + 1)); FAIL_NAMES+=("T12c 主入口含硬编码个人路径"); echo "  ❌ T12c"
else
    PASS=$((PASS + 1)); echo "  ✅ T12c 主入口无硬编码个人路径"
fi

# T12d: aikey 不得写入被 git 追踪的文件
if grep -qE 'sed -i.*FZ_AI_KEY' "${FZ_SRC_DIR}/modules/env.sh" 2>/dev/null; then
    FAIL=$((FAIL + 1)); FAIL_NAMES+=("T12d aikey 仍 sed 写入仓库文件"); echo "  ❌ T12d"
else
    PASS=$((PASS + 1)); echo "  ✅ T12d aikey 不再写入仓库文件"
fi

# T12e: 凭据护栏能拦住真 Key
_t12repo="$TEST_ROOT/t12_repo"; mkdir -p "$_t12repo/fz-tools"
cp "${FZ_SRC_DIR}/core.sh" "$_t12repo/fz-tools/"
( cd "$_t12repo" && git init -q && \
  echo "x" > base.txt && git add -A && git commit -qm base && \
  printf 'K="sk-ant-api03-AbCdEfGhIjKlMnOpQrStUvWx"\n' > leak.sh && \
  git add -A && \
  ( source fz-tools/core.sh; ! _fz_guard_staged_secrets ) )
assert "T12e 凭据护栏拦住真实 Key" [ $? -eq 0 ]

# T12f: 凭据护栏不误报占位符/文档写法
( cd "$_t12repo" && git reset -q && rm -f leak.sh && \
  printf 'ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n' > p.txt && \
  printf '# 示例: sk-ant-api03-AbCdEfGhIjKlMnOpQrStUvWx\n' >> p.txt && \
  printf 'FZ_AI_KEY=""\n' >> p.txt && \
  git add -A && \
  ( source fz-tools/core.sh; _fz_guard_staged_secrets ) )
assert "T12f 凭据护栏不误报占位符" [ $? -eq 0 ]

# T12g: p 不再自动改写版本号（旧版每次推送都产生版本号提交）
if grep -qE 'sed -i.*FZ_VERSION' "${FZ_SRC_DIR}/modules/push.sh" 2>/dev/null; then
    FAIL=$((FAIL + 1)); FAIL_NAMES+=("T12g p 仍在改写版本号"); echo "  ❌ T12g"
else
    PASS=$((PASS + 1)); echo "  ✅ T12g p 不再自动改写版本号"
fi

# ══════════════════════════════════════════
# T13 安装器（get.sh）
#  安装是用户接触本工具的第一步，出错代价最高：
#  · 重复安装不能堆叠 .bashrc
#  · 目标目录已有数据时不能覆盖
#  · 卸载不能吃掉用户的书签与 Key
# ══════════════════════════════════════════
echo ""
echo "══════════ T13 安装器（get.sh）══════════"

GET_SH="${FZ_SRC_DIR}/../get.sh"
if [ ! -f "$GET_SH" ]; then
    FAIL=$((FAIL + 1)); FAIL_NAMES+=("T13 get.sh 缺失"); echo "  ❌ T13 get.sh 缺失"
else
    _t13="$TEST_ROOT/t13"
    mkdir -p "$_t13/src" "$_t13/home"
    # 用本地 bare 仓库模拟远端，零网络
    git init -q --bare "$_t13/remote.git"
    ( cd "$_t13/src" \
      && cp -r "${FZ_SRC_DIR}" fz-tools && cp "$GET_SH" . \
      && git init -q && git add -A \
      && git -c user.email=a@b.c -c user.name=t commit -qm t13 \
      && git branch -M main \
      && git push -q "$_t13/remote.git" main ) >/dev/null 2>&1

    _t13_install() {
        HOME="$_t13/home" \
        FZ_REPO_URL="$_t13/remote.git" \
        FZ_HOME="$_t13/home/.local/share/fz" \
        FZ_RC="$_t13/home/.bashrc" \
        bash "$GET_SH" < /dev/null
    }

    # T13a 全新安装：目录 + bashrc 加载行
    _t13_install >/dev/null 2>&1
    assert "T13a 全新安装创建安装目录" test -d "$_t13/home/.local/share/fz/.git"
    assert "T13b 写入 bashrc 加载行" \
        bash -c "grep -q 'fz-tools/fzgit.sh' '$_t13/home/.bashrc'"

    # T13c 幂等：重复安装不得堆叠
    _t13_install >/dev/null 2>&1
    _cnt=$(grep -c 'fz-tools/fzgit.sh' "$_t13/home/.bashrc" 2>/dev/null || echo 0)
    assert "T13c 重复安装幂等（加载行仍为 1）" [ "$_cnt" = "1" ]

    # T13d 安装后可用（交互式 shell 中别名生效）
    assert "T13d 安装后 c 别名可用" \
        bash -c "HOME='$_t13/home' bash -ic 'type c' 2>/dev/null | grep -q 'c is aliased'"

    # T13e 拒绝覆盖非 git 目录（防吃数据）
    mkdir -p "$_t13/occupied"; echo "keep" > "$_t13/occupied/keep.txt"
    HOME="$_t13/home" FZ_REPO_URL="$_t13/remote.git" \
    FZ_HOME="$_t13/occupied" FZ_RC="$_t13/home/.bashrc" \
    bash "$GET_SH" < /dev/null >/dev/null 2>&1
    assert "T13e 不覆盖已有非 git 目录" test -f "$_t13/occupied/keep.txt"

    # T13f 无 TTY 时卸载必须显式 --yes（破坏性操作不默认同意）
    assert "T13f 无 --yes 时拒绝卸载" \
        bash -c "HOME='$_t13/home' FZ_HOME='$_t13/home/.local/share/fz' FZ_RC='$_t13/home/.bashrc' \
                 bash '$GET_SH' --uninstall </dev/null 2>&1 | grep -q '需要显式确认'"

    # T13g 卸载保留书签与 Key
    echo "工作台|$_t13/books" > "$_t13/home/.fz_bookmarks"
    echo "sk-ant-dummy" > "$_t13/home/.fz_ai_key"
    HOME="$_t13/home" FZ_HOME="$_t13/home/.local/share/fz" \
    FZ_RC="$_t13/home/.bashrc" bash "$GET_SH" --uninstall --yes </dev/null >/dev/null 2>&1
    assert "T13g 卸载删除安装目录" bash -c "[ ! -d '$_t13/home/.local/share/fz' ]"
    assert "T13h 卸载清除 bashrc 加载行" \
        bash -c "! grep -q 'fz-tools/fzgit.sh' '$_t13/home/.bashrc' 2>/dev/null"
    assert "T13i 卸载保留书签文件" test -f "$_t13/home/.fz_bookmarks"
    assert "T13j 卸载保留 API Key 文件" test -f "$_t13/home/.fz_ai_key"
fi

# ══════════════════════════════════════════
# T14 AI 备注（可选功能，默认关闭）
#  核心保证：
#  · 未配置 → 零网络请求（不能让用户莫名被计费/外发）
#  · 只支持 OpenAI 兼容协议（不绑定单一厂商）
#  · 任何异常 → 静默返回失败，p 降级到默认备注
# ══════════════════════════════════════════
echo ""
echo "══════════ T14 AI 备注（可选功能）══════════"

# T14a 未配置时未就绪
_t14_h="$TEST_ROOT/t14_home"; mkdir -p "$_t14_h"
assert "T14a 未配置时 AI 未就绪" \
    bash -c "HOME='$_t14_h'; unset FZ_AI_KEY FZ_AI_BASE_URL FZ_AI_MODEL FZ_AI_CONF_FILE; \
             source '${FZ_SRC_DIR}/core.sh'; source '${FZ_SRC_DIR}/modules/ai.sh'; ! _fz_ai_ready"

# T14b 配置文件读取
mkdir -p "$_t14_h"
cat > "$_t14_h/.fz_ai.conf" <<'CONF'
FZ_AI_BASE_URL=https://example.test/v1
FZ_AI_MODEL=test/model
FZ_AI_KEY=nvapi-TEST
CONF
chmod 600 "$_t14_h/.fz_ai.conf"
assert "T14b 读取配置文件后 AI 就绪" \
    bash -c "HOME='$_t14_h'; unset FZ_AI_KEY FZ_AI_BASE_URL FZ_AI_MODEL FZ_AI_CONF_FILE; \
             source '${FZ_SRC_DIR}/core.sh'; source '${FZ_SRC_DIR}/modules/ai.sh'; _fz_ai_ready"

# T14c 响应解析：各种模型输出脏格式都要能清干净
_t14_parse() {
    bash -c "HOME='$_t14_h'; source '${FZ_SRC_DIR}/core.sh'; source '${FZ_SRC_DIR}/modules/ai.sh'; \
             _fz_ai_extract_content \"\$1\"" _ "$1"
}
assert "T14c 解析纯文本" test "$(_t14_parse '{"choices":[{"message":{"content":"feat: 新增"}}]}')" = "feat: 新增"
assert "T14d 解析代码块包裹" test "$(_t14_parse '{"choices":[{"message":{"content":"```\nfix: 修复\n```"}}]}')" = "fix: 修复"
assert "T14e 多行只取首行" test "$(_t14_parse '{"choices":[{"message":{"content":"chore: 更新\n解释"}}]}')" = "chore: 更新"

# T14f 异常响应必须静默失败（不能假报成功）
assert "T14f 空 content 判定失败" \
    bash -c "HOME='$_t14_h'; source '${FZ_SRC_DIR}/core.sh'; source '${FZ_SRC_DIR}/modules/ai.sh'; \
             ! _fz_ai_extract_content '{\"choices\":[{\"message\":{\"content\":\"\"}}]}'"
assert "T14g 非 JSON 判定失败" \
    bash -c "HOME='$_t14_h'; source '${FZ_SRC_DIR}/core.sh'; source '${FZ_SRC_DIR}/modules/ai.sh'; \
             ! _fz_ai_extract_content 'garbage'"
assert "T14h 错误响应判定失败" \
    bash -c "HOME='$_t14_h'; source '${FZ_SRC_DIR}/core.sh'; source '${FZ_SRC_DIR}/modules/ai.sh'; \
             ! _fz_ai_extract_content '{\"error\":{\"message\":\"invalid key\"}}'"

# T14i 不得绑定单一厂商：代码里不应出现 anthropic 专用协议头
if grep -q 'api\.anthropic\.com\|x-api-key\|anthropic-version' \
        "${FZ_SRC_DIR}/modules/ai.sh" "${FZ_SRC_DIR}/modules/push.sh" 2>/dev/null; then
    FAIL=$((FAIL + 1)); FAIL_NAMES+=("T14i 仍绑定 Anthropic 专用协议"); echo "  ❌ T14i"
else
    PASS=$((PASS + 1)); echo "  ✅ T14i 已改为通用 OpenAI 兼容协议"
fi

# T14j 关闭功能后配置被删除
bash -c "HOME='$_t14_h'; source '${FZ_SRC_DIR}/core.sh'; source '${FZ_SRC_DIR}/modules/ai.sh'; _fz_ai_off" >/dev/null 2>&1
assert "T14j aikeyoff 删除配置文件" test ! -f "$_t14_h/.fz_ai.conf"

# ══════════════════════════════════════════
# T15 代码卫生（防止考古注释与文档腐化）
#  背景：注释里堆版本号（"v5.100 修复了…"）会让读者无法判断
#  哪段描述当前行为、哪段只是历史残骸。历史属于 CHANGELOG / git log。
# ══════════════════════════════════════════
echo ""
echo "══════════ T15 代码卫生 ══════════"

# T15a 源码注释里不得出现版本号
_t15_hits=$(grep -rn '^[[:space:]]*#.*v[0-9]\+\.[0-9]' \
    "${FZ_SRC_DIR}"/*.sh "${FZ_SRC_DIR}"/modules/*.sh 2>/dev/null \
    | grep -v 'smoke-test' \
    | grep -v '支持 v\|格式\|比较' || true)
if [ -n "$_t15_hits" ]; then
    FAIL=$((FAIL + 1)); FAIL_NAMES+=("T15a 注释含版本号")
    echo "  ❌ T15a 注释含版本号（应移到 CHANGELOG）:"
    printf '%s\n' "$_t15_hits" | head -3 | sed 's/^/     /'
else
    PASS=$((PASS + 1)); echo "  ✅ T15a 源码注释无版本号"
fi

# T15b README 不得承载 changelog
_t15_repo="$(cd "${FZ_SRC_DIR}/.." && pwd)"
if [ -f "${_t15_repo}/README.md" ] && grep -q '核心变化\|核心修复' "${_t15_repo}/README.md" 2>/dev/null; then
    FAIL=$((FAIL + 1)); FAIL_NAMES+=("T15b README 混入 changelog"); echo "  ❌ T15b README 混入 changelog"
else
    PASS=$((PASS + 1)); echo "  ✅ T15b README 不承载 changelog"
fi

# T15c 声明了 CHANGELOG 就必须存在
if [ -f "${_t15_repo}/README.md" ] && grep -q 'CHANGELOG' "${_t15_repo}/README.md" 2>/dev/null; then
    assert "T15c README 引用的 CHANGELOG 存在" test -f "${_t15_repo}/CHANGELOG.md"
fi

# T15d 主名应为 ghlogin（login 仅为兼容别名）
if grep -q "alias ghlogin=" "${FZ_SRC_DIR}/fzgit.sh" 2>/dev/null; then
    PASS=$((PASS + 1)); echo "  ✅ T15d 提供 ghlogin（避免遮蔽系统 login）"
else
    FAIL=$((FAIL + 1)); FAIL_NAMES+=("T15d 缺少 ghlogin"); echo "  ❌ T15d 缺少 ghlogin"
fi

# ══════════════════════════════════════════
echo ""
echo "══════════════════ 汇总 ══════════════════"
echo "通过: ${PASS}   失败: ${FAIL}"
if [ "$FAIL" -gt 0 ]; then
    printf '  ❌ %s\n' "${FAIL_NAMES[@]}"
    echo "隔离环境 ${TEST_ROOT} 已自动清理"
    exit 1
fi
echo "🎉 全套冒烟测试通过！临时环境已自动清理"
exit 0
