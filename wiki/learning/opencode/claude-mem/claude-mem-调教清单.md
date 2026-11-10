---
type: concept
status: developing
area: growth
title: "claude-mem 调教清单"
created: 2026-11-08
updated: 2026-11-10
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
  - "[[claude-mem-mode文件与覆盖机制]]"
---

# claude-mem 调教清单

> 一句话:**238 个键里真正值得调的只有 40 个左右。这篇把它们按"先后顺序"分成 8 轮,每轮只动几个键,改完有验证方法,不满意有回退值。**
>
> 全表看 [[claude-mem-配置详解]]。本篇的默认值和行为来自读源码(约 v15.12.0);第 1、2、3 轮已在本机配置并实测,结果写在各轮的"实测结果"里,其余轮次仍是读源码的结论,标"推断"的是我根据调用路径推的。

> 关于注释:`settings.json` 是严格 JSON 解析,**不能写注释**。键的说明放在配置仓库的 `claude-mem/settings.example.jsonc`(带行内注释的示例文件,与真实 `settings.json` 的键一一对应),改键时对照它看。

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

| 轮 | 目标 | 键数 | 优先级 | 状态 |
|---|---|---|---|---|
| 第 0 轮 | 先别动,记下"出厂状态" | 0 | 必做 | 已做 |
| 第 1 轮 | 观察者:接上 codebuddy(经公司网关)、中文输出 | 6 | 必改 | 已做,实测通过 |
| 第 2 轮 | 隐私:不泄密、不外发、不存图 | 7 | 必改 | 已做,脱敏已验证 |
| 第 3 轮 | 采集:什么该记、什么不该记 | 6 | 建议 | 已做,仅 SKIP_TOOLS 有效,其余 5 键在 OpenCode 下无效或暂不需要;另有 mode 层跳过规则,见本轮"observer 的跳过规则" |
| 第 4 轮 | 注入:开会话时塞多少旧记忆 | 6 | 建议 | 已测,保持默认,一个键都没改 |
| 第 5 轮 | 检索:中文召回与 90 天窗口 | 4 | 已完成 | 已做:`SEARCH_RECENCY_DAYS` 改为 `0`,其余 3 键保持默认;之后又上线本地 bge-m3 向量(及格非达标,见[[claude-mem-本地多语言向量方案]]) |
| 第 6 轮 | 跨端:OpenCode 与 DSH 共用 | 3 | 已完成 | 已做:`SESSION_START_INCLUDE_ALL_SOURCES="true"`;`desktop` profile 官方安装器必败,改为手动加插件和监听文件(见[[claude-mem-跨端共享]] 第 8 节)。三个方向已实测通 |
| 第 7 轮 | 运维:备份、日志、清理 | 6 | 可选 | 未做 |
| 附 | 先别碰的键 | | 观察 | 未做 |

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
| `OPENAI_COMPAT_BASE_URL` | 空        | `https://mapecology.testsite.woa.com/api/ecology/openai/v1`(公司网关) | 实际**没有直连 codebuddy**,走公司网关。网关持有并刷新 codebuddy 凭证,调用方只发固定的 Bearer key。域名含 `testsite`,是测试环境(稳定性未知) |
| `OPENAI_COMPAT_API_KEY`  | 空        | **不写进 settings.json** | 放 `~/.claude-mem/.env` 的 `OPENAI_COMPAT_API_KEY`。和 OpenRouter 的 key 分开存放 |
| `OPENAI_COMPAT_MODEL`    | 空        | `deepseek-v4.1-flash`   | 原样传给接口。自定义地址没有默认模型,留空会报 `No model configured`。每次工具调用都要调一次,选便宜、快的 |
| `MODE`                   | `code`   | `code--zh`              | 指向 `plugin/modes/code--zh.json`,观察笔记正文用中文写。文件不存在会报错                                                   |
| `OPENAI_COMPAT_PRESET`   | 空        | `custom`                | 预设是自动填默认地址的快捷方式(deepseek、groq、ollama 等);网关不在预设里,选 `custom` 后手填地址和模型 |

### 为什么走网关而不直连 codebuddy

| 项 | 情况 |
|---|---|
| codebuddy 直连 | 用浏览器 OAuth,token 会过期,每次请求带约 25 个租户/用户头 |
| claude-mem 能发的 | 只有 `Authorization: Bearer <key>` |
| 结论 | 直连大概率对不上(**推断,直连未实测**),所以改走公司网关 |

### 实际使用的最小 JSON(5 个键,不含 key)

```json
{
  "CLAUDE_MEM_PROVIDER": "openai-compatible",
  "CLAUDE_MEM_OPENAI_COMPAT_PRESET": "custom",
  "CLAUDE_MEM_OPENAI_COMPAT_BASE_URL": "https://mapecology.testsite.woa.com/api/ecology/openai/v1",
  "CLAUDE_MEM_OPENAI_COMPAT_MODEL": "deepseek-v4.1-flash",
  "CLAUDE_MEM_MODE": "code--zh"
}
```

密钥写在 `~/.claude-mem/.env`,格式为一行 `OPENAI_COMPAT_API_KEY=<key>`(此处不写真值)。`settings.json` 和 `.env` 的真文件都在 `~/.config/opencode/claude-mem/`,软链回 `~/.claude-mem/`。该配置仓库是私有的,`.env` 一并入库(已与用户确认)。

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

实测到的结论(2026-11-08):

- 接通后观察者能正常产出,`/api/health` 里 `ai.lastInteraction.success=true`、`provider=openai-compatible`。
- 网关调用实测:不带 key 返回 401 `invalid_api_key`;请求不带 `stream` 返回 400(上游只收流式);`stream:true` 返回 200,约 1.3 秒。
- `.env` 里的 key 会被 worker 读到。
- 接通前积压的 11 条队列被丢弃,没有补处理。
- `MODE=code--zh` 只让观察正文变中文,`facts` 字段仍夹带不少英文,会话总结(session_summaries)也仍是英文。

### 回退

`PROVIDER` 改回 `claude`(需本机有 Claude 登录)。不要回退到 `host`:它要求本机已有一个兼容服务,安装器不会替你起,对 OpenCode 与 DSH 大概率不可用(见 [[claude-mem-安装部署]] 2.4 节)。

