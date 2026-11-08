---
type: concept
status: developing
area: growth
title: "claude-mem 安装部署"
created: 2026-11-08
updated: 2026-11-08
tags:
  - learning
  - opencode
  - dsh
  - claude-mem
  - 安装
related:
  - "[[claude-mem-深入调研]]"
  - "[[OpenCode与DSH共享记忆-选型调研]]"
  - "[[claude-mem-配置详解]]"
  - "[[claude-mem-存储与读取机制]]"
  - "[[claude-mem-跨端共享]]"
---

# claude-mem 安装部署

> 一句话:**安装 claude-mem 就是在本机起一个常驻后台的小服务(worker),再给 OpenCode 和 DSH 各装一个适配插件;最大的两个坑是"选错观察者提供方会被引到云端登录"和"本机只有 opencode.jsonc,安装器却只认 opencode.json"。**
>
> 基于 claude-mem main 分支(约 v15.12.0)源码,**未实测**。凡标"未证实/未验证/推断/没读到"的地方,都不是确定结论。

---

## 一、先搞懂:装它到底装了什么

### 1.1 大白话

装完以后,你的电脑上多了三类东西:

| 东西                   | 是什么                                             | 类比                 |
| -------------------- | ----------------------------------------------- | ------------------ |
| worker               | 一个常驻后台的小服务(本机 HTTP 服务,Bun 管理),负责收材料、调模型写笔记、存库   | 办公室里一个一直在岗的"记录员"   |
| 适配插件                 | 给 OpenCode 装一个,给 DSH 装一个。插件负责把"你刚做了什么"报给 worker | 每个部门派一个"联络员"向记录员汇报 |
| 数据目录 `~/.claude-mem` | 设置文件、SQLite 数据库、向量库                             | 记录员的"档案柜"          |

另外两个概念要先知道:

- **观察者(observer)模型**:worker 收到材料后,要调一个大模型把它写成一条条"观察笔记"。这个模型叫观察者,调用它要花钱或要 key,所以"选哪家当观察者"是安装时最重要的决定。
- **observation(观察)**:观察者写出的一条笔记,有 ID,存进数据库。

### 1.2 术语表(第一次出现时的解释)

| 术语            | 解释                                                                                       |
| ------------- | ---------------------------------------------------------------------------------------- |
| hook(钩子)      | 在某个时间点自动触发的小程序。比如"每次 agent 调用完工具就通知一下 worker"。claude-mem 靠 hook 自动抓取,不靠 agent 自觉         |
| worker        | 见上表。停了它,只是少了记忆,模型请求不经过它(旁路)                                                              |
| MCP           | Model Context Protocol,agent 调外部工具的一种标准接口。安装器会往 OpenCode 配置里注册一个本地 MCP 服务,让 agent 能主动搜记忆 |
| profile       | DSH 的配置档案,一套独立的配置和插件集合。本机的 profile 叫 `desktop`,文档默认是 `web`                               |
| provider(提供方) | 观察者模型从哪来:`claude` / `codex` / `gemini` / `openrouter` / `openai-compatible` / `host`;其中 `openai-compatible` 安装器没有配置流程,只能装完手改配置 |
| Bun           | 一个 JavaScript 运行时,worker 靠它运行                                                            |
| uv / uvx      | Python 工具链,向量库 Chroma 通过 `uvx` 启动。缺了语义搜索会不可用                                             |
| Chroma        | 向量数据库,用来按意思找相近笔记                                                                         |
| doctor        | claude-mem 自带的自检命令                                                                       |

### 1.3 本机现状

| 项 | 现状 |
|---|---|
| `~/.config/opencode/` | 只有 `opencode.jsonc`,**没有** `opencode.json`;另有 `opencode-mem.jsonc`、`oh-my-opencode-slim.json`、`plugins/` 目录 |
| 现用记忆插件 | opencode-mem |
| `~/.dsh/` | 存在,`profiles` 目录在 |
| `~/.claude-mem` | 不存在,还没装过 |
| DSH profile 名 | `desktop` |

