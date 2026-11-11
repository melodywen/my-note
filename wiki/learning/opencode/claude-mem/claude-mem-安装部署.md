---
type: concept
status: developing
area: growth
title: "claude-mem 安装部署"
created: 2026-11-08
updated: 2026-11-11
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

> 一句话:**安装 claude-mem 就是在本机起一个常驻后台的小服务(worker),再给 OpenCode 和 DSH 各装一个适配插件;最大的坑是"选错观察者提供方会被引到云端登录";另一个是"安装器写死只认 opencode.json、不检查 opencode.jsonc",但实测 OpenCode V2 两个文件都会读取并合并、并存不冲突,本机已统一为 opencode.json。**
>
> 基于 claude-mem main 分支(约 v15.12.0)源码(装机当时为 15.12.0/15.12.1;**本机现为 v15.16.0,2026-11-11 升级**,升级步骤见 5.2 节);OpenCode 端已于 2026-11-08 装机并实测,实测记录见 3.7 节,DSH 端已于 2026-11-09 手动接入并实测(官方安装器对 `desktop` profile 必败,见 [[claude-mem-跨端共享]] 第 8 节)。凡标"未证实/未验证/推断/没读到"的地方,都不是确定结论。

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
| `~/.config/opencode/` | 现以 `opencode.json` 为唯一主配置(装机当时只有 `opencode.jsonc`、没有 `opencode.json`;该文件无注释,已合并进 `opencode.json` 并删除);另有 `opencode-mem.jsonc`、`oh-my-opencode-slim.json`、`plugins/` 目录 |
| 现用记忆插件 | opencode-mem |
| `~/.dsh/` | 存在,`profiles` 目录在 |
| `~/.claude-mem` | 装机前不存在(这是装机前的快照,现已装好) |
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
cp ~/.config/opencode/opencode.json ~/.config/opencode/opencode.json.bak
cp -r ~/.config/opencode/plugins ~/.config/opencode/plugins.bak
cp -r ~/.dsh/profiles ~/.dsh/profiles.bak
ls ~/.config/opencode/     # 记下当前文件清单,装完对比
```

### 2.3 暂停现用的 opencode-mem

claude-mem 和 opencode-mem 并存会**重复注入**上下文。测试期间先停掉 opencode-mem:在 `opencode.json` 里把 opencode-mem 的插件项临时移出(具体写法以你文件里的实际条目为准,本笔记没有读你的文件内容)。`opencode-mem.jsonc` 本身不用删,留着方便回退。

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
- 观察者接 codebuddy:**已实测通过**,但走的是公司网关,不是直连(见 3.6、3.7 和 [[claude-mem-调教清单]] 第 1 轮)。装机前读源码的判断是:`openai-compatible` 与 `openrouter` 都允许自定义 `BASE_URL`,前者更干净(见 3.6 节),理论可行。

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

### 3.0 配置文件:opencode.json 与 opencode.jsonc(已验证,不冲突)

> **结论(实测)**:OpenCode 安装器只读写 `~/.config/opencode/opencode.json`(写死路径,`OpenCodeInstaller.ts:109`),不检查 `opencode.jsonc`,文件不存在就新建。装机当时本机只有 `opencode.jsonc`,所以装完另起了一个 `opencode.json`。OpenCode V2(本机 v2.2.6)用 `opencode debug config` 实测:`opencode.json` 与 `opencode.jsonc` **都会读取并合并**,并存不冲突,claude-mem 只加载一份。本机已决定统一为 `~/.config/opencode/opencode.json`(原 `opencode.jsonc` 无注释,已合并并删除),**以后新增配置都改 `opencode.json`**。

稳妥步骤:

1. 装前已备份(2.2 节),并记下目录清单。
2. 装完立刻对比:

```bash
ls -la ~/.config/opencode/
cat ~/.config/opencode/opencode.json     # 看安装器写了什么
opencode debug config                    # 看合并后的最终配置
```

3. 若本机同时有 `opencode.json` 和 `opencode.jsonc`:两个并存不会冲突,可以不动;想统一的话,以 `opencode.json` 为准,先备份,把 `.jsonc` 的内容合并进去再移走 `.jsonc`(本机就是这么做的)。
4. V2 的 `debug config` 里 MCP 显示为 `mcp.servers.<名字>`(V1 写法 `mcp.<名字>` 仍兼容)。合并时具体字段名只按安装器在 `opencode.json` 里实际生成的内容照抄,不要自己编。
5. 若配置异常:用 `.bak` 恢复。

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

### 3.6 第六步:换成公司网关做观察者,并改中文输出

第一步用 `--provider claude` 装完后,观察者在本机找不到 claude 可执行文件,实测不工作(见 3.7)。要换掉它,走 `openai-compatible` 提供方,指向一个 OpenAI 兼容网关。**不是直接填 codebuddy 的地址和 key,那条路行不通**,原因见下面"为什么不直连 codebuddy"。

这里选 `openai-compatible` 而不选 `openrouter`:前者是独立提供方,不带 OpenRouter 归因请求头,key 也分开,而且**安装器没有它的配置流程**(`install.ts` 明说"在 settings.json 里配"),所以不会弹 cmem.ai 登录。

#### 为什么不直连 codebuddy

读了 `opencode-codebuddy-auth` 插件源码,codebuddy 的认证方式和 claude-mem 能发的请求对不上:

| 项 | codebuddy 插件的做法 | claude-mem `openai-compatible` 能发的 |
|---|---|---|
| 认证 | 浏览器 OAuth 登录,token 存在 `~/.local/share/opencode/auth.json`,有过期时间,由插件调刷新接口续期 | 一个固定的 key |
| 请求头 | 每次请求带约 25 个租户/用户头(`X-Tenant-Id`、`X-User-Id`、`X-Enterprise-Id`、`X-Domain` 等),从 JWT 解出 | 只发 `Authorization: Bearer <key>` |

所以直连大概率 401/403。这是**推断,未实测**。

#### 现在怎么配

改走用户自己的 OpenAI 兼容网关(`interact_ecology_agent_manager_api_server` 的 openai-gateway,规格见该仓库 `openspec/specs/openai-gateway/spec.md`)。网关用系统配置的固定 Key 校验调用方,自己持有并刷新 codebuddy 凭证,对请求和响应原样透传。

`~/.claude-mem/settings.json` 里的键:

| 键 | 值 |
|---|---|
| `CLAUDE_MEM_PROVIDER` | `openai-compatible` |
| `CLAUDE_MEM_OPENAI_COMPAT_PRESET` | `custom` |
| `CLAUDE_MEM_OPENAI_COMPAT_BASE_URL` | `https://mapecology.testsite.woa.com/api/ecology/openai/v1` |
| `CLAUDE_MEM_OPENAI_COMPAT_MODEL` | `deepseek-v4.1-flash` |
| `CLAUDE_MEM_MODE` | `code--zh` |

