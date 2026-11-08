---
type: concept
status: developing
area: growth
title: "claude-mem 调教清单"
created: 2026-11-08
updated: 2026-11-08
tags:
  - learning
  - opencode
  - dsh
  - claude-mem
  - 配置
  - 调教
related:
  - "[[claude-mem-配置详解]]"
  - "[[claude-mem-安装部署]]"
  - "[[claude-mem-存储与读取机制]]"
  - "[[claude-mem-跨端共享]]"
  - "[[claude-mem-深入调研]]"
---

# claude-mem 调教清单

> 一句话:**238 个键里真正值得调的只有 40 个左右。这篇把它们按"先后顺序"分成 8 轮,每轮只动几个键,改完有验证方法,不满意有回退值。**
>
> 全表看 [[claude-mem-配置详解]]。本篇的默认值和行为都来自读源码(约 v15.12.0),**没有实测**;标"推断"的是我根据调用路径推的。

---

## 怎么用这篇

### 调教的节奏

1. 一轮只改一类键,改完用一两天,看效果再进下一轮。同时改十个键,出了问题不知道是谁。
2. 每个键都写了"默认值"和"回退到"。不满意直接改回默认值,或者把这个键从 `settings.json` 里删掉(缺键会用默认值兜底)。
3. 改完要重启 worker,再改下一个:

```bash
npx claude-mem restart
```

4. 想知道某个键现在到底是什么值,打开 `~/.claude-mem/settings.json` 看,同时用 `env | grep CLAUDE_MEM` 确认没有同名环境变量覆盖它(环境变量优先)。

### 表里几个词

| 词 | 意思 |
|---|---|
| 观察(observation) | claude-mem 自动记下的一条工作笔记,由"观察者模型"在每次工具调用后生成 |
| 观察者(observer) | 负责写笔记的那个模型。你要接的是 codebuddy |
| 注入(inject) | 新会话开始时,把旧记忆塞进模型的上下文 |
| token | 模型计费和上下文长度的单位。注入越多越占上下文,也越费钱 |
| 优先级 | **必改**:不改就用不起来或有风险。**建议**:多数人该改。**可选**:有具体需求再动。**观察**:先不动,看了数据再说 |

### 8 轮总览

| 轮 | 目标 | 键数 | 优先级 |
|---|---|---|---|
| 第 0 轮 | 先别动,记下"出厂状态" | 0 | 必做 |
| 第 1 轮 | 观察者:接上 codebuddy、中文输出 | 6 | 必改 |
| 第 2 轮 | 隐私:不泄密、不外发、不存图 | 7 | 必改 |
| 第 3 轮 | 采集:什么该记、什么不该记 | 6 | 建议 |
| 第 4 轮 | 注入:开会话时塞多少旧记忆 | 6 | 建议 |
| 第 5 轮 | 检索:中文召回与 90 天窗口 | 4 | 建议 |
| 第 6 轮 | 跨端:OpenCode 与 DSH 共用 | 3 | 必改(若要共用) |
| 第 7 轮 | 运维:备份、日志、清理 | 6 | 可选 |
| 附 | 先别碰的键 | | 观察 |

---

## 第 0 轮:先别动,记下出厂状态

### 为什么

全新安装时,worker 第一次启动会把 238 个默认值**整份写进** `~/.claude-mem/settings.json`(权限 0600)。先留一份副本,后面改乱了可以对照,也可以整份恢复。

### 怎么做

```bash
cp ~/.claude-mem/settings.json ~/.claude-mem/settings.factory.json
```

之后每进一轮前,再留一份:

```bash
cp ~/.claude-mem/settings.json ~/.claude-mem/settings.round1.json
```

副本放在数据目录里,不要放进 wiki 仓库,里面可能有 API Key。

### 同时看两个现状

```bash
npx claude-mem doctor     # 自检:bun、uv、hook、worker 是否正常
```

在浏览器里打开 viewer(记忆的网页查看器)。**具体地址我没读到**,以 `doctor` 或安装结束的输出为准。

---