---

## 二、装之前先做的事

### 2.1 检查依赖

要求:Node 20.19+ 或 22.12+。Bun 和 uv 缺了安装器会自动装。装 DSH 侧需要 pnpm 和 dsh。

```bash
node -v          # 要 v20.19+ 或 v22.12+
bun -v           # 没有也行,安装器会补
uv --version     # 没有也行,安装器会补
pnpm -v          # 装 DSH 侧才需要
which dsh        # 装 DSH 侧才需要,能找到路径即可
```

预期:`node -v` 达标。不达标先升级 Node,否则别往下走。

### 2.2 备份(必做)

安装器会改 OpenCode 和 DSH 的配置,先备份:

```bash
cp ~/.config/opencode/opencode.jsonc ~/.config/opencode/opencode.jsonc.bak
cp -r ~/.config/opencode/plugins ~/.config/opencode/plugins.bak
cp -r ~/.dsh/profiles ~/.dsh/profiles.bak
ls ~/.config/opencode/     # 记下当前文件清单,装完对比
```

### 2.3 暂停现用的 opencode-mem

claude-mem 和 opencode-mem 并存会**重复注入**上下文。测试期间先停掉 opencode-mem:在 `opencode.jsonc` 里把 opencode-mem 的插件项临时注释掉(具体写法以你文件里的实际条目为准,本笔记没有读你的文件内容)。`opencode-mem.jsonc` 本身不用删,留着方便回退。

### 2.4 选观察者提供方

观察者每次工具调用都会被调用,持续有成本。选择决策表:

| provider            | 要 key 吗                   | 会联网登录 claude-mem 账号吗      | 适合谁                                      |
| ------------------- | ------------------------- | ------------------------- | ---------------------------------------- |
| `claude`            | 用已登录的 Claude CLI          | 不需要                       | 本机已有 Claude 订阅或登录                        |
| `codex`             | 用已登录的 Codex               | 不需要                       | 本机已有 Codex                               |
| `gemini`            | 要                         | **交互模式默认引导浏览器登录 cmem.ai** | 想用 Gemini 且接受登录                          |
| `openrouter`        | 要(如 `OPENROUTER_API_KEY`) | **交互模式默认引导浏览器登录 cmem.ai** | 想后续把 `BASE_URL` 改成 codebuddy 的人          |
| `openai-compatible` | 要                         | **不会**(安装器没有它的流程)         | 要接 codebuddy 等自定义地址:装完手改 `settings.json` |
| `host`              | 不要                        | 不需要                       | **不适合你**:要求本机已有一个兼容服务,见下文 |

要点:

- 选 `claude` / `codex` / `host`,不需要 claude-mem 账号。但 `host` 还要求本机有现成服务,见下一条。
- 选 `gemini` / `openrouter`,交互安装会走 `completeCmemTrialPairing`(浏览器配对 cmem.ai)。登录本身不会自动把记忆传云上,但会引出"托管观察者模型"这条路,里面发的是原始工具调用,风险最大(见第四节)。
- 非交互安装(脚本里跑)需要先准备好对应 API key(如 `OPENROUTER_API_KEY`),或用 `--provider claude`(没写 `--provider` 的非交互安装默认就是 claude)。这是源码推断(`validateNonInteractiveProvider`)。
- `host` 的真实含义:观察者不调云端,而是请求本机回环端口(127.0.0.1:37777 或 37778)上一个**你自己已经在跑的**兼容服务,由宿主 agent 充当记账员。安装器**不会替你起这个服务**,探测不到就直接报错退出(`cmem-memory-credentials.ts` 的 `resolveHostObserverPort`)。它是为 Grok Bot 和 Cursor 设计的(观察者模型名只有 `cursor`、`grok-bot` 两个,出处同文件的 `buildHostObserverSettings`),官方文档也只在 Grok Bot 章节讲它。**我没读到任何组件会在 OpenCode 或 DSH 上起这个服务,所以对你的两个端大概率不可用,不要当首选。**
- 观察者接 codebuddy 没实测。源码里 `openai-compatible` 与 `openrouter` 都允许自定义 `BASE_URL`,前者更干净(见 3.6 节),理论可行。

