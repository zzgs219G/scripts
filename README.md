# scripts

个人脚本仓库。《焚诀·Git 工作流》v5.2（防冲突推送·方向键导航·多平台远程）。

> v5.0 核心变化：消灭所有硬编码路径，以「书签」为核心，
> `c` 命令升级为 书签→项目→操作 三阶段交互导航，
> 支持项目在书签之间自由移动/复制并自动修复 Git 安全权限。
>
> v5.1 核心变化（体验增强 + P0 修复）：
> `pull` 升级为智能拉取（上游跟踪检查 / 脏工作区确认 / 显示新增提交），
> `c` 进入项目与 `b` 切换分支后自动显示状态摘要，
> `st` 增加领先/落后同步状态，`ok` 发布增加工作区检查与分步执行，
> 推送版本号按主版本正确递增（修复 v5.0 写死次版本的降级 bug）。
>
> v5.2 核心变化（防冲突 + 交互升级 + 多平台）：
> `p` 推送前 fetch 只读检测（**不触碰本地任何代码**），落后时列出远程
> 新提交与涉及文件 + 本地未提交改动数，三选项由用户决定
> （拉取合并 / `--force-with-lease` 安全强推带二次确认 / 取消）；
> `c` 导航全面接入方向键指示器（↑/↓ 移动 · 回车确认 · 数字直选 ·
> 管道环境自动退化为数字输入）；`remote` 支持多平台
> （GitHub / GitLab / Gitee / 腾讯云 CNB / CODING / 自定义），
> 选平台填用户名仓库名自动拼 URL 并附令牌获取提示。

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
├── docs/
│   └── 新手指南.md         # 🆕 面向不会 Git 的用户（场景问答/平台指南/电脑使用）
├── .gitignore
└── fz-tools/              # 《焚诀》工具包（v5.0 起）
    ├── fzgit.sh           # 主入口：环境变量 / 加载器 / 别名 / 帮助菜单
    ├── core.sh            # 内部工具（校验 / 转义 / .gitignore）
    ├── install.sh         # 安装 / 迁移脚本（旧版用户必看）
    ├── smoke-test.sh      # 冒烟测试（$TMPDIR 隔离环境，零网络依赖）
    └── modules/           # 功能模块，主入口自动加载
        ├── env.sh         # 环境配置 / 多平台远程管理 / GitHub 登录 / 信任 / AI Key / 自更新
        ├── bookmark.sh    # 🆕 书签管理（增删改查 / 首次引导 / FZ_BASE 迁移）
        ├── nav.sh         # 🆕 c 命令三阶段交互导航 / 项目总览 / 移动复制
        ├── clone.sh       # 🆕 交互式克隆（gh 仓库列表选择 / 自动书签注册）
        ├── pullall.sh     # 🆕 批量拉取（基于书签，支持指定书签）
        ├── branch.sh      # 分支管理 / 重命名 / 清理 / 同步 / 回主线
        ├── push.sh        # 智能推送（含 AI 生成 commit message）
        ├── merge.sh       # 合并发布 / 撤回最后一次提交
        ├── view.sh        # 日志 / 差异 / 仓库信息 / 远程文件列表
        ├── stash.sh       # 暂存与恢复
        ├── fix.sh         # 冲突解决引导
        ├── tag.sh         # 版本标签管理
        └── burn.sh        # 炼化源码（输出到项目上一级目录 / 第一个书签）
```

## 书签系统（v5.0 核心）

书签 = 一个顶层目录，目录下的每个子文件夹会被当作一个项目。
存储文件：`~/.fz_bookmarks`（每行 `名称|绝对路径`）。

- 首次执行 `c` / `setup` 时会自动引导创建第一个书签
- 旧版用户首次使用会自动把 `FZ_BASE` 导入为默认书签「工作台」
- `bookmark` 命令打开交互式管理菜单（增删改查）

## 安装（新用户）


```bash
# 1. 安装依赖
pkg install git curl gh

# 2. 克隆到 HOME
cd ~
git clone https://github.com/zzgs219G/scripts.git

# 3. 写入 ~/.bashrc（幂等，重复执行不会堆叠）
sed -i '/fz-tools\/fzgit.sh/d' ~/.bashrc
echo 'source "$HOME/scripts/fz-tools/fzgit.sh"' >> ~/.bashrc
source ~/.bashrc

