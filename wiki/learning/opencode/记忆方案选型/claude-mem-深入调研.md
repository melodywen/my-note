---
type: concept
status: developing
area: growth
title: "claude-mem 深入调研"
created: 2026-11-08
updated: 2026-11-08
tags:
  - learning
  - opencode
  - dsh
  - claude-mem
  - 记忆插件
  - 隐私
related:
  - "[[OpenCode与DSH共享记忆-选型调研]]"
  - "[[opencode-mem-调研与上手指南]]"
---
d
dd深入调研

> 一句话:**claude-mem 靠 hook 自动抓取每次工具调用,交给观察者模型写笔记,本机存 SQLite + Chroma。本地版核心能力没被剪裁,但安装时必须主动避开云登录,向量嵌入默认是英文模型。**
>
> 基于仓库 `thedotmack/claude-mem`(Apache-2.0,11.4 万星,最近提交 2026-11-06)的 README、安装器源码和官方文档。**未安装、未抓包,没有实测。**

---

## 一、优势

1. **抓取完整,不靠 agent 自觉。** hook 把读了什么、改了什么、跑了什么都交给观察者代理做笔记。mem0、Supermemory 这类要 agent 主动调用 add。
2. **渐进式取用省 token。** 新会话只注入一份紧凑索引;搜索分三步:`search`(索引,每条约 50 到 100 token)→ `timeline`(前后文)→ `get_observations`(完整内容,每条约 500 到 1000 token)。官方称约省 10 倍,是官方口径,未测。
3. **旁路。** 模型请求不经过它,worker 停了只是少了记忆。
4. **本地存储可检查。** `~/.claude-mem/claude-mem.db`;每条观察有 ID,可在网页查看器 `/viewer` 里查看。
5. **两端官方适配。** OpenCode 1.3.4+(含 2.0)和 DSH。
6. **有中文输出模式。** `plugin/modes/code--zh.json` 存在,观察和摘要用中文写。
7. **隐私标签。** `<private>` 包起来的内容不存。
8. **社区大。** 11.4 万星,更新频繁。

## 二、代价

- **持续的模型调用成本**:每次工具调用都发给观察者模型,要选便宜模型。
- **观察者接 codebuddy 没实测**:源码里 openrouter 提供方允许自定义 `BASE_URL` 与模型,理论可行。
- **默认开匿名统计(PostHog)**。
- **根在 Claude Code 生态**,OpenCode、DSH 是后加的适配器,成熟度未知。
- **依赖 Node 20.19+ 或 22.12+;Bun 和 uv 缺则自动装。**
- **记的是"做过什么",不做"偏好、项目规则"的提炼**(memsearch 有 `PROJECT.md`、`USER.md`)。

---

## 三、部署

### 形态

不是容器,是本机进程:

| 组件 | 位置 |
|---|---|
| worker | 本机常驻 HTTP 服务,Bun 管理 |
| 数据 | `~/.claude-mem/claude-mem.db`(SQLite + FTS5)加 Chroma |
| 设置 | `~/.claude-mem/settings.json` |
| 插件 | 每个客户端一个适配器 |

仓库另有 `docker-compose.yml`,但那是 server-beta 测试版,强制要求 Postgres 凭据,明确警告不要暴露公网,**不是本机用法**。

### 命令

```bash
# OpenCode(1.3.4+,含 2.0),装完重启
npx claude-mem install --ide opencode

# DSH(需要 pnpm 和 dsh)
npx claude-mem install --ide dsh --dsh-profile <profile>

npx claude-mem doctor      # 自检
npx claude-mem uninstall   # 卸载
```

本机 DSH profile 是 `desktop`,不是文档默认的 `web`,装之前要改参数。

### 装完会改什么(来自安装器源码)