> 建议:**第一次用 `--provider claude` 装**,不触发 cmem.ai 登录;装完直接按 3.6 节把五个键改成 `openai-compatible` + codebuddy。没有 Claude 登录时,装完到改好配置之前观察者会不可用,这段时间不会产生记忆,属预期。`--provider claude` 在没登录 Claude 的机器上是否能顺利装完,**未验证**。

### 2.5 关于 CLAUDE_MEM_ONLINE_OPTIN=false(事实冲突)

| 来源 | 说法 |
|---|---|
| 旧笔记(claude-mem-深入调研) | 装的时候加 `CLAUDE_MEM_ONLINE_OPTIN=false` 就能避免登录 |
| 本次源码调研 | 源码里**没找到处理该变量的逻辑**,只看到相关的邮箱注册设置被留空 |

结论:**"该变量能避免登录"未证实有效**。不要靠它保证不联网。真正可靠的做法是选不需要账号的提供方(`claude` / `codex`),装完再用第四节的清单核对。

---

## 三、分步安装

顺序:**先只装 OpenCode → 验证 → 再装 DSH**。每步确认没问题再往下。

### 3.0 风险项:opencode.jsonc 与 opencode.json

> **醒目风险**:源码里 OpenCode 安装器只读写 `~/.config/opencode/opencode.json`,**没有处理 `opencode.jsonc`**。本机只有 `opencode.jsonc`。所以装完可能**另起一个 `opencode.json`**。它和你现有的 `opencode.jsonc` 并存会不会冲突,**未验证**(取决于 OpenCode 自身的加载行为)。

稳妥步骤:

1. 装前已备份(2.2 节),并记下目录清单。
2. 装完立刻对比:

```bash
ls -la ~/.config/opencode/
cat ~/.config/opencode/opencode.json     # 如果新生成了,看里面写了什么
```

3. 若**新生成了 `opencode.json`**:
   - 先别急着删。重启 OpenCode,看现有配置(模型、其他插件)是否还正常生效。
   - 若现有配置失效或行为异常:把 `opencode.json` 里 claude-mem 相关的几项(plugin/plugins 数组里的插件路径、MCP 配置)手工合并到 `opencode.jsonc`,然后把 `opencode.json` 移走(如 `mv opencode.json opencode.json.new`),再重启验证。
   - 若合并后想回退:用 `.bak` 文件恢复。
4. 手工合并的具体字段名只按 `opencode.json` 里实际生成的内容照抄,不要自己编。

### 3.1 第一步:只装 OpenCode

```bash
# 推荐首次:claude 提供方,不触发 cmem.ai 登录,装完再改成 codebuddy
npx claude-mem install --ide opencode --provider claude
```

如果想用 openrouter(非交互,先备好 key,key 用你自己的):

```bash
OPENROUTER_API_KEY=<你的key> npx claude-mem install --ide opencode --provider openrouter
```

`--provider openrouter` 在非交互模式下是否还要额外参数,**未验证**。

可选参数:`--no-auto-start`(装完不自动启动 worker),`--model <id>`(指定模型)。

| | 内容 |
|---|---|
| 预期现象 | 检查 Node/Bun,创建或更新 `~/.claude-mem/settings.json`;复制 `~/.config/opencode/plugins/claude-mem.js`;写入 OpenCode 配置;清理全局 `AGENTS.md` 里旧的 claude-mem 记忆块;自动启动 worker |
| 出问题 | Node 版本不够:升级后重跑。选了 gemini/openrouter 却弹浏览器:关掉,改用 `--provider claude` 重装。安装报联网失败:更新日志提过"无法访问 cmem.ai 的非交互安装会失败",是否只针对 cmem 提供方,**未验证**;换 `claude` 再试 |

