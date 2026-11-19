# CHANGELOG

本文件只记录「改过什么」。使用方式见 [README.md](README.md)。

版本号由 `bash version.sh bump` 显式递增，不再随推送自动变化。

---

## v5.116 — 新增 token 指令：一键更换 HTTPS 令牌

### 变更

- 新增 `token` 指令（`modules/env.sh`），用于更换各平台 HTTPS 令牌：
  `token`（列出状态后选平台）、`token cnb`、`token github`、`token gitlab`、
  `token gitee`、`token coding`，也支持直接给域名 `token cnb.cool`。
- 界面会显示当前账号与**脱敏**令牌（如 `NEWT****（共 18 位）`），
  令牌输入不回显，输出不打印完整令牌。
- 走 git credential 协议（先 `reject` 再 `approve`），对 `store` / `cache` /
  `keychain` 各类助手都成立，不需要知道令牌缓存在哪个文件。

### 修复

- **写入后回读校验**：某些平台配置了 URL 专属 helper（如 `gh auth git-credential`）
  会接管该 host 的凭据，此时本指令写入的值读不回来。现在这种情况会明确报失败
  并提示改用 `ghlogin`，不再假报成功。
- **回读失败时回滚旧令牌**：`reject` 到 `approve` 之间若写入失败，旧令牌已被删除，
  用户会卡在「旧的没了、新的没成」。现在失败时自动写回原令牌。
- **不能靠 `approve` 退出码判断成败**：实测即使 helper 彻底失败（程序不存在 /
  目标文件不可写），`git credential approve` 仍返回 0。唯一可靠判据是回读。
- **先删旧再写新**：`store` 助手是追加写，不先 `reject` 会在 `~/.git-credentials`
  里留下新旧两条记录。

### 重构

- 平台表合并为**单一真相源**：`_fz_platforms` 一张表同时喂 remote 拼 URL、
  token 换令牌、HTTPS 凭据提示。原先 `remote` 与 `token` 各有一张表，
  新增平台必漏一处。

### 修复（假报成功）

- `repo` 的初始提交不再 `git commit ... 2>/dev/null || true`。缺身份时
  `git commit` 返回 128，被吞成 0 后仍继续 `git push` 并打印「已推送」，
  而代码根本没进任何提交。现在提交/推送失败都会明确报错并给出下一步。

### 修复（bash 3.2 兼容）

- `c <关键字>` 用到 `${var,,}`（bash 4 语法），macOS 自带的 `/bin/bash` 3.2
  会直接语法错误。改为内建 `_fz_lower`，零 fork，中文/数字原样保留。

### 测试

- 新增 T19（18 项）：令牌替换生效、旧值清除、不误伤其他平台、空输入不改动、
  未知平台报错、输出不泄露完整令牌、域名直给、助手覆盖时报失败、
  平台名归一（CODING 主机为 `e.coding.net`）、回滚后旧令牌仍在、
  平台表不重复。
- 新增 T20（3 项）：源码不得出现被吞掉的 `git commit`，
  并验证「无身份时 commit 确实失败」这一前提成立。
  ⚠️ 用例用 `env -u GIT_AUTHOR_*` 隔离，否则脚本顶部的 export 会盖过
  git config，让用例假绿。
- 新增 T21（4 项）：产品代码不得出现 bash 4 大小写替换语法，
  并校验 `_fz_lower` 行为。

---

## v5.111 — AI 备注改为协议中立

### 变更

- **AI 备注不再绑定 Anthropic**。原先写死 `api.anthropic.com` 私有协议
  （`x-api-key` + `v1/messages`），现改为通用 OpenAI 兼容接口
  （`/v1/chat/completions` + `Authorization: Bearer`）。
- 可接任何兼容端点：NVIDIA NIM（免费）、DeepSeek（低价）、Ollama（本地不外发）、
  自建代理。
- 新增 `modules/ai.sh`，从 `push.sh` / `env.sh` 中抽出。
- 配置改为 `~/.fz_ai.conf`（权限 600，key=value 三行）。
- 新增 `aikeyoff` 一键关闭（并清理旧版 `~/.fz_ai_key`）。
- `aikey` 增加数据流向明示与配置后连通性自测。

### 安全

- 默认关闭：不配置即零网络请求、零费用。

---

## v5.110 — 安全修复与工程规范化

### 安全（P0）

- **API Key 不再写入被 git 追踪的文件**。`aikey` 曾把 Key 明文
  `sed` 进 `fz-tools/fzgit.sh`，而 `p` 执行 `git add .` —— 配过 Key 后
  一次推送即公开泄漏。现改为独立文件 + `umask 077` 写入。
- **新增凭据护栏**：`p` 在提交前扫描暂存区，命中疑似 Key 即中止并撤销暂存。
- **移除硬编码个人路径**：主入口曾 `find /storage/emulated/0/常用/` 并
  `mkdir -p` 一个含 emoji 的个人目录，导致每个用户被创建别人的目录，
  且全新用户被误判为旧版用户而跳过首次引导。
