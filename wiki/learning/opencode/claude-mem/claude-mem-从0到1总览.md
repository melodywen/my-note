---
type: concept
status: developing
area: growth
title: "claude-mem 从 0 到 1:让 OpenCode 和 DSH 共用一份本地长期记忆"
created: 2026-11-09
updated: 2026-11-09
tags:
  - learning
  - opencode
  - dsh
  - claude-mem
  - 总览
  - 复现
related:
  - "[[claude-mem-安装部署]]"
  - "[[claude-mem-调教清单]]"
  - "[[claude-mem-配置详解]]"
  - "[[claude-mem-本地多语言向量方案]]"
  - "[[claude-mem-跨端共享]]"
  - "[[claude-mem-存储与读取机制]]"
  - "[[claude-mem-网页后台使用指南]]"
  - "[[claude-mem-深入调研]]"
---

# claude-mem 从 0 到 1:让 OpenCode 和 DSH 共用一份本地长期记忆

> 一句话:**一个本机常驻进程(worker)把两个编码工具的对话提炼成"观察",存进同一个本地数据库;下次开会话时再把相关记忆塞回去。**
>
> 这篇是总览,按"我怎么一步步做出来"的顺序写,照着能复现。每一步只讲做什么、怎么验、踩过什么坑;原理和全部细节在其他 7 篇里,这里用链接指过去,不重复。
>
> 依据:2026-11-08 到 11-09 在本机(macOS、M4 Pro、48GB)的实际操作和实测,claude-mem 15.12.0 升到 15.12.1。凡是只读了源码没实测的,正文里标了"未证实"。

---

## 目录

| 节   | 内容                           |
| --- | ---------------------------- |
| 0   | 最终长什么样(先看结果)                 |
| 1   | 开始前:这是什么、要准备什么               |
| 2   | 第 1 步:只装 OpenCode 端          |
| 3   | 第 2 步:换掉观察者(公司网关 + 中文)       |
| 4   | 第 3 步:隐私与采集                  |
| 5   | 第 4 步:中文搜得准(Ollama + bge-m3) |
| 6   | 第 5 步:接上 DSH,两端共用            |
| 7   | 第 6 步:配置进仓库管理                |
| 8   | 复现清单(一页版)                    |
| 9   | 验收:怎么证明真的通了                  |
| 10  | 踩过的坑                         |
| 11  | 现状边界与没解决的问题                  |
| 12  | 附:一路上的时间线                    |

---

## 0. 最终长什么样

```
OpenCode ──插件(钩子)──┐
                         ├──> worker(127.0.0.1:37701)──> SQLite 数据库 + 向量库(Chroma)
DSH ──会话日志文件─────┘            │                          ▲
        (worker 监听 ~/.dsh/sessions)  │                          │
                                       ├─ 观察者:公司网关上的 deepseek-v4.1-flash
                                       └─ 向量:本机 Ollama 的 bge-m3(1024 维)
DSH ←──插件(只负责读)── worker
```

| 项 | 最终状态 |
|---|---|
| 数据库 | `~/.claude-mem/claude-mem.db`,2026-11-09 下午实测 619 条观察、122 条摘要、208 条提问(会随使用增长) |
| 来源 | `opencode` 13 个会话、`dsh` 4 个、`claude` 1 个(`sdk_sessions.platform_source`) |
| worker | 15.12.1,端口 37701(默认端口按用户 uid 算,别人机器上不一定是这个) |
| 观察者 | `openai-compatible` 提供方,走公司网关,模型 `deepseek-v4.1-flash`,中文输出 |
| 向量 | 本机 Ollama 的 `bge-m3`,1024 维 |
| 隐私 | 入库前脱敏、不存图、云同步和托管记忆全关 |
| 配置位置 | 真文件在 `~/.config/opencode/claude-mem/`,软链回 `~/.claude-mem/`,进私有 git 仓库 |
| 配置键数 | `settings.json` 共 23 个键 |

---

## 1. 开始前

### 1.1 先搞清几个词