## 第 1 轮:观察者,接上 codebuddy 并改成中文

### 目标

让"写笔记的模型"用 codebuddy,而不是默认的 Claude;笔记用中文写。

### 要改的 6 个键

| 键(省略 `CLAUDE_MEM_` 前缀)   | 默认       | 改成                      | 说明                                                                                                  |
| ------------------------ | -------- | ----------------------- | --------------------------------------------------------------------------------------------------- |
| `PROVIDER`               | `claude` | `openai-compatible`     | 独立的提供方,不带 OpenRouter 归因头,key 独立;有效值只有 `claude`/`codex`/`gemini`/`openrouter`/`openai-compatible` 五个 |
| `OPENAI_COMPAT_BASE_URL` | 空        | codebuddy 的 OpenAI 兼容地址 | 留空且不选预设,就不连任何地方,只报"未配置端点"。**codebuddy 的真实地址我不知道**,得你提供                                              |
| `OPENAI_COMPAT_API_KEY`  | 空        | codebuddy 的 Key         | 和 OpenRouter 的 key 分开存放                                                                             |
| `OPENAI_COMPAT_MODEL`    | 空        | 便宜的模型名                  | 原样传给接口。自定义地址没有默认模型,留空会报 `No model configured`。每次工具调用都要调一次,选便宜、快的                                    |
| `MODE`                   | `code`   | `code--zh`              | 指向 `plugin/modes/code--zh.json`,观察笔记用中文写。文件不存在会报错                                                   |
| `OPENAI_COMPAT_PRESET`   | 空        | **保持为空**                | 预设是自动填默认地址的快捷方式(deepseek、groq、ollama 等);接 codebuddy 手填地址,所以留空                                       |

### 最小可用 JSON

```json
{
  "CLAUDE_MEM_PROVIDER": "openai-compatible",
  "CLAUDE_MEM_OPENAI_COMPAT_BASE_URL": "<codebuddy 的 OpenAI 兼容地址>",
  "CLAUDE_MEM_OPENAI_COMPAT_API_KEY": "<codebuddy 的 Key>",
  "CLAUDE_MEM_OPENAI_COMPAT_MODEL": "<便宜的模型名>",
  "CLAUDE_MEM_MODE": "code--zh"
}
```

注意:整份 `settings.json` 里还有另外 233 个键,上面只是要**改动**的 5 个值,不是整个文件。改的时候在原文件里找到这几个键改值,别把文件替换成这 5 行(缺键会用默认值兜底,但不要依赖这一点去删别的键)。

### 这一轮要盯的 3 个相关键(先别动)

| 键 | 默认 | 为什么先不动 |
|---|---|---|
| `OPENAI_COMPAT_REASONING` | 空 | 空 = 每个请求都带 `reasoning:{enabled:false}` 关掉思考,避免带思考的模型把输出额度花在思考上、返回空内容。如果 codebuddy 对这个字段报 400,源码会自动去掉重发一次 |
| `OBSERVER_MAX_OUTPUT_TOKENS` | `4096` | 笔记被截断或返回空时再调大(范围 256 到 1000000) |
| `QUOTA_FALLBACK_PROVIDER` | `claude` | 主提供方失败时转给谁。默认 `claude`,但本机没有 Claude 登录或 Key 就等于无处可退,工作会卡住等待。想要"失败就原地等"可设 `off`;想退到另一个,设成 `gemini`/`openrouter` 之一,前提是配好了对应 key |

### 不用管的

`TIER_ROUTING_ENABLED`、`QUOTA_THRESHOLD_*` 这几个只对 `provider=claude` 生效,用 codebuddy 的人不受影响。

### 验证

1. 重启 worker 后,在 OpenCode 里随便做几步操作(读文件、跑个命令)。
2. 等一两分钟,打开 viewer,看是否出现新的观察笔记,是不是中文。
3. 没有笔记:`npx claude-mem doctor`,再看日志。常见原因是地址错、Key 错、模型名错、模型不支持这个接口。
4. 同时确认没连 `cmem.ai`:

