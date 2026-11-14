# AGENTS.md — 改动本仓库前的必读契约

本仓库是 **bash 函数库**（被 `source` 进交互式 shell），不是独立命令行程序。
理解这一条，才能判断什么改动是安全的。

---

## 一、先理解形态：这是「库」，不是「程序」

```
用户的 ~/.bashrc
  └─ source <仓库>/fz-tools/fzgit.sh     ← 加载进「当前 shell 进程」
        ├─ core.sh
        └─ modules/*.sh                    ← 只定义函数，不执行动作
```

**运行时 = 用户正在用的那个 shell**。因此：

| 约束 | 原因 | 违反后果 |
|---|---|---|
| 加载阶段（`source` 时）**绝不能**执行有副作用的命令 | 每次开终端都会跑一遍 | 启动变慢、写脏磁盘、报错刷屏 |
| 函数内改目录必须考虑调用方 | 函数和用户共用同一个 cwd | `c` 是**故意**改 cwd 的，其余函数不许 |
| 变量默认必须 `local` | 会覆写用户环境或调用方的同名变量 | 极难排查的串扰 |
| 不能依赖 `set -e` | 交互式 shell 里 `set -e` 会直接踢掉用户会话 | 终端退出 |
| 必须兼容 bash 3.2+（macOS 自带） | 用户在 macOS / WSL / Termux 都可能跑 | 语法直接崩 |

### 「为什么必须 clone 才能用」

这是**功能决定的，不是设计缺陷**。`c` 需要改变父 shell 的 cwd，而
POSIX 规定任何子进程都无法改变父进程的 cwd —— 所以只能 `source`，
所以必须有本地文件副本。同形态的工具都这样分发：`nvm`、`asdf`、
`oh-my-zsh`。

**不要**为了“看起来像个正常程序”而改造成 PATH 里的可执行文件，
那会让 `c` 退化成“打印路径让你自己 cd”。

---

## 二、硬性红线（违反即拒绝提交）

### 🔴 凭据永不入库

```bash
# ❌ 绝对禁止：本文件被 git 追踪，p 会 git add .
export FZ_AI_KEY="sk-ant-..."

# ✅ 正确：存 HOME 下，权限 600
printf '%s\n' "$key" > ~/.fz_ai_key && chmod 600 ~/.fz_ai_key
```

历史上 `aikey` 就曾把 Key `sed` 进 `fz-tools/fzgit.sh`，而 `p` 执行
`git add .` —— 配过 Key 的人一次推送就把密钥公开了。
`smoke-test.sh` 的 `T12*` 用例锁死了这条，别绕过它。

### 🔴 不硬编码任何个人路径

仓库是公开的。`/storage/emulated/0/常用/工作台😡/...` 这种路径
对其他用户毫无意义，且旧实现在 `source` 时还会 `mkdir -p` 它。

一律用 `"${HOME}/..."` 加环境变量覆盖，且**不在加载阶段创建目录**。

### 🔴 加载阶段不写磁盘、不联网、不阻塞

`source fzgit.sh` 必须是纯内存操作。需要目录时由用到它的函数自己
`mkdir -p` 并处理失败。

### 🔴 不在 `p` 里改仓库文件

旧实现在每次推送时 `sed` 覆盖 `FZ_VERSION`，导致每次推送必然产生
一个「版本号变动」提交，多分支并行时还是固定冲突源。
版本号现在只由 `version.sh` 在发版时显式递增。

### 🔴 AI 功能必须保持「默认关闭 + 协议中立」

`modules/ai.sh` 是可选的 commit 备注生成器。三条不可让步：

| 约束 | 原因 |
|---|---|
| 未配置时**零网络请求** | 不能让用户莫名被计费或被外发数据 |
| 只用 OpenAI 兼容协议（`/v1/chat/completions`） | 绑定单一厂商会迅速过时；NVIDIA/DeepSeek/Ollama/代理都兼容 |
| 任何异常静默返回失败 | `p` 必须能降级到默认备注，不能因为 AI 挂了就推不上去 |

**数据流向必须对用户可见**：`aikey` 里已写明会把 diff 前 200 行发到第三方。
不要把这段提示删掉——这是用户知情权的唯一入口。

`smoke-test.sh` 的 `T14*` 用例锁定了以上行为。

### 🔴 不破坏安装器契约

`get.sh` 是用户接触本工具的第一步，出错代价最高。以下性质**必须**保持，
`smoke-test.sh` 的 `T13*` 用例已锁死：

| 性质 | 原因 |
|---|---|
| 幂等 | 重复安装不得堆叠 `.bashrc` 加载行 |
| 不覆盖 | 目标目录已存在且非 git 仓库时拒绝执行（防吃用户数据） |
| 卸载保守 | 保留 `~/.fz_bookmarks` 与 `~/.fz_ai_key` |
| 破坏性操作需显式确认 | 无 TTY 时卸载必须带 `--yes`，不接受「默认同意」 |
| stdin 处理 | `curl \| bash` 时 stdin 是管道，需先探测 `/dev/tty` 可读再切换——直接 `exec < /dev/tty` 失败会关掉 stdin，导致后续所有确认都被当作取消 |


---

## 三、代码风格

### 变量命名

| 作用域 | 前缀 | 例 |
|---|---|---|
| 函数内 | `local`，名字随意 | `local b_name` |
| 函数内循环/中间变量 | 加函数名前缀防撞 | `local _bm_n _bm_p` |
| 跨函数返回（global） | `FZ_` + 大写 | `FZ_PICK_RET` |
| 用户可覆盖的配置 | `FZ_` + 大写 | `FZ_BASE` |

`_bm_load` 里那句「内部 read 变量必须用 `_bm_` 前缀」是被 bug 教出来的，
不是规定 —— 能用 `local` 就用 `local`。