| 词 | 白话 |
|---|---|
| claude-mem | 给编码 agent 加"长期记忆"的开源工具。它记的不是聊天原文,而是 AI 提炼后的短条目 |
| worker | claude-mem 在本机常驻的后台进程。所有端都往它发数据、从它取记忆 |
| 观察(observation) | 一条记忆。每次工具调用后,由"观察者"AI 提炼出一条标题 + 要点 |
| 观察者 | 负责提炼观察的那个 AI 模型。**每次工具调用都会调用它,把对话原文发给它,所以要选便宜的、可信的** |
| 钩子 / 插件 | OpenCode 端靠插件在"工具跑完""用户发言"等时刻通知 worker |
| 嵌入模型 / 向量 | 把文字变成一串数字,用来按"意思"搜索。默认模型是英文的,中文搜不准 |
| Chroma | claude-mem 用的向量数据库,由一个叫 chroma-mcp 的子进程管理 |
| 来源(platform source) | 每条记忆的标签:`opencode`、`dsh`、`claude` |

### 1.2 要准备的

| 东西 | 要求 | 怎么查 |
|---|---|---|
| Node | 20.19+ 或 22.12+(本机 24) | `node -v` |
| Bun、uv | 缺了安装器会自动装 | `bun -v`、`uv --version` |
| OpenCode | 已能正常用 | `opencode --version` |
| 一个观察者模型的访问方式 | 见 1.3 | |
| Ollama | 第 4 步才需要 | `ollama --version` |
| DSH + pnpm | 第 5 步才需要 | `which dsh`、`pnpm -v` |

### 1.3 先决定:观察者用谁

这是整件事里最该先想清楚的一个决定,因为它每次工具调用都会跑,持续花钱,并且会把对话内容发出去。

| 选项 | 要不要 key | 注意 |
|---|---|---|
| `claude` / `codex` | 用本机已登录的 CLI | 本机没登录就不能用 |
| `gemini` / `openrouter` | 要 | **交互安装会引导你去浏览器登录 cmem.ai**(作者的托管服务) |
| `openai-compatible` | 要 | 安装器没有它的流程,**不会弹登录**;装完手改配置。适合接公司网关 |
| `host` | 不要 | 要求本机已有现成兼容服务,不适合普通用户 |

我选的是 **`openai-compatible` 接公司网关**。为什么不直连 codebuddy:它的认证是浏览器 OAuth + 约 25 个租户头,claude-mem 只能发一个固定 key,对不上(推断,未实测),所以用一个会替你持有 codebuddy 凭证的 OpenAI 兼容网关。细节见 [[claude-mem-安装部署]] 3.6。

> 如果你没有这样的网关:最省事是本机有 Claude Code 就用 `claude`;或者用 `openrouter` 自带 key。这两条我没在本机走通过,不保证。

---

## 2. 第 1 步:只装 OpenCode 端

**先备份**(安装器会改配置):

```bash
cp ~/.config/opencode/opencode.jsonc ~/.config/opencode/opencode.jsonc.bak
cp -r ~/.config/opencode/plugins ~/.config/opencode/plugins.bak
```

**如果你装过别的记忆插件**(我之前装过 opencode-mem),先停掉:两个并存会重复注入上下文。

**安装**(首次用 `claude` 提供方,不触发 cmem.ai 登录,稍后改):

```bash
npx claude-mem install --ide opencode --provider claude
npx claude-mem telemetry disable      # 关匿名统计
npx claude-mem doctor                 # 体检
```

我的实测:

| 现象 | 说明 |
|---|---|
| 腾讯 npm 镜像对个别包报 403 | 不影响结果,忽略 |
| worker 在 37701 起来,`/api/projects` 出现来源 `opencode` | 说明插件被自动加载并写入成功 |
| 观察 0 条,队列积压 | 因为本机没有 claude,观察者不工作。**预期内**,下一步就换掉 |

### 2.1 一个必须处理的坑:`opencode.json` 与 `opencode.jsonc`

安装器只读写 `opencode.json`,不认 `opencode.jsonc`。如果你和我一样用的是 `.jsonc`,装完会**另生成一个 `opencode.json`**。

我的做法:

1. 看新生成的 `opencode.json` 里写了什么(主要是 claude-mem 的 MCP 配置)。
2. 把那段 MCP 并进自己的 `opencode.jsonc`:

```jsonc
"mcp": {
  "claude-mem": {
    "type": "local",
    "command": [
      "<node 的绝对路径>",
      "<家目录>/.claude/plugins/marketplaces/thedotmack/plugin/scripts/mcp-server.cjs"
    ]
  }
}
```

3. 把 `opencode.json` 移走备份,重启 OpenCode,`opencode mcp list` 确认全部 connected。

### 2.2 另一个坑:`claude-mem.js` 不要入库