### 3.2 第二步:关匿名统计

```bash
npx claude-mem telemetry disable
npx claude-mem telemetry status     # 确认已关
```

默认匿名统计(PostHog)是开的,发什么具体内容没读。

### 3.3 第三步:体检

```bash
npx claude-mem doctor
```

| | 内容 |
|---|---|
| 预期现象 | 检查项包括:Bun、uv、worker 守护进程是否在跑、Chroma MCP 与集合健康度、各 CLI 设置与 API key 状态、安装目录和 marketplace 运行时是否存在 |
| 出问题 | 哪项报红按第五节故障表处理。worker 没起可 `npx claude-mem start` 或 `restart` |

### 3.4 第四步:重启 OpenCode 并核对(见第四节)

装完需要**重启 OpenCode**。先做 3.0 的文件核对,再做第四节的隐私核对和功能验证。**通过后再装 DSH。**

### 3.5 第五步:装 DSH

```bash
npx claude-mem install --ide dsh --dsh-profile desktop --provider claude
```

本机 profile 是 `desktop`,不是文档默认的 `web`,不写 `--dsh-profile` 会按默认 `web` 处理,不符合本机。

| | 内容 |
|---|---|
| 预期现象 | 在 `~/.claude-mem/integrations/dsh.json` 记下受管理的 profile;通过子进程 `dsh plugin --profile desktop add --workspace-root <target>` 委托 DSH 装插件;修改 `transcript-watch.json` 监听 `~/.dsh/sessions` |
| 出问题 | 提示找不到 pnpm 或 dsh:先装好再重跑。profile 不存在:`ls ~/.dsh/profiles` 确认名字。想回退:用 `~/.dsh/profiles.bak` 恢复 |

关于旧笔记提到的 `dsh/cordis.patch.yml`:**本次源码调研没有看到安装器直接操作它**,是通过 `dsh plugin ... add` 委托 DSH 自己处理的。以研究结论为准,旧笔记的说法不再采用。DSH 最终写了哪些文件,以装完实际对比为准。

### 3.6 第六步:换成 codebuddy 做观察者,并改中文输出(可选)

如果第一步用的是 `--provider claude`,想换成 codebuddy,要一起改下面 5 个键,**缺一个都不会生效**(详细说明见 [[claude-mem-配置详解]]):

```text
CLAUDE_MEM_PROVIDER                 → openai-compatible
CLAUDE_MEM_OPENAI_COMPAT_BASE_URL   → <codebuddy 的 OpenAI 兼容地址>
CLAUDE_MEM_OPENAI_COMPAT_API_KEY    → <codebuddy 的 API Key>
CLAUDE_MEM_OPENAI_COMPAT_MODEL      → <便宜的模型>
CLAUDE_MEM_MODE                     → code--zh
```

这里选 `openai-compatible` 而不选 `openrouter`:前者是独立提供方,不带 OpenRouter 归因请求头,key 也分开,而且**安装器没有它的配置流程**(`install.ts` 明说"在 settings.json 里配"),所以不会弹 cmem.ai 登录。

改完用 `npx claude-mem restart` 重启 worker,再回到第四节核对:`BASE_URL` 不含 `cmem.ai`,云同步相关键仍为空。

`MODE` 只管"笔记用什么语言写",和观察者换不换模型无关,可以单独改,换提供方前后都能用 `code--zh`(是否生效以实测为准)。

---

## 四、装完核对

### 4.1 会被改动/新增的文件清单

**OpenCode 侧**