密钥不进 `settings.json`(它在 Git 里),放 `~/.claude-mem/.env`:

```text
OPENAI_COMPAT_API_KEY=<你的网关 key>
```

要点:

- `BASE_URL` 只写到 `/v1`,claude-mem 会自动补 `/chat/completions`(`OpenAICompatProvider.ts` 约 474-476 行)。
- 网关上游只收流式请求,claude-mem 默认发流式字段,正好匹配。
- 上游若拒绝 `reasoning:{enabled:false}`,claude-mem 会自动去掉该字段重发一次(约 690-697 行)。
- 域名含 `testsite`,是**测试环境**。观察者每次调用都会把对话原文发给该网关。
- `MODE` 只管"笔记用什么语言写",和观察者换不换模型无关。

改完用 `npx claude-mem restart` 重启 worker,再回到第四节核对:`BASE_URL` 不含 `cmem.ai`,云同步相关键仍为空。

### 3.7 实测记录(2026-11-08)

按过程大致排列,个别条目的先后未逐一核对。

| 现象 | 原因 | 处理 |
|---|---|---|
| 执行 `npx -y claude-mem install --ide opencode --provider claude --no-auto-start`(v15.12.0),腾讯镜像 `https://mirrors.tencent.com/npm/` 对部分包返回 403 报错 | 镜像对部分包拒绝访问 | 不影响安装结果,可忽略 |
| 安装后 worker 在 37701 健康;`/api/projects` 显示来源 `opencode`、项目 `my-note`,提问原文写入 `user_prompts` 表 | 安装器构建的 OpenCode 插件 `plugins/claude-mem.js`(约 500KB)被 OpenCode 自动加载 | 无需处理 |
| 安装器会生成 `opencode.json`,而本机当时用 `opencode.jsonc` | 安装器写死 `opencode.json`,不检查 `.jsonc` | 11-08 当时曾把 claude-mem 的 MCP 并入 `opencode.jsonc` 并移走 `opencode.json`,`opencode mcp list` 显示 9 个 MCP 全部 connected。后来用 `opencode debug config` 验证两文件并存不冲突,本机改为统一 `opencode.json`(`.jsonc` 已并入并删除) |
| 曾尝试把 `plugins/claude-mem.js` 入配置仓库,被工蜂 bugbot 拦下,报压缩文件里重试逻辑判断写反 | 该文件是第三方产物 | 不入库,已写入配置仓库 `.gitignore` |
| 观察者不工作:观察 0 条,队列积压 11 | 找不到 claude 可执行文件 | 改用 `openai-compatible`(见 3.6) |
| 直连 codebuddy 行不通(推断,未实测) | 认证方式和请求头对不上 | 走公司网关(见 3.6) |
| 网关无 key 返回 401 `invalid_api_key` | 未带 key | 带上 key |
| 带 key 不带 `stream` 返回 400 "Non-stream chat request is currently not supported" | 上游只收流式 | claude-mem 默认发流式字段,无需改 |
| 带 `stream:true` 返回 200,流式分片,以 `[DONE]` 结束,约 1.3 秒 | 正常 | 无需处理 |
| 切换后 `/api/health` 的 `ai.provider` 为 `openai-compatible`,`lastInteraction.success=true`;观察者调用 `deepseek-v4.1-flash-ioa`,每次约 3000-7000 token;观察从 0 增长,队列积压归零 | 配置生效 | 无需处理 |
| 切换前积压的 11 条没有补处理,日志为 "Skipped expired live observer inputs; no replay scheduled" | 过期的观察输入被丢弃,不重放 | 提问原文仍在 `user_prompts`,不补处理 |
| `settings.json` 与 `.env` 要进配置仓库管理 | 真文件放仓库,让 `~/.claude-mem/` 下的路径指过去 | `settings.json` 真文件放 `~/.config/opencode/claude-mem/settings.json`,软链回 `~/.claude-mem/settings.json`;`.env` 同样放该目录,软链回 `~/.claude-mem/.env`。仓库是私有仓库,用户确认 `.env` 可入库。重启 worker 后软链的 `.env` 照常被读到(观察继续入库) |
| 日志:tree-sitter CLI 下载校验失败,校验和 `e3b0c442...` 是空文件的哈希 | 下载得到空内容,疑为公司网络或镜像拦截(未证实) | `smart_search`、`smart_outline`、`smart_unfold` 不能解析代码,File Read Gate 保持关闭;不影响记忆读写,暂不处理 |
| 日志:My Work 看板找不到登录的 Claude/Codex/Gemini | 本机没有这些登录 | 与记忆无关,忽略 |
| 重启时日志有"自替换交接超时,回退到命令行启动"告警 | 原因没查 | 重启仍成功,忽略 |
| `CLAUDE_MEM_CLOUD_SYNC_DEVICE_ID` 有值,疑似云同步开关 | 它不是开关:首次启动 worker 时由 `ensureLocalDeviceIdentity` 生成,写回 `settings.json` 和数据库表 `local_work_view_identity`,之后沿用(worker 重启 4 次值不变);两处不一致会报错拒绝写入 | 不用删。云同步是否关闭看 `CLOUD_SYNC_HUB_URL` 是否为空(空即关闭);日志里 `sync.cmem.ai` 出现 0 次 |
| `settings.json` 想写注释说明各键 | 它是标准 JSON(`atomic-json.ts` 用 `JSON.parse`),不能写注释,worker 也会重写它 | 配置仓库 `claude-mem/` 目录放带逐键注释的 `settings.example.jsonc`,worker 不读它 |