`~/.config/opencode/plugins/claude-mem.js` 是安装器构建出来的约 500KB 产物。我试过把它放进配置仓库,被代码平台的自动审查拦下(它扫的是压缩后的第三方代码)。结论:**加进 `.gitignore`,不入库**。

---

## 3. 第 2 步:换掉观察者(公司网关 + 中文)

装完后观察者不工作,改 `~/.claude-mem/settings.json` 的 5 个键:

| 键 | 值 |
|---|---|
| `CLAUDE_MEM_PROVIDER` | `openai-compatible` |
| `CLAUDE_MEM_OPENAI_COMPAT_PRESET` | `custom` |
| `CLAUDE_MEM_OPENAI_COMPAT_BASE_URL` | `<你的网关地址>/v1` |
| `CLAUDE_MEM_OPENAI_COMPAT_MODEL` | `deepseek-v4.1-flash`(每条对话都调用,选便宜快的) |
| `CLAUDE_MEM_MODE` | `code--zh`(官方中文模式,只让观察用中文写) |

**密钥不写进 `settings.json`**(它要进 git),放 `~/.claude-mem/.env`:

```text
OPENAI_COMPAT_API_KEY=<你的 key>
```

然后重启 worker:

```bash
npx claude-mem restart
```

要点:

- `BASE_URL` 只写到 `/v1`,claude-mem 自己补 `/chat/completions`。
- 网关上游只收流式请求,claude-mem 默认就发流式,不用改。
- 我的网关是**测试环境**域名,观察者每次都会把对话原文发过去。这点要自己评估能不能接受。

**验收**:

```bash
curl -s http://127.0.0.1:37701/api/health      # ai.provider 应为 openai-compatible
```

实测切换后 `lastInteraction.success=true`,观察数从 0 开始增长,队列积压归零。切换前积压的 11 条没有补处理(过期的观察输入被丢弃,不重放),但提问原文仍在 `user_prompts`。

---

## 4. 第 3 步:隐私与采集

这一步是"先把不该发的堵住"。我改了 7 个隐私键、6 个采集键(只有一个真正有效)。

### 4.1 隐私(第 2 轮)

| 键 | 值 | 作用 |
|---|---|---|
| `CLAUDE_MEM_REDACT_ENABLED` | `true` | 入库前把已识别的密钥换成 `<redacted/>`,内置约 35 条规则,**拦不住自然语言里的机密** |
| `CLAUDE_MEM_REDACT_GENERIC_ENABLED` | `true` | 再加 4 条无前缀规则:`password=`、`*_TOKEN=`、`Bearer` 等,低置信度会误伤 |
| `CLAUDE_MEM_MEDIA_CAPTURE_ENABLED` | `false` | 默认把截图存本机且无总量上限,这里关 |
| `CLAUDE_MEM_TELEGRAM_ENABLED` | `false` | 没填 bot token 本来就不发,关了图安心 |
| `CLAUDE_MEM_CLOUD_SYNC_HUB_URL`、`_TOKEN`、`_USER_ID` | 全部留空 | **必须为空**,空即关闭云同步 |
| `CLAUDE_MEM_PRO_MEMORY_KEY`、`_BASE_URL`、`_MODEL` | 全部留空 | **必须为空**,填了 KEY 观察内容会交给云端模型 |

`CLAUDE_MEM_CLOUD_SYNC_DEVICE_ID` 有值是正常的:首次启动自动生成的本机标识,**不是云同步开关**。别删,和数据库不一致会报错。

### 4.2 采集(第 3 轮)

只有 `CLAUDE_MEM_SKIP_TOOLS` 在 OpenCode 下真正有效:跳过低价值工具,少调观察者、少噪音。我在出厂默认的 5 个后面,按近 30 天实际调用追加了 9 个:

```text
ListMcpResourcesTool,SlashCommand,Skill,TodoWrite,AskUserQuestion,
glob,question,session_search,lsp_prepare_rename,lsp_diagnostics,
background_cancel,invalid,zhiyan-log_GetCurrentTimestamp,iWiki_prepareAttachmentUpload
```

OpenCode 的工具名是小写,`SKIP_TOOLS` 不分大小写,实测有效。**注意:这份名单是我的工具集决定的,你要按自己的调用情况选。**

其余 5 个采集键在 OpenCode 下无效或暂时不需要,没改。详见 [[claude-mem-调教清单]] 第 2、3 轮。

### 4.3 注入与检索(第 4、5 轮)