### 实测结果

| 项 | 结果 |
|---|---|
| 能否调通 | 通过,经公司网关调用 `deepseek-v4.1-flash` |
| 接通后数据 | 观察 25 到 31 条(随对话增长)、会话总结 4 条以上、队列积压 0 |
| 笔记语言 | 观察正文为中文;facts 和会话总结仍有英文 |

仍未证实:

- 直连 codebuddy 是否真的不行(只是推断)。
- 额度限制、长期稳定性。网关域名含 `testsite`,是测试环境,可能变动。
- 笔记质量只看过数量和语言,没有系统评估。

---

## 第 2 轮:隐私,不泄密、不外发、不存图

### 为什么先于一切

每次工具调用都会触发一次观察者模型调用,**原始的工具输入输出会发给观察者**。你的终端输出、读到的文件、`.env` 里的内容都可能在里面。先把脱敏打开。

### 要改的键

| 键                        | 默认      | 改成        | 说明                                                                                                                                                   |
| ------------------------ | ------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `REDACT_ENABLED`         | `false` | `"true"`  | 总开关。入库前把已识别的密钥替换成 `<redacted type='规则名'/>`,覆盖工具输入输出、提示词、总结。内置 35 条规则,含 aws、github_pat、openai_key、anthropic_key、jwt、private_key_pem、url_credentials 等 |
| `REDACT_GENERIC_ENABLED` | `false` | `"true"`  | 额外 4 条没有厂商前缀的规则:`password=`、`*_TOKEN/*_SECRET/*_API_KEY`、`Authorization: Bearer`、`Basic`。要求值至少 8 位且含字母,`max_tokens=4096` 这类纯数字不误杀。低置信度,可能误伤          |
| `MEDIA_CAPTURE_ENABLED`  | `true`  | `"false"` | 默认**会把图片存在本机**,每张最大 3 MiB,本地没有总量上限。不需要就关                                                                                                             |
| `TELEGRAM_ENABLED`       | `true`  | `"false"` | 图个安心。没填 bot token 和 chat id 本来就不会发                                                                                                                   |

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

### 实测结果

已配置并生效的 4 个键(worker 读到的值已核对):

| 键 | 值 |
|---|---|
| `REDACT_ENABLED` | `"true"` |
| `REDACT_GENERIC_ENABLED` | `"true"` |
| `MEDIA_CAPTURE_ENABLED` | `"false"` |
| `TELEGRAM_ENABLED` | `"false"` |

`CLOUD_SYNC_HUB_URL`、`CLOUD_SYNC_TOKEN`、`PRO_MEMORY_KEY` 核对为空。

`MEDIA_CAPTURE_ENABLED` 有一次性迁移(曾把已保存的 `"false"` 改成 true)。本机迁移标记文件 `~/.claude-mem/.settings.json.media-capture-default-on-v1` 已存在,所以写 `"false"` 会被保留。

脱敏验证:

| 方式 | 做法 | 结果 |
|---|---|---|
| 单元 | 直接调用源码 `redactSensitive`,配置同上,13 个用例 | GitHub token、OpenAI `sk-`、AWS `AKIA`、JWT、URL 里的密码(只替换密码,主机和用户名保留)、`password=`、`MY_API_KEY=`、`Authorization: Bearer`、带变量名的网关 key、带 Bearer 的 curl 里的网关 key,全部被替换成 `<redacted type='规则名'/>`。误伤对照 `max_tokens=4096` 和设备 ID 未被误伤 |
| 端到端 | 在真实工具调用里放 4 个假密钥,等观察者处理后扫描全库 38 张表 | 明文残留 0,库里有 redacted 标记 |

限制与未证实:

- **裸 key 不会被脱敏**:前后没有变量名或 `Bearer` 等关键词、也没有厂商前缀的字符串,规则认不出。实测漏掉了(网关 key 单独出现时未脱敏)。
- 对策是 `REDACT_CUSTOM_PATTERNS` 自定义规则,但这会把 key 的前缀写进 `settings.json`。已决定先不加。
- 库和日志里搜不到网关 key 明文,但**原因没完全查清**,不能当作脱敏一定可靠的证据。
- **未验证**:发给网关的请求包是否也已脱敏。没抓包,只是从调用点推断。
- 脱敏开启前的旧记忆不会被回头脱敏。

---

## 第 3 轮:采集,什么该记、什么不该记

### 目标

少记噪音,省观察者的调用次数(省钱省时间),也让记忆更干净。

### 先说结论:6 个键里,在 OpenCode 下真正有用的只有 SKIP_TOOLS

2026-11-08 逐个键用探针实测(往 `POST /api/sessions/observations` 发构造的工具事件,看返回 `skipped` 还是 `queued`),并读了 OpenCode 插件源码(`integrations/opencode-plugin/core.ts`)。

| 键 | 在 OpenCode 下 | 证据 |
|---|---|---|
| `SKIP_TOOLS` | **有效** | 实测:新增的 9 个工具名都返回 `skipped / tool_excluded`;`bash`、`read`、`grep`、`edit`、`write`、`task` 等 10 个对照仍入队。不区分大小写,`todowrite` 与 `TodoWrite` 都跳 |
| `SKIP_BASH_PATTERNS` | **无效** | 实测:设规则 `^echo CM_R3_PROBE` 后,工具名 `Bash` 被跳过(`bash_pattern_excluded`),但 `bash` 和 `shell` 照常入队。源码 `shellCommandOf` 只认 `Bash`、`PowerShell`、`exec_command` 三个名字,OpenCode 的命令工具叫小写 `bash`。要让它生效得改源码 |
| `SKIP_SUBAGENT_OBSERVATIONS` / `SKIP_AGENT_TYPES` | **无效** | 实测:请求带 `agentId` 和 `agentType` 时被跳过,不带则入队。源码判定"子代理事件"要求两个字段同时有值;而 OpenCode 插件发给 worker 的字段里没有 `agentId`、`agentType`(`captureTool` 只发 `contentSessionId`、`tool_name`、`tool_input`、`tool_response`、`cwd`、`platform_source`、`tool_use_id`)。所以 OpenCode 的子代理工具调用在 worker 看来都是主代理。**没有在真实子代理场景再跑一遍**,但上述两项合起来足以判断 |
| `EXCLUDED_PROJECTS` | 有效,但**当前不需要** | 实测:`/tmp/cm-r3-excluded/**` 配上后,该目录及其子目录返回 `project_excluded`,同级其他目录仍入队。你目前没有不想留记录的仓库,所以没配 |
| `OBSERVE_BARE_PROMPTS` | 保持默认 `false` | 没改,没测 |
| `OBSERVER_ENABLED` | 保持默认 `true` | 总开关,没改 |