# 4. 初始化
setup    # 检查环境 + 配置 Git 全局信息 + 创建书签
login    # 登录 GitHub（可选）
aikey    # 配置 AI commit Key（可选，自动生成提交信息）
```

## 迁移（旧版 curl 注入用户）

旧版把整段代码注入 `~/.bashrc`，v4.0 改为直接 source 主入口。
执行一次即可自动完成迁移：

```bash
git clone https://github.com/zzgs219G/scripts.git
cd scripts
bash fz-tools/install.sh
```

install.sh 会自动：备份 `~/.bashrc`、删除旧注入块、迁移已配置的
AI Key 到新主入口、写入新的 source 行。

## v4.0 → v5.0 平滑升级（旧用户迁移指南）

v5.0 用「书签」取代了硬编码的 `FZ_BASE` 工作台。升级**零成本**：

1. 更新代码：`cd <scripts仓库> && git pull`（或重跑 `install.sh`）
2. 首次执行 `c` 或 `setup` 时，检测到 `~/.fz_bookmarks` 为空
   且旧 `FZ_BASE` 存在，会自动将其导入为默认书签「工作台」
   （名称可自定义，回车即用默认）
3. 旧 `FZ_BASE` 环境变量保留，仅用于 `f` 炼化输出备用，
   不再影响导航 / 克隆 / 批量拉取
4. 之后可用 `bookmark` 命令自由增删改查书签

> 想手动迁移？一行即可：`bookmark` → 添加书签 → 名称「工作台」→ 路径填旧工作台路径。

## 依赖

- **git** — 核心
- **curl** — AI commit 请求
- **gh**（GitHub CLI）— login / repo / rls / 交互式克隆列表功能
- **python3**（可选）— AI 响应解析更稳定
- **Anthropic API Key**（可选）— `aikey` 配置后，`p` 推送自动生成 commit message

## 指令总览（按模块）

**环境（env.sh）**
- `up` 检查更新（v4.0 起基于 git pull 更新整个仓库）
- `setup` 检查环境 + 配置 Git 全局信息 + 创建书签
- `login` 登录 GitHub（浏览器 / Token）
- `repo` 创建远程仓库
- `remote` 管理远程地址（增删改查）
- `trust` 信任当前目录（safe.directory）
- `aikey` 配置 AI commit Key（Anthropic）

**书签（bookmark.sh）🆕**
- `bookmark` 打开书签管理菜单（增删改查）
- 书签文件 `~/.fz_bookmarks`，每行 `名称|绝对路径`
- 失效书签在列表中标记 `[失效]`，选择后提示移除

**项目导航（nav.sh）🆕**
- `c` 三阶段交互导航：书签选择 → 项目列表 → 项目操作
  - v5.2 全面接入方向键指示器：↑/↓（或 j/k）移动高亮、回车确认、
    数字 1-9 直接跳选，q/b/0 快捷键保留；管道/脚本环境自动退化为
    数字输入模式（自动化测试兼容）
  - 项目列表按 `[0]` 或 `q` 直接进入书签根目录
  - 项目操作支持：进入 / 📦移动 / 📋复制到其他书签
  - 移动/复制自动处理冲突（覆盖 / 重命名_副本 / 取消）
  - 移动后自动添加 `safe.directory`
  - v5.1 进入项目后自动显示分支/变更/领先落后摘要
- `c <名字>` 书签直达项目列表 / 项目关键字模糊直达
- `lsp` 所有书签项目状态总览
- `st` 当前分支 + 变更数 + 所在书签名称 + 领先/落后同步状态（v5.1）

**克隆（clone.sh）🆕**
- `cl` 交互式克隆：`gh repo list` 列出仓库 → 选择 → 选目标目录
  （当前目录 / 书签目录）→ 自动注册书签 → 询问是否进入
- `cl <仓库名或URL>` 直接克隆到当前目录，自动识别/注册书签
- `cl <仓库名或URL> <书签名>` 直接克隆到指定书签目录

**批量拉取（pullall.sh）🆕**
- `pullall` 遍历所有书签下含 `.git` 的一级子目录批量 `git pull`
- `pullall <书签名>` 只更新指定书签下的项目
- 执行前确认列表，统计成功/失败，最后显示失败项目列表

**分支操作（branch.sh）**
- `b` 列出分支 → 选编号切换；`b <名字>` 直接切换/创建
  （v5.1 切换分支后自动显示状态摘要）
- `b all` 打捞全部远程分支并本地镜像；`b -l` 显示所有分支
- `b ql` 清理分支缓存；`b -d <名>` 删本地；`b -dr <名>` 删远程
- `rn` 重命名当前分支（本地 + 远程同步）
- `bclean` 清理已合并的本地分支
- `gsync` 安全同步远程（fetch + rebase，冲突自动回退 merge）
- `gomain` 回到 main/master
- v5.0 增加当前书签/路径提示

**推送与发布（push.sh / merge.sh）**
- `p` 推送；v5.0 增加前置检查（不在书签项目内时询问是否继续）、
  推送成功显示远程地址；v5.1 无备注时提供默认备注确认；
  v5.2 推送前 fetch 只读检测：落后远程时列出远程新提交、涉及文件、
  本地未提交改动数，三选项由用户决定（拉取合并 / --force-with-lease
  安全强推带二次确认 / 取消），推送被拒时给出 pull/st 引导
- `p skip` 跳过 CI 构建，`p "备注"` 指定备注
- `remote` 远程仓库管理；v5.2 支持多平台模板
  （GitHub / GitLab / Gitee / 腾讯云 CNB / CODING / 自定义），
  选平台→填用户名/仓库名自动拼 URL，附各平台令牌获取提示
- `ok` 合并 dev→main 发布（合并前确认待提交列表）；
  v5.1 发布前检查工作区、分步执行 checkout→merge→push；
  `ok dev main skip` 跳过 CI
- `no` 撤回最后一次发布 ⚠️ 危险

**查看与对比（view.sh）**
- `st` 当前分支 + 变更文件数 + 书签名称 + 领先/落后同步状态（v5.1）
- `info` 仓库完整信息（含领先 / 落后）
- `rls 用户/仓库` 查看远程仓库文件列表
- `lg` 提交历史图（默认 15 条）；`lg 30` 指定条数
- `d` 未暂存变更；`d s` 已暂存变更

**实用工具（stash.sh / fix.sh / tag.sh / burn.sh）**
- `save` 暂存工作区；`pop` 恢复暂存
- `fix` 冲突解决引导
- `tag` 查看标签；`tag v1.0` 发布；`tag -d v1.0` 删除
- `f` 全量打包源码（过滤矢量图/密钥/缓存/锁文件/资源目录下 json-xml；kotlin 注释+import 自动过滤并附去重依赖清单；大文件完整打包并标注路径与大小）
- `f <模块>` 只打包指定模块
- `f -d` 只打包未提交的改动 + 新文件
- `undo` 撤销工作区所有修改 ⚠️；`unstage` 取消所有暂存
- `pull` 智能拉取（v5.1：显示分支 / 检查上游跟踪 / 脏工作区确认 / 显示新增提交）
- `h` 显示帮助菜单

## 更新机制

`up` 不再下载单文件，而是基于 git 拉取整个仓库：

1. 定位 scripts 仓库根目录（`git rev-parse --show-toplevel`），
   非 git clone 安装的无法更新
2. `git fetch --tags` 拉取远程，并从远程默认分支的
   `fz-tools/fzgit.sh` 读取 `FZ_VERSION` 与本地比较
   （版本比较支持 `v1.2.3` / `4.0` 格式）
3. 检测到新版本后询问确认，确认则 `git pull` 更新整个仓库
4. 更新后自动重新加载 `~/.bashrc`（若提示无变化，手动执行 `source ~/.bashrc`）

> **版本号说明**：推送 scripts 仓库时，`FZ_VERSION` 由「焚诀算法阵」
> 按当前主版本自动递增（如 v5.x → v5.x+1）。v5.1 修复了旧版
> 写死次版本导致版本号降级的 bug，因此 `p` 后版本号变化属正常行为，
> 执行 `up` 即可同步本地。

## v5.1 → v5.2 平滑升级

v5.2 不改变书签数据结构（`~/.fz_bookmarks`）与任何指令名，升级零成本：

1. 更新代码：`up`（或 `cd <scripts仓库> && git pull`）
2. 重新加载：`source ~/.bashrc`
3. 升级后新增 / 增强的行为：
   - `p` 推送防冲突：推送前 fetch 只读检测，落后时三选项（拉取/安全强推/取消），
     机器绝不擅自合并或覆盖，所有动代码的操作都由用户确认
   - `c` 导航方向键化：↑/↓ + 回车选择，数字直选保留，脚本/管道自动退化
   - `remote` 多平台：GitHub / GitLab / Gitee / 腾讯云 CNB / CODING 模板拼 URL
   - 电脑端支持：FZ_BASE 跨平台化，非 Termux 环境自动回退 `~/repos`
   - 新增 [docs/新手指南.md](docs/新手指南.md)：面向不会 Git 的用户

## v5.0 → v5.1 平滑升级

v5.1 不改变书签数据结构（`~/.fz_bookmarks`）与任何指令名，升级零成本：

1. 更新代码：`up`（或 `cd <scripts仓库> && git pull`）
2. 重新加载：`source ~/.bashrc`
3. 升级后新增 / 增强的行为：
   - `pull` 智能拉取：显示分支、检查上游跟踪、脏工作区确认、显示新增提交
   - `c` 进入项目 / `b` 切换分支后自动显示状态摘要
   - `st` 增加领先/落后同步状态（🔵分叉 / 🟡领先 / 🔴落后）
   - `ok` 发布前检查工作区，分步执行 checkout→merge→push（失败不再误报成功）
   - `p` 无备注时提供默认备注确认（不再直接提交 "⚡ update"）

## 常见问题

- **提示"缺少模块文件"**：确认 `~/.bashrc` 中 source 的是
  `fz-tools/fzgit.sh`，而不是旧的单文件。
- **`up` 拉取失败**：检查本地 scripts 仓库是否有未提交的改动
  （有改动时 git pull 会拒绝，先提交或 stash）。
- **旧版 `up` 报"获取远程版本失败"**：旧单文件已下线，请执行
  `bash fz-tools/install.sh` 迁移到新结构。
- **`p` 推送 scripts 仓库后版本号变了**：这是焚诀算法阵的正常行为，
  版本号按当前主版本 + 提交数自增（v5.1 起修复了写死次版本的降级 bug）。

## 回滚

- 本地备份：仓库根目录的 `fzgit.orig.sh`（已被 .gitignore 忽略）
- 或从 git 历史恢复旧单文件：

```bash
git show <旧提交>:fzgit.sh > fzgit.sh
```

然后删除 `fz-tools/`，并把 `~/.bashrc` 中的 source 行换回旧文件即可。