**OpenCode 侧**
- 拷贝 `~/.config/opencode/plugins/claude-mem.js`
- 在 `~/.config/opencode/opencode.json` 写入本地 MCP 配置
- 清理全局 `AGENTS.md` 里旧版本的 claude-mem 记忆块

主配置是 `opencode.jsonc`,安装器会不会另起 `opencode.json` 并与之冲突,**未验证**,装前备份、装后核对。

**DSH 侧**
- 调 `dsh plugin --profile <name> add` 装进 profile(`dsh/cordis.patch.yml` 注入 `@claude-mem/dsh`)
- 在 `~/.dsh/sessions` 加一个受管会话监听

### 推荐装法

```bash
# 1. 备份
cp ~/.config/opencode/opencode.jsonc ~/.config/opencode/opencode.jsonc.bak
cp -r ~/.dsh/profiles ~/.dsh/profiles.bak

# 2. 不登录、先只装 OpenCode,并关统计
CLAUDE_MEM_ONLINE_OPTIN=false npx claude-mem install --ide opencode --provider openrouter
npx claude-mem telemetry disable

# 3. 改 ~/.claude-mem/settings.json
#    CLAUDE_MEM_OPENROUTER_BASE_URL → codebuddy 的地址
#    CLAUDE_MEM_OPENROUTER_MODEL    → 便宜的模型
#    CLAUDE_MEM_MODE                → code--zh

# 4. 验证后再装 DSH,并打开
#    CLAUDE_MEM_SESSION_START_INCLUDE_ALL_SOURCES: "true"
```

注意事项:
- 与现用 opencode-mem 并存会重复注入上下文,测试时先暂停 opencode-mem。
- `--provider openrouter` 在非交互模式下是否还要额外参数,**未验证**。
- 可选观察者提供方:`claude`、`gemini`、`openrouter`、`host`。`host` 让宿主 agent 自己写笔记,无需 key,可能最省事,**未读它在 OpenCode、DSH 上的表现**。

---

## 四、数据会不会发到云端

> 登录本身不会自动把记忆传上云,但登录会带来另外两种外发。

| 路径 | 触发条件 | 发什么 | 默认 |
|---|---|---|---|
| 云同步 | `CLOUD_SYNC_TOKEN`、`USER_ID`、`HUB_URL` 三个都非空 | 观察摘要、完整提示词原文,开了截图保留还会传截图 | **关**(`HUB_URL` 为空则完全关闭) |
| 托管观察者模型 | 登录后选 claude-mem 为提供方 | **每次工具调用的内容**发到 `https://cmem.ai/api/inference/v1` | 需选择才发 |
| 匿名统计 | 默认 | 使用统计,具体内容我没读 | **开** |

托管观察者那一项风险最大:发出去的是原始工具调用,等于把代码和对话交给第三方。源码 `src/shared/cmem-gateway.ts` 里有试用、订阅、额度概念,到期会退回用户自己的 Anthropic 套餐,说明这是商业引流路径。

不登录时:观察者模型内容只发给你自己选的提供方(接 codebuddy 就是发 codebuddy,不新增第三方),存储都在本机。

### 装完核对清单

`~/.claude-mem/settings.json`:
- `CLAUDE_MEM_CLOUD_SYNC_HUB_URL`、`CLAUDE_MEM_CLOUD_SYNC_TOKEN`、`CLAUDE_MEM_PRO_MEMORY_KEY` 为空
- `CLAUDE_MEM_OPENROUTER_BASE_URL` 指向 codebuddy,不含 `cmem.ai`

再用 `lsof -i` 或日志确认 worker 没连 `cmem.ai`、`sync.cmem.ai`。

未验证:不登录时安装器会不会因联网失败而中断(更新日志提过"无法访问 cmem.ai 的非交互安装会失败",可能只针对选了 cmem 提供方的情况)。

---

## 五、云上与本地的差异

依据 `docs/ip-boundary.md`、`docs/license.md` 与官方 cloud-sync 页:**记忆核心能力本地与云上同一套,没被剪裁;云上多的是托管服务和多设备、团队层。**