```bash
lsof -i -P | grep -i cmem
```

### 回退

`PROVIDER` 改回 `claude`(需本机有 Claude 登录),或用安装器装的 `host`。**我没读到 `host` 提供方在 OpenCode 与 DSH 上的实际表现**,需要实测。

### 没实测

codebuddy 能否被 `openai-compatible` 调通、笔记质量如何、有无额度限制,都没实测。**这是整套方案第一个要验证的点**,过不了这关,后面都不用调。

---

## 第 2 轮:隐私,不泄密、不外发、不存图

### 为什么先于一切

每次工具调用都会触发一次观察者模型调用,**原始的工具输入输出会发给观察者**。你的终端输出、读到的文件、`.env` 里的内容都可能在里面。先把脱敏打开。

### 要改的键

| 键 | 默认 | 改成 | 说明 |
|---|---|---|---|
| `REDACT_ENABLED` | `false` | `"true"` | 总开关。入库前把已识别的密钥替换成 `<redacted type='规则名'/>`,覆盖工具输入输出、提示词、总结。内置 35 条规则,含 aws、github_pat、openai_key、anthropic_key、jwt、private_key_pem、url_credentials 等 |
| `REDACT_GENERIC_ENABLED` | `false` | `"true"` | 额外 4 条没有厂商前缀的规则:`password=`、`*_TOKEN/*_SECRET/*_API_KEY`、`Authorization: Bearer`、`Basic`。要求值至少 8 位且含字母,`max_tokens=4096` 这类纯数字不误杀。低置信度,可能误伤 |
| `MEDIA_CAPTURE_ENABLED` | `true` | `"false"` | 默认**会把图片存在本机**,每张最大 3 MiB,本地没有总量上限。不需要就关 |
| `TELEGRAM_ENABLED` | `true` | `"false"` | 图个安心。没填 bot token 和 chat id 本来就不会发 |

### 要核对、必须保持为空的键

| 键 | 必须是 | 为什么 |
|---|---|---|
| `CLOUD_SYNC_HUB_URL` | 空 | 源码注释:为空 = 同步完全关闭。非空且 TOKEN、USER_ID 也有值,才会向 `{HUB_URL}/v1/sync/ops` 上传数据 |
| `CLOUD_SYNC_TOKEN` | 空 | 同上 |
| `PRO_MEMORY_KEY` | 空 | cmem.ai 网关的 Key。一旦被采用,观察内容会交给云端模型处理 |

### 可选:自定义脱敏规则

内置规则覆盖不了的内部格式(如公司内部 token 前缀),可以自己加:

```json
"CLAUDE_MEM_REDACT_CUSTOM_PATTERNS": "[{\"name\":\"internal_token\",\"regex\":\"MYCO_[A-Za-z0-9]{20,}\"}]"
```

要点:
- 值是**字符串**,里面是 JSON 数组,所以内层引号要转义(源码默认值 `"[]"` 就是字符串)。**用户手写 JSON 布尔或数组是否也被接受,没读到,照字符串写最稳**。
- 自定义规则排在内置规则**之前**先跑。
- 正则写错的项会被忽略并记警告,不会报错,所以要靠验证确认生效。

### 验证

1. 找一条含假密钥的操作,比如让 agent 执行 `echo "token=abc12345678"`。
2. 在 viewer 里看对应笔记,应该是 `<redacted type='…'/>` 而不是原文。
3. 想看命中次数:临时把 `REDACT_LOG_MATCHES` 设 `"true"`,日志只记规则名和次数,不记原文。看完关回去。

### 回退

`REDACT_ENABLED` 改回 `"false"`。注意:**已经存进去的内容不会被回头脱敏**,所以这一轮要在第一次真正使用前就做。

### 限制

脱敏只能抓"已识别的格式"。它拦不住自然语言里的敏感内容,比如你在对话里说出的业务机密。

---

## 第 3 轮:采集,什么该记、什么不该记

### 目标

少记噪音,省观察者的调用次数(省钱省时间),也让记忆更干净。

### 键