- 第 4 轮"开会话时塞多少旧记忆":测过,**保持默认,一个键都没改**。
- 第 5 轮:只改了一个键 `CLAUDE_MEM_SEARCH_RECENCY_DAYS = "0"`。默认 90 天窗口会让不带日期的语义搜索看不到 90 天前的记忆;`0` 表示不设窗口。

---

## 5. 第 4 步:中文搜得准(Ollama + bge-m3)

### 5.1 问题

默认嵌入模型 `all-MiniLM-L6-v2` 只有英文词表,中文被切成单字或未知符。实测(旧库):中文问中文名次不稳,中文问英文记忆基本垫底。

### 5.2 为什么不能"改个配置换模型"

| 配置键 | 实测 |
|---|---|
| `CLAUDE_MEM_EMBEDDING_MODEL` | 改什么都不报错、也不生效,只有服务器模式(Postgres)读它 |
| `CLAUDE_MEM_CHROMA_EMBEDDING_FUNCTION` | 真正生效的键,但白名单只有 `default / openai / cohere / jina / voyageai / roboflow`。写白名单外的值,**运行中不报错,重启 worker 才报错** |

白名单里除 `default` 外全是云端接口(会把记忆文本发给第三方)。其中 `openai` 可以指向本机服务,这是突破口。

### 5.3 做法(原理见 [[claude-mem-本地多语言向量方案]] 第四节)

**1)装 Ollama 并拉模型**

```bash
ollama pull bge-m3
ollama cp bge-m3 text-embedding-ada-002     # 别名,下面解释
```

**2)写 `~/.chroma_env`**(chroma-mcp 子进程自己读这个文件,不是 claude-mem 的 `.env`):

```text
OPENAI_API_KEY=<任意非空字符串>
OPENAI_BASE_URL=http://127.0.0.1:11434/v1
```

**3)`settings.json` 改一个键**:

```json
"CLAUDE_MEM_CHROMA_EMBEDDING_FUNCTION": "openai"
```

**4)重启 worker,整库回填**(我的库约 70 到 90 秒,期间搜索不可用)。

### 5.4 这条路为什么走得通

1. chroma-mcp 创建集合时用**无参**方式构造嵌入函数,所以不能在配置里传模型名或地址。
2. 无参的 `OpenAIEmbeddingFunction` 模型名默认是 `text-embedding-ada-002`,地址由底层 openai 库读环境变量 `OPENAI_BASE_URL`。
3. chroma-mcp 启动时读 `.chroma_env`。claude-mem 启动它时工作目录是家目录,所以实际读的是 `~/.chroma_env`。
4. Ollama 的 `/v1/embeddings` 兼容 OpenAI 格式,所以能接上。
5. Ollama 里没有叫 `text-embedding-ada-002` 的模型,请求会 404,所以用 `ollama cp` 起别名。**这个别名不能删。**
6. claude-mem 自己的 `.env` 只放行 11 个凭据键,`OPENAI_BASE_URL` 会被丢弃,所以必须放 `.chroma_env`。

### 5.5 效果(诚实版)

30 条手工标准答案的验收(中问中 20 条、英问中 10 条):

| 方向 | 模型 | 第 1 名对 | 前 3 名有对的 | 前 6 名有对的 |
|---|---|---|---|---|
| 中问中 | 默认 MiniLM | 4 | 5 | 8 |
| 中问中 | bge-m3 | 8 | 12 | 17 |
| 英问中 | 默认 MiniLM | 5 | 5 | 7 |
| 英问中 | bge-m3 | 3 | 7 | 8 |

**结论:中问中从"基本不可用"变成"勉强可用";英问中没有变好;不能说达标。** 这 30 条问题和标准答案是我设计的,不是你真实会问的,样本也小。更大批量压测和更大模型(8B)的对比见向量方案 5.5、5.6:换更大模型没有明显收益,当前不换。

### 5.6 风险

- `.chroma_env` 是 chroma-mcp 0.2.6 自带的行为,**不是 claude-mem 官方支持的配置**。升级后若 chroma-mcp 版本变了可能失效(失效时向量写入失败,SQLite 里的记忆不丢)。
- Ollama 变成常驻依赖;没开时新记忆写不进向量库,恢复后会补(断 Ollama 场景没专门测)。
- 旧 384 维向量留在 `~/.claude-mem/chroma.old-384`,确认稳定后可删。

---

## 6. 第 5 步:接上 DSH,两端共用

### 6.1 DSH 这一端怎么接的