---

## 四、装完核对

### 4.1 会被改动/新增的文件清单

**OpenCode 侧**

| 路径 | 动作 |
|---|---|
| `~/.config/opencode/plugins/claude-mem.js` | 新增(拷贝编译好的插件) |
| `~/.config/opencode/opencode.json` | 读取并写入:在 `plugin`(OpenCode v1)或 `plugins` 数组加插件路径;解析到 `mcp-server.cjs` 时注册本地 MCP;文件不存在就新建。本机现已是既有主配置文件,安装器就地改。OpenCode 2 会自己从 `plugins/claude-mem.js` 加载,安装器对 V2 会去掉 config 里的 plugin 条目(因为文件路径会报 "configured plugin path must be a directory") |
| 全局 `AGENTS.md` | 清理旧版本的 claude-mem 记忆块 |

**DSH 侧**(以下是官方安装器会做的事;本机 `desktop` profile 装不了,是手动做的,见 [[claude-mem-跨端共享]] 第 8 节)

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
2. 打开 worker 的网页查看器 `http://127.0.0.1:37701/viewer`,看有没有出现新的观察(observation)。37701 是本机实测的 worker 端口。
   也可以用接口查(均为实测可用,字段含义没有逐项记录):

   | 接口 | 用途 |
   |---|---|
   | `/api/health` | 看 worker 健康;其中 `ai.provider` 应为 `openai-compatible`,`lastInteraction.success` 应为 `true` |
   | `/api/stats` | 看统计数据 |
   | `/api/projects` | 看项目和来源;本机显示来源 `opencode`、项目 `my-note` |
   | `/api/processing-status` | 看观察的处理状态 |

   ```bash
   curl -s http://127.0.0.1:37701/api/health
   ```
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

