#!/usr/bin/env bash
# 冒烟测试脚本: $1=主入口 $2=临时工作台 $3=临时HOME $4=假FZ_TOOLS_DIR
shopt -s expand_aliases
source "$1" || { echo "FATAL: source 失败"; exit 2; }
export FZ_BASE="$2" HOME="$3"
mkdir -p "$FZ_BASE" "$HOME"
echo "== STEP 01 =="; echo "VERSION=$FZ_VERSION"
[ "$FZ_VERSION" = "4.0" ] && echo "PASS 01 版本号 v4.0"
for fn in _update_script _check_git_repo _git_auto_ignore _json_escape _setup_env _trust_dir _github_login _create_repo _remote_mgr _c_jump _ls_projects _branch_mgr _rename_branch _clean_branches _sync_branch _ai_commit_msg _p_push _ok_merge _no_revert _main_branch _log_pretty _diff_view _stash_save _stash_pop _fix_conflict _tag_mgr _f_burn _clone_repo _pull_all _repo_info _ai_setup _rls_remote; do
  [ "$(type -t $fn)" = "function" ] || { echo "FAIL 02 缺少函数: $fn"; exit 1; }
done
echo "PASS 02 32 个函数全部就位"
for a in up setup login repo remote trust aikey c lsp b rn bclean gsync p ok no gomain f lg d save pop fix tag cl pullall info rls st pull undo unstage h; do
  alias "$a" >/dev/null 2>&1 || { echo "FAIL 03 缺少别名: $a"; exit 1; }
done
echo "PASS 03 33 个别名全部注册"
source "$1" >/dev/null 2>&1 && echo "PASS 04 重复 source 幂等"
exp=$(printf "\"hello\"")
[ "$(_json_escape hello)" = "$exp" ] && echo "PASS 05 json_escape"
echo "== STEP 02 =="
_check_git_repo && echo "PASS 06 check_git_repo"
_p_push </dev/null >/dev/null 2>&1 && echo "PASS 07 p_push 无变更路径"
_git_auto_ignore >/dev/null && [ -f .gitignore ] && echo "PASS 08 git_auto_ignore"
_log_pretty 5 >/dev/null && echo "PASS 09 log_pretty"
_diff_view >/dev/null && echo "PASS 10 diff_view"
_repo_info >/dev/null && echo "PASS 11 repo_info"
_fix_conflict >/dev/null && echo "PASS 12 fix_conflict"
_main_branch >/dev/null && echo "PASS 13 main_branch"
_branch_mgr -l >/dev/null && echo "PASS 14 branch_mgr -l"
_tag_mgr >/dev/null && echo "PASS 15 tag_mgr 列表"
_clean_branches </dev/null >/dev/null 2>&1 && echo "PASS 16 clean_branches"
_sync_branch </dev/null >/dev/null 2>&1 && echo "PASS 17 sync_branch 无远程"
_ok_merge nonexist </dev/null >/dev/null 2>&1; [ $? -eq 1 ] && echo "PASS 18 ok_merge 分支不存在守卫"
echo "== STEP 03 =="
echo more >> a.txt
_stash_save smoke >/dev/null 2>&1 && _stash_pop >/dev/null 2>&1 && echo "PASS 19 stash save/pop"
_rename_branch renamed >/dev/null 2>&1 && echo "PASS 20 rename_branch"
_p_push </dev/null >/dev/null 2>&1
git log -1 --oneline | grep -q "update" && echo "PASS 21 p_push 变更路径已提交"
_ai_commit_msg >/dev/null 2>&1; [ $? -eq 1 ] && echo "PASS 22 ai_commit_msg 无Key返回1"
echo "" | _ai_setup >/dev/null 2>&1 && echo "PASS 23 ai_setup 空输入不写入"
_github_login </dev/null >/dev/null 2>&1; echo "      login rc=$? (沙箱无 gh 时预期1)"
_rls_remote </dev/null >/dev/null 2>&1; [ $? -eq 1 ] && echo "PASS 24 rls_remote 用法守卫"
echo "== STEP 04 =="
export FZ_TOOLS_DIR="$4"
_update_script </dev/null >/dev/null 2>&1; echo "      up rc=$? (假FZ_TOOLS_DIR，预期1)"
_c_jump </dev/null >/dev/null 2>&1 && echo "PASS 25 c_jump 空工作台"
_ls_projects >/dev/null && echo "PASS 26 ls_projects"
_pull_all >/dev/null && echo "PASS 27 pull_all"
_clone_repo </dev/null >/dev/null 2>&1 && echo "PASS 28 clone_repo 用法提示"
_trust_dir >/dev/null 2>&1 && echo "PASS 29 trust_dir"
h | grep -q "焚诀·Git 工作流" && echo "PASS 30 h 菜单渲染"
h | grep -q "v4.0" && echo "PASS 31 h 显示 v4.0"
echo "== STEP 05 =="
echo "fn(){}" > code_test.js
git add code_test.js
_f_burn >/dev/null 2>&1
ls "$HOME"/code_*.txt >/dev/null 2>&1 && ls "$FZ_BASE"/code_*.txt >/dev/null 2>&1 && echo "PASS 32 f_burn 产物生成(HOME+工作台)"
echo "ALL_SMOKE_DONE"