| 键 | 默认 | 建议 | 说明 |
|---|---|---|---|
| `SKIP_TOOLS` | `ListMcpResourcesTool,SlashCommand,Skill,TodoWrite,AskUserQuestion` | 先保持;观察后追加 | 不记的工具名,逗号分隔,不区分大小写。OpenCode 的 `read` 会被适配成 `Read` 再匹配 |
| `SKIP_BASH_PATTERNS` | 空 | 按需 | 一个正则,命令匹配上就不记。例:`^(ls\|cat\|pwd\|cd)\b`(多个用 `\|` 连接)。写错的正则被忽略,等于没设 |
| `SKIP_SUBAGENT_OBSERVATIONS` | `false` | 按需 | 设 `"true"` 跳过所有子代理产生的笔记。你用 oh-my-openagent 这类多代理编排,子代理很多,这个值得考虑 |
| `SKIP_AGENT_TYPES` | 空 | 按需 | 按子代理类型精确跳过,逗号分隔。源码注释推荐 `workflow-subagent` |
| `EXCLUDED_PROJECTS` | 空 | 建议 | 不记的项目路径,glob 通配,支持 `*` `**` `?` 和开头的 `~`。命中的目录既不采集也不注入。**含敏感内容的仓库在这里排除** |
| `OBSERVE_BARE_PROMPTS` | `false` | 保持 | 默认你的提示词不单独调一次观察者,而是随下一次工具事件那次调用一起带上,省调用。设 `true` 才恢复单独调用 |

### 怎么判断该不该跳

先跑两三天默认值,在 viewer 里翻笔记。如果发现:
- 大量"执行了 ls / cat / pwd"这类笔记,加到 `SKIP_BASH_PATTERNS`。
- 大量子代理的流水账,开 `SKIP_SUBAGENT_OBSERVATIONS`。
- 某个仓库不想留记录,加进 `EXCLUDED_PROJECTS`。

### 验证

改完做一次对应操作,看 viewer 里是否还出现新笔记。

### 回退

清空对应键,或恢复默认值。注意:**已记的笔记不会被删**,只影响新采集。

### 总开关

`OBSERVER_ENABLED` 默认 `true`,显式写 `"false"` 才关闭"新笔记和会话摘要"的生成;写错按开启处理。想临时停止记忆,用这个。

---

## 第 4 轮:注入,开会话时塞多少旧记忆

### 先理解

每次新开会话,claude-mem 会把一批旧记忆塞进上下文。塞得多,模型"记得"多,但也更占上下文、更费 token。这一轮的目标是找到适合你的量。

### 键

| 键 | 默认 | 说明 | 调法 |
|---|---|---|---|
| `CONTEXT_OBSERVATIONS` | `50` | 最多注入多少条观察。校验范围 0 到 200,取最近的 N 条 | 嫌上下文太满就降到 20 到 30;想要更多历史就升 |
| `CONTEXT_SESSION_COUNT` | `10` | 显示最近多少次"会话总结" | 一般不动。上下文超预算时会被减半 |
| `CONTEXT_FULL_COUNT` | `0` | 最近前 N 条除了标题还展开详细内容。0 = 全只显示标题 | 想让最近几条更详细可设 3 到 5。上下文瘦身时它最先被砍 |
| `CONTEXT_FULL_FIELD` | `narrative` | 展开时用哪个字段:`narrative`(叙述长文)或 `facts`(要点列表) | 只在 `FULL_COUNT` 大于 0 时有用。想省 token 用 `facts` |
| `CONTEXT_OBSERVATION_TYPES` | 空 | 类型白名单,如 `bugfix,decision,discovery`。空 = 当前模式里的所有类型 | 只能缩小不能超出模式的类型表;模式里没有的名字被忽略 |
| `CONTEXT_MAIN_AGENT_ONLY` | `true` | 注入时不带子代理的笔记,避免流水账挤掉主会话的长期记忆 | 保持。搜索和 viewer 仍能看到全部 |

### 调教顺序建议