| 路径 | 动作 |
|---|---|
| `~/.config/opencode/plugins/claude-mem.js` | 新增(拷贝编译好的插件) |
| `~/.config/opencode/opencode.json` | 读取并写入:在 `plugin`(OpenCode v1)或 `plugins` 数组加插件路径;解析到 `mcp-server.cjs` 时注册本地 MCP。**本机原本没有此文件,可能新建** |
| 全局 `AGENTS.md` | 清理旧版本的 claude-mem 记忆块 |

**DSH 侧**

| 路径 | 动作 |
|---|---|
| `~/.claude-mem/integrations/dsh.json` | 记录受管理的 profile |
| DSH profile(由 `dsh plugin ... add` 处理) | 装插件,具体改了哪些文件没读 |
| `transcript-watch.json` | 修改,监听 `~/.dsh/sessions` |

**claude-mem 自身**

| 路径 | 内容 |
|---|---|
| `~/.claude-mem/settings.json` | 设置 |
| `~/.claude-mem/claude-mem.db` | SQLite 数据库(SQLite + FTS5) |
| `~/.claude-mem/` 下的 Chroma 数据 | 向量库 |

### 4.2 隐私核对

目标:确认记忆内容没出本机,没连 cmem.ai。

检查 `~/.claude-mem/settings.json`:

| 键 | 期望 |
|---|---|
| `CLAUDE_MEM_CLOUD_SYNC_HUB_URL` | 空(为空则云同步完全关闭) |
| `CLAUDE_MEM_CLOUD_SYNC_TOKEN` | 空 |
| `CLAUDE_MEM_PRO_MEMORY_KEY` | 空 |
| `CLAUDE_MEM_OPENAI_COMPAT_BASE_URL`(若用 openai-compatible) | 指向 codebuddy,不含 `cmem.ai` |

```bash
grep -n -E "CLOUD_SYNC|PRO_MEMORY_KEY|BASE_URL" ~/.claude-mem/settings.json
lsof -i -P | grep -i -E "bun|node" | grep -i -E "cmem|ESTABLISHED"
```

预期:没有指向 `cmem.ai`、`sync.cmem.ai` 的连接。`lsof` 只能看到那一刻的连接,建议跑一段会话后再看一次,或查 worker 日志。

回顾外发路径:

| 路径 | 触发条件 | 默认 |
|---|---|---|
| 云同步 | `CLOUD_SYNC_TOKEN`、`USER_ID`、`HUB_URL` 三个都非空 | 关 |
| 托管观察者模型 | 登录后选 claude-mem 为提供方,工具调用内容发到 `https://cmem.ai/api/inference/v1` | 需选择才发 |
| 匿名统计 | 默认开 | 开,用 3.2 关 |

不登录时,观察者内容只发给你自己选的提供方。选 `host` 时请求只发到本机回环端口;那头的 agent 自己会不会再往外发,没读到。

### 4.3 功能验证

1. 重启 OpenCode,开一个新会话,用中文做点小事:例如让 agent 读一个文件、改一行、跑一条命令。
2. 打开 worker 的网页查看器 `/viewer`,看有没有出现新的观察(observation)。查看器的具体端口我没读到,可先 `npx claude-mem status` 看 worker 信息。
3. 看产出的笔记是不是中文(设了 `code--zh` 才会)。
4. 开第二个新会话,看开头是否注入了一份紧凑的记忆索引。
5. 在会话里让 agent 搜一次记忆(也可用 `npx claude-mem search` 子命令)(`search` 的具体参数没读,先不要凭空猜,走会话内搜索更稳)。

没有观察产出时:先 `npx claude-mem doctor`,再确认 worker 在跑,再确认观察者提供方可用(key/额度;选了 host 的话,还要确认本机回环端口上有服务在听)。

DSH 装好后同样做一遍,并验证跨来源召回。旧笔记提到可打开 `CLAUDE_MEM_SESSION_START_INCLUDE_ALL_SOURCES: "true"`,让一端能看到另一端的记忆,详见 [[claude-mem-跨端共享]]。

---

## 五、进阶

### 5.1 命令速查

所有命令前缀 `npx claude-mem`。