| 方向 | 做法 |
|---|---|
| **写**(DSH 的对话进库) | worker **监听** `~/.dsh/sessions` 下的会话日志(`.jsonl.zstd`),按 schema 解析出提问、回答、工具调用,来源标为 `dsh` |
| **读**(DSH 取记忆) | DSH 插件 `@claude-mem/dsh`,配置 `injectContext: true`、`ingest: false`、`summarize: false`,**只负责注入,不负责写** |

### 6.2 官方安装器对 `desktop` 必败,手动做

官方命令 `npx claude-mem install --ide dsh --dsh-profile <名字>` 会调 `dsh plugin --profile <名字> add`。但 `dsh` 把 `desktop` 这个名字写死拒绝(`@deepseek-ai/dsh/lib/bin.js` 第 36 行),报 `profile "desktop" is managed exclusively by the Electron application`。**按名字判断,与桌面应用是否在运行无关。**

> 副作用:安装器失败前已经把 claude-mem 本体从 15.12.0 升到 15.12.1 并停了 worker。别对 `desktop` 反复跑。升级后手动拉起:`bun ~/.claude/plugins/cache/thedotmack/claude-mem/<版本>/scripts/worker-service.cjs start`。

如果你的 profile 不是 `desktop`(例如 `web`),可以直接用官方命令:

```bash
npx claude-mem install --ide dsh --dsh-profile <名字> --runtime worker
```

DSH 目前必须用 `--runtime worker`,不能用 server 模式。

### 6.3 手动做法(等价于安装器干的两件事)

**A. 读:让 DSH 加载插件**

1. 把插件包复制进 DSH 配置仓库,例如 `plugins/claude-mem-dsh/`。来源是 `~/.claude/plugins/marketplaces/thedotmack/dsh/`。
2. 在 profile 的 `package.json` 里:

```json
{
  "dependencies": {
    "@claude-mem/dsh": "link:../plugins/claude-mem-dsh"
  },
  "dsh": {
    "profile": {
      "bundles": [ "...原有的...", "@claude-mem/dsh" ]
    }
  }
}
```

3. `pnpm install`,重启 DSH。

这份是**复制品**,claude-mem 升级后不会自动更新。想自动跟随可以把 `link:` 改成指向 `~/.claude/plugins/marketplaces/thedotmack/dsh` 的绝对路径;代价是换机器会失效。我没采用。

**B. 写:让 worker 采集 DSH 会话**

新建 `~/.claude-mem/transcript-watch.json`,核心是一条 `watches`:

```json
{
  "version": 1,
  "schemas": { "dsh": { "...内嵌 transcript-schema.json 的内容..." } },
  "watches": [
    {
      "name": "dsh",
      "path": "<家目录>/.dsh/sessions",
      "schema": "dsh",
      "startAtEnd": true,
      "managedBy": "claude-mem"
    }
  ],
  "stateFile": "<家目录>/.claude-mem/transcript-watch-state.json"
}
```

要点:

- `schema` 内容照抄 `~/.claude/plugins/marketplaces/thedotmack/dsh/transcript-schema.json`,不要自己编。
- 监听名 `dsh` 就是写入时的"来源"。
- `startAtEnd: true` 表示只采集启动之后的新内容,不回灌历史会话。
- 这个文件里没有密钥。
- 改完重启 worker,看日志里有 `Watching transcript file ... .dsh/sessions/...`。

**C. 放开来源过滤**

默认 OpenCode 只会看到 `opencode` 来源的记忆。`settings.json` 加一个键:

```json
"CLAUDE_MEM_SESSION_START_INCLUDE_ALL_SOURCES": "true"
```

OpenCode 插件每次请求都重读这个文件,改完不用重启 OpenCode。DSH 要重启才会重新取。

### 6.4 两端要互通的三道关卡

| 关卡 | 检查点 | 怎么确认 |
|---|---|---|
| 项目名一致 | 默认用 **git 仓库根目录的文件夹名**。两端在同一个仓库启动才一致 | 网页或 `/api/projects` 看两端项目名 |
| 来源过滤放开 | `SESSION_START_INCLUDE_ALL_SOURCES=true` | 见 6.3 C |
| 两端都接上、同一个 worker | 监听条目存在、DSH 插件在 bundles 里、端口一致 | 日志、`/api/projects` |

项目名的坑:

| 情况 | 结果 |
|---|---|
| 两端在同一个 git 仓库里启动 | 一致,能共享 |
| 两个不同仓库恰好同名 | 记忆混在一起 |
| 一端在仓库外 | 项目名可能不同,互相看不到 |
| 仓库目录改名 | 项目名跟着变,旧记忆对不上 |