### 函数命名

```
_c_xxx      命令 c 的实现
_bm_xxx     书签（bookmark）相关
_fz_xxx     通用内部工具
模块内部辅助  加模块名前缀，如 _fz_picker_paint_row
```

### 注释：写「为什么」，不写「改过什么」

**禁止在注释里写版本号**（`v5.100 修复了…`）。版本历史属于
`CHANGELOG.md` 与 `git log`，写进源码会让代码变成考古现场：
读者无法判断哪段注释描述的是当前行为、哪段只是历史残骸。

自检：`grep -rn 'v[0-9]\+\.[0-9]' fz-tools/ --include='*.sh'` 应为空
（`smoke-test.sh` 的用例编号除外）。

```bash
# ❌ 禁止（这是 git log 的活，写在这里会让代码变成考古现场）
# v5.100 核心修复：判定基准从 @{u} 改为「本次目标远程 $_fz_target_ref」
#   旧版用 @{u}：当上游指向另一个远程时，落后检测全看错对象...

# ✅ 正确（记录不变的原因，读者需要它来判断能不能改）
# 判定基准必须是「本次目标远程」而非 @{u}：
# 一个项目可能同时绑 GitHub 和 CNB，上游只指向其中一个。
```

一段注释如果只在解释「以前是错的、现在对了」，删掉它 —— 信息在 `git log` 里。
只有当历史能防止未来的人重新踩坑时，才保留（并且要压缩到一两句）。

### 错误处理

```bash
# ✅ 保留真实报错，区分「本来就没变更」和「真的失败了」
local out
if ! out=$(git commit -m "$msg" 2>&1); then
    if echo "$out" | grep -qiE "nothing to commit"; then
        # 真的没变更
    else
        echo "❌ 提交失败: $out" >&2
        return 1
    fi
fi

# ❌ 禁止把失败原因 2>/dev/null 掉然后当成功处理
```

**绝不假报成功**。旧版曾因 `git commit ... 2>/dev/null` 吞掉署名缺失的
错误，还打印「✅ 推送成功」——代码根本没进任何提交。

### 交互

- 非 TTY（`[ ! -t 0 ]`）时必须退化为非交互行为，不能 `read` 死等
- 会改数据、会覆盖、会推送的操作，先确认
- 危险操作（`no` / `undo` / 强推）必须二次确认

---

## 四、改动流程

```
1. 改之前：跑一遍 bash fz-tools/smoke-test.sh，确认基线是绿的
2. 改的时候：只动必要的函数，不顺手重构、不统一风格
3. 改之后：再跑一遍，必须仍然全绿
4. 涉及新行为：在 smoke-test.sh 加用例锁住它
```

### 本地自检（提交前必跑）

```bash
# 1. 静态检查（门槛 warning，产品代码必须零告警）
shellcheck -S warning fz-tools/*.sh fz-tools/modules/*.sh get.sh version.sh

# 2. 语法
for f in fz-tools/*.sh fz-tools/modules/*.sh get.sh version.sh; do bash -n "$f"; done

# 3. 冒烟（63 项，$TMPDIR 隔离，零网络）
bash fz-tools/smoke-test.sh
```

CI 会做同样的事，外加 bash 3.2 兼容性与凭据扫描。**不要在 CI 之外合并**。

### 测试约定

`smoke-test.sh` 是唯一的自动化防线。它保证：

- `$TMPDIR` 隔离 `HOME`、`GIT_CONFIG_GLOBAL`
- 本地 bare 仓库模拟远端，零网络依赖
- 交互全部管道喂入，可无人值守

**新增用例必须遵守隔离**：别不小心探测到真实的 `/storage` 或
真实 `~/.fz_bookmarks`。

保护性用例（`T12*` 凭据隔离、`T13*` 安装器）**不得删除**。CI 会检查
这些用例仍然存在——删掉它们来「让 CI 变绿」会被直接拦下。

### 版本号

```bash
bash version.sh bump        # 次版本 +1
bash version.sh bump major  # 主版本 +1
```

日常改动不用碰版本号。

---

## 五、当前已知遗留（改到了顺手处理，没改到不必专门开刀）

| 位置 | 问题 | 处理建议 |
|---|---|---|
| `modules/nav.sh` `_fz_picker` | 180 行手写 TUI（CJK 宽度、ESC 分片、原位重绘） | 可 `command -v fzf` 时优先用 fzf，手写实现作兜底 |
| `nav.sh` `FZ_PICK_*` | 用全局变量当函数返回值 | 量很大，改动需谨慎；新代码别学 |
| `alias login` | 覆盖系统 `login(1)` | 建议改名 `ghlogin`，但会破坏现有用户习惯 |
| `README.md` | 混入了 v5.x changelog | 该拆到 `CHANGELOG.md` |
| `docs/文档.md` | 内容是一段 shell 脚本，非文档 | 未提交；建议删除或用例化进 `reasonix.sh` |
| `smoke-test.sh:10` | 注释引用了不存在的 `plan.md` | 顺手删 |

---

## 六、提交前自检

- [ ] `shellcheck -S warning` 产品代码零告警
- [ ] `bash -n` 所有改动的文件通过
- [ ] `bash fz-tools/smoke-test.sh` 全绿（含 T12 安全 / T13 安装器）
- [ ] 没有硬编码个人路径
- [ ] 没有把凭据写进任何被追踪的文件
- [ ] 加载阶段没有新增副作用
- [ ] 新增变量是 `local`，除非它确实需要跨函数
- [ ] 注释解释「为什么」，不是「改过什么」
- [ ] 失败路径没有被 `2>/dev/null` 吞掉
- [ ] 新增行为有对应的冒烟用例