| 命令 | 作用 |
|---|---|
| `install` | 安装并接入某个 IDE |
| `repair` | 修复安装(具体修什么没读) |
| `update` / `upgrade` | 刷新钩子和依赖 |
| `uninstall` / `remove` | 卸载 |
| `start` / `stop` / `restart` | 启停 worker |
| `status` | 查看 worker 状态 |
| `doctor` | 自检 |
| `backup run\|status\|list` | 本地数据库快照 |
| `restore <file>` | 从快照恢复 |
| `telemetry status\|enable\|disable` | 匿名统计开关 |
| `search` | 搜索记忆(参数没读) |
| `prune` | 清理(具体清什么没读) |
| `teambrain` | 团队相关(没读) |
| `server` / `worker` / `mcp` / `hook` | 运行时与内部入口 |
| `adopt` / `project` / `cleanup` | 其他管理命令(没读细节) |
| `transcript` (watch) / `memory` (ingest) | 监听转录、摄入记忆 |

安装核心参数:

| 参数 | 作用 |
|---|---|
| `--ide <id>` | 指定 IDE,如 `opencode`、`dsh`、`claude-code`、`cursor` |
| `--dsh-profile <name>` | DSH 的 profile,默认 `web` |
| `--provider <name>` | `claude` / `codex` / `gemini` / `openrouter` / `host`(`host` 需要本机已有兼容服务,对 OpenCode/DSH 不推荐;`openai-compatible` 不走安装器,见 3.6 节) |
| `--model <id>` | 指定模型 |
| `--no-auto-start` | 安装结束不自动启动 worker |
| `--disable-auto-memory` | 显式禁用 Claude Code 原生自动记忆 |
| `--runtime worker\|server` | 非交互选择运行时 |

仓库里另有 `docker-compose.yml`,是 server-beta 测试版,强制要 Postgres 凭据,**不是本机用法**。`--runtime server` 是否与它相关,没读到,本机用 `worker`。

### 5.2 升级

```bash
npx claude-mem update
npx claude-mem doctor
```

升级后同样重启 OpenCode,并重新核对 `opencode.json` 有没有被改动。

### 5.3 卸载

```bash
npx claude-mem uninstall
```

会清理:

- 停止 worker 进程
- 移除 marketplace 和 plugin cache 目录
- 清理各 IDE 的配置(如 OpenCode 的 `opencode.json` 和 `claude-mem.js`)
- 移除旧别名和可执行钩子文件

**不会删数据目录。** 卸载程序明确保留数据目录,并打印手动删除命令建议。确认不要数据了再手动删:

```bash
rm -rf ~/.claude-mem
```

卸载后核对:

- 本机原先的 `opencode.jsonc` 里没有 claude-mem 条目(安装器没写过它,所以也不会清它)。
- 若曾手工把 claude-mem 配置合并进 `opencode.jsonc`,**卸载不会清这部分**,要手工删。这一条是据"安装器只处理 `opencode.json`"的推断。
- DSH 侧是否一并移除 profile 里的插件,没读到,装/卸前后对比 `~/.dsh/profiles`。
- 恢复 opencode-mem:把 2.3 节注释掉的条目放开。

### 5.4 备份与迁移

数据目录默认 `~/.claude-mem`,可用 `CLAUDE_MEM_DATA_DIR` 改位置。

```bash
npx claude-mem backup run       # 立即做一份快照
npx claude-mem backup list      # 列出快照
npx claude-mem backup status
npx claude-mem restore <file>   # 恢复
```

自动备份的键(`settings.json`):

| 键 | 含义 | 默认 |
|---|---|---|
| `CLAUDE_MEM_BACKUP_ENABLED` | 是否开启自动备份 | 来源里示例为 `true` |
| `CLAUDE_MEM_BACKUP_INTERVAL_HOURS` | 快照频率(小时) | 24 |
| `CLAUDE_MEM_BACKUP_RETAIN_COUNT` | 保留份数 | 7 |