本机 2026-11-11 从 15.12.1 升到 v15.16.0,实际做法:

```bash
# 升级前备份数据库和配置
cp ~/.claude-mem/claude-mem.db ~/.claude-mem/claude-mem.db.bak
cp ~/.claude-mem/settings.json ~/.claude-mem/settings.json.bak
cp ~/.config/opencode/opencode.json ~/.config/opencode/opencode.json.bak

npx claude-mem@latest install --ide opencode
npx claude-mem@latest restart      # 升级后需重启 worker
npx claude-mem doctor
```

要点:

- 必须单独写 `--ide opencode`:整体跑 `npx claude-mem install` 曾报 `all-ides-failed`,单独指定 `--ide` 可绕过。
- 升级后配置(`settings.json`、`~/.chroma_env`)不会被覆盖。
- 升级后重启 OpenCode,并重新核对 `opencode.json` 有没有被改动。
- 版本记录与逐次升级细节见 [[claude-mem-升级与版本记录]]。
- 旧写法 `npx claude-mem update` 只刷新钩子和依赖,本机升级没有用它。

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

- 本机配置已统一为 `opencode.json`,正是安装器会处理的那份;卸载后核对其中 claude-mem 的 MCP 条目是否已清掉(是否清干净没实测)。
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
| 装完 OpenCode 配置异常 | 安装器改了 `opencode.json`(加 MCP 条目,V2 下还会去掉 plugin 条目);`opencode.json` 与 `opencode.jsonc` 并存不会冲突(V2 实测) | 按 3.0 节核对 `opencode.json`,必要时用 `.bak` 恢复 |
| 中文查不到语义相近的笔记 | 向量嵌入默认是英文模型 | 关键词检索(中文子串匹配)可用,语义检索偏弱,属推测,要实测;详见 [[claude-mem-深入调研]] |
| 笔记重复出现在会话里 | opencode-mem 没停 | 回到 2.3 节暂停它 |

---

## 六、没读到/不确定清单

1. **`CLAUDE_MEM_ONLINE_OPTIN=false` 是否有效**:源码中没找到处理该变量的逻辑,**未证实有效**,与旧笔记结论冲突。
2. **非交互安装的细节**:`--provider openrouter` 非交互时是否还要额外参数,**未验证**;"需要 API key 或 `--provider claude`"是源码推断。
3. **不登录时安装器会不会因联网失败而中断**:**未验证**,更新日志的说法可能只针对 cmem 提供方。
4. **DSH 侧**:没看到直接操作 `cordis.patch.yml`,而是委托 `dsh plugin ... add`;DSH 最终改了哪些文件,没读到。旧笔记的说法不采用。**2026-11-09 实测:对 `desktop` profile,`dsh plugin` 被 `dsh` 命令行写死拒绝(`bin.js:36`),安装器必败;本机改为手动加插件依赖和监听文件,见 [[claude-mem-跨端共享]] 第 8 节。**
5. **`host` 提供方**:已读源码确认它依赖本机已在运行的兼容服务,装不上就报错;但 OpenCode、DSH 上有没有现成组件充当这个服务,没读到,只能说大概率没有。
6. **直连 codebuddy 是否 401/403**:只是据插件源码的推断,**未实测**。
7. **观察者发给网关的请求包是否已脱敏**:没抓包,**未证实**。
8. **两端项目名是否一致**:OpenCode 端是 `my-note`;**已实测**:DSH 在 `my-note` 目录开,项目名也是 `my-note`;DSH 写入的来源名是 `dsh`(见 [[claude-mem-跨端共享]] 第 8 节)。
9. **网页保存设置后软链是否保持**:据 `atomic-json` 只读推断,**未验证**。
10. **tree-sitter 下载得到空内容的原因**:疑为公司网络或镜像拦截,**未证实**;"自替换交接超时"告警的原因没查。
11. **日志文件位置**:没记录。worker 端口键已确认是 `CLAUDE_MEM_WORKER_PORT`,默认 `37700 + (uid % 100)`。
12. **`repair`、`prune`、`search`、`teambrain` 等命令的细节参数**:没读到;`install`/`restart`/`restore`/`search`/`start`/`status`/`stop`/`uninstall`/`update` 在源码命令分支中存在,具体参数未读。
13. **卸载是否清理 DSH 侧 profile 里的插件**:没读到。
14. **匿名统计具体发什么**:没读。

---

## 相关笔记

- [[claude-mem-深入调研]]:优势、代价、云端外发路径、检索机制
- [[OpenCode与DSH共享记忆-选型调研]]:为什么选它
- [[claude-mem-配置详解]]:settings.json 各键
- [[claude-mem-存储与读取机制]]:数据怎么存、怎么取
- [[claude-mem-跨端共享]]:OpenCode 与 DSH 如何共享