实测:在 `~/ai-work/my-note` 开 DSH,项目是 `my-note`;在 `~/.config/opencode` 开,项目是 `opencode`。

---

## 7. 第 6 步:配置进仓库管理

目标:换机器、改坏了能还原。

```
~/.config/opencode/claude-mem/              (配置仓库里,真文件)
├── settings.json            ← 软链到 ~/.claude-mem/settings.json
├── .env                     ← 软链到 ~/.claude-mem/.env
├── chroma_env               ← 软链到 ~/.chroma_env
├── transcript-watch.json    ← 软链到 ~/.claude-mem/transcript-watch.json
└── settings.example.jsonc   ← 带逐键注释的说明,worker 不读
```

要点:

- `settings.json` 是标准 JSON,**不能写注释**,worker 也会重写它。所以注释放 `settings.example.jsonc`,改了真文件要同步改它。
- `.env`、`chroma_env` 含密钥:仓库必须是**私有**的。提交前先单独跑一遍密钥扫描,确认没有真实 key 的值再提交推送。
- `claude-mem.js` 不入库(见 2.2)。
- 软链是否会被 worker 或网页保存操作覆盖成普通文件:**网页保存是否保持软链,未实测**。

---

## 8. 复现清单(一页版)

> 假设你和我一样:macOS、用 OpenCode、有一个 OpenAI 兼容的观察者端点、想接 DSH 且 profile 是 `desktop`。条件不同的地方会写明。

```text
[ ] 0. node -v 达标;备份 opencode.jsonc 和 plugins/
[ ] 1. 停掉其他记忆插件(如 opencode-mem)
[ ] 2. npx claude-mem install --ide opencode --provider claude
[ ] 3. npx claude-mem telemetry disable
[ ] 4. 若生成了 opencode.json:把 claude-mem 的 mcp 并入 opencode.jsonc,
       移走 opencode.json,重启 OpenCode,opencode mcp list 全部 connected
[ ] 5. ~/.claude-mem/.env 写 OPENAI_COMPAT_API_KEY=<key>
[ ] 6. settings.json 设观察者 5 键(PROVIDER/PRESET/BASE_URL/MODEL/MODE)
[ ] 7. settings.json 设隐私键(REDACT x2、MEDIA_CAPTURE=false、TELEGRAM=false)
        + 云同步、托管记忆相关键保持为空
[ ] 8. settings.json 设 SKIP_TOOLS(按自己的工具集)与 SEARCH_RECENCY_DAYS="0"
[ ] 9. npx claude-mem restart;curl 127.0.0.1:<端口>/api/health
        看 ai.provider = openai-compatible
[ ] 10. 在 OpenCode 里干点活,确认观察数在增长、观察是中文
[ ] 11. ollama pull bge-m3;ollama cp bge-m3 text-embedding-ada-002
[ ] 12. 写 ~/.chroma_env(OPENAI_API_KEY 非空任意值 + OPENAI_BASE_URL=http://127.0.0.1:11434/v1)
[ ] 13. settings.json 设 CHROMA_EMBEDDING_FUNCTION="openai";重启 worker;等回填完成
[ ] 14. DSH:复制插件包到配置仓库,package.json 加依赖和 bundles,pnpm install
[ ] 15. 新建 ~/.claude-mem/transcript-watch.json(监听 ~/.dsh/sessions)
[ ] 16. settings.json 设 SESSION_START_INCLUDE_ALL_SOURCES="true"
[ ] 17. 重启 worker 与 DSH
[ ] 18. 按第 9 节做验收
[ ] 19. 配置进私有仓库,软链回 ~/.claude-mem/;提交前跑密钥扫描
```

不同条件下的调整:

| 你的情况 | 要改的地方 |
|---|---|
| 没有 DSH | 做到第 13 步即可 |
| DSH profile 不是 `desktop` | 第 14 到 15 步可直接用官方命令 |
| 没有公司网关 | 第 5、6 步换成你自己的提供方(见 1.3) |
| Linux / Windows | Ollama、路径、软链写法不同,我没在这些系统上试过 |
| 库里已有很多旧记忆 | 第 13 步回填时间会更长;旧英文记忆不会自动改成中文 |

---

## 9. 验收:怎么证明真的通了

每一项都有"期望结果",没有期望结果的"通过"没有意义。

