#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
#  焚诀·Git 工作流 v5.0 — 全套冒烟测试
#  用法: bash fz-tools/smoke-test.sh
#  特性:
#    · $TMPDIR 隔离环境（独立 HOME / GIT_CONFIG_GLOBAL）
#    · 本地 bare 仓库模拟远端，零网络依赖
#    · 交互流程全部自动应答（管道喂入）
#    · 结束自动清理全部临时文件（trap EXIT）
#  覆盖 plan.md 8.2 六个测试用例 + 各模块核心函数
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

# T1b 全新安装向导：书签为空且无 FZ_BASE → 引导创建
rm -f "$HOME/.fz_bookmarks"
FZ_BASE=""
printf "主工作台\n%s\n" "$BM1" | _bm_init >/dev/null 2>&1
assert "T1b 全新向导：创建书签文件" grep -q "^主工作台|${BM1}$" "$HOME/.fz_bookmarks"

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

cd "$TEST_ROOT"
_c_jump <<< $'1\n0\n' >/dev/null 2>&1
assert "T3a 阶段1→2 [0] 进入书签根目录" [ "$PWD" = "$BM1" ]

_c_jump <<< $'1\n1\n1\n' >/dev/null 2>&1
assert "T3b 阶段3 [1] 进入项目" [ "$PWD" = "$BM1/projA" ]

_c_jump <<< $'1\n1\n\n' >/dev/null 2>&1
assert "T3f 阶段3 回车默认=1 进入项目" [ "$PWD" = "$BM1/projA" ]

_c_jump "主工作台" <<< $'0\n' >/dev/null 2>&1
assert "T3c 书签关键字直达阶段2" [ "$PWD" = "$BM1" ]

_c_jump "projA" >/dev/null 2>&1
assert "T3d 项目关键字模糊直达" [ "$PWD" = "$BM1/projA" ]

printf "1\nb\nq\n" | _c_jump >/dev/null 2>&1
assert "T3e [b] 返回书签选择后 [q] 退出" [ $? -eq 0 ]

# ══════════════════════════════════════════
echo ""
echo "══════════ T4 移动/复制 + safe.directory（用例6）══════════"

cd "$TEST_ROOT"
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
cd "$BM1"
printf "n\n" | _clone_direct "file://${REMOTE}" >/dev/null 2>&1
assert "T5a 克隆到书签目录" [ -d "$BM1/origin" ]

# T5b 非书签目录克隆 → 询问是否加入书签
mkdir -p "$TEST_ROOT/elsewhere"
cd "$TEST_ROOT/elsewhere"
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

cd "$BM1"
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

cd "$BM1/projB"
_f_burn >/dev/null 2>&1
assert "T7a 炼化输出到项目上一级目录" [ -f "$BM1/code_projB.txt" ]

# ══════════════════════════════════════════
echo ""
echo "══════════ T8 上下文感知（计划书 6.2 / 6.5）══════════"

cd "$BM1/projB"
bm=$(_bm_current)
assert "T8a 识别当前书签" [ "$bm" = "主工作台" ]

mkdir -p "$TEST_ROOT/outside/gitx"
( cd "$TEST_ROOT/outside/gitx" && git init -q && echo y > y.txt && printf 'build/\n' > .gitignore && git add . && git commit -qm c )
cd "$TEST_ROOT/outside/gitx"
printf "n\n" | _p_push >/dev/null 2>&1; rc=$?
assert "T8b 非书签内推送前置检查拦截" [ "$rc" -ne 0 ]

cd "$BM1/projB"
rm -f "$BM1/code_projB.txt"   # 清理 T7 炼化产物，恢复"无变更"场景
out=$(_p_push 2>&1)
assert "T8c 书签内无变更提示" grep -q "没有任何变更" <<<"$out"

# ══════════════════════════════════════════
echo ""
echo "══════════ T9 状态与总览（lsp / st）══════════"

cd "$BM1/projB"
out=$(_st_status 2>&1)
assert "T9a st 显示书签上下文" grep -q "主工作台" <<<"$out"
out=$(_ls_projects 2>&1)
assert "T9b lsp 总览含项目" grep -q "projB" <<<"$out"

# ══════════════════════════════════════════
echo ""
echo "══════════ T10 模块加载完整性 ══════════"

missing=0
for fn in _bm_init _bm_load _bm_add _bm_remove _bm_get_path _bm_rename _bm_current _bookmark_mgr \
          _c_jump _c_project_menu _bm_move_copy _ls_projects _st_status \
          _clone_repo _clone_direct _clone_interactive _pull_all \
          _f_burn _p_push _branch_mgr _ok_merge _tag_mgr _repo_info; do
    declare -F "$fn" >/dev/null 2>&1 || { echo "  ❌ 缺少函数: $fn"; missing=$((missing + 1)); }
done
if [ "$missing" -eq 0 ]; then
    PASS=$((PASS + 1)); echo "  ✅ 全部 24 个核心函数已加载"
else
    FAIL=$((FAIL + 1)); FAIL_NAMES+=("模块加载完整性（缺 $missing 个函数）")
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