### 依据:你自己的使用数据

没有靠猜。OpenCode 自己的库(`~/.local/share/opencode/opencode.db`,`part` 表)里有全部工具调用记录,取库内最近 30 天(库里最新一条是 2026-10-09)共 26763 次工具调用:

| 工具 | 次数 | 平均输出长度(字符) | 判断 |
|---|---|---|---|
| `bash` | 13713 | 1068 | 占一半,内容混杂,留着 |
| `read` | 4613 | 4740 | 留着,文件证据来源 |
| `edit` | 3106 | 333 | 留着 |
| `grep` | 1295 | 1832 | 留着 |
| `skill_mcp` | 1200 | 1549 | 留着 |
| `todowrite` | 692 | 872 | 出厂默认已跳 |
| `write` | 475 | 27 | 留着 |
| `glob` | 200 | 1510 | **跳**:只是文件名列表 |
| `question` | 92 | 196 | **跳**:向用户提问,没有结论价值 |
| `session_search` | 51 | 285 | **跳**:查别的会话,不是本会话产出 |
| `lsp_prepare_rename`、`lsp_diagnostics` | 74、4 | 31、20 | **跳**:输出几乎为空 |
| `background_cancel`、`invalid` | 17、6 | 229、3362 | **跳**:取消动作、无效调用 |
| `zhiyan-log_GetCurrentTimestamp`、`iWiki_prepareAttachmentUpload` | 14、21 | 29、37 | **跳**:只返回时间戳或上传句柄 |

子代理占比:主会话 24401 次、子代理会话 2362 次(约 9%),其中 `explore` 占 2033 次。这些在 OpenCode 下无法按子代理跳过,所以没配。

### 已配置的值

只改了 `SKIP_TOOLS`,其余 5 个键保持出厂默认:

```text
CLAUDE_MEM_SKIP_TOOLS = ListMcpResourcesTool,SlashCommand,Skill,TodoWrite,AskUserQuestion,glob,question,session_search,lsp_prepare_rename,lsp_diagnostics,background_cancel,invalid,zhiyan-log_GetCurrentTimestamp,iWiki_prepareAttachmentUpload
```

前 5 个是出厂默认,后 9 个是新增。改后 worker 读到的值已核对,`settings.json` 软链未被破坏。

### 刻意没跳的

| 工具 | 为什么留着 |
|---|---|
| `bash` | 占一半,但里面有 `npm run build`、`curl`、`git` 等有价值的命令,也有 `cd`、`ls`、`cat` 噪音;`SKIP_BASH_PATTERNS` 无效,没法只滤噪音,整体跳会丢大量信息 |
| `read`、`grep`、`edit`、`write` | 是"改了什么、看了什么"的主要证据 |
| `task`、`skill_mcp`、`webfetch`、`websearch_*`、`background_output` | 输出可能很长,但有研究结论价值。是否跳,要看实际产出的记忆质量,**没有数据支撑,不动** |

### 没解决的

- `bash` 里的 `cd`、`ls`、`cat` 噪音压不掉,要改源码才行(把 `shellCommandOf` 加上小写 `bash`)。这是源码补丁,升级会冲掉,没做。
- 子代理(约 9% 的调用)压不掉,原因同上,要让 OpenCode 插件发 `agentId`/`agentType`,也得改源码。
- 这一轮只是按工具名分类,没有评估"哪些工具产出的记忆质量高"。要做得精,需要跑几天后翻 viewer 看。

### observer 的跳过规则(mode 层,2026-11-10 补)

上面 6 个键都是"按工具/项目"在入队前拦。还有另一层:**观察者(observer)模型自己按 mode 文件里的规则判断"这条记不记"**。第 3 轮原先漏了这一层。

> mode 文件怎么加载、`MODE` 的配方怎么拆、JSON 里能写哪些键、怎么新建覆盖文件,单独写了一篇:[[claude-mem-mode文件与覆盖机制]]。本节只讲和"跳过规则"直接相关的部分。

**规则在哪:** `plugin/modes/code.json` 的两段提示词。
- `recording_focus`:该记什么(新能力、发布的修复、具体的调试发现等)。
- `skip_guidance`:该跳过什么。默认 `code` 里的要点:本会话已记过的事实/决策/修复,换说法也不再记;重复确认同一结果的迭代(评审轮次、重试)只记第一次;只描述"分析过程"的不记。跳过时 observer 回 `<skip_summary reason="noise" />`。

**中文模式有没有这套规则:有。** `code--zh.json` 只有 15 个键(翻译占位符),不含这两段;但 worker 的 `loadMode` 用 `parseInheritance` 按 `--` 把 `code--zh` 拆成父 `code` + 覆盖 `code--zh`,再 `deepMerge`(覆盖方有的键盖掉父,其余沿用父)。所以这两段规则对 `code--zh` 一直生效。依据:读 `worker-service.cjs` 的 `loadMode`/`parseInheritance`/`deepMerge`,**没有实测 observer 的行为**。

