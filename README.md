# scripts

个人脚本仓库。《焚诀·Git 工作流》—— 面向个人多项目场景的 Git 工作流工具。

核心是**书签 + `c` 跳转**：把常用目录登记为书签，`c` 三阶段导航
（书签 → 项目 → 操作），方向键选择，直接 `cd` 进去。

```bash
c          # 书签 → 项目 → 进入（最常用）
st         # 当前分支 + 变更清单 + 领先/落后
p          # 智能推送（防冲突检测）
```

> 版本变更记录见 [CHANGELOG.md](CHANGELOG.md)。本文件只讲怎么用。

## 推荐环境

推荐使用 **ZeroTermux** 以获得最佳体验（在 Termux 环境下测试通过）。
开源地址：[https://github.com/hanxinhao000/ZeroTermux](https://github.com/hanxinhao000/ZeroTermux)

> **电脑也能用**：Windows（Git Bash / WSL）、macOS、Linux 均可运行，
> FZ_BASE 已跨平台化（无手机存储时自动回退 `~/repos`）。
> 详见 [docs/新手指南.md](docs/新手指南.md) Q4。

## 目录结构

```
scripts/
├── README.md
├── CHANGELOG.md           版本变更记录
├── AGENTS.md              改动本仓库前的必读契约（AI/协作规范）
├── get.sh                 一行安装 / 卸载入口
├── version.sh             版本号管理（发版时显式递增）
├── .shellcheckrc          shellcheck 基线配置
├── .github/workflows/ci.yml  CI：lint / 语法 / bash3.2 / 冒烟 / 凭据扫描
├── docs/
│   ├── 流程文档.md         # 完整流程：安装→日常→推送→炼化→异常恢复
│   └── 新手指南.md         # 面向不会 Git 的用户（场景问答/平台指南/电脑使用）
├── .gitignore
└── fz-tools/              # 《焚诀》工具包
    ├── fzgit.sh           # 主入口：环境变量 / 加载器 / 别名 / 帮助菜单
    ├── core.sh            # 内部工具（校验 / 状态摘要 / 凭据护栏 / 转义）
    ├── install.sh         # 安装 / 迁移脚本（旧版用户必看）
    ├── smoke-test.sh      # 冒烟测试（63 项，$TMPDIR 隔离，零网络依赖）
    └── modules/           # 功能模块，主入口自动加载
        ├── env.sh         # 环境配置 / 多平台远程 / GitHub 登录 / 信任 / AI Key / 自更新
        ├── bookmark.sh    # 书签管理（增删改查 / 首次引导 / FZ_BASE 迁移）
        ├── nav.sh         # c 命令三阶段交互导航 / 项目总览 / 移动复制
        ├── clone.sh       # 交互式克隆（gh 仓库列表选择 / 自动书签注册）
        ├── pullall.sh     # 批量拉取（基于书签，支持指定书签）
        ├── branch.sh      # 分支管理 / 重命名 / 清理 / 同步 / 回主线
        ├── push.sh        # 智能推送（含 AI 生成 commit message）
        ├── merge.sh       # 合并发布 / 撤回最后一次提交
        ├── view.sh        # 日志 / 差异 / 仓库信息 / 远程文件列表
        ├── stash.sh       # 暂存与恢复
        ├── fix.sh         # 冲突解决引导
        ├── tag.sh         # 版本标签管理
        ├── reasonix.sh    # 一键安装/升级 Reasonix CLI（Termux 编译安装）
        ├── ai.sh          # AI 备注（可选，OpenAI 兼容接口）
        └── burn.sh        # 炼化源码（输出到项目上一级目录 / 第一个书签）
```

## 书签系统

书签 = 一个顶层目录，目录下的每个子文件夹会被当作一个项目。
存储文件：`~/.fz_bookmarks`（每行 `名称|绝对路径`）。

- 首次执行 `c` / `setup` 时会自动引导创建第一个书签
- 显式设置过 `FZ_BASE` 的旧用户，首次使用会把它导入为默认书签「工作台」
- `bookmark` 命令打开交互式管理菜单（增删改查）

## Termux 初始化（首次打开 Termux 必做）

> **仅限 Termux 环境**。电脑端（Git Bash / WSL / macOS / Linux）请直接跳到下一节「安装（新用户）」。

首次安装 Termux 后，建议先执行以下两步，避免后续安装依赖、访问存储出现权限或源损坏问题：

```bash
# 1. 更新软件源与系统包（防止旧源导致 pkg install 失败/装到旧版本）
apt update && apt full-upgrade -y

# 2. 授予 Termux 访问手机共享存储权限（~/storage 目录生成，克隆/读写项目必需）
termux-setup-storage
```

> 💡 `termux-setup-storage` 执行后会弹出系统授权弹窗，**请点击「允许」**。若误关，可重新执行该命令或在系统设置 → 应用 → Termux → 权限 → 存储 中手动开启。

---

## 安装（新用户）

**一行安装（推荐）**：

```bash
pkg install git                      # Termux 先装 git
curl -fsSL https://raw.githubusercontent.com/zzgs219G/scripts/main/get.sh | bash
```

安装器会：克隆到 `~/.local/share/fz` → 幂等写入 `~/.bashrc` →
自动跑一次 `setup`。重新打开终端即可用。

卸载：

```bash
curl -fsSL https://raw.githubusercontent.com/zzgs219G/scripts/main/get.sh \
  | bash -s -- --uninstall --yes
```

> 卸载会保留你的 `~/.fz_bookmarks`（书签）与 `~/.fz_ai_key`（Key）。

**手动安装（想自己控制位置时）**：

```bash
pkg install git curl gh              # 核心依赖
git clone https://github.com/zzgs219G/scripts.git
cd scripts && bash fz-tools/install.sh
setup    # 检查环境 + 配置 Git 全局信息 + 创建书签
```

### 为什么必须下载到本地（不能像 apk 那样“装个包”）

因为 `c` 需要**改变当前 shell 的工作目录**，而 POSIX 规定任何子进程
都无法改变父进程的 cwd。所以本工具只能是「被 `source` 的函数库」，
必然需要本地文件副本 —— 与 `nvm` / `asdf` / `oh-my-zsh` 的形态一致。

shell 脚本没有「编译成二进制」这一步：运行时就是你的 bash，源码即产物
（`npm install -g` 装的也是源码）。差别不在编译，而在**有没有固定的
安装位置和安装器** —— 这正是 `get.sh` 解决的问题。

## 迁移（旧版 curl 注入用户）

旧版把整段代码注入 `~/.bashrc`，现在改为直接 source 主入口。
执行一次即可自动完成迁移：

```bash
git clone https://github.com/zzgs219G/scripts.git
cd scripts
bash fz-tools/install.sh
```

install.sh 会自动：备份 `~/.bashrc`、删除旧注入块、把已配置的
AI Key 迁移到 `~/.fz_ai_key`（权限 600）、写入新的 source 行。
若发现历史版本曾把 Key 写进仓库文件，会自动清空并提示轮换。

## 依赖

- **git** — 核心
- **curl** — 仅 AI 备注功能需要
- **gh**（GitHub CLI）— login / repo / rls / 交互式克隆列表功能
- **python3** 或 **jq**（可选）— AI 响应解析更稳定

### AI 生成 commit 备注（可选，默认关闭）

**不配置就完全不会联网、不会产生费用。** `p` 默认问你要备注，
回车使用 `⚡ update: 日期时间`。

配置后 `p` 会自动生成备注，配置存放在 `~/.fz_ai.conf`（权限 600，
不在仓库内）：

```bash
aikey      # 交互式配置：Base URL / 模型名 / Key
aikeyoff   # 关闭并删除配置
```

支持**任何 OpenAI 兼容端点**（`/v1/chat/completions`），内置提示包括：

| 服务 | Base URL | 费用 |
|---|---|---|
| NVIDIA NIM | `https://integrate.api.nvidia.com/v1` | 免费（约 40 请求/分），需 build.nvidia.com 注册 |
| DeepSeek | `https://api.deepseek.com/v1` | 按量付费，单价很低 |
| Ollama（本机） | `http://localhost:11434/v1` | 完全免费、数据不外发 |

> ⚠️ **数据流向**：启用后会把 `git diff` 的统计与**前 200 行差异**
> 发送到你配置的服务。NVIDIA 免费层明确声明会记录输入输出用于
> 改进模型；Anthropic/DeepSeek 的付费接口默认不用于训练。
> 介意的话用 Ollama 本地跑，或干脆不配置。

> 早期版本只支持 Anthropic 的私有协议，现已改为通用 OpenAI 兼容接口。
> 若你配过旧的 `~/.fz_ai_key`，它不会被自动沿用（协议不同），
> 执行一次 `aikey` 重新配置即可；`aikeyoff` 会一并清理旧文件。

## 指令总览（按模块）

> 💡 **日常其实只用这四个**：`c`（进目录）、`st`（看状态）、`p`（推送）、`h`（帮助）。
> 其余是特定场景才用的，忘了就敲 `h all` 查。

**环境（env.sh）**
- `init` 在空文件夹里初始化 git 仓库（自动建 `main` 分支 + 初始提交），
  并引导你绑定远程、首次推送
- `up` 检查更新（基于 git pull 更新整个仓库）
- `setup` 检查环境 + 配置 Git 全局信息 + 创建书签
- `ghlogin` 登录 GitHub（浏览器 / Token）；`login` 为兼容别名
- `repo` 创建远程仓库
- `remote` 管理远程地址（增删改查）
- `trust` 信任当前目录（safe.directory）
- `aikey` 配置 AI 备注（任何 OpenAI 兼容端点，可选）
- `aikeyoff` 关闭 AI 备注并删除配置

**书签（bookmark.sh）**
- `bookmark` 打开书签管理菜单（增删改查）
- 书签文件 `~/.fz_bookmarks`，每行 `名称|绝对路径`
- 失效书签在列表中标记 `[失效]`，选择后提示移除

**项目导航（nav.sh）**
- `c` 三阶段交互导航：书签选择 → 项目列表 → 项目操作
  - 方向键 ↑/↓（或 j/k）移动高亮 · 回车确认 · 数字直选 · q/b/0 快捷键
  - 数字先入缓冲区，底部显示 `编号: 11▌`，回车提交 / 退格修正 / ESC 放弃；
    项目数 ≤ 9 时输 `1` 立即生效，≥ 10 时等续输（支持多位数编号）
  - 管道/脚本环境自动退化为数字输入模式（自动化测试兼容）
  - `[0]` 或 `q` 直接进入书签根目录
  - 项目操作：进入 / 📦移动 / 📋复制到其他书签
  - 移动/复制自动处理冲突（覆盖 / 重命名_副本 / 取消）
  - 移动后自动添加 `safe.directory`
  - 进入项目后自动显示分支/变更/领先落后摘要
- `c <名字>` 书签直达项目列表 / 项目关键字模糊直达
- `lsp` 所有书签项目状态总览
- `st` 当前分支 + 变更文件清单（按新增/修改/删除/未跟踪分组）
  + 书签名称 + 领先/落后 + 远程地址 + 提交数/追踪数/标签数

**克隆（clone.sh）**
- `cl` 交互式克隆：`gh repo list` 列出仓库 → 选择 → 选目标目录
  （当前目录 / 书签目录）→ 自动注册书签 → 询问是否进入
- `cl <仓库名或URL>` 直接克隆到当前目录，自动识别/注册书签
- `cl <仓库名或URL> <书签名>` 直接克隆到指定书签目录

**批量拉取（pullall.sh）**
- `pullall` 遍历所有书签下含 `.git` 的一级子目录批量 `git pull`
- `pullall <书签名>` 只更新指定书签下的项目
- 执行前确认列表，统计成功/失败，最后显示失败项目列表

**分支操作（branch.sh）**
- `b` 列出分支 → 选编号切换；`b <名字>` 直接切换/创建
- `b all` 打捞全部远程分支并本地镜像；`b -l` 显示所有分支
- `b ql` 清理分支缓存；`b -d <名>` 删本地；`b -dr <名>` 删远程
- `rn` 重命名当前分支（本地 + 远程同步）
- `bclean` 清理已合并的本地分支
- `gsync` 安全同步远程（fetch + rebase，冲突自动回退 merge）
- `gomain` 回到 main/master

**推送与发布（push.sh / merge.sh）**
- `p` 智能推送：
  - 前置检查（作者身份 / 是否在书签项目内），推送成功显示远程地址
  - 推送前 fetch 只读检测，落后远程时列出远程新提交与涉及文件，
    三选项由用户决定（拉取合并 / `--force-with-lease` 安全强推 / 取消）
  - 「是否需要推送」以**本次目标远程**为基准，多远程项目下不会误判
  - 被拒时先确认网络可达，再给出 pull/st/fix 引导
  - 提交失败会保留 git 的真实报错，不假报成功
- `p skip` 跳过 CI 构建；`p "备注"` 指定备注
- `p cnb skip` / `p skip "备注"` / `p -r cnb -m "备注"` 可自由组合
- 推完目标远程后，其他仍落后的远程只**提示**不自动推
  （`📡 远程 [cnb] 还落后 N 个提交，如需同步: p cnb`）
- `remote` 多平台模板（GitHub / GitLab / Gitee / 腾讯云 CNB / CODING / 自定义），
  选平台→填用户名/仓库名自动拼 URL，附各平台令牌获取提示
- `ok` 合并 dev→main 发布（合并前确认待提交列表；发布前检查工作区、
  分步执行 checkout→merge→push）；`ok dev main skip` 跳过 CI
- `no` 撤回最后一次发布 ⚠️ 危险

**查看与对比（view.sh）**
- `st` 同导航模块（当前分支 + 变更文件清单 + 书签 + 同步状态 + 仓库核心信息）
- `info` 仓库完整信息（含贡献者）
- `rls 用户/仓库` 查看远程仓库文件列表（如 `rls zzgs219G/scripts`，需要 gh 已登录）
- `lg` 提交历史图（默认 15 条）；`lg 30` 指定条数
- `d` 未暂存变更；`d s` 已暂存变更
- `h` 常用指令菜单；`h all` 全部指令（含低频指令）

**实用工具（stash.sh / fix.sh / tag.sh / burn.sh）**
- `save` 暂存工作区（含未跟踪的新文件）；`pop` 恢复最近的暂存
- `fix` 冲突解决引导
- `tag` 查看标签；`tag v1.0` 发布；`tag -d v1.0` 删除
- `f` 全量打包源码（过滤矢量图/密钥/缓存/锁文件/资源目录下 json-xml；
  kotlin 注释+import 自动过滤并附去重依赖清单；大文件完整打包并标注路径与大小）
- `f <模块>` 只打包指定模块
- `f -d` 只打包未提交的改动 + 新文件
- `undo` 撤销工作区所有修改 ⚠️；`unstage` 取消所有暂存
- `pull` 智能拉取（显示分支 / 检查上游跟踪 / 脏工作区确认 / 显示新增提交）

**应用安装（reasonix.sh）**
- `rsx` 一键安装 / 升级 Reasonix CLI（Termux 下自动装 golang/git/make）
- 流程：克隆或复用 `~/DeepSeek-Reasonix`（`studio` 分支）→ `make build`
  → 复制到 `$PREFIX/bin`（非 Termux 回退 `~/.local/bin`）
  → 把 `~/.reasonix/config.toml` 的 `bash = "enforce"` 改为 `"off"`（不关闭则无权限）
- 可覆盖变量：`RSX_REPO_URL` / `RSX_SRC_DIR` / `RSX_BRANCH`

## 质量保障

本仓库有一道自动化防线，提交前建议本地跑一遍：

```bash
shellcheck -S warning fz-tools/*.sh fz-tools/modules/*.sh get.sh version.sh
bash fz-tools/smoke-test.sh        # 63 项，零网络依赖
```

CI（`.github/workflows/ci.yml`）在每次 push / PR 时执行 6 个 job：

| job | 内容 |
|---|---|
| `lint` | shellcheck（Ubuntu + macOS，门槛 warning） |
| `syntax` | `bash -n` 全量语法检查 |
| `compat` | 用 macOS 自带 bash 3.2 验证兼容性 |
| `smoke` | 63 项冒烟测试 + 校验安全用例未被删除 |
| `no-secrets` | 扫描工作区凭据；全历史仅告警 |
| `version` | 版本号格式合法 + `p` 未复活自动改版本号 |

## 更新机制

`up` 基于 git 拉取整个仓库（不再下载单文件）：

1. 定位 scripts 仓库根目录（`git rev-parse --show-toplevel`），
   非 git clone 安装的无法更新
2. `git fetch --tags` 拉取远程，并从远程默认分支的
   `fz-tools/fzgit.sh` 读取 `FZ_VERSION` 与本地比较
   （版本比较支持 `v1.2.3` / `4.0` 格式）
3. 检测到新版本后询问确认，确认则 `git pull` 更新整个仓库
4. 更新后自动重新加载 `~/.bashrc`（若提示无变化，手动执行 `source ~/.bashrc`）

> **版本号说明**：版本号不再随推送自动递增。
> 旧实现在每次 `p` 时用 commit 数量覆盖 `FZ_VERSION`，导致每次推送
> 都必然产生一个「版本号变动」提交、版本号与内容脱钩、且多分支并行时
> 是固定冲突源。现在改为发版时显式递增：
>
> ```bash
> bash version.sh            # 查看当前版本
> bash version.sh bump       # 次版本 +1（5.109 → 5.110）
> bash version.sh bump major # 主版本 +1（5.109 → 6.0）
> bash version.sh set 5.120  # 指定版本
> ```

## 常见问题

- **提示"缺少模块文件"**：确认 `~/.bashrc` 中 source 的是
  `fz-tools/fzgit.sh`，而不是旧的单文件。
- **`up` 拉取失败**：检查本地 scripts 仓库是否有未提交的改动
  （有改动时 git pull 会拒绝，先提交或 stash）。
- **旧版 `up` 报"获取远程版本失败"**：旧单文件已下线，请执行
  `bash fz-tools/install.sh` 迁移到新结构。
- **`p` 推送后版本号还会变吗**：不会。版本号只在显式执行
  `bash version.sh bump` 时变化，`p` 不再改写它（旧版每次推送都会改）。

## 回滚

- 本地备份：仓库根目录的 `fzgit.orig.sh`（已被 .gitignore 忽略）
- 或从 git 历史恢复旧单文件：

```bash
git show <旧提交>:fzgit.sh > fzgit.sh
```

然后删除 `fz-tools/`，并把 `~/.bashrc` 中的 source 行换回旧文件即可。
