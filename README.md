# scripts

个人脚本仓库。《焚诀·Git 工作流》v4.0（模块化重构版）。

## 推荐环境

推荐使用 **ZeroTermux** 以获得最佳体验（在 Termux 环境下测试通过）。
开源地址：[https://github.com/hanxinhao000/ZeroTermux](https://github.com/hanxinhao000/ZeroTermux)

## 目录结构

```
scripts/
├── README.md
├── .gitignore
└── fz-tools/              # 《焚诀》工具包（v4.0 起）
    ├── fzgit.sh           # 主入口：环境变量 / 加载器 / 别名 / 帮助菜单
    ├── core.sh            # 内部工具（校验 / 转义 / .gitignore）
    ├── install.sh         # 安装 / 迁移脚本（旧版用户必看）
    └── modules/           # 功能模块，主入口自动加载
        ├── env.sh         # 环境配置 / GitHub 登录与远程 / 信任 / AI Key / 自更新
        ├── nav.sh         # 工作台导航 / 克隆 / 批量拉取
        ├── branch.sh      # 分支管理 / 重命名 / 清理 / 同步 / 回主线
        ├── push.sh        # 智能推送（含 AI 生成 commit message）
        ├── merge.sh       # 合并发布 / 撤回最后一次提交
        ├── view.sh        # 日志 / 差异 / 仓库信息 / 远程文件列表
        ├── stash.sh       # 暂存与恢复
        ├── fix.sh         # 冲突解决引导
        ├── tag.sh         # 版本标签管理
        └── burn.sh        # 炼化源码（打包为单文本喂给 AI）
```

## 安装（新用户）

```bash
# 1. 克隆仓库
git clone https://github.com/zzgs219G/scripts.git

# 2. 写入 ~/.bashrc（路径按实际克隆位置调整）
echo 'source /存储路径/scripts/fz-tools/fzgit.sh' >> ~/.bashrc
source ~/.bashrc

# 3. 初始化
setup    # 检查环境 + 配置 Git 全局信息
login    # 登录 GitHub（可选）
aikey    # 配置 AI commit Key（可选）
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

## 依赖

- **git** — 核心
- **curl** — AI commit 请求
- **gh**（GitHub CLI）— login / repo / rls 功能
- **python3**（可选）— AI 响应解析更稳定
- **Anthropic API Key**（可选）— `aikey` 配置后，`p` 推送自动生成 commit message

## 指令总览（按模块）

**环境（env.sh）**
- `up` 检查更新（v4.0 起基于 git pull 更新整个仓库）
- `setup` 检查环境 + 配置 Git 全局信息
- `login` 登录 GitHub（浏览器 / Token）
- `repo` 创建远程仓库
- `remote` 管理远程地址（增删改查）
- `trust` 信任当前目录（safe.directory）
- `aikey` 配置 AI commit Key（Anthropic）

**项目导航（nav.sh）**
- `lsp` 工作台所有项目状态总览
- `c` 列表选择 / 编号瞬移；`c <名字>` 关键字模糊直达
- `cl <url>` 克隆（支持 `用户名/仓库名` 短格式）
- `pullall` 一键拉取所有项目

**分支操作（branch.sh）**
- `b` 列出分支 → 选编号切换；`b <名字>` 直接切换/创建
- `b all` 打捞全部远程分支并本地镜像；`b -l` 显示所有分支
- `b ql` 清理分支缓存；`b -d <名>` 删本地；`b -dr <名>` 删远程
- `rn` 重命名当前分支（本地 + 远程同步）
- `bclean` 清理已合并的本地分支
- `gsync` 安全同步远程（fetch + rebase，冲突自动回退 merge）
- `gomain` 回到 main/master

**推送与发布（push.sh / merge.sh）**
- `p` 推送，`p skip` 跳过 CI 构建，`p "备注"` 指定备注
- `ok` 合并 dev→main 发布；`ok dev main skip` 跳过 CI
- `no` 撤回最后一次发布 ⚠️ 危险

**查看与对比（view.sh）**
- `st` 当前分支 + 变更文件数
- `info` 仓库完整信息（含领先 / 落后）
- `rls 用户/仓库` 查看远程仓库文件列表
- `lg` 提交历史图（默认 15 条）；`lg 30` 指定条数
- `d` 未暂存变更；`d s` 已暂存变更

**实用工具（stash.sh / fix.sh / tag.sh / burn.sh）**
- `save` 暂存工作区；`pop` 恢复暂存
- `fix` 冲突解决引导
- `tag` 查看标签；`tag v1.0` 发布；`tag -d v1.0` 删除
- `f` 炼化全部源码（喂给 AI）；`f <模块>` 只炼化指定模块
- `undo` 撤销工作区所有修改 ⚠️；`unstage` 取消所有暂存
- `pull` 拉取最新代码；`h` 显示帮助菜单

## 更新机制

`up` 不再下载单文件，而是：
1. 定位 scripts 仓库根目录（`git rev-parse --show-toplevel`）
2. `git fetch --tags` 获取远程版本并与本地 `FZ_VERSION` 比较
3. 有新版本则 `git pull` 更新整个仓库
4. 自动重新加载 `~/.bashrc`

## 常见问题

- **提示"缺少模块文件"**：确认 `~/.bashrc` 中 source 的是
  `fz-tools/fzgit.sh`，而不是旧的单文件。
- **`up` 拉取失败**：检查本地 scripts 仓库是否有未提交的改动
  （有改动时 git pull 会拒绝，先提交或 stash）。
- **旧版 `up` 报"获取远程版本失败"**：旧单文件已下线，请执行
  `bash fz-tools/install.sh` 迁移到新结构。
- **`p` 推送 scripts 仓库后版本号变了**：这是焚诀算法阵的正常行为，
  版本号随提交数自增（v4.x）。

## 回滚

- 本地备份：仓库根目录的 `fzgit.orig.sh`（已被 .gitignore 忽略）
- 或从 git 历史恢复旧单文件：

```bash
git show <旧提交>:fzgit.sh > fzgit.sh
```

然后删除 `fz-tools/`，并把 `~/.bashrc` 中的 source 行换回旧文件即可。