**实际现象:** 记忆整理这类多步操作(写新记忆、归档、删旧、复核),每一步都会各记一条"过程记忆",一次整理约 3 到 4 条。推测原因(推断,没验证):
- observer 按**单个会话**判断"是否已记过",子会话之间互相看不见;
- 每一步在它眼里都是新事实(写入了 #X、归档了 #Y),不算重复。

OpenCode 插件不发 `agentId`/`agentType`,`SKIP_SUBAGENT_OBSERVATIONS` 也压不住子会话,这一点见上面"没解决的"。

**原理:这个文件到底改了什么(读 `worker-service.cjs` 得出)**

1. **改的是 observer 的系统提示词。** 拼提示词的函数(`QGe`)按顺序把 `system_identity`、`observer_role`、`spatial_awareness`、`recording_focus`、`skip_guidance`、类型说明等段落拼成一段。`skip_guidance` 在其中原样出现,覆盖文件只是把这一段文字换掉,新增的规则就成了提示词里的一行。
2. **判断是 observer 这个 LLM 做的,不是程序。** 每来一条工具调用,observer 读完提示词,自己决定回两种东西之一:
   - 一个或多个 `<observation>…</observation>`:要记;
   - `<skip_summary reason="noise" />`:跳过。
3. **worker 只认格式。** 解析函数(`V6e`)看到回复里有 `<skip_summary … />`,就返回"空观察列表 + 已跳过",**不写库**,这条就没了。回复既不是观察也不是 skip 的(比如写了一句"跳过这条"之类的话),提示词里写明会**再问一次,仍不对就丢弃**。
4. **程序里没有"匹配到整理回执就丢"的逻辑。** 全靠模型照着提示词里那一行执行。

**这决定了两个限制:**
- **软规则,不保证。** 模型可能把"已归档 #1482"当成有价值的发现照记。第 6 条能压住多少,只能实测。
- **只管观察条目的生成。** 工具调用本身仍然送进 worker,原始调用另外同步落库(`upsertToolUse`)。这部分不进开场注入的 50 条,不占名额。

**和 `SKIP_TOOLS` 的区别:** `SKIP_TOOLS` 在入队前按工具名拦,是硬规则,但只能按工具名,拦不了"整理流程里的 shell 调用"而不误伤别的 shell。`skip_guidance` 是 observer 看到内容后自己判断,能按"这件事是不是整理回执"来跳过,但不保证。两者是两道关,可以同时用。

**可选的调法(没实测):** 不改插件文件(更新会被覆盖),用官方支持的覆盖 mode:
1. 新建覆盖文件(用户 mode 目录,见 [[claude-mem-配置详解]] 的 modes 说明;**文件名是 `code--<名字>.json`,不带 `zh`**,原因见 [[claude-mem-mode文件与覆盖机制]] 2.1),只写 `prompts.skip_guidance`,在默认文本基础上加一条"记忆整理等流程的操作回执(写入、归档、删除、复核确认)一律跳过,只记最终结论和踩坑"。
2. 把 `CLAUDE_MEM_MODE` 改成新 ID,重启 worker。
3. 回退:`MODE` 改回 `code--zh`,删掉覆盖文件。

**注意:** `MODE` 是全局的,影响所有项目;重启 worker 会中断正在被记录的会话;`skip_guidance` 是给 LLM 的文字规则,能压住多少没测。

#### 覆盖文件(已建在磁盘上,尚未启用)

**文件名和 `MODE` 的值不是同一个字符串,这里最容易搞错:**
- `CLAUDE_MEM_MODE` 填 `code--zh--lean`;
- worker 按 `--` 把它拆成父 `code`,加上两个覆盖 `code--zh`、`code--lean`,**按这个顺序**逐个 `deepMerge`;
- `code--zh` 是内置的(插件自带);`code--lean` 不是内置的,所以去用户目录找,文件就叫 **`~/.claude-mem/modes/code--lean.json`**(不是 `code--zh--lean.json`);
- 这样中文翻译键来自 `code--zh`,`skip_guidance` 来自最后合并的 `code--lean`,互不冲突;
- 用户目录里的同名文件如果和内置 mode 重名,会被忽略并报错 `bundled mode cannot be shadowed`,所以名字不能取成内置的。

`~/.claude-mem/modes` 是软链,指向 `~/.config/opencode/claude-mem/modes/`(和 `settings.json` 一样随配置仓库走)。

写法:覆盖文件**只需要写要覆盖的那一个键**(合并后才校验完整性)。`skip_guidance` 是字符串,覆盖会**整段替换**默认文本,所以前 5 条是对默认英文的逐条直译,只在后面追加第 6 条。规则本身改成了**中文**,方便人审;只有末尾的 `<skip_summary reason="noise" />` 标签必须原样保留,worker 用正则解析它。

```json
{
  "name": "Code Development (Chinese, lean)",
  "prompts": {
    "skip_guidance": "何时跳过\n------------\n跳过例行操作:\n- 本会话中你已经记录过的事实、决策或修复状态,即使换了说法也不要再记。尤其是反复确认同一结果的循环(评审轮次、重试、轮询):只在第一次确认时记一次,之后对同一事实的再次确认一律跳过。\n- 空的状态检查\n- 没有报错的软件包安装\n- 没有后续发现的简单文件列表\n- 查无结果的文件相关调研\n- 只说明\"做了某一步\"或\"结果符合预期\"的操作回执,例如:写入了一条记忆、归档或删除了旧记忆、\"记忆 #N 已写入\"、\"已归档到文件 X\"、复查确认删除生效、提交或推送完成。这类回执只有在结果出乎意料,或其中包含决策、根因、踩坑时才记。\n\n如果要跳过,请严格只回复 <skip_summary reason=\"noise\" />(reason 属性里写一句简短理由),不要回复其他任何内容。不要回复空内容,也不要用文字解释为什么跳过。"
  }
}
```

第 6 条是"判断标准"而不是"清单":只说明"做了某一步"或"结果符合预期"的回执一律跳过,**这类回执如果结果出乎意料、或包含决策、根因、踩坑,仍然要记**(限定"这类回执",避免被读成"所有观察都只有这几种才记")。英文对照和逐条说明见 [[claude-mem-mode文件与覆盖机制]] 5.2。

启用步骤(**都还没做**):
1. 确认文件和软链在:`ls -la ~/.claude-mem/modes/code--lean.json`(`~/.claude-mem/modes` 已软链到 `~/.config/opencode/claude-mem/modes/`);
2. 把 `CLAUDE_MEM_MODE` 改成 `code--zh--lean`(两份 settings.json 里 worker 读哪份没确认,见清单第 13 条);
3. 重启 worker;
4. 验证:取 `/api/context/inject` 看开头的 `Mode:` 行是否变化,再做一次整理,数新增过程记忆的条数,对比此前的 3 到 4 条。

已读源码确认的(`loadModeFile`/`loadMode`/`validateMode`):
- `parseInheritance("code--zh--lean")` 得到父 `code`、覆盖 `code--zh` 和 `code--lean`,所以要建的文件是 `code--lean.json`;
- `code--lean` 不是内置 mode,`loadModeFile` 会去 `~/.claude-mem/modes/` 找;
- 校验发生在合并之后,覆盖文件只写 `name` 和 `prompts.skip_guidance` 是可以的;
- 加载失败不会静默:抛 `Jw` 类错误直接失败,其余错误回退到内置 `code`(英文),所以文件写错的后果是 observer 输出变成英文,看 `Mode:` 行能发现。

仍然没验证的:
- 实际启动 worker 后合并是否如上述(只读了代码,没跑);
- LLM 看到新增的第 6 条后,真的会跳过整理回执,还是照记。

### 怎么验证

用探针(往 `/api/sessions/observations` 发构造的事件)最直接,返回 `skipped` 即生效。注意探针会在库里留一个空会话,没有观察、总结或提问记录。

### 回退

把 `SKIP_TOOLS` 改回出厂默认(前 5 个)即可。已记的笔记不会被删,只影响新采集。

### 总开关

`OBSERVER_ENABLED` 默认 `true`,显式写 `"false"` 才关闭"新笔记和会话摘要"的生成;写错按开启处理。想临时停止记忆,用这个。

---

## 第 4 轮:注入,开会话时塞多少旧记忆

### 先理解

每次新开会话,claude-mem 会把一批旧记忆塞进上下文。塞得多,模型"记得"多,但也更占上下文、更费 token。这一轮的目标是找到适合你的量。

### 键

| 键                           | 默认          | 说明                                                 | 调法                                                                                                                                 |
| --------------------------- | ----------- | -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `CONTEXT_OBSERVATIONS`      | `50`        | 最多注入多少条观察。校验范围 0 到 200,取最近的 N 条                    | 嫌上下文太满就降到 20 到 30;想要更多历史就升                                                                                                         |
| `CONTEXT_SESSION_COUNT`     | `10`        | 显示最近多少次"会话总结"                                      | 一般不动。上下文超预算时会被减半                                                                                                                   |
| `CONTEXT_FULL_COUNT`        | `0`         | 最近前 N 条除了标题还展开详细内容。0 = 全只显示标题                      | 想让最近几条更详细可设 3 到 5。上下文瘦身时它最先被砍                                                                                                      |
| `CONTEXT_FULL_FIELD`        | `narrative` | 展开时用哪个字段:`narrative`(叙述长文)或 `facts`(要点列表)          | 只在 `FULL_COUNT` 大于 0 时有用。**实测 `facts` 反而比 `narrative` 更长**(`FULL_COUNT=3` 时 6095 对 5645 字符,样本仅 3 条展开),原先"想省 token 用 `facts`"的说法不成立 |
| `CONTEXT_OBSERVATION_TYPES` | 空           | 类型白名单,如 `bugfix,decision,discovery`。空 = 当前模式里的所有类型 | 只能缩小不能超出模式的类型表;模式里没有的名字被忽略                                                                                                         |
| `CONTEXT_MAIN_AGENT_ONLY`   | `true`      | 注入时不带子代理的笔记,避免流水账挤掉主会话的长期记忆                        | 保持。搜索和 viewer 仍能看到全部                                                                                                               |

### 调教顺序建议

1. 先保持默认 50,用一两天。
2. 感觉"开场塞太多废话":降 `CONTEXT_OBSERVATIONS`,并用 `CONTEXT_OBSERVATION_TYPES` 只留 `decision,bugfix` 这类高价值类型(观察类型表在 `plugin/modes/code.json`,已读:`bugfix`、`feature`、`refactor`、`change`、`discovery`、`decision`、`security_alert`、`security_note`、`sensitive`。`code--zh.json` 只有提示词文案,没有类型表,类型沿用 `code`,所以白名单里写英文类型名)。
3. 感觉"记得不够细":升 `CONTEXT_FULL_COUNT`。

### 验证

注入文本可以直接取:OpenCode 插件开会话时调用的就是 `GET /api/context/inject?cwd=<目录>&platformSource=opencode`,用 `curl -G` 带上这两个参数即可拿到原文并量长度。

### 实测结果(2026-11-08)

库里当时 130 条观察、20 条总结。默认值下注入约 5000 字符(折算约 2500 到 3300 token,按中英混合估算),由 50 条观察标题、10 条会话总结和一段约 1450 字符的"待办清单"说明组成。逐键改动后的长度:

| 动作 | 注入字符数 | 结论 |
|---|---|---|
| 默认(50/10/0) | 约 5035 | 基线 |
| `OBSERVATIONS=30` | 4223 | 只省约 800,不值得 |
| `FULL_COUNT=3`,`narrative` | 5645 | 多约 600,换最近 3 条展开正文 |
| `FULL_COUNT=3`,`facts` | 6095 | 比 `narrative` 更长 |
| `OBSERVATION_TYPES=decision,change` | 6006,观察变 35 条 | 变长,且库里 discovery 占 103/130,过滤后丢掉"发现了什么"类结论 |
| `WORK_STATE_ENABLED=false` | 3580 | 省约 1450,代价是失去 `work_state_write` |
| `MEMORY_INSTRUCTIONS_ENABLED=false` | 5035,无变化 | 在 OpenCode 下无效 |

结论:总量本来就小,每个键最多省 15% 到 30%,**不改任何键**。`MEMORY_INSTRUCTIONS_ENABLED` 无效的原因是它只在 Claude Code 的钩子路径(`cli/handlers/context.ts`)里读取,OpenCode 走的是 `/api/context/inject`,不读它。`CONTEXT_MAIN_AGENT_ONLY` 在 OpenCode 下也形同虚设,因为插件不发 `agentId`/`agentType`,所有事件都当主代理。

新项目(库里没有任何观察)注入的是约 2050 字符的欢迎提示,不含记忆段。

### 想要但要谨慎:每次提问的语义注入

| 键 | 默认 | 说明 |
|---|---|---|
| `SEMANTIC_INJECT` | `false` | 实验性。设 `"true"` 后,每次你提交提示词(需 20 个字符以上,且不是纯媒体),按意思去搜相关旧记忆追加进来 |
| `SEMANTIC_INJECT_LIMIT` | `5` | 每次最多注入几条,服务端夹在 1 到 20 之间 |

**不建议这一轮开。** 它走的是普通搜索入口,据此推断同样受 90 天窗口约束、依赖向量检索质量。而你的笔记是中文,默认向量模型对中文弱(见第 5 轮)。先把第 5 轮的召回质量搞清楚,再决定要不要开。

**在 OpenCode 上很可能不生效(2026-11-09 补,读源码核对,未实测)**
- 读这个开关并请求语义注入的代码,只在 Claude Code 的提问钩子 `src/cli/handlers/session-init.ts`(231 到 258 行)。
- OpenCode 插件源码 `src/integrations/opencode-plugin/` 里搜不到 `semantic`,没有读这个开关,也没有请求语义注入接口。已装的 `~/.config/opencode/plugins/claude-mem.js` 里只有一份打包进去的默认设置表(值为 `"false"`),不是调用。
- 所以你用 OpenCode 时,设 `SEMANTIC_INJECT="true"` 多半**什么都不会发生**。这是读代码的推断,没有在 OpenCode 上实测开关前后的差别。
- OpenCode 上"开场给我多少记忆"靠上面的 `CONTEXT_OBSERVATIONS`(按时间取最近 N 条标题),不是按问题相关度。
- 另外,`claude_mem_search` 工具每次固定返回 **10 条**,数字写死在插件源码里(`opencode-plugin/core.ts:443` 的 `limit=10`),**没有配置项**。详见 [[claude-mem-本地多语言向量方案]] 5.7。

### 其他注入类键(默认值已合理)

| 键 | 默认 | 备注 |
|---|---|---|
| `MEMORY_INSTRUCTIONS_ENABLED` | `true` | 注入时附一段"怎么用 claude-mem 记忆"的说明。**在 OpenCode 下无效**(实测设 `false` 长度不变,见上)。只对 Claude Code 路径有效 |
| `WELCOME_HINT_ENABLED` | `true` | 项目还没有任何观察时,注入一段欢迎提示,第一条记忆落库后消失 |
| `WORK_STATE_ENABLED` | `true` | 注入"工作状态(待办清单)"段落。你自己另有任务跟踪(如 todo 工具)可设 `false` |
| `REINFORCE_ALPHA` | `0` | 实验性排序权重,0 = 关,注入就是"最近的 N 条"。文档建议试 0.5,**暂不动** |

---

## 第 5 轮:检索,中文召回与 90 天窗口

### 先看清现状

你的笔记是中文,而本机默认配置在中文上有两个已知短板(下表是读源码得出;向量层的中文召回另有实测,见本节"实测结果"):

| 短板 | 在哪 | 是什么 |
|---|---|---|
| 1. 向量层 | `ChromaSync.ts`,由 `CHROMA_EMBEDDING_FUNCTION=default` 决定 | 默认嵌入模型 `all-MiniLM-L6-v2` 是英文调优,词表把中日韩文字切成单字或 `[UNK]`,"换个说法找同一件事"这种语义召回对中文偏弱(源码注释承认,Issue #3422) |
| 2. 关键词层 | `SessionSearch.ts`,查询含汉字就跳过全文检索 | SQLite 的 FTS5 不切分汉字,于是降级成多列 `LIKE '%…%'` 子串匹配。"登录页面"和"页面登录"除非挨在一起否则匹配不上 |

还有第三个坑,和中文无关但会让你搜不到旧东西:**90 天窗口**。

### 键

| 键                           | 默认                 | 建议             | 说明                                                                                                                                                                                                  |
| --------------------------- | ------------------ | -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SEARCH_RECENCY_DAYS`       | `90`               | 建议改成 `"0"` 或更大 | 不带日期的语义搜索只返回最近 N 天的匹配。默认 90,所以**超过 90 天的旧记忆在语义搜索里搜不到**。`0` = 关闭窗口。明确给 `dateStart/dateEnd` 时以你给的范围为准。非非负整数的值会被忽略保持 90。改完要重启 worker                                                                   |
| `CHROMA_EMBEDDING_FUNCTION` | `default`          | **先别改**        | 白名单只有 `default`/`openai`/`cohere`/`jina`/`voyageai`/`roboflow`。除 `default` 外全是云端 API,**会把你的记忆文本发给第三方**。只对新建集合生效,改了还必须重建索引                                                                           |
| `CHROMA_MODE`               | `local`            | 保持             | `local` 由 worker 用 uvx 在本机起 chroma-mcp 子进程;`remote` 连已有的 Chroma 服务                                                                                                                                  |
| `EMBEDDING_MODEL`           | `all-MiniLM-L6-v2` | **改了也没用**      | 可选 4 个(含 3 个多语言),但**只在服务器模式(Postgres + pgvector)下被读取**。worker/Chroma 路径用的是 `CHROMA_EMBEDDING_FUNCTION`。这条由 grep 确认:`CLAUDE_MEM_EMBEDDING_MODEL` 在 src 里只被 `ObservationEmbeddingService.ts`(服务器模式)读取 |

### 90 天窗口对"补查"的影响

已读 `SearchOrchestrator.ts`(第 155 到 195 行):Chroma 有 query 时先走语义搜索,**只有某个类别(观察、会话、提示词)整类为空,才去 SQLite 补查**;SQLite 补查不套 90 天窗口(源码注释明说)。所以**如果近 90 天里有几条不相干的结果,这一类就不算空,100 天前那条精确匹配的笔记不会被 LIKE 捞回来**。这个推论已用构造的数据实测证实(见下)。所以第一件事就是放宽窗口。

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

### 实测结果(2026-11-08)

**已配置:`SEARCH_RECENCY_DAYS = "0"`**,其余 3 个键(`CHROMA_EMBEDDING_FUNCTION`、`CHROMA_MODE`、`EMBEDDING_MODEL`)保持默认。worker 约 7 秒后读到新值,搜索正常,`settings.json` 软链完好,日志无告警。

这一轮不能在真实库上对比,因为库里最早一条观察是今天 16:17,没有超过 90 天的数据。改用上游源码直接跑,构造数据验证两条推论:

| 实验 | 构造 | 结果 |
|---|---|---|
| 窗口过滤 | 向量层命中 2 条:5 天前一条、100 天前一条 | 窗口 90 天只返回 `[1]`;窗口 0 返回 `[1,2]` |
| 补查推论 A | 向量层近期无命中(该类整类为空),关键词层有一条 100 天前的精确命中 | 触发 SQLite 补查,返回 100 天前那条 |
| 补查推论 B | 向量层近期有 1 条不相干命中,关键词层同样有 100 天前的精确命中 | 不触发补查,SQLite 调用 0 次,100 天前那条被漏掉 |

B 就是之前推论的情形:近 90 天里只要有一条不相干的向量结果,这一类就不算空,100 天前的精确命中捞不回来。关掉窗口后向量层本身就不再按时间截断,这个坑就没了。上游自带的 `chroma-search-strategy.test.ts` 37 条测试通过(含 `0` 关闭窗口、自定义 N 天、显式日期范围优先、corpus 构建绕过窗口)。

限制:以上用 mock 数据在源码层验证,没有在真实向量库里放 90 天前的数据再搜。关窗口的副作用(旧而不相关的结果混进来)取决于向量层返回多少候选,本机库太小,看不出来。

### 中文召回

此前已实测(纯向量,29 条观察、12 条查询,样本小,仅作方向):英问英与英问中尚可,**中问英垫底**(命中排名 29/20/22)。`all-MiniLM-L6-v2` 是英文调优模型。

可选项的取舍:

| 选项 | 状态 |
|---|---|
| 云端嵌入函数(`openai`/`cohere`/`jina`/`voyageai`/`roboflow`) | **不建议**:会把记忆文本发给第三方,与第 2 轮隐私目标冲突;只对新建集合生效,还得重建索引 |
| `EMBEDDING_MODEL` 换多语言模型 | **无效**:只在服务器模式(Postgres + pgvector)读取 |
| 服务器模式 | 要 Postgres,不是轻量用法,没试 |
| 改源码换本地多语言嵌入(`LocalEmbedder`→`ChromaSync`) | 只改配置做不到,没实现 |
| memsearch(自带本地 bge-m3) | 备选方向,没评估 |

结论:中文召回的短板**这一轮没有改配置能解决的办法**,先接受现状。关键词层对原词匹配可用,实际表现等 DSH 接入、真实项目积累几百条以后再评估。

**后续订正(2026-11-08)**:上面"没有改配置能解决"只对 `CLAUDE_MEM_EMBEDDING_MODEL` 成立(本机路径改任何值都不报错也不生效)。后来发现可以借 `CLAUDE_MEM_CHROMA_EMBEDDING_FUNCTION=openai` 加 `~/.chroma_env` 指向本机 Ollama 的 bge-m3,已上线。30 条手工标准答案验收:中问中从基本不可用变成勉强可用(第 1 名 4 到 8 条/20,前 3 名 5 到 12 条/20),英问中没变好;**及格不是达标**。另外 `CHROMA_EMBEDDING_FUNCTION` 填白名单外的值,运行中不报错,重启 worker 后才报错;`DELETE /api/observation/:id` 会同步清 SQLite 与向量。原理、步骤、验收见 [[claude-mem-本地多语言向量方案]]。

### 中文召回的最终做法(2026-11-09 补)

**一句话:没有改源码。用 Ollama 在本机跑多语言模型 `bge-m3`,把它伪装成 OpenAI 的嵌入接口,让 claude-mem 借用的 chroma-mcp 去连它。数据不出本机。**

**用了哪几样东西**

| 东西 | 在哪 | 作用 |
|---|---|---|
| Ollama + `bge-m3` | 本机 `127.0.0.1:11434` | 真正算向量的多语言模型,1024 维 |
| 模型别名 `text-embedding-ada-002` | Ollama 里,`ollama cp bge-m3 text-embedding-ada-002` | chroma-mcp 的 OpenAI 嵌入函数无参构造时只认这个模型名,别名让它指向 bge-m3。**不能删、不能覆盖** |
| `~/.chroma_env` | 软链,真文件在 `~/.config/opencode/claude-mem/chroma_env` | 写 `OPENAI_BASE_URL=http://127.0.0.1:11434/v1` 和占位的 `OPENAI_API_KEY`。chroma-mcp 启动时会读它 |
| `CLAUDE_MEM_CHROMA_EMBEDDING_FUNCTION` | `settings.json`,值 `"openai"` | 让 claude-mem 用 openai 这个嵌入函数名。这个名字实际连的是上面的本机 Ollama,不是云端 |

**软链关系**
- `~/.chroma_env` 是软链,指向配置仓库里的 `claude-mem/chroma_env`,所以这份配置跟着配置仓库走。
- 同理,`~/.claude-mem/settings.json` 软链回 `~/.config/opencode/claude-mem/settings.json`。
- 里面的 key 只是占位,不是真 key;网关的真 key 只在 `.env`。

**做法(顺序)**
1. 拉模型并建别名:`ollama pull bge-m3`,再 `ollama cp bge-m3 text-embedding-ada-002`。
2. 写 `chroma_env` 并软链到 `~/.chroma_env`。
3. 备份后,在 `settings.json` 加 `CLAUDE_MEM_CHROMA_EMBEDDING_FUNCTION="openai"`。
4. 旧的 384 维向量库改名保留(`chroma.old-384`),重启 worker,整库自动重建为 1024 维(约 70 秒)。
5. **回退**:函数改回 `default`,换回 `chroma.old-384` 与 `chroma-sync-state.json`,重启 worker。

**效果(以最新验收为准)**

| 口径 | 结果 |
|---|---|
| 30 条手工标准答案,中问中,第 1 / 前 3 / 前 6 名 | 8 / 16 / 18(共 20 条) |
| 同上,英问中 | 3 / 7 / 9(共 10 条) |
| 9884 道 LLM 出题,线上现状 | 第 1 名 61.6%,前 6 名 90.9%,按我预设的线是"及格" |

- 上一段"4 到 8 条、前 3 名 5 到 12 条"是我早期用错口径(按表格出现顺序当名次)得出的,**已被上表取代**。
- 结论:中文从基本不可用变成可用,但**及格,没到好**。主因更像是库里同主题条目太相似和 claude-mem 的向量化方式,不是模型。
- 完整过程与数据:[[claude-mem-本地多语言向量方案]] 的 5.3(验收)、5.4(根因)、5.5(换模型)、5.6(大批量压测)。

**要知道的限制**
- `.chroma_env` 是 chroma-mcp 自带的行为,不是 claude-mem 官方支持的配置,升级后可能失效。
- Ollama 变成常驻依赖;没开时新记忆写不进向量库,恢复后会回填(推断,没专门测)。
- chroma-mcp 无法给查询加前缀,所以不能换需要前缀的模型(如 Qwen3)。

---

## 第 6 轮:跨端,OpenCode 与 DSH 共用记忆

### 这一轮的核心

两端要共用记忆,取决于三件事:**项目是否一致、来源是否被过滤、DSH 是否真的在采集**。

### 键

| 键                                   | 默认      | 要改成      | 说明                                                                                                                 |
| ----------------------------------- | ------- | -------- | ------------------------------------------------------------------------------------------------------------------ |
| `SESSION_START_INCLUDE_ALL_SOURCES` | `false` | `"true"` | 默认只注入"本工具自己"写的记忆(按 `platform_source` 过滤),所以 OpenCode 看不到 DSH 写的、反之亦然。设 `true` 就不按来源过滤。OpenCode 插件每次请求实时读它,**无需重启** |
| `PROJECT_NAME_SOURCE`               | `path`  | 视情况      | 决定"这条记忆算哪个项目"。`path` = 用 git 仓库根目录的文件夹名;`git-remote` = 用 origin 地址推出的 `org/repo`,改目录名也不变。**两端同目录同设置才会落到同一项目**      |
| `TRANSCRIPTS_ENABLED`               | `true`  | 保持       | DSH 的记忆是靠 worker 读 DSH 会话记录采集的。设 `false` 则 DSH 自动采集失效                                                              |

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

### 实测结果(2026-11-09)

**一句话:读、写、搜索三个方向都通了,但 `desktop` profile 要手动装。**

- **`desktop` profile 不能用官方安装器装。** `dsh` 命令行写死拒绝名字叫 `desktop` 的 profile(`@deepseek-ai/dsh/lib/bin.js:36`),与桌面应用是否运行无关。安装器还会顺带把 claude-mem 本体升级并停掉 worker,别反复跑。
- **手动做法两件事:** ① 在 DSH 配置仓库的 `desktop/package.json` 加 `@claude-mem/dsh` 依赖和 bundle;② 新建 `~/.claude-mem/transcript-watch.json`(监听名 `dsh`,目录 `~/.dsh/sessions`,`startAtEnd: true`),重启 worker。本机把监听文件放进配置仓库并软链。
- **DSH 来源名是 `dsh`**(已实测)。
- **项目名一致,但看在哪个目录开 DSH:** 在 `my-note` 开则项目是 `my-note`,在 `~/.config/opencode` 开则项目是 `opencode`。
- **OpenCode 能搜到 DSH 写的观察**(搜"武汉天气"排第 1、2 名);**DSH 启动时能读到 OpenCode 写的观察概览**(启动注入与主动搜索两路都通)。
- 只有问答、没有工具调用的 DSH 会话,不产生观察,只产生摘要。
- **DSH 的 `mem_search` 工具能搜到 OpenCode 写的记忆**(在 DSH 问"搜一下 claude-mem 向量方案",返回 30 条,含 OpenCode 写的观察 `#315` 等)。
- 完整过程见 [[claude-mem-跨端共享]] 第 8 节。

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

1. codebuddy 的真实 OpenAI 兼容地址:不需要了,本机走公司网关,模型 `deepseek-v4.1-flash`。
2. 观察者经公司网关调通:已实测。笔记质量只看过数量和语言,额度限制没查。
3. `host` 提供方:源码确认它依赖本机已在运行的兼容服务,安装器不起;OpenCode、DSH 上有没有现成服务,没读到。
4. viewer 的具体地址、备份快照的具体目录:没读到。
5. `code--zh` 模式沿用 `code` 的类型表(已读 `code.json`);`code--zh` 实际输出的笔记质量没实测。
6. OpenCode 里能否直接看到注入的上下文文本:界面里能否看到没读到;但可用 `/api/context/inject` 取到同样的文本,见第 4 轮。
7. 用户手写 JSON 布尔值或数组(而非字符串)是否被接受:没读到,照字符串写最稳。
8. 中文向量召回:默认模型下已实测偏弱(纯向量,样本小,中问英垫底);后来不改源码,靠 `CHROMA_EMBEDDING_FUNCTION=openai` 加本机 Ollama 的 bge-m3 换成多语言向量,已上线,数字见 [[claude-mem-本地多语言向量方案]] 5.3。
9. 90 天窗口对补查的影响:已用构造数据在上游源码层实测,推论成立;没有在真实向量库里放 90 天前的数据验证。
10. DSH 写入记忆时用的来源名:已实测是 `dsh`。
11. 两端同目录算出的项目名是否一致:已实测一致(都是 `my-note`),但取决于在哪个目录开 DSH。
12. 图片采集的具体上限(本地 3 MiB、给模型 256 KiB、每事件最多 4 张)来自源码注释,没实测。
13. 覆盖 mode 的 `skip_guidance` 能压住多少"过程记忆"(整理流程的写入/归档/复核回执):没测。改 `MODE` 后是否必须重启 worker、两份 `settings.json` 里 worker 实际读哪份:也没确认。见第 3 轮"observer 的跳过规则"。