| 能力 | 本地 | 云上(cmem.ai Pro) |
|---|---|---|
| 自动抓取、观察者写笔记 | 有,用自己的模型 | 有,也可用托管模型 |
| SQLite + 向量检索、三步渐进搜索 | 有 | 有 |
| `/viewer`、`<private>`、中文模式 | 有 | 有 |
| 多设备同步 | 无 | 有(sync hub,worker 随写随同步) |
| 团队共享 TeamBrain、云端查看 | 无 | 有 |
| SSO、RBAC、审计、DLP、高级知识代理、SLA | 无 | 商业版 |

保留为商业、不在开源仓库的:托管云、团队同步、管理后台、SSO/SAML/SCIM、企业 RBAC、审计日志 UI、DLP 与策略引擎、高级知识代理、托管评测、客户部署工具。

个人单机用,云上多出的东西基本用不上。

和其他候选对比:

| | 本地版是否阉割核心 | 服务端是否开源 |
|---|---|---|
| mem0 | 是(缺时间推理、Dream、图记忆) | 是 |
| Supermemory | 官方称云版用专有模型 | **否** |
| claude-mem | **否** | **是** |

未验证:官方没写"云版质量更好";定价页 404 没读到;两边检索算法是否完全一致没比对代码。观察者模型质量取决于自选模型,与云上调优过的托管模型可能有差异。

---

## 六、检索:不是只有向量

三层混合:

| 层 | 技术 | 作用 |
|---|---|---|
| 关键词 | SQLite FTS5 | 精确匹配标题、副标题、叙述、事实、概念 |
| 中文子串 | `LIKE` 子串匹配 | 查询含汉字等字符时绕开 FTS5 |
| 向量语义 | Chroma + 嵌入模型 | 按意思找相近笔记 |

另有结构化过滤:类型、项目、日期、文件路径、概念。

**混合方式**:`SearchOrchestrator` 先走 Chroma 语义检索,结果为空的类别再用 SQLite 补;Chroma 关闭或失败时降级为纯 SQLite。向量与关键词的具体融合算法没读到,只看到"向量优先,空类别补"。

### 中文

FTS5 默认分词器切不开汉字、日韩文、泰文等。`SessionSearch.ts` 的 `UNSEGMENTED_SCRIPT_RANGES` 正则(含 `\p{Script=Han}`)识别这类字符,**查询含这类字符时改走子串匹配**,混合查询会拆段逐项匹配(修 Issue #3801、#3982)。所以中文**关键词检索可用**,代价是子串匹配不排序、数据量大时可能慢,没测。

### 向量嵌入是英文模型

- 默认 `CLAUDE_MEM_CHROMA_EMBEDDING_FUNCTION: 'default'`,即 `all-MiniLM-L6-v2`,源码注释写明英文调优。
- 白名单只有 `default`、`openai`、`cohere`、`jina`、`voyageai`、`roboflow`,**没有本地多语言选项**。换好的中文嵌入只能用云端,会把笔记发给第三方。
- `CLAUDE_MEM_EMBEDDING_MODEL` 注释说可选 `models.ts` 里的其他模型,**没读该文件,可能有出路**。

| 场景 | 预期 |
|---|---|
| 关键词、文件名、术语查询 | 好 |
| 英文笔记语义检索 | 还行 |
| 中文笔记换说法的语义检索 | **弱**(推测,要实测) |

缓解思路(推测):编码场景里文件路径、函数名、命令这类英文词占比不小。

对比 memsearch:自带 bge-m3 本地嵌入加 BM25 混合,这一点明显更适合中文。

---

## 七、待办

- 读 `src/services/vector/models.ts`,确认有没有本地多语言嵌入。
- 实测观察者模型接 codebuddy。
- 实测 OpenCode、DSH 两端跨来源召回与中文召回。