| # | 验什么 | 怎么验 | 期望 |
|---|---|---|---|
| 1 | worker 正常 | `curl http://127.0.0.1:37701/api/health` | `status=ok`,`ai.provider=openai-compatible` |
| 2 | 观察者通 | 在 OpenCode 里让它读文件、跑命令,几分钟后看观察数 | 观察数增长,标题是中文 |
| 3 | 向量用上 bge-m3 | 看向量集合维度 | 1024(不是 384) |
| 4 | 中文能搜到 | `GET /api/search?query=<中文关键词>&limit=10&format=json&type=observations` | 相关观察排在前几 |
| 5 | DSH 被采集 | 在 DSH 里提问并让它调一次工具,看会话来源 | 库里出现 `platform_source=dsh` 的会话,且有观察 |
| 6 | OpenCode 能搜到 DSH 写的 | 在 OpenCode 搜 DSH 里干过的事 | DSH 写的观察出现在前几名(实测通) |
| 7 | DSH 启动时读到 OpenCode 写的 | 新开 DSH 会话,问它"启动时注入了什么记忆" | 它能说出来自 OpenCode 的内容(实测通) |
| 8 | DSH 主动搜到 OpenCode 写的 | 在 DSH 里让它搜一个 OpenCode 里做过的主题 | 调 `mem_search`,结果含 OpenCode 写的观察(实测通) |
| 9 | 隐私 | 看配置里 `BASE_URL` | 不含 `cmem.ai`;云同步和托管记忆相关键为空 |

查来源的 SQL(只读):

```bash
sqlite3 -readonly ~/.claude-mem/claude-mem.db \
  "select platform_source,count(*) from sdk_sessions group by 1"
```

---

## 10. 踩过的坑

| 坑 | 现象 | 原因 / 处理 |
|---|---|---|
| 安装器另生成 `opencode.json` | 与 `opencode.jsonc` 并存 | 见 2.1,手工合并后移走 |
| 观察者一直不工作 | 观察 0 条、队列积压 | 默认走 `claude`,本机没登录。换 `openai-compatible` |
| 直连 codebuddy 不行 | 认证和请求头对不上(推断) | 走公司网关 |
| 切换观察者后旧积压没补 | 日志 "Skipped expired live observer inputs" | 过期输入不重放;提问原文仍在 `user_prompts` |
| 改 `EMBEDDING_FUNCTION` 为白名单外的值 | 运行中不报错,重启后全部回填失败 | 只用 `default`/`openai`;见 5.2 |
| `OPENAI_BASE_URL` 写进 claude-mem 的 `.env` 无效 | 向量请求仍去官方 OpenAI | 它只放行 11 个凭据键;要写在 `~/.chroma_env` |
| Ollama 报 404 | 找不到 `text-embedding-ada-002` | `ollama cp` 起别名,且不能删 |
| DSH 官方安装器对 `desktop` 失败 | `rejectElectronProfile` | 手动做(6.3);且别反复跑,它会先把本体升级并停 worker |
| 升级后 `restart` 报校验失败 | 用了旧版本路径 | 实际已起;确认后可用新版本路径 `worker-service.cjs start` |
| `claude-mem.js` 入库被拦 | 自动审查报压缩代码问题 | 加 `.gitignore`,不入库 |
| `SESSION_START_INCLUDE_ALL_SOURCES` 改了没效果 | OpenCode 看不到 DSH 的 | 先查 worker 是不是同一个、再查项目名是否一致 |
| DSH 那一轮没有摘要 | 日志 `Missing last_assistant_message` | 是那一轮 DSH 模型返回 401,没有回答;与 claude-mem 无关 |
| 日志 tree-sitter CLI 下载校验失败 | 校验和是空文件的哈希 | 疑为公司网络拦截(未证实);只影响代码解析类工具,不影响记忆读写 |
| My Work 页面一直空 | `waiting-for-agent` | 见第 11 节 |

---

## 11. 现状边界与没解决的问题

### 11.1 My Work 页面(`/?view=rules` 等)是空的

- 原因:My Work 的规则、目标、进度要靠 claude-mem 调用本机**已登录的 Claude Code、Codex 或 Gemini** 来生成。OpenCode、DSH 都不在这三种之内,所以永远是 `waiting-for-agent`。
- 不影响记忆的写入、搜索、注入。
- 已向上游提了 issue:<https://github.com/thedotmack/claude-mem/issues/5535>(2026-11-09)。尚无回复,不知道会不会被采纳。
- 登录三种 agent 之一后是否真的能生成规则:读源码得出,**未实测**。