- `source` 主入口不再写磁盘。

### 修复

- `nav.sh` 字符宽度判断：`[[ $ch == [^\x00-\x7F] ]]` 在 bash 里是字符集合
  而非数值范围，导致空格、`!`、`~` 等 ASCII 标点被算作全角（宽度 2），
  菜单折行、指示器错位。改为按 UTF-8 字节数判断。
- `burn.sh` 模块过滤失效：`[ -n "$m" ] && grep ... || cat` 在 grep 无匹配时
  触发 `cat`，导致 `f <模块>` 输出全部文件。**过滤不到的模块与不过滤结果相同**。
- `clone.sh` `cd` 失败仍打印「已进入」。
- 64 处 `read` 缺 `-r`，导致路径中的反斜杠被吃掉（`/a\b` → `/ab`）。
- `gh repo create` 的退出码取错；`gh api user` 失败时拼出
  `github.com//repo.git` 并静默加错远程。
- shellcheck `warning` 从 34 项降至 0。

### 新增

- `get.sh`：一行安装 / 卸载入口（安装到 `~/.local/share/fz`，幂等写 `.bashrc`）。
- `version.sh`：版本号显式管理（`show` / `bump` / `bump major` / `set`）。
- `.github/workflows/ci.yml`：6 个 job（lint / syntax / compat / smoke / no-secrets / version）。
- `.shellcheckrc`：静态检查基线。
- 冒烟测试 46 → 63 项，新增 T12 安全回归、T13 安装器。

### 变更

- **`p` 不再自动改写 `FZ_VERSION`**。旧实现用 commit count 覆盖版本号，
  导致每次推送必然产生一次「版本号变动」提交、版本号与内容脱钩、
  多分支并行时是固定冲突源。
- `AGENTS.md` 重写：针对 bash 库形态，含四条红线与本地自检清单。

---

## v5.109 及更早

以下为改造前的历史记录，保留原貌。

### v5.100 — 多远程推送基准

一个项目同时绑 GitHub + CNB 时（如 `origin`=GitHub、`cnb`=cnb.cool），
旧版 `p` 用当前分支上游 `@{u}` 判断「是否需要推送」。若上游指向 cnb
而本地与 cnb 已一致，`p` 会对 GitHub 假报「没有任何变更，无需推送」
并**直接返回，`git push origin` 从未执行**——GitHub 永远停在旧版。

判断基准改为**本次目标远程**（`$_fz_remote/分支`），并修复
`p "备注"` 被误当远程名、`p <远程>` 首推不建跟踪、
推送兜底静默 `git push -u` 改写上游等一串同源问题。
推完目标远程后若其他远程仍落后，仅提示不自动推。

### v5.101 — 多位数编号

项目数 ≥ 10 时，单键即时返回导致「想输 11，一敲 1 就进了第 1 项」。
改为数字先进缓冲区，仅在确认不存在更长合法编号时立即生效。

### v5.103 — `st` 合并 `info`

`st` 除分支/变更外，增加远程地址、提交数、追踪文件数、标签数，
并逐条列出变更文件（不再只报个数）。

### v5.96 - v5.98 — 交互体验

- 方向键上下移动闪烁：改为定向重绘，不再整屏刷新。
- 方向键无反应：`read -rsn2` 假设 ESC 序列三字节同包到达，
  但 Termux 会分片发送；改为逐字节补读。
- 指示器不动：重绘缓存了首轮样式，改为按当前选中项现场生成。

### v5.2 — 防冲突推送

- `p` 推送前 `fetch` 只读检测，落后时列出远程新提交与涉及文件，
  三选项由用户决定（拉取合并 / `--force-with-lease` / 取消）。
- `c` 导航接入方向键指示器，管道环境自动退化为数字输入。
- `remote` 支持多平台模板（GitHub / GitLab / Gitee / CNB / CODING / 自定义）。

### v5.1

- `pull` 升级为智能拉取（上游跟踪检查 / 脏工作区确认 / 显示新增提交）。
- `c` 进入项目与 `b` 切换分支后自动显示状态摘要。
- `st` 增加领先/落后同步状态。
- `ok` 发布增加工作区检查与分步执行。

### v5.0 — 书签系统

消灭硬编码 `FZ_BASE`，以「书签」为核心。`c` 升级为
书签→项目→操作 三阶段交互导航，支持项目在书签间移动/复制
并自动修复 Git 安全权限。

### v4.0

从「整段注入 `~/.bashrc`」改为 `source` 主入口，模块化拆分。

### 迁移指南

- v4.0 → v5.0：`~/.fz_bookmarks` 为空且旧 `FZ_BASE` 存在时，
  首次执行 `c`/`setup` 会自动导入为默认书签「工作台」。
  `FZ_BASE` 之后仅用于 `f` 的输出来源，不再影响导航/克隆/批量拉取。
- v5.1 → v5.2：不改变书签数据结构与任何指令名，升级零成本。
- v5.0 → v5.1：同上。