1. 先保持默认 50,用一两天。
2. 感觉"开场塞太多废话":降 `CONTEXT_OBSERVATIONS`,并用 `CONTEXT_OBSERVATION_TYPES` 只留 `decision,bugfix` 这类高价值类型(观察类型表在 `plugin/modes/code.json`,已读:`bugfix`、`feature`、`refactor`、`change`、`discovery`、`decision`、`security_alert`、`security_note`、`sensitive`。`code--zh.json` 只有提示词文案,没有类型表,类型沿用 `code`,所以白名单里写英文类型名)。
3. 感觉"记得不够细":升 `CONTEXT_FULL_COUNT`。

### 验证

开一个新会话,看注入的内容长度和内容(OpenCode 里能否直接看到注入文本,**没读到**;可看 viewer 或日志)。

### 想要但要谨慎:每次提问的语义注入

| 键 | 默认 | 说明 |
|---|---|---|
| `SEMANTIC_INJECT` | `false` | 实验性。设 `"true"` 后,每次你提交提示词(需 20 个字符以上,且不是纯媒体),按意思去搜相关旧记忆追加进来 |
| `SEMANTIC_INJECT_LIMIT` | `5` | 每次最多注入几条,服务端夹在 1 到 20 之间 |

**不建议这一轮开。** 它走的是普通搜索入口,据此推断同样受 90 天窗口约束、依赖向量检索质量。而你的笔记是中文,默认向量模型对中文弱(见第 5 轮)。先把第 5 轮的召回质量搞清楚,再决定要不要开。

### 其他注入类键(默认值已合理)

| 键 | 默认 | 备注 |
|---|---|---|
| `MEMORY_INSTRUCTIONS_ENABLED` | `true` | 注入时附一段"怎么用 claude-mem 记忆"的说明。设 `false` 省一点 token,但可能影响模型是否会主动去查记忆 |
| `WELCOME_HINT_ENABLED` | `true` | 项目还没有任何观察时,注入一段欢迎提示,第一条记忆落库后消失 |
| `WORK_STATE_ENABLED` | `true` | 注入"工作状态(待办清单)"段落。你自己另有任务跟踪(如 todo 工具)可设 `false` |
| `REINFORCE_ALPHA` | `0` | 实验性排序权重,0 = 关,注入就是"最近的 N 条"。文档建议试 0.5,**暂不动** |

---

## 第 5 轮:检索,中文召回与 90 天窗口

### 先看清现状

你的笔记是中文,而本机默认配置在中文上有两个已知短板(下表是读源码得出,**没实测**):