### 11.2 记忆不会自动去矛盾

- 源码里没有对已存观察做矛盾检测、失效或合并的代码(我在 `src` 下搜了 `supersed/contradict/dream/consolidat` 等关键词,命中的 60 处全是"生成作业被取代""进程登记被取代"之类,和记忆整合无关)。
- 后果:库里互相矛盾的结论不会自己消失,只能靠后来的观察覆盖,或人工订正。旧的英文记忆、过时的调教说法就是实例。
- 上游有个提案 issue #1792(Dream Cycle:worker 内定时聚类、重写汇总、清过时),**仅是提案,没有实现**。我这轮没有重新核对它当前状态。
- Anthropic 自己的 Dreams 是 Managed Agents 平台的独立功能,不是 claude-mem 的一部分。

### 11.3 其他没验证的

| 项 | 状态 |
|---|---|
| 发给观察者的请求是否已脱敏 | 没抓包验证 |
| 网页保存配置是否保持软链 | 没测 |
| `SEMANTIC_INJECT` 在 OpenCode 下是否生效 | 读源码推断多半不生效,没实测 |
| `claude_mem_search` 的返回条数 | 固定 10 条,插件侧写死,不可配 |
| `CLAUDE_MEM_ONLINE_OPTIN=false` 是否能避免联网登录 | 源码里没找到处理逻辑,未证实有效 |
| `--provider claude` 在没登录 Claude 的机器上能否装完 | 我用过,有效,但没专门验证它不联网 |
| Ollama 长期运行的内存、稳定性 | 没测 |
| 库扩大到几千条后的检索表现 | 没测 |
| DSH 官方有没有给桌面版装插件的正规入口 | 没查 |

### 11.4 我没有处理、你装的时候要自己决定的

| 项 | 说明 |
|---|---|
| 运维类(备份、日志保留) | `BACKUP_ENABLED` 默认关。想要快照要自己开,见 [[claude-mem-调教清单]] 第 7 轮(我没做) |
| 旧向量目录 | `chroma.old-384` 何时删 |
| 旧英文记忆、测试过程记录 | 要不要清理 |
| `WORK_STATE_ENABLED`、`WORK_VIEW_AUTO_REFRESH` | 要不要关,见 11.1 |

---

## 12. 附:一路上的时间线

| 时间 | 做了什么 |
|---|---|
| 11-08 上午 | 调研并选定 claude-mem;读源码、写安装部署文档;装 OpenCode 端 |
| 11-08 | 发现观察者不工作;读 codebuddy 认证源码;改走公司网关(`openai-compatible`)、`MODE=code--zh` |
| 11-08 | 第 2 轮隐私、第 3 轮采集;配置进仓库、做 `settings.example.jsonc` |
| 11-08 下午 | 第 4 轮注入(保持默认);第 5 轮检索窗口改 0 |
| 11-08 傍晚 | 中文检索不好用;读 chroma-mcp 源码,找到 `.chroma_env` 这条路;Ollama + bge-m3 上线、整库回填;30 条验收,结论"及格非达标" |
| 11-08 晚 | 多模型对比、大批量压测:结论是当前不换模型 |
| 11-09 上午 | 第 6 轮:接 DSH。官方安装器对 `desktop` 必败;手动加插件、加监听;worker 升到 15.12.1 |
| 11-09 | 三个方向实测:DSH 写、OpenCode 搜到;DSH 启动注入;DSH `mem_search` 搜到 OpenCode 记忆 |
| 11-09 下午 | 订正文档里已被实测推翻或证实的旧"未实测"说法;查清 `Missing last_assistant_message` 与 My Work 空页面的成因;向上游提交 #5535 |

---

## 13. 读哪篇

| 想了解 | 读 |
|---|---|
| 完整安装步骤、故障表、卸载 | [[claude-mem-安装部署]] |
| 每一个配置键是什么意思 | [[claude-mem-配置详解]] |
| 每个键我是怎么决定改不改的 | [[claude-mem-调教清单]] |
| Ollama + bge-m3 的原理、验收、对比 | [[claude-mem-本地多语言向量方案]] |
| 两端共用的原理与三道关卡 | [[claude-mem-跨端共享]] |
| 数据存在哪、怎么读出来 | [[claude-mem-存储与读取机制]] |
| 网页后台怎么看 | [[claude-mem-网页后台使用指南]] |
| 它和其他记忆方案比 | [[claude-mem-深入调研]] |