迁移到新机器:复制整个数据目录,并在新机器上设置相同的 `CLAUDE_MEM_DATA_DIR`;或用 `restore`。新机器仍要重新跑 `install` 装适配插件,这一点是我的理解,来源没明说。

### 5.5 常见故障排查

| 现象 | 可能原因 | 怎么办 |
|---|---|---|
| 提示 `The worker port is held by another process` | worker 端口被别的进程占了 | `lsof -i -P` 找占用者,结束它或 `npx claude-mem stop` 后 `start`;端口键是 `CLAUDE_MEM_WORKER_PORT`,默认 `37700 + (uid % 100)`,你这台机器是 `37701`,见 [[claude-mem-配置详解]] |
| worker 起不来或卡住 | 进程异常、依赖缺失 | `npx claude-mem doctor` → `restart`;仍不行看日志(日志位置没读到) |
| 提示语义搜索未启用 | Chroma 退出或 `uvx` 找不到 | 确认 `uv --version`,没有就让安装器重装(`repair` 是否覆盖这一点没读到)或手动装 uv;再 `doctor` |
| 装完 OpenCode 配置失效 | 新生成 `opencode.json` 与 `opencode.jsonc` 并存(**未验证**是否冲突) | 按 3.0 节处理,必要时用 `.bak` 恢复 |
| 中文查不到语义相近的笔记 | 向量嵌入默认是英文模型 | 关键词检索(中文子串匹配)可用,语义检索偏弱,属推测,要实测;详见 [[claude-mem-深入调研]] |
| 笔记重复出现在会话里 | opencode-mem 没停 | 回到 2.3 节暂停它 |

---

## 六、没读到/不确定清单

1. **`opencode.jsonc` 与 `opencode.json` 并存是否冲突**:源码只读写 `opencode.json`,对 `opencode.jsonc` 没有检测和处理;并存后 OpenCode 本身怎么加载,**未证实**。
2. **`CLAUDE_MEM_ONLINE_OPTIN=false` 是否有效**:源码中没找到处理该变量的逻辑,**未证实有效**,与旧笔记结论冲突。
3. **非交互安装的细节**:`--provider openrouter` 非交互时是否还要额外参数,**未验证**;"需要 API key 或 `--provider claude`"是源码推断。
4. **不登录时安装器会不会因联网失败而中断**:**未验证**,更新日志的说法可能只针对 cmem 提供方。
5. **DSH 侧**:没看到直接操作 `cordis.patch.yml`,而是委托 `dsh plugin ... add`;DSH 最终改了哪些文件,没读到。旧笔记的说法不采用。
6. **`host` 提供方**:已读源码确认它依赖本机已在运行的兼容服务,装不上就报错;但 OpenCode、DSH 上有没有现成组件充当这个服务,没读到,只能说大概率没有。
7. **观察者接 codebuddy**:没实测,理论可行。
8. **`/viewer` 的具体地址、日志位置**:没读到。worker 端口键已确认是 `CLAUDE_MEM_WORKER_PORT`,默认 `37700 + (uid % 100)`。
9. **`repair`、`prune`、`search`、`teambrain` 等命令的细节参数**:没读到。
10. **卸载是否清理 DSH 侧 profile 里的插件**,以及卸载不清手工合并内容:后者是推断。
11. **匿名统计具体发什么**:没读。
12. **全文基于源码阅读,没有任何一步在本机实测过**;`~/.claude-mem` 本机尚不存在。

---

## 相关笔记

- [[claude-mem-深入调研]]:优势、代价、云端外发路径、检索机制
- [[OpenCode与DSH共享记忆-选型调研]]:为什么选它
- [[claude-mem-配置详解]]:settings.json 各键
- [[claude-mem-存储与读取机制]]:数据怎么存、怎么取
- [[claude-mem-跨端共享]]:OpenCode 与 DSH 如何共享