| 短板 | 在哪 | 是什么 |
|---|---|---|
| 1. 向量层 | `ChromaSync.ts`,由 `CHROMA_EMBEDDING_FUNCTION=default` 决定 | 默认嵌入模型 `all-MiniLM-L6-v2` 是英文调优,词表把中日韩文字切成单字或 `[UNK]`,"换个说法找同一件事"这种语义召回对中文偏弱(源码注释承认,Issue #3422) |
| 2. 关键词层 | `SessionSearch.ts`,查询含汉字就跳过全文检索 | SQLite 的 FTS5 不切分汉字,于是降级成多列 `LIKE '%…%'` 子串匹配。"登录页面"和"页面登录"除非挨在一起否则匹配不上 |

还有第三个坑,和中文无关但会让你搜不到旧东西:**90 天窗口**。

### 键

| 键 | 默认 | 建议 | 说明 |
|---|---|---|---|
| `SEARCH_RECENCY_DAYS` | `90` | 建议改成 `"0"` 或更大 | 不带日期的语义搜索只返回最近 N 天的匹配。默认 90,所以**超过 90 天的旧记忆在语义搜索里搜不到**。`0` = 关闭窗口。明确给 `dateStart/dateEnd` 时以你给的范围为准。非非负整数的值会被忽略保持 90。改完要重启 worker |
| `CHROMA_EMBEDDING_FUNCTION` | `default` | **先别改** | 白名单只有 `default`/`openai`/`cohere`/`jina`/`voyageai`/`roboflow`。除 `default` 外全是云端 API,**会把你的记忆文本发给第三方**。只对新建集合生效,改了还必须重建索引 |
| `CHROMA_MODE` | `local` | 保持 | `local` 由 worker 用 uvx 在本机起 chroma-mcp 子进程;`remote` 连已有的 Chroma 服务 |
| `EMBEDDING_MODEL` | `all-MiniLM-L6-v2` | **改了也没用** | 可选 4 个(含 3 个多语言),但**只在服务器模式(Postgres + pgvector)下被读取**。worker/Chroma 路径用的是 `CHROMA_EMBEDDING_FUNCTION`。这条由 grep 确认:`CLAUDE_MEM_EMBEDDING_MODEL` 在 src 里只被 `ObservationEmbeddingService.ts`(服务器模式)读取 |

### 90 天窗口对"补查"的影响

已读 `SearchOrchestrator.ts`(第 155 到 195 行):Chroma 有 query 时先走语义搜索,**只有某个类别(观察、会话、提示词)整类为空,才去 SQLite 补查**;SQLite 补查不套 90 天窗口(源码注释明说)。所以**如果近 90 天里有几条不相干的结果,这一类就不算空,100 天前那条精确匹配的笔记不会被 LIKE 捞回来**。这个推论是我根据读到的分支条件推的,没实测。所以第一件事就是放宽窗口。

### 调教顺序

1. 改 `SEARCH_RECENCY_DAYS` 为 `"0"`,重启。这一步几乎没副作用。
2. **做一次真实召回测试,别凭感觉**:挑 10 条你过去记过的中文笔记,用不同说法去搜(不是原词),记录能搜到几条。这是判断"向量短板严不严重"的唯一办法。
3. 如果召回很差,选项有:
   - 接受现状,主要靠关键词(中文子串匹配对"原词"其实可用)。
   - 换云端嵌入函数(会外发记忆文本,和第 2 轮的隐私目标冲突,需要你权衡)。
   - 走服务器模式用多语言本地模型(强制要 Postgres,不是轻量用法)。
   - 回头看 memsearch,它自带本地 bge-m3(多语言),这是中文场景的实际优势。见 [[OpenCode与DSH共享记忆-选型调研]]。

### 验证

用 viewer 的搜索或 MCP 的 `search` 工具,拿"同义不同词"的查询去测。记录:原词命中率、换说法命中率、超过 90 天的命中率。

### 回退

`SEARCH_RECENCY_DAYS` 改回 `"90"`。

---

## 第 6 轮:跨端,OpenCode 与 DSH 共用记忆

### 这一轮的核心

两端要共用记忆,取决于三件事:**项目是否一致、来源是否被过滤、DSH 是否真的在采集**。

### 键

| 键 | 默认 | 要改成 | 说明 |
|---|---|---|---|
| `SESSION_START_INCLUDE_ALL_SOURCES` | `false` | `"true"` | 默认只注入"本工具自己"写的记忆(按 `platform_source` 过滤),所以 OpenCode 看不到 DSH 写的、反之亦然。设 `true` 就不按来源过滤。OpenCode 插件每次请求实时读它,**无需重启** |
| `PROJECT_NAME_SOURCE` | `path` | 视情况 | 决定"这条记忆算哪个项目"。`path` = 用 git 仓库根目录的文件夹名;`git-remote` = 用 origin 地址推出的 `org/repo`,改目录名也不变。**两端同目录同设置才会落到同一项目** |
| `TRANSCRIPTS_ENABLED` | `true` | 保持 | DSH 的记忆是靠 worker 读 DSH 会话记录采集的。设 `false` 则 DSH 自动采集失效 |

### 要知道的 3 个限制

1. **`CONTEXT_PROJECTS` 对 OpenCode 无效。** 它让会话开始读"所有项目"而不是当前项目,但 OpenCode 插件自己拼 `/api/context/inject?cwd=…` 请求,源码里没读这个键;只在走 hook 的客户端(如 Claude Code)生效。**不要指望靠它让 OpenCode 看到别的项目。**
2. **"来源"和"项目"是两个字段。** 项目名只管归哪个项目;来源(`platformSource`)区分来自哪个客户端。OpenCode 固定写 `opencode`,DSH 来自 transcript watch 里配置的名字(如 `dsh`)。两个独立,互不影响。
3. **DSH 写入时用的来源名,源码里没查到**,要装完到 viewer 核对。

### 项目名一致性,最容易踩的坑

- 同一个仓库,OpenCode 在 `/a/repo` 开、DSH 在 `/b/repo` 开(比如不同 worktree),`path` 模式下取的是文件夹名,恰好都叫 `repo` 才算同一项目;worktree 会拼成"父项目/子名",可能不一致。
- 想让多个目录归到同一个项目,用 `PROJECT_ENVIRONMENTS`:

```json
"CLAUDE_MEM_PROJECT_ENVIRONMENTS": "[{\"name\":\"my-note\",\"patterns\":[\"~/ai-work/my-note\",\"~/ai-work/my-note/**\"]}]"
```

目录命中某环境的 `patterns` 就用 `name` 作项目名,**优先级高于一切自动推算**。默认 `[]` = 不归并。

### 验证

1. 在 OpenCode 里做一些操作,等笔记出现,在 viewer 记下它的 `project` 和 `platform_source`。
2. 在 DSH 里同一个目录做一些操作,同样记下。
3. 两条的 `project` 一样吗?`platform_source` 分别是什么?
4. 开新会话,看注入里有没有对方的笔记。

### 没实测

跨端实际能否召回、DSH 来源名是什么,都没实测。详见 [[claude-mem-跨端共享]]。

---

## 第 7 轮:运维,备份、日志、清理

都是可选项,稳定运行后再动。

| 键 | 默认 | 建议 | 说明 |
|---|---|---|---|
| `BACKUP_ENABLED` | `false` | 建议开 `"true"` | 自动给本地数据库做快照。开启后需重启 worker |
| `BACKUP_INTERVAL_HOURS` | `24` | 保持 | 快照间隔,小时 |
| `BACKUP_RETAIN_COUNT` | `7` | 保持 | 最多保留几份,更旧的被清理 |
| `LOG_LEVEL` | `INFO` | 排查时改 `DEBUG` | 可选 `DEBUG`/`INFO`/`WARN`/`ERROR`/`SILENT`。写错会被拒绝 |
| `LOG_RETENTION_DAYS` | `30` | 保持 | 日志保留天数,0 = 永久 |
| `TOOL_USES_RETENTION_DAYS` | `0` | 观察 | `tool_uses` 表存每次工具调用的原始输入输出。0 = 永久保留。**这张表会随使用持续增长**,磁盘紧张时设成 `"90"` 之类,worker 启动时清理已关联到笔记且超过 N 天的记录。非非负整数一律当 0,不会误删 |

数据目录默认是 `~/.claude-mem`(`DATA_DIR`),备份快照也在这个体系里。**备份文件具体放哪个子目录,我没读到。**

---

## 附:先别碰的键

下面这些看着诱人,但现阶段动它们收益小或风险大。

| 键 | 默认 | 为什么先别碰 |
|---|---|---|
| `CHROMA_EMBEDDING_FUNCTION` | `default` | 换云端会外发记忆文本,与隐私目标冲突;改后要重建索引 |
| `EMBEDDING_MODEL`、`SERVER_VECTOR_SEARCH` | | 只在服务器模式生效,本机 worker 模式改了没用 |
| `RUNTIME` | `worker` | 改成 `server` 要另配 Postgres 和鉴权,不是轻量用法 |
| `DEDUP_ENABLED` | `false` | 开了第 0 层会自动合并标题完全相同的笔记。先观察重复率再决定 |
| `FOLDER_CLAUDEMD_ENABLED` | `false` | 开了会在你的项目目录里**真的新增/改写 `CLAUDE.md`**,污染仓库 |
| `FILE_READ_GATE_ENABLED` | `true` | 仅对 Claude Code 生效,对 OpenCode 无影响 |
| `REINFORCE_ALPHA` | `0` | 实验性排序 |
| `MEDIA_INFERENCE_ENABLED` | `false` | 开了会把图片发给观察者模型理解,额外产生付费调用 |
| `PROVIDER_BY_SOURCE` | 空 | 可按客户端分别指定提供方,格式是 JSON 字符串如 `{"opencode":"openai-compatible","dsh":"openai-compatible"}`。两端用同一个观察者就不需要 |
| `CLOUD_SYNC_*`、`TEAMBRAIN_*`、`PRO_*`、`ONLINE_SIGNUP_*` | 空 | 云端相关,保持为空 |
| `WORKER_PORT` | `37700+(uid%100)`,本机 `37701` | 端口被占才改 |
| `ALLOWED_ORIGINS`、`PUBLIC_URL`、`WORKER_INGEST_TOKEN` | 空 | 远程访问用,本机用不到 |

---

## 一页对照:每轮改完的 JSON 增量

每轮累加,**只列需要改的键**,其余保持默认。值全部是字符串。

```json
{
  "CLAUDE_MEM_PROVIDER": "openai-compatible",
  "CLAUDE_MEM_OPENAI_COMPAT_BASE_URL": "<codebuddy 的 OpenAI 兼容地址>",
  "CLAUDE_MEM_OPENAI_COMPAT_API_KEY": "<codebuddy 的 Key>",
  "CLAUDE_MEM_OPENAI_COMPAT_MODEL": "<便宜的模型名>",
  "CLAUDE_MEM_MODE": "code--zh",

  "CLAUDE_MEM_REDACT_ENABLED": "true",
  "CLAUDE_MEM_REDACT_GENERIC_ENABLED": "true",
  "CLAUDE_MEM_MEDIA_CAPTURE_ENABLED": "false",
  "CLAUDE_MEM_TELEGRAM_ENABLED": "false",

  "CLAUDE_MEM_SEARCH_RECENCY_DAYS": "0",

  "CLAUDE_MEM_SESSION_START_INCLUDE_ALL_SOURCES": "true",

  "CLAUDE_MEM_BACKUP_ENABLED": "true"
}
```

上面这段**不能直接替换整份 `settings.json`**,是"要改的值"清单。第 3、4 轮的键依你的观察再加。

---

## 每轮改完的自检

- [ ] 改完重启了 worker(`npx claude-mem restart`)
- [ ] `env | grep CLAUDE_MEM` 没有会覆盖的同名环境变量
- [ ] 做了该轮的"验证"步骤,有证据,不是凭感觉
- [ ] 留了该轮前的副本,知道怎么回退
- [ ] 云同步三个键仍为空
- [ ] `OPENAI_COMPAT_BASE_URL` 不含 `cmem.ai`

---

## 没读到 / 没实测清单

1. codebuddy 的真实 OpenAI 兼容地址和可用模型名:未知,需要你提供。
2. codebuddy 能否被 `openai-compatible` 调通、笔记质量、有无额度限制:没实测。
3. `host` 提供方在 OpenCode、DSH 上的表现:没读到。
4. viewer 的具体地址、备份快照的具体目录:没读到。
5. `code--zh` 模式沿用 `code` 的类型表(已读 `code.json`);`code--zh` 实际输出的笔记质量没实测。
6. OpenCode 里能否直接看到注入的上下文文本:没读到。
7. 用户手写 JSON 布尔值或数组(而非字符串)是否被接受:没读到,照字符串写最稳。
8. 中文向量召回的实际差距:源码注释佐证,没实测。
9. 90 天窗口对补查的影响:已读 `SearchOrchestrator.ts` 的分支条件,推论成立,没实测。
10. DSH 写入记忆时用的来源名:源码里没查到。
11. 两端同目录算出的项目名是否一致:源码层面一致,没实测。
12. 图片采集的具体上限(本地 3 MiB、给模型 256 KiB、每事件最多 4 张)来自源码注释,没实测。
