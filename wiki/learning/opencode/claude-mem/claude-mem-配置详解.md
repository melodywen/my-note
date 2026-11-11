---
type: concept
status: developing
area: growth
title: "claude-mem 配置详解"
created: 2026-11-08
updated: 2026-11-11
tags:
  - learning
  - opencode
  - dsh
  - claude-mem
  - 配置
related:
  - "[[claude-mem-深入调研]]"
  - "[[OpenCode与DSH共享记忆-选型调研]]"
  - "[[claude-mem-安装部署]]"
  - "[[claude-mem-存储与读取机制]]"
  - "[[claude-mem-跨端共享]]"
  - "[[claude-mem-调教清单]]"
---

# claude-mem 配置详解

> 一句话:**claude-mem 的全部设置都在 `~/.claude-mem/settings.json` 一个文件里,新手只需要改 5 到 6 个键(观察者提供方、地址、密钥、模型、模式、脱敏开关),其余保持默认;隐私相关的几个键要装完核对一遍。**
>
> 基于 claude-mem main 分支(约 v15.12.0)源码,主体是读源码的结论;238 键清单按 v15.12.0 整理。本机已于 2026-11-11 升到 v15.16.0,升级后键清单未逐项重新核对,其中 SKIP_*、REDACT_* 等条目已按 v15.15.x/v15.16.0 复核;本机已实测的部分(观察者、向量、跨端)见 [[claude-mem-调教清单]]、[[claude-mem-本地多语言向量方案]]、[[claude-mem-跨端共享]]。
>
> **想一点点调教?** 看 [[claude-mem-调教清单]]:它从 238 个键里挑出约 40 个,按"先后顺序"分 8 轮,每轮有验证方法和回退值。

---

## 第一层:大白话

### 配置文件是什么、在哪

claude-mem 有一个常驻本机的后台进程,叫 **worker**(可以理解成"值班的小管家")。它做什么、用哪个模型、记多少、往哪存,都看一张"设置清单",这张清单就是:

```
~/.claude-mem/settings.json
```

文件里是一个 JSON 对象,每一项是 `"键": "值"`,键都以 `CLAUDE_MEM_` 开头。源码里定义了 **238 个**这样的键(`src/shared/SettingsDefaultsManager.ts`,用脚本数过)。

**全新安装时,worker 第一次启动会把这 238 个默认值整份写进文件**(第 893 到 915 行,已读源码),所以装完你看到的是一份很长的完整 JSON,不是只有几行。完整内容见文末附录。你要改的只是其中几项,其余保持原样。读取时如果某个键缺失,会用源码里的默认值兜底。

### 改了怎么生效

改完文件**需要重启 worker**,不会自动热加载。命令:

```bash
npx claude-mem restart
# 或
npx claude-mem worker restart
```

这一条来自"已读源码推断":配置主要在进程初始化或具体功能点读取,所以改全局设置通常要重启宿主进程。没有逐个键验证过是否都需要重启。

### 先认几个词

| 词               | 大白话                                                                                               |
| --------------- | ------------------------------------------------------------------------------------------------- |
| 观察者模型           | 像一个"记账员"。你(或 agent)每调用一次工具,claude-mem 把这次操作的内容交给它,它写成一条简短笔记存起来。记账员用的是哪家的模型,由配置决定,每次工具调用都要花一次调用成本。 |
| 提供方(provider)   | 记账员"在哪上班",也就是调哪家的接口:`claude`、`codex`、`gemini`、`openrouter`、`openai-compatible`、`host`(`host` 需要本机已有兼容服务,对 OpenCode/DSH 不推荐)。                                |
| 模式(mode)        | 记账员的"工作手册"。同样是记代码开发,英文手册让它写英文笔记,中文手册(`code--zh`)让它写中文笔记。手册是 `plugin/modes/` 下的一个 JSON 文件。         |
| 向量嵌入(embedding) | 把一句话变成一串数字,意思相近的话数字也相近,所以能"按意思找",不要求关键词一字不差。像给每条笔记在地图上标一个坐标,查询时找离得近的。                             |
| Chroma          | 存这些"坐标"的向量数据库,也负责"找最近的几个"。像一个按坐标排好的档案柜。claude-mem 默认开着,本机运行。                                      |
| SQLite          | 另一个本机数据库,存笔记原文,做关键词检索。                                                                            |
| 脱敏(redact)      | 存之前把密钥、口令之类敏感串替换掉。                                                                                |

向量嵌入、Chroma 在检索里具体怎么用,见 [[claude-mem-存储与读取机制]]。

---

## 第二层:最小可用配置

新手只需要关心下面 6 个键。注意:这几个键安装器**不会帮你填**,`openai-compatible` 只能手改 `settings.json`(`src/npx-cli/commands/install.ts` 里明确写了这一点)。

| 键                                | 填什么                         | 为什么要改                                                                   |
| -------------------------------- | --------------------------- | ----------------------------------------------------------------------- |
| `CLAUDE_MEM_PROVIDER`                | `openai-compatible`         | 默认是 `claude`。要接 codebuddy 这类自定义的 OpenAI 兼容地址,优先用 `openai-compatible`:它是独立的提供方,不带 OpenRouter 的归因请求头,key 也和 OpenRouter 分开(见第三层第 09、10 组) |
| `CLAUDE_MEM_OPENAI_COMPAT_BASE_URL`  | `<codebuddy 的 OpenAI 兼容地址>` | 让观察者调用 codebuddy。留空且不选预设,就不会连任何地方,只报"未配置端点" |
| `CLAUDE_MEM_OPENAI_COMPAT_API_KEY`   | `<codebuddy 的 API Key>`     | 调用凭证 |
| `CLAUDE_MEM_OPENAI_COMPAT_MODEL`     | `<便宜的模型名>`                  | 原样传给接口。每次工具调用都会调用一次,选便宜的。留空会用预设的默认模型,自定义地址下建议必填 |
| `CLAUDE_MEM_MODE`                | `code--zh`                  | 让观察和摘要用中文写                                                              |
| `CLAUDE_MEM_REDACT_ENABLED`      | `true`                      | 默认 `false`;打开后存之前自动脱敏                                                   |

可以直接抄的示例(尖括号处换成你自己的):

```json
{
  "CLAUDE_MEM_PROVIDER": "openai-compatible",
  "CLAUDE_MEM_OPENAI_COMPAT_BASE_URL": "<codebuddy 的 OpenAI 兼容地址>",
  "CLAUDE_MEM_OPENAI_COMPAT_API_KEY": "<codebuddy 的 API Key>",
  "CLAUDE_MEM_OPENAI_COMPAT_MODEL": "<便宜的模型名>",
  "CLAUDE_MEM_MODE": "code--zh",
  "CLAUDE_MEM_REDACT_ENABLED": "true"
}
```

说明:

- 本机实际没有直连 codebuddy,而是走公司网关,模型 `deepseek-v4.1-flash`,已跑通(见 [[claude-mem-调教清单]] 第 1 轮)。这里的示例保留占位符,方便别的环境照抄。
- 研究文件的推荐示例里,布尔值写成了字符串 `"true"`/`"false"`;源码是否同样接受 JSON 布尔值,没读到,照抄字符串写法最稳。
- 另有三个键值得顺手关掉,默认值都已读源码:`CLAUDE_MEM_REDACT_GENERIC_ENABLED`(默认 `false`,打开后连没有固定前缀的密码、`*_TOKEN=`、`Authorization: Bearer` 也脱敏)、`CLAUDE_MEM_MEDIA_CAPTURE_ENABLED`(**默认 `true`,会把图片存在本机**,不想存就设 `false`)、`CLAUDE_MEM_TELEGRAM_ENABLED`(**默认 `true`**,但没填 bot token 和 chat id 就不会发送)。这几个不是必须的。
- "关统计"不靠 `settings.json`,用命令:

```bash
npx claude-mem telemetry disable
```

- 观察者:已实测经公司网关调用通过,直连 codebuddy 未试(推断行不通)。
- 改完记得重启 worker,再按文末"配置自检清单"核对。

---

## 第三层:分组详解(238 个键全部在内)

说明:

- 共 20 组,每组一张表。键名省略了 `CLAUDE_MEM_` 前缀,实际写进文件时要带上。
- "默认值"来自源码 `DEFAULTS`;"空"表示默认是空字符串。有 11 个默认值是运行时算出来的,按本机填的具体值,见文末附录。
- "注释"由读源码得出,括号里是依据的文件。没标"推断"的,都是在源码里找到了读取位置。
- "新手"一列是建议:**不动**(保持默认)、**按需**(有需求再改)、**建议改**(多数人该改)、**保持为空**(填了会有副作用)、**装完核对**(装完去确认值对不对)。
- 所有值都是字符串,包括 `"true"`、`"false"` 和数字。

| 组 | 管什么 | 键数 |
|---|---|---|
| 01 | Worker 进程与通信 | 16 |
| 02 | 数据、日志与备份 | 8 |
| 03 | 采集范围与过滤 | 11 |
| 04 | 项目归属与会话来源 | 10 |
| 05 | 观察者:选谁来写笔记 | 16 |
| 06 | 提供方:Claude | 6 |
| 07 | 提供方:Codex | 6 |
| 08 | 提供方:Gemini | 4 |
| 09 | 提供方:OpenRouter(可接自定义地址) | 9 |
| 10 | 提供方:OpenAI 兼容 | 7 |
| 11 | 观察者请求行为 | 7 |
| 12 | 隐私与脱敏 | 5 |
| 13 | 会话开始时注入什么 | 20 |
| 14 | 每次提问时的语义注入与文件夹说明 | 7 |
| 15 | 向量与检索(Chroma、嵌入模型) | 17 |
| 16 | 去重 | 7 |
| 17 | 云同步、团队与账号 | 27 |
| 18 | 服务器模式与队列 | 13 |
| 19 | 通知与外部集成 | 32 |
| 20 | My Work 视图 | 10 |

### 01. Worker 进程与通信

管后台常驻小服务 worker 怎么启动、监听哪里、hook 怎么找到它、多久算超时。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `WORKER_PORT` | `37701` | worker(后台常驻服务)监听的本地端口号,hook(钩子:agent 某个时刻自动触发的小程序)和 OpenCode/DSH 插件都靠它找到 worker。默认值不是固定的 37700,而是 37700+(uid%100)(uid 是当前系统用户编号;取不到 uid 时用数据目录路径的哈希对 100 取余),所以不同用户/机器上数字不同,你这里是 37701。(src/shared/install-port.ts) | 装完核对 |
| `WORKER_HOST` | `127.0.0.1` | worker 监听的网卡地址。默认 127.0.0.1 表示只允许本机访问;改成非回环地址会把 worker API 暴露到网络,启动时源码会发出警告(未配 TV_TOKEN 时)。(src/shared/worker-utils.ts、src/services/worker-service.ts) | 不动 |
| `WORKER_URL` | 空 | 给客户端(hook/插件)指定的完整 worker 地址,如 https://xxx。留空表示按 HOST+PORT 连本机;一旦填了,就被视为“worker 由外部管理”,hook 不会再自己拉起 worker,且必须是 http(s) 绝对地址、非本机必须用 https。(src/shared/worker-url.ts、src/shared/worker-autostart.ts) | 保持为空 |
| `WORKER_INGEST_TOKEN` | 空 | 远程上报口令:当 hook 在另一台机器、需要通过 HTTP 把事件传给 worker(/api/spool/ingest)时,双方用这个口令做 Bearer 认证。留空则 worker 拒绝远程上报(返回 503)。本机单机使用用不到。(src/services/worker/http/routes/HookSpoolRoutes.ts) | 保持为空 |
| `WORKER_INGEST_MAX_BYTES` | `5242880` | 远程上报接口单次请求体的大小上限,单位字节,默认 5242880(5 MiB);填的值不是正整数时回退到 5 MiB。只在启用远程上报时有意义。(src/services/worker/http/routes/HookSpoolRoutes.ts) | 不动 |
| `HOOK_SPOOL_TRANSPORT` | `auto` | hook 把事件交给 worker 的“暂存队列(spool)”走哪条路:'http' 强制走 HTTP 上传,'filesystem' 强制走本地文件,默认 'auto' 则按 WORKER_URL/WORKER_HOST 是否指向非本机自动判断(本机=文件,远程=HTTP)。(src/shared/hook-spool-remote.ts) | 不动 |
| `ALLOWED_ORIGINS` | 空 | 允许哪些浏览器来源(origin,即网页的 协议+域名+端口)跨域调用 worker 的 API,逗号分隔的完整 origin 列表;本机 localhost/127.0.0.1 默认放行。放进来的域名也会通过防 DNS 重绑定的 Host 检查,不在列表里的页面发删除请求会被拒。仅在通过自定义域名/反代访问网页界面时才需要。(src/services/worker/http/origin-policy.ts、middleware.ts) | 保持为空 |
| `PUBLIC_URL` | 空 | worker 跑在端口转发/反向代理后面时,界面(viewer,记忆的网页查看器)的链接应该显示成什么浏览器可访问的地址,例如 https://37700.host.<user>.<domain>;留空则按 localhost 生成链接。环境变量同名值优先。(src/shared/viewer-url.ts) | 保持为空 |
| `API_TIMEOUT_MS` | `30000` | hook 调用 worker API 的超时时间,单位毫秒,默认 30000(30 秒),有效范围 500~300000,越界回退默认值。超时后该次 hook 会放弃等待,不会卡住 agent。(src/shared/worker-utils.ts、src/shared/hook-constants.ts) | 不动 |
| `SESSION_INIT_TIMEOUT_MS` | `10000` | 会话开始时(用户提交第一条提示词那一刻,hook 向 worker 注册会话并取回记忆上下文)的整体超时,单位毫秒,默认 10000(10 秒;Windows 上 7 秒),上限受 hook 的 15 秒总预算限制,最小 500。(src/shared/worker-utils.ts、src/shared/hook-constants.ts) | 不动 |
| `IDLE_EXIT_SEC` | `0` | worker 空闲自动退出的秒数(opt-in,最小 60)。默认 0=永不自动退出;设了之后,没有会话活动、没有排队任务、没有请求时 worker 会优雅关闭,下一次 hook 读记忆时会再把它拉起来。AUTOSTART=false 或正在监视 transcript(会话记录文件)时不会启用。(src/services/worker-service.ts、src/services/worker/idle-exit-monitor.ts) | 不动 |
| `HOOK_FAIL_LOUD_THRESHOLD` | `3` | hook 连续 N 次连不上 worker 后,在该会话里提醒一次“worker 不可用”(只提醒,不会阻塞 agent)。默认 3;值不是 ≥1 的整数时回退到默认。(src/shared/worker-utils.ts) | 不动 |
| `WORKER_HEARTBEAT_STALE_MS` | `120000` | worker 的“心跳”(定期写下的存活标记)多久没更新才算失联,单位毫秒,默认 120000(2 分钟),范围 10000~3600000。心跳比这个值新就当作“慢但活着”,不会被强行回收端口或重启。(src/shared/port-reclaim.ts) | 不动 |
| `TV_TOKEN` | 空 | “Observation TV”(观察笔记远程直播)的访问口令。留空=关闭,worker 行为完全不变;只有同时把 WORKER_HOST 设成非回环地址并填了口令,才会向持口令者只读开放 /tv、/stream 和 GET /api/observations。(src/services/worker-service.ts、SettingsDefaultsManager.ts 注释) | 保持为空 |
| `RUNTIME` | `worker` | hook 选择哪种运行时:'worker'(默认,本机后台服务,你现在用的)或 'server'/'server-beta'(需要另配数据库的服务端形态,Docker 部署用),其它值一律按 worker 处理。个人本机使用保持 worker。(src/services/hooks/runtime-selector.ts、src/server/runtime/create-server-service.ts) | 不动 |
| `WORKER_AUTOSTART` | `true` | true(默认)=hook/MCP 需要时会自动启动、重启 worker;false=worker 由外部(如 launchd、容器)管理,hook 只使用已在运行的 worker,绝不启动、杀掉或重建它。填了 WORKER_URL 也等同于 false。(src/shared/worker-autostart.ts) | 不动 |

### 02. 数据、日志与备份

管数据放哪、日志留多久、旧数据清不清、要不要自动快照。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `DATA_DIR` | `/Users/melodycchen/.claude-mem` | claude-mem 所有数据的根目录(settings.json、数据库、日志、transcript-watch.json、modes 等都在这里),默认 ~/.claude-mem。环境变量同名值优先;改了它,默认端口和 transcript 配置路径也会跟着按新目录推算。OpenCode 和 DSH 必须指向同一个目录才能共用记忆。(src/shared/SettingsDefaultsManager.ts) | 不动 |
| `LOG_LEVEL` | `INFO` | 日志详细程度,可选 DEBUG / INFO / WARN / ERROR / SILENT,默认 INFO;写入 settings 时会校验,不在此列表会被拒绝。排查问题时临时改 DEBUG。(src/utils/logger.ts、src/services/worker/http/routes/SettingsRoutes.ts) | 不动 |
| `PYTHON_VERSION` | `3.13` | 启动向量检索组件 Chroma(用 Python 的 uvx 运行)时指定的 Python 版本,格式必须是 3.X 或 3.XX,默认 3.13;环境变量同名值优先。只影响 Chroma 子进程的启动参数。(src/services/sync/ChromaMcpManager.ts) | 不动 |
| `BACKUP_ENABLED` | `false` | 是否自动给本地数据库做快照备份。默认 false(关闭,需主动开启);开启后需重启 worker 才生效。(src/npx-cli/commands/backup.ts、doctor.ts) | 按需 |
| `BACKUP_INTERVAL_HOURS` | `24` | 自动快照的间隔,单位小时,默认 24(每天一次)。仅在 BACKUP_ENABLED=true 时有意义。(src/npx-cli/commands/doctor.ts、SettingsDefaultsManager.ts 注释) | 不动 |
| `BACKUP_RETAIN_COUNT` | `7` | 最多保留最近多少份快照,默认 7,更旧的会被清理。仅在 BACKUP_ENABLED=true 时有意义。(SettingsDefaultsManager.ts 注释、SettingsRoutes.ts 校验) | 不动 |
| `TOOL_USES_RETENTION_DAYS` | `0` | tool_uses(记录每次工具调用原始输入输出的备份表)保留天数。0=永久保留(默认);N=worker 启动时清理已关联到观察笔记且超过 N 天的记录。非非负整数的值一律当作 0,不会误删。(src/shared/retention-days.ts、src/services/worker/DatabaseManager.ts) | 不动 |
| `LOG_RETENTION_DAYS` | `30` | 按天滚动的日志文件保留天数,默认 30;0=永久保留。worker 启动 5 分钟后及此后每天清理一次,今天和昨天的日志始终保留。(src/services/worker-service.ts、src/shared/retention-days.ts) | 不动 |

### 03. 采集范围与过滤

管"哪些操作会被记下来":总开关、跳过哪些工具和命令、图片和子代理要不要记。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `SKIP_TOOLS` | `ListMcpResourcesTool,SlashCommand,Skill,TodoWrite,AskUserQuestion` | 不记录观察笔记(observation:对一次操作的摘要笔记)的工具名,逗号分隔,默认跳过 ListMcpResourcesTool、SlashCommand、Skill、TodoWrite、AskUserQuestion 这类低价值工具。匹配规则是整名精确相等、不区分大小写、不支持通配符(写 `claude_mem_*` 无效,要逐个列全名)。OpenCode 的 read 会被适配成 Read 后同样匹配。(src/shared/is-tool-skipped.ts) | 不动 |
| `SKIP_BASH_PATTERNS` | 空 | 一个正则表达式,命令行类工具(Bash/PowerShell/Codex exec_command)的命令匹配上就不记录。留空=全部记录;想写多个用 \| 连接,如 ^(ls\|cat\|pwd)\b。写错的正则会被忽略(等于没设)。**v15.16.0 起对 OpenCode 生效**(上游 #5666 已修):OpenCode 插件的映射表把小写 bash 上报为 Bash(read/write/edit 同样映射成大写),而 worker 的 shellCommandOf 只认 Bash/PowerShell/exec_command,所以现在能命中。接口实测:Bash + 命中脚本 => skipped(bash_pattern_excluded),直接发小写 bash 仍会入队。限制:只拦命中的命令本身,拦不住 cd 之后用相对路径调用脚本、也拦不住用 curl 读旧记忆。(src/services/worker/http/shared.ts) | 按需 |
| `SKIP_SUBAGENT_OBSERVATIONS` | `false` | 设为 'true' 则跳过所有子代理(subagent,主 agent 派出去干活的小 agent)产生的观察笔记,默认 false 不跳过。只对同时带 agent id 和 agent type 的子代理事件生效,主 agent 不受影响。**对 OpenCode 无效**:判定 subagent 需 agentId 与 agentType 同时存在,而 OpenCode 插件不上报这两个字段。(src/shared/should-skip-agent-observation.ts) | 按需 |
| `SKIP_AGENT_TYPES` | 空 | 按子代理类型(agent_type)精确跳过,逗号分隔,默认空=不跳过;源码注释推荐的值是 workflow-subagent,用来去掉 Dynamic Workflows(动态工作流)大量并发子代理产生的噪音。同样依赖 agentId 与 agentType,**对 OpenCode 无效**(插件不带这两个字段)。(src/shared/should-skip-agent-observation.ts) | 按需 |
| `CAPTURE_ADVISOR_CALLS` | `false` | 默认 false。设 true 后,Stop hook(会话停止时触发)会扫描会话记录末尾,把 Claude Code 的 advisor(顾问)工具调用及其建议文本存到本地,仅 worker 运行时有效。(src/cli/handlers/summarize.ts) | 不动 |
| `DELIVERABLES_ENABLED` | `true` | 默认 true:Stop hook 会把这一轮产出的交付文件复制到 ~/.claude-mem/deliverables/<项目>/ 并记录,供“My Work”页面链接;设 false 则不再复制和记录,但已在里面的文件保留。(src/cli/deliverables-capture.ts) | 不动 |
| `OBSERVER_ENABLED` | `true` | 记忆采集总开关。只有显式写 'false' 才关闭“新观察笔记和会话摘要”的生成;缺失或写错都按开启处理,避免手误丢记忆。默认 true。(src/shared/observer-capture.ts) | 不动 |
| `MEDIA_CAPTURE_ENABLED` | `true` | 是否保存工具调用中出现的图片。默认 true(界面上的“Keep images”开关);每张图有大小上限(规范版 3 MiB、给模型的副本 256 KiB),一个事件最多存 4 张,本地没有总量上限,图片随其事件被删除才清除。关闭后图片内容会被替换成简短描述。(src/services/worker/http/shared.ts、SettingsDefaultsManager.ts 注释) | 按需 |
| `MEDIA_INFERENCE_ENABLED` | `false` | 是否把图片发给“观察者模型”(生成观察笔记的大模型)去理解。默认 false,与保存图片是独立开关,开启会额外产生付费调用。(src/services/worker/media-capability.ts) | 不动 |
| `MODE` | `code` | 模式配置名,决定观察笔记的提示词和分类;值对应插件目录里的 plugin/modes/<mode>.json,也可用 ~/.claude-mem/modes/ 下的自定义覆盖(--<name> 形式)。默认 code;code--zh 是中文模式(输出中文观察笔记),code--ja 等同理。worker 启动时加载,找不到文件会报错。(src/services/domain/ModeManager.ts、src/services/worker-service.ts) | 建议改 |
| `OBSERVE_BARE_PROMPTS` | `false` | 默认 false:用户的提示词不单独调一次观察者模型,而是随下一次工具事件那次调用一起带上,省模型调用。设 true 则恢复为每条用户提示词单独调用一次。(src/services/worker/session/recycle-conversation.ts) | 不动 |

### 04. 项目归属与会话来源

管"这条记忆算哪个项目、来自哪个客户端":项目名怎么算、哪些目录不记、从哪里读会话记录。和 OpenCode、DSH 共用记忆直接相关。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `MEMORY_SEARCH_HOOK_ENABLED` | `true` | 默认 true:agent 读/搜索本地记忆文件(如 MEMORY.md)时,hook 会顺带从 claude-mem 数据库查相关观察笔记作为补充(仅限 worker 运行时、只返回索引字段)。设 'false' 关闭这个补充。(src/cli/handlers/memory-search.ts) | 不动 |
| `MEMORY_INSTRUCTIONS_ENABLED` | `true` | 默认 true:会话开始注入上下文时,附带一段“如何使用 claude-mem 记忆”的说明文字。设 'false' 则不附带(省一点 token)。(src/cli/handlers/context.ts) | 不动 |
| `MEMORY_WATCH_ROOTS` | 空 | 显式配置要导入为记忆的文件夹,JSON 数组 [{path, project, platformSource?}],最多 8 项;path 须为绝对路径或 ~/ 开头,project 是这些文件归属的项目名(决定“记忆算哪个项目”),platformSource 可指定来自哪个客户端。留空=不导入任何文件,源码强调不会猜归属。(src/services/memory/config.ts、file-watcher.ts) | 保持为空 |
| `TRANSCRIPTS_ENABLED` | `true` | 是否启用 transcript(会话记录文件)监视器:worker 通过读取各客户端写在磁盘上的会话记录来采集记忆。DSH 的记忆就是由它读 DSH 会话记录采集的(安装脚本写明 the worker captures transcripts once),设 'false' 则 DSH 的自动采集失效,安装脚本也会提示。默认 true。(src/services/worker-service.ts、src/services/integrations/DeepSeekHarnessInstaller.ts) | 不动 |
| `TRANSCRIPTS_CONFIG_PATH` | `/Users/melodycchen/.claude-mem/transcript-watch.json` | 监视器配置文件路径,默认 <数据目录>/transcript-watch.json;文件里列出要监视哪些客户端的会话记录目录(每项 watch 的 name 经归一化后就是该条记忆的“来源客户端”,如 dsh、codex)。文件不存在则跳过自动采集,不会报错。DSH 安装时会往这个文件里写入名为 dsh 的 watch。(src/services/worker-service.ts、src/services/transcripts/processor.ts) | 装完核对 |
| `CODEX_TRANSCRIPT_INGESTION` | `false` | 默认 false。Codex 自带原生 hook 采集顶层会话,所以默认会把 transcript-watch 里对应的 Codex 监视项移除以免重复采集;设 true 则保留并全量读取 Codex 会话记录。与 OpenCode/DSH 无关。(src/services/transcripts/config.ts) | 不动 |
| `CODEX_SUBAGENT_INGESTION` | `false` | 默认 false。Codex 的子代理会话不触发 hook,通过 transcript 采集它们的每次工具调用都会产生观察者模型费用,所以需主动开启;开启后监视项只收子代理会话,且受 SKIP_SUBAGENT_OBSERVATIONS 约束。与 OpenCode/DSH 无关。(src/services/transcripts/config.ts) | 不动 |
| `EXCLUDED_PROJECTS` | 空 | 不记录的项目路径,逗号分隔的 glob 通配模式(支持 * ** ? 和开头的 ~;同时匹配完整路径和文件夹名)。命中的目录:不采集观察笔记、会话开始不注入记忆,hook、worker 接口、transcript 监视以及 DSH 插件的上下文读取都会检查它。默认空=不排除任何项目。(src/utils/project-filter.ts、src/shared/should-track-project.ts、src/services/worker/http/shared.ts) | 按需 |
| `PROJECT_ENVIRONMENTS` | `[]` | 把多个目录归并成同一个“项目”的规则,JSON 数组 [{name, patterns, inherit?}]:目录(路径经 glob 匹配,也会尝试 realpath)命中某环境的 patterns 就用 name 作项目名,优先级高于一切自动推算(git 根目录、git-remote 等)。inherit 省略则仍可读取原来推算出的项目键,写成 [] 则只读该环境自己。默认 [] 不归并。环境变量同名值优先。(src/utils/project-name.ts、src/utils/project-environments.ts) | 按需 |
| `PROJECT_NAME_SOURCE` | `path` | 决定“这条记忆算哪个项目”的命名方式。'path'(默认):在 git 仓库里用仓库根目录的文件夹名(worktree/子模块会拼成 父项目/子名),不在仓库里用标记根或当前目录名;'git-remote':用 git origin 地址推出的 org/repo 稳定名,改目录名也不变,取不到 origin 时退回 path。OpenCode 和 DSH 都把工作目录(cwd)交给 worker 统一算项目名,所以两边只要同目录、同设置就落到同一个项目,共用记忆;注意项目名只管“归哪个项目”,“来自哪个客户端”由另一个字段 platformSource 区分(OpenCode 固定为 opencode,DSH 来自 transcript watch 的名字,如 dsh)。(src/utils/project-name.ts、src/integrations/opencode-plugin/core.ts、src/services/transcripts/processor.ts) | 按需 |

### 05. 观察者:选谁来写笔记

管"记账员"是谁:选哪家提供方、默认模型、额度用完退到谁、按复杂度分流到哪个模型。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `MODEL` | `haiku` | provider=claude(用 Claude 作观察者)时,给每次工具调用写笔记的模型。默认 haiku 是 Claude Code 的别名,始终指向最新的 Haiku(便宜小模型),所以不要写带日期的具体 ID。只在 provider=claude 时生效,用 openrouter/openai-compatible 时不读取它(各自有自己的 MODEL 键)。也可写 $TIER:fast 等分级别名(ClaudeProvider.ts、model-aliases.ts) | 不动 |
| `PROVIDER` | `claude` | 选择 observer(观察者,给每次工具调用写笔记的模型)走哪家 provider(提供方,即调用哪家接口)。源码实际校验的有效值只有 5 个:claude(Claude 订阅/API Key)、codex(本机 Codex CLI)、gemini(Google Gemini)、openrouter(OpenRouter 接口,可通过 BASE_URL 改地址)、openai-compatible(任意 OpenAI 格式接口,有独立配置)。填其他值会被设置接口拒绝。README/安装器里出现的 cmem 是托管观察者(cmem.ai 网关),它只是安装器里的选项,不是有效值,选它会被写成 openrouter+cmem.ai 网关地址,工具调用内容会发到第三方 cmem.ai。默认 claude。想用 codebuddy 的 OpenAI 兼容接口,应改为 openai-compatible 或 openrouter(SettingsRoutes.ts、provider-dispatch.ts、install.ts) | 建议改 |
| `PROVIDER_BY_SOURCE` | 空 | 按"来源客户端"分别指定 provider:值是一个 JSON 字符串,如 {"codex":"codex","claude":"claude"},键是会话来源(客户端)名,值必须是 claude/gemini/openrouter/codex/openai-compatible 之一。来源名会被规范化:含 codex/cursor/claude/kimi 的归为对应名,其他名字(如 opencode、dsh)转小写、空白换成连字符后原样使用。没有对应条目、或对应 provider 没配好时,回退到 CLAUDE_MEM_PROVIDER。留空=所有来源都用全局 provider。格式不对整个值被忽略并打警告(provider-by-source.ts、platform-source.ts、provider-dispatch.ts) | 不动 |
| `QUOTA_FALLBACK_PROVIDER` | `claude` | "备用观察者":当所选 provider 暂时无法服务(额度用完、限流/过载重试后仍失败、宕机、连续回复不可用)时,观察者的活儿转给谁。可选 claude(留空等同)、gemini、openrouter、openai-compatible、off(不转移,原地等待)。默认 claude,但只有本机存在 Claude 登录或 Key 时才真的会用;没有 Claude 的人等于无处可退。主 provider 恢复后会把活儿收回(provider-dispatch.ts) | 按需 |
| `QUOTA_FALLBACK_MODEL` | 空 | 当备用 provider 是 Claude 时,备用那次运行用哪个 Claude 模型;留空=沿用 CLAUDE_MEM_MODEL 与分级路由。对非 Claude 的备用 provider 无效,因为只有 ClaudeProvider 读取模型覆盖值(SessionRoutes.ts、SessionManager.ts) | 不动 |
| `QUOTA_FALLBACK_AUTH_METHOD` | 空 | "订阅额度防护"的一部分:主 Claude 凭据因额度被暂停时,换用哪种 Claude 凭据继续。可选空(关闭)/subscription(Claude Code 登录)/api-key(.env 里的 ANTHROPIC_FALLBACK_API_KEY)。会先于 QUOTA_FALLBACK_PROVIDER 尝试。只涉及 Claude 凭据,不用 Claude 的人不受影响(源码注释;docs/usage/quota-fallback) | 不动 |
| `QUOTA_THRESHOLD_FIVE_HOUR` | `0.95` | "订阅额度防护":Claude 订阅的 5 小时用量窗口,用到这个比例(0~1 的小数,0.95=95%)就停止后台写笔记,免得挤占你正在交互的 Claude 额度。填成 93 这类百分数会被当作无效、改回默认并警告。只对 Claude 订阅(登录)方式生效,API Key 方式豁免,用 codebuddy/OpenAI 兼容接口的人完全不受影响(RateLimitStore.ts) | 不动 |
| `QUOTA_THRESHOLD_SEVEN_DAY` | `0.93` | "订阅额度防护":Claude 订阅的 7 天(周)用量窗口阈值,0~1 小数,0.93=93%,到了就暂停后台观察。只对 Claude 订阅方式生效,用 codebuddy 的人不受影响(RateLimitStore.ts) | 不动 |
| `QUOTA_THRESHOLD_SEVEN_DAY_OPUS` | `0.93` | "订阅额度防护":Claude 订阅里 Opus 模型的周用量窗口阈值,0~1 小数。只对 Claude 订阅方式生效,用 codebuddy 的人不受影响(RateLimitStore.ts) | 不动 |
| `QUOTA_THRESHOLD_SEVEN_DAY_SONNET` | `0.92` | "订阅额度防护":Claude 订阅里 Sonnet 模型的周用量窗口阈值,0~1 小数。只对 Claude 订阅方式生效,用 codebuddy 的人不受影响(RateLimitStore.ts) | 不动 |
| `QUOTA_THRESHOLD_OVERAGE` | `0.95` | "订阅额度防护":Claude 订阅超出套餐后进入"超额(overage)"计费时的用量阈值,0~1 小数。只对 Claude 订阅方式生效,用 codebuddy 的人不受影响(RateLimitStore.ts) | 不动 |
| `TIER_ROUTING_ENABLED` | `true` | "按复杂度分流模型"总开关:true 时,若队列里的事件都是简单类工具调用,就改用 TIER_SIMPLE_MODEL;含"总结"任务时用 TIER_SUMMARY_MODEL(非空才生效);其余用默认模型。填 false 关闭。注意:只有 ClaudeProvider 读取这个模型覆盖值,所以 provider 不是 claude(如 openai-compatible/openrouter)时不起作用,对用 codebuddy 的人无影响(SessionRoutes.ts、model-aliases.ts、SessionManager.ts) | 不动 |
| `TIER_SIMPLE_MODEL` | `haiku` | 分流用:全是简单工具调用时改用的 Claude 模型,默认 haiku(可移植别名,在直连 API、Bedrock、Vertex、Azure 都能用)。只影响 provider=claude,用 codebuddy 的人无影响(SessionRoutes.ts、model-aliases.ts) | 不动 |
| `TIER_SUMMARY_MODEL` | 空 | 分流用:会话总结类任务用的模型。留空=沿用默认模型(CLAUDE_MEM_MODEL)。只影响 provider=claude(SessionRoutes.ts、model-aliases.ts) | 不动 |
| `TIER_FAST_MODEL` | `haiku` | "$TIER:fast"这个别名解析到的实际模型,默认 haiku。仅当你把 CLAUDE_MEM_MODEL 写成 $TIER:fast 这种别名时才用到;留空时回退为 haiku(model-aliases.ts) | 不动 |
| `TIER_SMART_MODEL` | `sonnet` | "$TIER:smart"这个别名解析到的实际模型,默认 sonnet。仅当 CLAUDE_MEM_MODEL 写成 $TIER:smart 时用到;留空回退为 sonnet(model-aliases.ts) | 不动 |

### 06. 提供方:Claude

provider=claude 时用到的设置。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `CLAUDE_OBSERVATION_BATCH_SIZE` | `1` | provider=claude 时,同一上下文中排队的多个工具调用事件,合并进一次观察者提示词里发送的数量(1~32)。默认 1=每个事件单独发一次,最稳;调大可省请求次数(ClaudeProvider.ts) | 不动 |
| `CLAUDE_AUTH_METHOD` | `subscription` | Claude provider 的认证方式:subscription(用已登录的 Claude Code 订阅,默认)、api-key(用 Anthropic API Key)、gateway(走自定义网关)(docs/configuration)。只对 provider=claude 有意义,也是额度防护是否生效的依据(api-key 豁免) | 不动 |
| `CLAUDE_CODE_PATH` | 空 | Claude Code 命令行可执行文件的路径。留空=自动检测(相当于 which claude)。只能通过设置文件或环境变量改,改后需重启后台服务(find-claude-executable.ts) | 不动 |
| `CLAUDE_CONFIG_DIR` | 空 | 仅为 claude-mem 覆盖 Claude 的配置目录(CLAUDE_CONFIG_DIR),用于读取钥匙串里的 Claude 凭据和启动 SDK 子进程。留空=沿用环境变量 CLAUDE_CONFIG_DIR 或默认目录(EnvManager.ts) | 不动 |
| `OBSERVER_CLAUDE_CONFIG_DIR` | 空 | 只给观察者的 Claude 子进程指定一个单独的配置目录,用来把观察者产生的对话记录(transcript)挪出 ~/.claude/projects;凭据仍用默认配置。仅当 CLAUDE_MEM_CLAUDE_CONFIG_DIR 为空时才生效;填的话必须是非空路径(EnvManager.ts、SettingsRoutes.ts) | 不动 |
| `MAX_CONCURRENT_AGENTS` | `2` | 同时运行的 Claude SDK 代理子进程上限,默认 2。调大更快但更吃内存和额度;运行中可按新值放行(ClaudeProvider.ts) | 不动 |

### 07. 提供方:Codex

provider=codex 时用到的设置。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `CODEX_MODEL` | 空 | provider=codex 时使用的 Codex 模型。留空=让 Codex 用它自己的默认模型;填的话必须是你的订阅可用的模型(CodexProvider.ts) | 不动 |
| `CODEX_PATH` | `codex` | Codex 命令行可执行文件名或路径,默认 codex(走 PATH 查找)。只能在设置文件或环境变量中改,路径开头不要用 ~(不会被展开),要写绝对路径(install/tool-path.ts、doctor.ts) | 不动 |
| `CODEX_REASONING_EFFORT` | `low` | Codex 的推理强度,合法值:none/minimal/low/medium/high/xhigh/max/ultra,留空=用 Codex 默认。默认 low 省 token(token=模型计费和上下文的计量单位)。Codex 不接受的值会让 Codex 观察暂停(CodexProvider.ts、SettingsRoutes.ts) | 不动 |
| `CODEX_MAX_CONCURRENT_AGENTS` | `2` | Codex 并行处理请求的 app-server 客户端数量,范围 1~8,默认 2。只能写在设置文件里,改后要重启后台服务(CodexProvider.ts、docs/configuration) | 不动 |
| `CODEX_OBSERVATION_BATCH_SIZE` | `8` | Codex 一次请求最多合并的排队观察事件数,范围 1~32,默认 8(CodexProvider.ts) | 不动 |
| `CODEX_OBSERVATION_BATCH_MAX_CHARS` | `32000` | Codex 一次合并请求的字符预算,范围 4000~128000,默认 32000(CodexProvider.ts、docs/configuration) | 不动 |

### 08. 提供方:Gemini

provider=gemini 时用到的设置。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `GEMINI_API_KEY` | 空 | provider=gemini 时的 Google Gemini API Key。留空时会改读 ~/.claude-mem/.env 里的 GEMINI_API_KEY;不用 Gemini 就保持为空。注意 cmem.ai 的 cm_pro_ 密钥不会被发给 Google(GeminiProvider.ts) | 保持为空 |
| `GEMINI_API_KEYS` | 空 | 额外的 Gemini Key 列表(换行、逗号或空格分隔),某个 Key 限流/额度用尽/认证失败时轮换到下一个。留空则读 .env 里的 GEMINI_API_KEYS(GeminiProvider.ts、api-key-pool.ts) | 保持为空 |
| `GEMINI_MODEL` | `gemini-flash-latest` | provider=gemini 时用的模型,默认 gemini-flash-latest(Google 维护的别名,始终指向当前 Flash 型号)。填了无效型号会警告并退回默认(GeminiProvider.ts、docs/configuration) | 不动 |
| `GEMINI_RATE_LIMITING_ENABLED` | `true` | 是否对 Gemini 请求做客户端限速(防止免费档被限流)。默认 true=开;只有值为字符串 false 才关闭(GeminiProvider.ts) | 不动 |

### 09. 提供方:OpenRouter(可接自定义地址)

provider=openrouter 时用到的设置。它允许自定义 BASE_URL,是接 codebuddy 的主要路线。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `OPENROUTER_API_KEY` | 空 | provider=openrouter 时发给接口的 API Key,以 Authorization: Bearer 带出。读取顺序:设置里的这个值(或同名环境变量)→ ~/.claude-mem/.env 里的 OPENROUTER_API_KEY。注意它与 openai-compatible 路线的 Key 完全独立、互不共用。cm_pro_ 开头的 cmem.ai 密钥只会发给 cmem.ai 网关,个人 Key 不会发给网关(OpenRouterProvider.ts) | 按需 |
| `OPENROUTER_API_KEYS` | 空 | 额外的 OpenRouter Key 列表(换行/逗号分隔),某个 Key 限流、额度用尽或被拒时轮换。读取顺序:设置值 → .env 的 OPENROUTER_API_KEYS;用 cmem.ai 网关时不使用(OpenRouterProvider.ts、docs/configuration) | 保持为空 |
| `OPENROUTER_MODEL` | `cohere/north-mini-code:free` | openrouter 路线使用的模型 ID,原样传给接口。默认是 OpenRouter 的免费模型 cohere/north-mini-code:free。支持用逗号或空白写多个:第一个是主模型,其余作为 OpenRouter 的备用模型(备用列表只发给 openrouter.ai,自定义地址只会收到第一个)。把 BASE_URL 指向 codebuddy 时必须改成 codebuddy 实际提供的模型 ID,否则会拿免费默认 ID 去请求(OpenRouterProvider.ts) | 装完核对 |
| `OPENROUTER_BASE_URL` | 空 | openrouter 路线的接口地址,允许自定义(openai-compatible 路线另有自己的 BASE_URL)。留空=连 OpenRouter 官方 https://openrouter.ai/api/v1/chat/completions(也认环境变量 OPENROUTER_BASE_URL)。填基础地址(如 https://xxx/v1)会自动补 /chat/completions,已带该后缀则原样使用;必须是 http(s) 地址。重要差别:这条路线无论连哪个地址,每次请求都带 OpenRouter 的归因请求头(HTTP-Referer、X-OpenRouter-Title、X-OpenRouter-Categories),也就是把 claude-mem 的 OpenRouter 身份标识一并发给你填的主机;openai-compatible 路线则不带这些头(OpenRouterProvider.ts、openrouter-base-url.ts、openrouter-attribution.ts、openai-compat-presets.ts) | 装完核对 |
| `OPENROUTER_TEMPERATURE` | 空 | 温度(控制回答随机性的参数),取 0~2 的数字时才会作为 temperature 合并进请求体;留空或超出范围=不发送,由接口用自己的默认值(OpenRouterProvider.ts) | 不动 |
| `OPENROUTER_SITE_URL` | 空 | OpenRouter 归因用的站点地址,作为 HTTP-Referer 请求头发出。留空=用 claude-mem 自己的 GitHub 地址 https://github.com/thedotmack/claude-mem;填了就是把你的流量归到你填的应用名下。即使 BASE_URL 指向非 OpenRouter 的主机,这个头也会发(openrouter-attribution.ts、OpenRouterProvider.ts) | 不动 |
| `OPENROUTER_APP_NAME` | `claude-mem` | OpenRouter 归因用的应用名,作为 X-OpenRouter-Title 请求头发出,仅作显示名,默认 claude-mem;设为空则回退成 Claude-Mem(openrouter-attribution.ts、OpenRouterProvider.ts) | 不动 |
| `OPENROUTER_EXTRA_BODY` | 空 | 以 JSON 对象形式给请求体追加厂商特有字段,例如 {"reasoning":{"enabled":false}}。只能写在设置文件或环境变量里(设置接口不接受),且永远不会发给 cmem 网关。如果同时设了 REASONING_EFFORT,其中的 reasoning 字段会被忽略。留空=不追加(OpenRouterProvider.ts、openrouter-extra-body.ts) | 不动 |
| `OPENROUTER_REASONING_EFFORT` | 空 | openrouter 路线的"推理强度"(让模型先思考多少),可选 none/minimal/low/medium/high。留空=在 openrouter.ai 和 cmem 网关上关闭推理;设了具体强度则只对 openrouter.ai 官方地址生效,自定义 BASE_URL 不发送这个字段(OpenRouterProvider.ts) | 不动 |

### 10. 提供方:OpenAI 兼容

provider=openai-compatible 时用到的设置,独立于 OpenRouter,不共用 key。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `OPENAI_COMPAT_PRESET` | 空 | openai-compatible 路线的"预设端点"名,用来自动填默认地址和默认模型。源码内置的预设包括 nvidia-nim、orcarouter、api-route、opper、atlascloud、runcrate、cheapaimodel、obscurify-ai、deepseek、opencode-go、opencode-zen、groq、together、minimax、minimax-cn、iflytek、ollama、lmstudio、vllm、custom。留空或写错名字都等于 custom(自己手填 BASE_URL,此时不连任何地方)。接 codebuddy 保持为空并填 BASE_URL 即可(openai-compat-presets.ts) | 保持为空 |
| `OPENAI_COMPAT_API_KEY` | 空 | openai-compatible 路线的 API Key,以 Authorization: Bearer 发出。读取顺序:设置里的这个值 → ~/.claude-mem/.env 里的 OPENAI_COMPAT_API_KEY(所有端点共用同这一个名字)。与 OpenRouter 的 Key 完全独立、不共用。远程地址视为必须有 Key;本机/内网地址(localhost、127.*、10.*、192.168.*、172.16-31.* 等)可以没有。远程服务若不需要认证,随便填个非空值即可(OpenAICompatProvider.ts、EnvManager.ts) | 装完核对 |
| `OPENAI_COMPAT_API_KEYS` | 空 | openai-compatible 路线额外的 Key 列表(换行/逗号分隔),用于限流或失效时轮换。留空则读 .env 里的 OPENAI_COMPAT_API_KEYS。单 Key 够用时保持为空(OpenAICompatProvider.ts) | 保持为空 |
| `OPENAI_COMPAT_BASE_URL` | 空 | openai-compatible 路线的接口地址,同样自动补 /chat/completions。非空时覆盖预设的地址;留空时用预设自带的地址,而预设也为空(custom)时 apiUrl 为空,不会连接任何地方,只会报"No OpenAI-compatible endpoint configured"。这条路线不发 OpenRouter 的归因请求头,也不适用 cmem 网关的凭据绑定规则,是接 codebuddy 这类第三方 OpenAI 兼容接口更干净的路线(OpenAICompatProvider.ts、openai-compat-presets.ts) | 装完核对 |
| `OPENAI_COMPAT_MODEL` | 空 | openai-compatible 路线使用的模型 ID,原样传给接口。留空=用预设的默认模型;custom 预设没有默认模型,留空会直接报"No model configured",所以接 codebuddy 必须填(OpenAICompatProvider.ts、openai-compat-presets.ts) | 装完核对 |
| `OPENAI_COMPAT_REASONING` | 空 | 是否让模型"先思考再回答"(reasoning)。留空或 off=每个请求都带 reasoning:{enabled:false} 关掉思考,避免带思考的模型把输出额度花在思考上而返回空内容;on=不发这个字段,交给端点自己决定。如果端点对这个字段返回 400(如 vLLM),会自动去掉重发一次(OpenAICompatProvider.ts) | 不动 |
| `OPENAI_COMPAT_OBSERVATION_BATCH_SIZE` | `1` | openai-compatible 路线下,同上下文的排队事件合并进一次观察者提示词的数量(1~32),默认 1=每个事件单独发,需要时才开启(OpenAICompatProvider.ts) | 不动 |

### 11. 观察者请求行为

管发给观察者模型的每次请求:等多久、能说多长、一段对话多大就换新的。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `OBSERVER_MAX_CONVERSATION_CHARS` | `400000` | 一段观察者对话允许累积的字符数,超过就废弃重开新一段(新一段会带上本会话已有的笔记摘要)。实际上限取这个值与观察者模型上下文窗口的一半(约 4 字符≈1 token)两者中较小者;token=模型计费和上下文的计量单位(OpenAICompatibleProvider.ts、docs/configuration) | 不动 |
| `OBSERVER_THINKING` | `disabled` | Claude 观察者发送的 thinking 参数(是否让模型先思考):disabled(默认,省 token)、adaptive(由模型决定)、enabled 或 enabled:预算、omit(完全不发该字段,给"总在思考"、拒绝 disabled 的网关用)。属于 Claude 观察者的设置,用 OpenAI 兼容接口的人用 CLAUDE_MEM_OPENAI_COMPAT_REASONING 控制思考(hardened-options.ts、docs/configuration) | 不动 |
| `OBSERVER_CONTEXT_WINDOW` | 空 | 观察者模型的上下文窗口大小,单位 token(token=模型计费和上下文的计量单位)。留空=自动判断:Claude 为 200000,Gemini 查内置表,OpenRouter 查其模型目录;其他 OpenAI 兼容端点(本地或自建网关)找不到时回落到 131072。若你的模型窗口更小(如 16384)就要手填,最小值 8192(SettingsRoutes.ts、context-window.ts、docs/configuration) | 装完核对 |
| `OBSERVER_MAX_OUTPUT_TOKENS` | `4096` | 每个 HTTP 观察者请求允许模型输出的最大 token 数(max_tokens / max_completion_tokens;Gemini 为 maxOutputTokens),默认 4096,范围 256~1000000。带思考的模型若在回答前就把额度花光,需要调大(docs/configuration、reasoning-budget.ts) | 按需 |
| `LLM_TIMEOUT_MS` | `180000` | 每次非流式观察者请求的超时(毫秒,500~300000),默认 180000=3 分钟,用来拦截卡死的请求。OpenRouter 和 openai-compatible 默认是流式请求,不受它约束,而由空闲超时(STREAM_IDLE)加 300 秒总上限控制;不支持流式的端点才会用到它(retry.ts、docs/configuration) | 不动 |
| `FIELD_OPTIMIZE_TIMEOUT_MS` | `180000` | 压缩"过长字段"(某次工具结果太大时先交给模型浓缩)那一步的超时,毫秒,默认 180000。该步骤只尝试一次,失败或超时就退回为截断,所以不会卡死观察者。请求发往同一个后端,因此和 LLM_TIMEOUT_MS 用同样的超时(field-optimizer.ts、SettingsDefaultsManager.ts) | 不动 |
| `LLM_STREAM_IDLE_TIMEOUT_MS` | `90000` | 流式请求的"空闲窗口"(毫秒,500~300000),默认 90000:连续这么久既没收到 token 也没收到保活信号,就放弃该请求。自建后端在负载均衡后排队时,排队等待会被当成空闲,需要调大(streamed-chat-completion.ts、docs/configuration) | 按需 |

### 12. 隐私与脱敏

存之前把密钥、口令之类敏感内容替换掉。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `REDACT_ENABLED` | `false` | 总开关,默认 false(opt-in,源码注释 Opt-in auto-redaction;本机已设为 "true")。设为 "true" 后,记忆入库前会把已识别的密钥/口令串替换成 <redacted type='规则名'/> 占位符(这叫脱敏),覆盖工具输入输出、提示词、总结等;内置规则共 35 条:url_credentials(URL 里的密码)、aws_access_key、aws_secret_key、aws_session_token、github_pat、openai_key、anthropic_key、slack_token、jwt、private_key_pem、stripe_key、google_api_key、google_oauth_token、gitlab_token、huggingface_token、npm_token、docker_pat、linear_key、notion_token、sendgrid_key、digitalocean_token、shopify_token、pypi_token、databricks_token、vault_token、nvidia_nim_key、runcrate_key、groq_key、xai_key、perplexity_key、supabase_token、sentry_token、slack_webhook、discord_webhook、claude_mem_key。单个字段超过 100 万字符会整段替换成 oversize 占位符;settings.json 损坏时,若之前开过脱敏会继续保持开启。v15.15.2 起,REDACT_ENABLED=true 时 server capture 会在数据离开本机前先脱敏,会话元数据入库前也会脱敏(本机是本地 worker 模式,该改动对本机是否实际生效**未核对**)。(src/utils/redaction.ts) | 建议改 |
| `REDACT_DISABLED_BUILTINS` | 空 | 逗号分隔的规则名清单,列在里面的内置规则会被关掉、其余照常生效,例如 "jwt,slack_token"。规则名就是 REDACT_ENABLED 里列出的那些,也可填 generic_password 等通用规则名。默认空=一条都不关。(src/utils/redaction.ts) | 不动 |
| `REDACT_CUSTOM_PATTERNS` | `[]` | 自定义脱敏规则:JSON 数组,每项形如 {"name":"规则名","regex":"正则"};它们排在内置规则之前先跑,匹配到的内容同样被替换成 <redacted type='name'/>。缺 name、正则非法或不是数组的项会被忽略并记警告。默认 [] 即没有自定义规则。(src/utils/redaction.ts) | 按需 |
| `REDACT_LOG_MATCHES` | `false` | 为 true 时,每次脱敏扫描命中后在调试日志里写一行“规则名,命中次数”,只记次数,不记被替换的原文。默认 false,用途是打开后确认脱敏规则确实命中过。只有 REDACT_ENABLED 开着才会产生日志。(src/utils/redaction.ts) | 不动 |
| `REDACT_GENERIC_ENABLED` | `false` | 默认 false(opt-in;本机已设为 "true")。在 REDACT_ENABLED 开启的前提下,再额外启用 4 条“没有厂商前缀”的通用规则:generic_password(password=/passwd=/*_PWD= 的值)、generic_token(*_TOKEN/*_SECRET/*_API_KEY 的值,以及配置风格位置的裸 token=/secret=/api_key=)、bearer_token(Authorization: Bearer …)、basic_auth(Authorization: Basic …)。值需 ≥8 位且含字母,所以 max_tokens=4096 这类纯数字不会被误杀,但属于“低置信度”规则,可能误伤。可用 REDACT_DISABLED_BUILTINS 按名关掉其中某条。(src/utils/redaction.ts) | 按需 |

### 13. 会话开始时注入什么

新开一个会话时,往上下文里塞哪些旧记忆、塞多少、长什么样。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `CONTEXT_OBSERVATIONS` | `50` | 新会话开始时最多注入多少条“观察”(observation=claude-mem 自动记下的一条工作笔记)。默认 50,设置接口校验范围 0~200;取最近的 N 条(REINFORCE_ALPHA>0 时按强化排序)。文件夹 CLAUDE.md 生成也用这个数当上限。条数越多越占上下文。(src/services/context/ContextConfigLoader.ts、SettingsRoutes.ts、claude-md-utils.ts) | 按需 |
| `SESSION_START_INCLUDE_ALL_SOURCES` | `false` | “来源”指记忆是由哪个工具写入的(数据库里的 platform_source,如 claude、codex、cursor、opencode;Claude Code 的 platform 会被归一成 claude,OpenCode 插件固定写 opencode)。默认 false:会话开始注入时只带“本工具自己”写的记忆(请求里带 platformSource=本工具名),所以 OpenCode 看不到 Claude Code 写的、反之亦然。设为 true 则不加来源过滤,各工具的记忆混在一起注入——这是让 OpenCode 与 DSH 共用记忆的开关。它同时影响:SessionStart 注入、OpenCode 插件的注入(每次请求实时读取,无需重启)、记忆搜索 hook 与读文件时的历史时间线查询;注意它只管“注入/hook 查询”,“项目”范围由 CONTEXT_PROJECTS 与当前目录决定,两者互相独立。DSH 写入时用的来源名源码中未涉及,需装完后到查看页(viewer)核对。(src/cli/handlers/context.ts、src/integrations/opencode-plugin/core.ts、src/cli/handlers/memory-search.ts、file-context.ts) | 建议改 |
| `CONTEXT_PROJECTS` | `current` | 决定会话开始时读哪些“项目”的记忆。项目指记忆的归属键:默认按路径取 git 仓库根目录的文件夹名(worktree 是“父仓库/worktree名”,不在 git 里则取标记根或当前目录名;CLAUDE_MEM_PROJECT_NAME_SOURCE 可改成按 git remote 取名)。默认 current=只读当前这个项目;all=读本地目录里所有项目(排除 EXCLUDED_PROJECTS 里的),其他项目按名字排序在前、当前项目放最后,且 CONTEXT_OBSERVATIONS 条数上限由所有项目共享,会稀释当前项目的占比。仅 worker(本机默认)模式有效,server 模式会忽略;目录查询失败则退回当前项目。只在走 hook 的客户端(如 Claude Code)生效:OpenCode 插件自己拼 /api/context/inject?cwd=… 请求,源码里没读这个键,所以对 OpenCode 不起作用。(src/cli/handlers/context.ts、src/integrations/opencode-plugin/core.ts) | 按需 |
| `CONTEXT_SHOW_READ_TOKENS` | `false` | 为 true 时,在注入的每条观察后面显示读它大约要多少 token(模型的计费/长度单位,~Nt)。纯显示,不改变注入哪些内容。默认 false。(src/services/context/formatters/) | 不动 |
| `CONTEXT_SHOW_WORK_TOKENS` | `false` | 为 true 时,每条观察后显示当初产生这条记忆所花的“工作量”token 数(研究、构建、决策花掉的)。纯显示项,默认 false。(src/services/context/formatters/) | 不动 |
| `CONTEXT_SHOW_SAVINGS_AMOUNT` | `false` | 为 true 时,在注入的统计行里显示“复用记忆省了多少 token”的绝对数。仅当有工作量 token 时才显示,默认 false。(src/services/context/formatters/) | 不动 |
| `CONTEXT_SHOW_SAVINGS_PERCENT` | `true` | 为 true 时,统计行里显示“复用记忆省了百分之几”。默认 true(开)。纯显示,不影响注入内容。(src/services/context/formatters/) | 不动 |
| `CONTEXT_OBSERVATION_TYPES` | 空 | 逗号分隔的观察类型白名单(如 bugfix,decision,discovery),只注入这些类型。默认空=当前模式(CLAUDE_MEM_MODE)里的所有类型;它只能缩小、不能超出当前模式的类型表,模式里没有的名字会被忽略(全被忽略则退回全部)。(src/services/context/ContextConfigLoader.ts) | 不动 |
| `CONTEXT_OBSERVATION_CONCEPTS` | 空 | 逗号分隔的“概念”标签白名单(如 how-it-works,gotcha),只注入带这些概念的观察。默认空=当前模式里的所有概念;同样只能缩小,不在当前模式里的概念会被忽略。(src/services/context/ContextConfigLoader.ts) | 不动 |
| `CONTEXT_FULL_COUNT` | `0` | 最近的前 N 条观察除了标题,还会展开显示详细字段(由 CONTEXT_FULL_FIELD 决定是 narrative 还是 facts)。默认 0=全部只显示标题。注入过长需要瘦身时,这一项最先被砍掉。(src/services/context/ContextBuilder.ts、ContextBudget.ts) | 按需 |
| `CONTEXT_FULL_FIELD` | `narrative` | 展开详细内容时用哪个字段:narrative=叙述性长文,facts=要点列表。只能填这两个,默认 narrative;只有 CONTEXT_FULL_COUNT>0 时才起作用。(src/services/context/sections/TimelineRenderer.ts) | 不动 |
| `CONTEXT_SESSION_COUNT` | `10` | 注入时显示最近多少次“会话总结”(每个会话结束时生成的小结)。默认 10。上下文超预算时会被减半。(src/services/context/ContextBuilder.ts、ContextBudget.ts) | 按需 |
| `CONTEXT_SHOW_LAST_SUMMARY` | `true` | 为 true 时,把最近一次会话的总结(请求/调查/学到/完成/下一步)放进注入内容。默认 true;上下文超预算时它是较早被丢弃的内容之一。(src/services/context/sections/SummaryRenderer.ts) | 不动 |
| `CONTEXT_SHOW_LAST_MESSAGE` | `false` | 为 true 时,把上一个会话里助手最后一条回复(从对话记录文件里读)也注入进来;会排除当前会话。默认 false,开了会让 SessionStart 无法用缓存、必须实时生成,且这条回复长度无上限,超预算时会被优先丢弃。(src/services/context/ObservationCompiler.ts、src/cli/handlers/context.ts) | 不动 |
| `CONTEXT_MAIN_AGENT_ONLY` | `true` | 默认 true:注入时不带子代理(subagent,主会话派出去干活的小代理)产生的观察,避免它们的流水账把主会话的长期记忆挤出窗口。只有显式设成 'false' 才会带上;搜索和查看页仍能看到全部。(src/services/context/ContextConfigLoader.ts、docs/public/configuration.mdx) | 不动 |
| `REINFORCE_ALPHA` | `0` | 实验性排序权重(ACT-R 记忆模型)。默认 0=关闭,注入就是“最近的 N 条”。大于 0(文档建议试 0.5)时,会先取更宽的候选池(最多约 5 倍、上限 500),让“后来又被再次确认过”的老观察按强度升到窗口里。非数字或负数按 0 处理。(src/services/reinforcement/rank.ts、ContextConfigLoader.ts) | 不动 |
| `CONTEXT_SHOW_TERMINAL_OUTPUT` | `true` | 默认 true:会话开始时,除了把上下文给模型,还把一份预览作为 systemMessage 显示给用户看(终端里能看到注入了什么)。Codex 平台固定不显示(避免超出其 hook 输出上限)。关掉只是少显示预览,不影响模型拿到的内容。(src/cli/handlers/context.ts) | 不动 |
| `WELCOME_HINT_ENABLED` | `true` | 默认 true:当某个项目一条观察都还没有时,会话开始会注入一段“claude-mem status”欢迎提示(说明这个项目还没有记忆、第一条记忆落库后提示就消失)。设为 false 则不注入。(src/services/worker/http/routes/SearchRoutes.ts) | 不动 |
| `WORK_STATE_ENABLED` | `true` | 默认 true。设为 'false' 则会话开始不再注入“工作状态(work state,待办/进行中清单)”段落,MCP 也不再提供 work_state_* 工具,适合自己另有一套任务跟踪的宿主。已写入的清单仍保留在数据库里。(src/shared/work-state-setting.ts、SearchRoutes.ts、mcp-server.ts) | 不动 |
| `FILE_READ_GATE_ENABLED` | `true` | 默认 true:仅对 Claude Code,当某代码文件(≥32KB)有观察历史时,拦下“整文件 Read”,引导改用 smart_outline/smart_unfold/get_observations;带 offset/limit 的定点读取不受影响。设为 'false' 则永不拦截,仍会把该文件的观察时间线作为上下文附上。(src/cli/handlers/file-context.ts、docs/public/configuration.mdx) | 不动 |

### 14. 每次提问时的语义注入与文件夹说明

除了会话开始,还能在每次提问时按意思注入相关旧记忆;也能把记忆写进各文件夹的说明文件。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `FOLDER_CLAUDEMD_ENABLED` | `false` | 默认 false。设为 true 后,每次记忆入库时,会往被读/改文件所在的各个文件夹里自动生成/更新一份 CLAUDE.md(文件夹说明文件),写入该文件夹的近期记忆;这会真的在你的项目目录里新增/改写文件,所以默认关闭。(src/services/worker/agents/ResponseProcessor.ts、src/utils/claude-md-utils.ts) | 不动 |
| `FOLDER_USE_LOCAL_MD` | `false` | 为 true 时,上面那些文件夹说明改写到 CLAUDE.local.md(通常不入 git),而不是 CLAUDE.md。默认 false。只有 FOLDER_CLAUDEMD_ENABLED 开着才有意义。(src/utils/claude-md-utils.ts) | 不动 |
| `FOLDER_MD_EXCLUDE` | `[]` | JSON 数组,里面的文件夹路径不会生成文件夹说明文件(整个文件夹排除)。默认 [] 即无排除;内容不是合法 JSON 数组会被忽略并记警告。(src/utils/claude-md-utils.ts) | 不动 |
| `FOLDER_MD_SKELETON_DENYLIST` | `[]` | JSON 数组,元素是 glob 通配符。文件夹命中其中之一、且生成出来的内容是空壳(skeleton)时,就跳过写入,避免在非内容目录里留下空 CLAUDE.md;有真实活动的文件夹仍会生成。与 FOLDER_MD_EXCLUDE 的区别是它不整体排除文件夹。默认 [] 即保持原行为。(src/utils/claude-md-utils.ts) | 不动 |
| `SEMANTIC_INJECT` | `false` | 实验性,默认 false。设为 true 后,每次你提交提示词(UserPromptSubmit)时,按提示词的意思去搜相关旧记忆并追加到这次上下文里(提示词需 ≥20 个字符,且不是纯媒体)。它走的是和普通搜索同一个入口(searchManager.search,且不带日期),据此推断同样受 SEARCH_RECENCY_DAYS 约束、依赖向量检索质量(中文召回见 CHROMA_EMBEDDING_FUNCTION 说明)。**OpenCode 上很可能不生效**(2026-11-09 读源码核对,未实测):读这个开关并请求语义注入的只有 Claude Code 的提问钩子 session-init.ts,OpenCode 插件源码里没有相关调用;OpenCode 的搜索工具 claude_mem_search 固定返回 10 条,写死在 opencode-plugin/core.ts:443,无配置项。(src/cli/handlers/session-init.ts、SearchRoutes.ts) | 按需 |
| `SEMANTIC_INJECT_LIMIT` | `5` | 每次提问最多注入多少条匹配的观察。默认 5,服务端会把值夹在 1~20 之间。仅 SEMANTIC_INJECT 开启时有用。(src/services/worker/http/routes/SearchRoutes.ts、src/shared/semantic-context.ts) | 不动 |
| `SEMANTIC_INJECT_FORMAT` | `narrative` | narrative=每条匹配注入标题+完整叙述(默认,模型无需再调用工具即可读到内容);index=每条只注入 id+标题+副标题,模型需要再调用 get_observations 才能展开(省 token,但没展开的只剩标题)。其它值按 narrative 处理。(src/services/worker/http/routes/SearchRoutes.ts) | 不动 |

### 15. 向量与检索(Chroma、嵌入模型)

管"按意思找"的那一套:Chroma 怎么连、用哪个嵌入模型、搜多久以内的记忆。中文召回的关键在这一组。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `CHROMA_ENABLED` | `true` | Chroma 是专门存“向量”的数据库(向量嵌入=把文字变成一串数字,以便按意思找)。默认 true=启用按意思搜索;设为 'false' 则不启动 Chroma,只用 SQLite 做关键词搜索,按意思找的能力整体关闭。(src/services/worker-service.ts、DatabaseManager.ts) | 不动 |
| `CHROMA_MODE` | `local` | local(默认):由 worker 通过 uvx 在本机拉起一个持久化的 chroma-mcp 子进程,数据存在数据目录下的 chroma 文件夹,写入串行执行;remote:不自己起,改连一个已经存在的 Chroma 服务,使用下面的 HOST/PORT/SSL/API_KEY/TENANT/DATABASE。写错时按 local 处理。(src/services/sync/ChromaMcpManager.ts) | 不动 |
| `CHROMA_HOST` | `127.0.0.1` | 仅 CHROMA_MODE=remote 时使用:远程 Chroma 服务的主机地址。默认 127.0.0.1,本机默认的 local 模式下完全不读。(src/services/sync/ChromaMcpManager.ts) | 不动 |
| `CHROMA_PORT` | `8000` | 仅 remote 模式使用:远程 Chroma 服务的端口。默认 8000;local 模式下不读。(src/services/sync/ChromaMcpManager.ts) | 不动 |
| `CHROMA_SSL` | `false` | 仅 remote 模式使用:连远程 Chroma 是否走 HTTPS。默认 false。(src/services/sync/ChromaMcpManager.ts) | 不动 |
| `CHROMA_API_KEY` | 空 | 仅 remote 模式使用:连远程 Chroma 的访问密钥,非空才会传给 chroma-mcp。属于敏感信息,设置接口返回时会被遮盖。local 模式留空即可。(src/services/sync/ChromaMcpManager.ts、SettingsRoutes.ts) | 保持为空 |
| `CHROMA_TENANT` | `default_tenant` | 仅 remote 模式使用:Chroma 的租户名(tenant,多租户部署里的命名空间)。保持默认值 default_tenant 时不会向 chroma-mcp 传该参数。(src/services/sync/ChromaMcpManager.ts) | 不动 |
| `CHROMA_DATABASE` | `default_database` | 仅 remote 模式使用:Chroma 里的数据库名。保持默认 default_database 时不传该参数。(src/services/sync/ChromaMcpManager.ts) | 不动 |
| `CHROMA_PREWARM_TIMEOUT_MS` | `120000` | 预热超时(毫秒)。启动 chroma-mcp 前会先“预热”一次(让 uvx 把运行环境下载/构建好),这是等它完成的时限。默认 120000(2 分钟);合法范围 1~600000,超出范围按默认并记警告;环境变量优先于配置文件。网络慢导致首次安装超时才需要加大。(src/services/sync/ChromaMcpManager.ts) | 不动 |
| `CHROMA_MUTATION_TIMEOUT_MS` | `600000` | 单次向 Chroma 写入/建索引的超时(毫秒)。源码注释:嵌入和索引写入可能超过 MCP SDK 默认的 60 秒,所以放宽到默认 600000(10 分钟);实际会被夹在 60000~3600000 之间。(src/services/sync/ChromaMcpManager.ts) | 不动 |
| `CHROMA_MAX_PENDING_MUTATIONS` | `5000` | 等待写入 Chroma 的队列上限,默认 5000。超过后新的写入会被推迟到以后的回填(backfill)里补做,用来限制批量导入时的内存压力,平时正常写入不受影响。填非正整数时按 5000。(src/services/sync/ChromaMcpManager.ts) | 不动 |
| `CHROMA_EMBEDDING_FUNCTION` | `default` | 新建 Chroma 集合时使用的“嵌入函数”(把文字变成数字的方法)。有效值白名单只有 6 个:default、openai、cohere、jina、voyageai、roboflow,其它值会直接报错,并导致每次写入失败。default=本地内置的 all-MiniLM-L6-v2,只在本机算、不外发,但它是英文调优的:源码说明它的词表会把中日韩文字拆成单字或 [UNK],这正是中文召回差的原因。openai/cohere/jina/voyageai/roboflow 都是调用厂商 API:需要在环境变量里放该厂商的 API Key,并会把你的记忆文本发给第三方。只对“新建集合”生效;改了之后旧集合不会变,必须重建索引(重新嵌入)才会真正换。注意:本机多语言本地模型(EMBEDDING_MODEL)不在这条路径上。(src/services/sync/ChromaSync.ts、SettingsDefaultsManager.ts) | 不动 |
| `SERVER_VECTOR_SEARCH` | `auto` | 仅“服务器模式”(runtime=server,Postgres+pgvector)读取,本机默认的 worker 模式不读。控制服务器是否做“按意思搜索”:'true' 开启,'false' 关闭(只剩关键词),默认 auto=新建数据库自动开、升级前已有的老数据库保持仅关键词,避免升级后突然产生大量嵌入计算。开启后已有数据会在启动时于后台补算向量,可能耗时很久。(src/server/services/ObservationEmbeddingService.ts、SettingsDefaultsManager.ts) | 不动 |
| `EMBEDDING_BACKFILL_THREADS` | 空 | 仅服务器模式:服务启动发现有观察还没有当前模型的向量时,会在后台补算(可能耗数小时),本项限制这次补算最多用几个 CPU 线程,直到下次重启。空=机器线程数的一半,0=用满所有线程,负数/非数字按默认。本机 worker 模式不读。(src/server/services/ObservationEmbeddingService.ts) | 不动 |
| `EMBEDDING_MODEL` | `all-MiniLM-L6-v2` | 仅服务器模式(Postgres+pgvector)的“按意思搜索”使用的嵌入模型,必须是 src/services/vector/models.ts 里的 4 个之一,否则报错:all-MiniLM-L6-v2(默认,Chroma 同款,仅英文)、paraphrase-multilingual-MiniLM-L12-v2(多语言)、multilingual-e5-small(多语言)、granite-embedding-97m-multilingual-r2(多语言)。后 3 个对中日韩文本召回明显更好,但算力成本更高(文档称约 1.2~4.3 倍)。改模型会让所有观察在后台重新嵌入,完成前搜索只覆盖已重算的部分。我 grep 的结论:本机默认 worker/Chroma 路径不读取这个键(只有 ObservationEmbeddingService 读取),所以在本机改它不会改善中文召回。(src/services/vector/models.ts、src/server/services/ObservationEmbeddingService.ts、docs/public/hosted-server.mdx) | 不动 |
| `CHROMA_UVX_PATH` | 空 | uvx(Python 工具 uv 附带的启动器,用来启动 chroma-mcp)的可执行文件路径。默认空=先在 uv 的常见安装目录找,再找 PATH;只有装了 uvx 但程序找不到时才需要填绝对路径。(src/shared/uvx-bin-dirs.ts、dependency-preflight.ts) | 按需 |
| `SEARCH_RECENCY_DAYS` | `90` | 不带日期的语义搜索只返回最近 N 天内的匹配,默认 90。坑:这意味着超过 90 天的旧记忆在语义搜索里搜不到(明确给 dateStart/dateEnd 时才不受限,会以你给的范围为准)。0=关闭时间窗口,所有已索引的记忆都可命中;填更大的数则放宽窗口。非负整数以外的值会被忽略并保持 90。改完需重启 worker 才生效。(src/services/worker/search/types.ts、strategies/ChromaSearchStrategy.ts、worker-service.ts) | 建议改 |

### 16. 去重

把重复的笔记合并或标出来。默认关闭。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `DEDUP_ENABLED` | `false` | 去重总开关,默认 false;关闭时行为与旧版完全一致。开启后分两层:第 0 层——同一项目/来源/代理下标题规范化后完全相同的观察自动合并(次数累加);第 1 层——只把“相似但不完全相同”的记录登记为待人工审阅的候选,不会自动合并。下面几个 DEDUP_* 都只在它开着时才起作用。(src/services/sqlite/SessionStore.ts、dedup-store.ts、docs/public/configuration.mdx) | 不动 |
| `DEDUP_COSINE_THRESHOLD` | `0.80` | 判定“相似候选”的最低余弦相似度(按标题词的 IDF 加权,0~1,越高越严格)。源码注释:对短标题的经验最佳点(F1≈0.95)。默认 0.80,非数字回退 0.8。(src/services/sqlite/dedup-store.ts) | 不动 |
| `DEDUP_IDF_VETO_DF` | `10` | 否决规则:如果标题里有某个词在该项目里只出现在 ≤N 条记录中(罕见词,说明它能区分事物,如 rdlp-api 与 rdlp-plugin),就否决合并。默认 10。(src/services/sqlite/dedup-store.ts) | 不动 |
| `DEDUP_MIN_SHARED_TOKENS` | `2` | 两条标题至少共享多少个词才会进入相似度计算,默认 2;源码注释:用来滤掉稀疏向量带来的噪声。(src/services/sqlite/dedup-store.ts) | 不动 |
| `DEDUP_MIN_PROJECT_DOCS` | `10` | 冷启动门槛:一个项目的记录少于 N 条时跳过第 1 层相似度判断,因为词频统计(IDF)在记录太少时不可靠。默认 10。(src/services/sqlite/dedup-store.ts) | 不动 |
| `DEDUP_MAX_SCAN` | `2000` | 每插入一条新观察时,最多拿它跟同项目多少条最近标题比较,默认 2000;触顶会写调试日志,更早的行由 dedup-scan 覆盖。(src/services/sqlite/dedup-store.ts) | 不动 |
| `DEDUP_MAX_BACKFILL_ROWS` | `50000` | dedup-scan(对已有历史数据做全量去重扫描)遇到记录数超过此值的项目就跳过,出于内存安全。默认 50000。(src/services/sqlite/dedup-store.ts) | 不动 |

### 17. 云同步、团队与账号

登录 cmem.ai 之后才会用到的设置;不登录就全部保持为空。隐私核对重点看这一组。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `CLOUD_SYNC_TOKEN` | 空 | 云同步(把笔记同步到 cmem.ai 的服务器)的登录令牌,相当于密码;由安装器在浏览器登录 cmem.ai 后写入。只有 TOKEN、USER_ID、HUB_URL 三个键同时非空,云同步才会启动;启动后你的观察记录(observation)、会话摘要、你输入的提示词(prompt)以及“我的工作”状态,还有改标题/重映射项目这类修改操作,都会被推送到 HUB_URL 指向的服务器。要保持“纯本地”,请让这三个键都为空(默认就是空)。该键在网页接口里会被打码显示。(CloudSync.ts、SettingsRoutes.ts) | 保持为空 |
| `CLOUD_SYNC_USER_ID` | 空 | 云同步的账号 ID,由安装器登录 cmem.ai 后写入,同步时随请求一起带给服务器标识“是谁的数据”;TeamBrain(团队共享)也复用它作为 X-User-Id。与 TOKEN、HUB_URL 三者同时非空才会触发云端上传;“纯本地”请保持为空。(CloudSync.ts、teambrain.ts) | 保持为空 |
| `CLOUD_SYNC_HUB_URL` | 空 | 云同步服务器(sync-hub)的网址,例如 https://sync.cmem.ai。源码注释明确写了“为空 = 同步完全关闭”:为空时程序根本不会向外发任何同步请求;非空且 TOKEN、USER_ID 也有值时,会向 {HUB_URL}/v1/sync/ops 上传数据,并轮询拉取其他设备的数据。“纯本地”请保持为空。(CloudSync.ts) | 保持为空 |
| `CLOUD_SYNC_DEVICE_ID` | 空 | 本机在云同步里的设备编号。第一次启动云同步时自动生成并回写到这里,之后固定不变;同步没启用时保持为空即可。别手改,否则会被当成另一台设备。(SettingsDefaultsManager.ts、local-device-identity.ts) | 不动 |
| `CLOUD_SYNC_DEVICE_NAME` | `melodycchens-MacBook-Pro.local` | 本机在 cmem.ai“设备”面板里显示的名字,默认取本机主机名(hostname),所以你会看到默认值是电脑名。只有云同步启用后才会上传这个名字(最多 80 个字符);纯本地时不会发到任何地方。(CloudSync.ts) | 不动 |
| `CLOUD_SYNC_WS` | `true` | 云同步的“实时通知”开关(WebSocket=保持一条长连接,服务器有新数据时立刻通知)。取值 'true'/'false',默认 'true';设成 'false' 就只靠定时轮询,同步结果一样正确,只是慢一点。该键只在云同步已启用时才有意义,没登录云同步时不会连接任何服务器。(worker-service.ts、SyncClient.ts) | 不动 |
| `CLOUD_SYNC_KEEP_PULLING` | `false` | 云同步的“空闲时是否继续拉取”开关。默认 'false':没有会话运行约一小时后暂停拉取;设成 'true' 则不暂停,每 30 秒轮询一次,适合没有 hook 的云端查看用副本。仅云同步启用时生效。(worker-service.ts、SyncClient.ts) | 不动 |
| `CLOUD_SYNC_CONTENT_BATCH_SIZE` | `40` | 云同步每批推送的内容条数,默认 40。源码注释说明:一次推 200 条在服务器繁忙时会超时,所以调小了。仅云同步启用时用到;设置接口会校验该值。(CloudSync.ts、SettingsRoutes.ts) | 不动 |
| `CLOUD_SYNC_REQUEST_TIMEOUT_MS` | `90000` | 云同步推送内容时单次请求的超时时间,单位毫秒,默认 90000(90 秒),与服务器端的处理租约时长保持一致。仅云同步启用时用到。(CloudSync.ts) | 不动 |
| `TEAMBRAIN_URL` | 空 | TeamBrain(团队大脑:把你的会话信息共享给团队、并在会话开头读到队友在做什么)的服务器网址,例如 https://cmem.ai。源码注释:为空 = TeamBrain 关闭(“恰好在该键被设置时才开启”)。开启后会向该网址发请求(带上云同步的 TOKEN 与 USER_ID 作为身份,查询时会带上当前项目名)。由 `claude-mem teambrain join` 命令写入。纯本地请保持为空。(teambrain.ts) | 保持为空 |
| `TEAMBRAIN_TEAM_ID` | 空 | 你这台电脑加入的 TeamBrain 团队 ID,由 `teambrain join` 命令写入;teambrain 的 share/leave 命令默认使用它。没加入团队时为空。(teambrain.ts、teambrain 命令) | 保持为空 |
| `PRO_TRIAL_EMAIL` | 空 | 登录流程的记录字段:安装器在浏览器登录 cmem.ai(试用)时,把登录链接发到的邮箱记在这里,作为“别再重复打扰”的标记。由安装器写入,你不需要填;该键在网页接口里不会被展示。(SettingsDefaultsManager.ts 注释、SettingsRoutes.ts) | 不动 |
| `PRO_TRIAL_AT` | 空 | 登录流程的记录字段:最近一次发送登录链接的时间(ISO 时间戳)。由安装器的浏览器登录步骤写入,没走过登录流程就是空。仅是一条记录,不影响运行。(SettingsDefaultsManager.ts 注释) | 不动 |
| `PRO_TRIAL_STATE` | 空 | 试用状态记录:'link_sent'=登录已开始但凭证还没领取,'active'=已完成。安装器收到 cmem.ai 下发的记忆凭证后会写成 'active'。没走过登录就是空。(install.ts) | 不动 |
| `PRO_TRIAL_ENDS_AT` | 空 | 免费试用的到期日(ISO 日期),由安装器从 cmem.ai 的返回结果里写入。仅用于在会话上下文里提示“试用还剩几天”,不影响功能;没试用就是空。(install.ts、context.ts) | 不动 |
| `ONLINE_SIGNUP_EMAIL` | 空 | 安装时的可选“留邮箱”记录:交互式安装中如果你主动填了邮箱,才会写入这里并提交到 cmem.ai 的候补名单;直接回车跳过则为空。属于联系方式,网页接口会把它屏蔽,也不能通过 HTTP 写入。(install.ts、SettingsRoutes.ts) | 不动 |
| `ONLINE_SIGNUP_NOTE` | 空 | 安装时留邮箱时附带的那句“希望我们怎么帮你”备注,与 ONLINE_SIGNUP_EMAIL 一起由安装器写入;没填就是空。(install.ts) | 不动 |
| `ONLINE_SIGNUP_AT` | 空 | 留邮箱那一刻的时间(ISO 时间戳),由安装器写入;没留邮箱就是空。仅是记录。(install.ts) | 不动 |
| `ONLINE_SIGNUP_SENT` | 空 | 邮箱是否已成功提交到候补名单:'true'=已提交,'false'=没发出去,下次安装时会静默重试一次。没留邮箱就是空。(install.ts) | 不动 |
| `PRO_PLAN` | 空 | 登录流程的记录字段:cmem.ai 在登录完成时返回的套餐类型('trial' 试用 / 'pro' 付费 / 'none' 无;TeamBrain 席位会写 'teambrain_seat')。由安装器或 teambrain join 写入,仅用于提示,没登录为空。(install.ts、teambrain.ts、context.ts) | 不动 |
| `PRO_FALLBACK_AT` | 空 | “降级”记录:cmem 网关(cmem.ai 提供的记忆生成服务)彻底拒绝了你的密钥后,worker 会写入当时的时间,并改回用 Anthropic 套餐来生成记忆;空=没发生过降级。只由事件触发写入,成功连上网关或装入新密钥后会被清空。(cmem-gateway.ts、provider-dispatch.ts) | 不动 |
| `PRO_FALLBACK_MESSAGE` | 空 | 降级记录:网关被拒绝时给出的提示文字,会显示在会话上下文的提示里;空=使用通用提示。由 worker 在降级时写入。(cmem-gateway.ts、context.ts) | 不动 |
| `PRO_FALLBACK_ACTION` | 空 | 降级记录:网关给出的“该怎么办”说明,由 worker 在降级时写入,仅用于提示显示。(cmem-gateway.ts、context.ts) | 不动 |
| `PRO_FALLBACK_URL` | 空 | 降级记录:网关给出的处理链接(空=默认指向 cmem.ai/pro 续费页),由 worker 在降级时写入,仅用于提示显示。(cmem-gateway.ts、context.ts) | 不动 |
| `PRO_MEMORY_KEY` | 空 | 浏览器配对后暂存的“记忆密钥”(cmem.ai 网关的 API 密钥),在你选定记忆生成方(provider)之前先放在这里;一旦被采用,会被搬到 OPENROUTER_API_KEY 并把本键清空。有值且被采用后,记忆生成请求会发到 cmem.ai 网关(即观察内容会交给云端模型处理)。纯本地请保持为空;网页接口会对它打码。(cmem-memory-credentials.ts、SettingsRoutes.ts) | 保持为空 |
| `PRO_MEMORY_BASE_URL` | 空 | 与 PRO_MEMORY_KEY 配对的网关地址,由 cmem.ai 下发;空时回退为 cmem 官方推理网关地址(/api/inference/v1)。只有 PRO_MEMORY_KEY 被采用时才会成为记忆生成请求的目的地,即观察内容会发往该地址。纯本地请保持为空。(cmem-memory-credentials.ts) | 保持为空 |
| `PRO_MEMORY_MODEL` | 空 | 与 PRO_MEMORY_KEY 配对的模型名,由 cmem.ai 下发;空时回退为 'cmem-observer'。只在密钥被采用时才生效,纯本地请保持为空。(cmem-memory-credentials.ts) | 保持为空 |

### 18. 服务器模式与队列

runtime=server 时用的 Postgres 服务器、鉴权和任务队列。本机默认 worker 模式基本用不到。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `QUEUE_ENGINE` | `sqlite` | 任务队列(队列=让任务排队依次处理)的引擎,只能是 'sqlite'(默认,存在本机数据库里)或 'bullmq'(需要 Redis 服务),填别的会报错。只在 runtime=server(服务器模式)下生效,本机默认是 worker 模式,可以不管。(redis-config.ts、create-server-service.ts) | 不动 |
| `REDIS_URL` | 空 | Redis(一种常用的内存数据库,BullMQ 队列要靠它)的完整连接地址,必须以 redis:// 或 rediss:// 开头。填了就优先于 HOST/PORT;QUEUE_ENGINE=bullmq 时必须设置。该值可能含密码,网页接口会打码。只在 runtime=server(服务器模式)下生效,本机默认是 worker 模式,可以不管。(redis-config.ts、create-server-service.ts) | 保持为空 |
| `REDIS_HOST` | `127.0.0.1` | Redis 的主机地址,默认 127.0.0.1(本机)。仅当 REDIS_URL 为空时才用。只在 runtime=server(服务器模式)下生效,本机默认是 worker 模式,可以不管。(redis-config.ts) | 不动 |
| `REDIS_PORT` | `6379` | Redis 的端口,默认 6379,必须是 1–65535 的整数,否则报错。仅当 REDIS_URL 为空时才用。只在 runtime=server(服务器模式)下生效,本机默认是 worker 模式,可以不管。(redis-config.ts) | 不动 |
| `REDIS_MODE` | `external` | Redis 的运行方式,只能是 external(用现成的外部 Redis,默认)、managed 或 docker。只在 runtime=server(服务器模式)下生效,本机默认是 worker 模式,可以不管。(redis-config.ts) | 不动 |
| `QUEUE_REDIS_PREFIX` | `claude_mem_37701` | 队列在 Redis 里所有键的名字前缀,用来区分同一个 Redis 上的不同安装;默认值里的数字是每台安装的端口派生值,非字母数字下划线连字符的字符会被替换成下划线。只在 runtime=server(服务器模式)下生效,本机默认是 worker 模式,可以不管。(redis-config.ts) | 不动 |
| `AUTH_MODE` | `api-key` | 服务器接口的鉴权方式:'api-key'(默认,必须带 API 密钥)或 'local-dev'(本机开发时免密)。local-dev 还要同时设置 CLAUDE_MEM_ALLOW_LOCAL_DEV_BYPASS=1、且只放行本机回环请求,Docker 部署里禁止使用。只在 runtime=server(服务器模式)下生效,本机默认是 worker 模式,可以不管。(auth.ts、create-server-service.ts) | 不动 |
| `SERVER_URL` | `http://127.0.0.1:37878` | 服务器运行时的网址,hook(钩子:Claude Code 触发的小程序)在服务器模式下用它找服务器;默认 http://127.0.0.1:37878(本机地址,端口按每次安装派生)。这是新的标准键,hook 先读它,为空才回退到旧名 SERVER_BETA_URL。只在 runtime=server(服务器模式)下生效,本机默认是 worker 模式,可以不管。(runtime-selector.ts、SettingsDefaultsManager.ts) | 不动 |
| `SERVER_API_KEY` | 空 | hook 访问本机服务器用的 API 密钥,服务器模式安装时由安装器写入。为空时 hook 会因“缺少 API 密钥”回退/报错。网页接口会打码。只在 runtime=server(服务器模式)下生效,本机默认是 worker 模式,可以不管。(server-bootstrap.ts、runtime-selector.ts) | 不动 |
| `SERVER_PROJECT_ID` | 空 | hook 在服务器模式下默认使用的 Postgres 项目 ID(服务器端用来区分项目的编号),由安装器写入;为空则回退到旧键 SERVER_BETA_PROJECT_ID。只在 runtime=server(服务器模式)下生效,本机默认是 worker 模式,可以不管。(runtime-selector.ts、server-bootstrap.ts) | 不动 |
| `SERVER_BETA_URL` | `http://127.0.0.1:37878` | 旧名字的兼容回退:SERVER_URL 为空时才会读它,让早期安装的 settings.json 继续有效。新安装用 SERVER_URL 即可。只在 runtime=server(服务器模式)下生效,本机默认是 worker 模式,可以不管。(runtime-selector.ts、SettingsDefaultsManager.ts 注释) | 不动 |
| `SERVER_BETA_API_KEY` | 空 | 旧名字的兼容回退:SERVER_API_KEY 为空时才会读它。新安装用 SERVER_API_KEY。只在 runtime=server(服务器模式)下生效,本机默认是 worker 模式,可以不管。(runtime-selector.ts、server-bootstrap.ts) | 不动 |
| `SERVER_BETA_PROJECT_ID` | 空 | 旧名字的兼容回退:SERVER_PROJECT_ID 为空时才会读它。新安装用 SERVER_PROJECT_ID。只在 runtime=server(服务器模式)下生效,本机默认是 worker 模式,可以不管。(runtime-selector.ts、server-bootstrap.ts) | 不动 |

### 19. 通知与外部集成

Telegram 通知、Notion 导出、Grok Bot、CCS 对齐等可选外挂。默认基本都是空的或关的。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `TELEGRAM_ENABLED` | `true` | Telegram(聊天软件)通知的总开关,默认 'true',但这只是“允许”:没有填 BOT_TOKEN(机器人密钥)和 CHAT_ID(接收人)就不会发任何消息。单条观察提醒另有开关(默认关),会话收尾通知还要配置路由才会发。(TelegramNotifier.ts、TelegramWrapupNotifier.ts) | 不动 |
| `TELEGRAM_BOT_TOKEN` | 空 | Telegram 机器人的密钥,属于 Telegram 外挂。为空 = 不会向 Telegram 发送任何内容;填了之后,匹配条件的观察标题、项目名等会发到 Telegram 服务器。网页接口会打码。(TelegramNotifier.ts、SettingsRoutes.ts) | 保持为空 |
| `TELEGRAM_CHAT_ID` | 空 | Telegram 外挂:接收提醒的聊天/群 ID。为空时单条观察提醒不会发送。(TelegramNotifier.ts) | 保持为空 |
| `TELEGRAM_WRAPUPS_ENABLED` | `true` | Telegram 外挂:“会话结束总结”通知的开关,默认 'true';但源码注释说明必须给项目配置了明确的路由(WRAPUP_ROUTES)才会发送,默认路由为空,所以实际不发。(TelegramWrapupNotifier.ts) | 不动 |
| `TELEGRAM_OBSERVATION_ALERTS_ENABLED` | `false` | Telegram 外挂:单条观察即时提醒的开关,默认 'false'(需主动开启)。不开启就不会发提醒,哪怕 ENABLED 是 true。(TelegramNotifier.ts) | 不动 |
| `TELEGRAM_WRAPUP_ROUTES` | `{}` | Telegram 外挂:“项目 → Telegram 路由”的 JSON 对象,每个项目可配 chat_id,也可覆盖机器人密钥。默认 '{}'(空),所以不会发会话总结。网页接口会打码。(TelegramWrapupNotifier.ts) | 保持为空 |
| `TELEGRAM_TRIGGER_TYPES` | `security_alert,sensitive` | Telegram 外挂:哪些类型的观察会触发提醒,逗号分隔,默认 'security_alert,sensitive'(安全告警与敏感信息)。只有在提醒开关打开且有 token/chat id 时才有意义。(TelegramNotifier.ts) | 不动 |
| `TELEGRAM_TRIGGER_CONCEPTS` | 空 | Telegram 外挂:按“概念标签”触发提醒的列表,逗号分隔,默认空。类型和概念两个列表都为空时,不会发送任何提醒。(TelegramNotifier.ts) | 不动 |
| `GROK_BOT_AWARENESS_ENABLED` | `false` | Grok Bot 外挂(一个本地的 AI 助手产品)的“感知推送”总开关,默认 'false'。开启后,匹配条件的观察会被追加写入你指定的 Grok Bot 席位的本地日志文件(不走网络);关闭就什么都不写。(GrokBotAwarenessPusher.ts) | 不动 |
| `GROK_BOT_AWARENESS_AGENT_IDS` | 空 | Grok Bot 外挂:允许被写入的席位(agent)ID 白名单,逗号分隔。源码注释:空列表 = 不写入任何席位。(GrokBotAwarenessPusher.ts) | 保持为空 |
| `GROK_BOT_AWARENESS_TRIGGER_TYPES` | `decision,bugfix,security_alert,sensitive` | Grok Bot 外挂:哪些类型的观察算“值得感知”,默认 'decision,bugfix,security_alert,sensitive'。同一份条件也被 Grok Bot webhook 复用(但 webhook 只有设了网址才会发)。(GrokBotAwarenessPusher.ts、GrokBotBrainbeat.ts) | 不动 |
| `GROK_BOT_AWARENESS_TRIGGER_CONCEPTS` | 空 | Grok Bot 外挂:按概念标签筛选“值得感知”的观察,逗号分隔,默认空;与 TRIGGER_TYPES 一起被感知推送和 webhook 共用。(GrokBotAwarenessPusher.ts、GrokBotBrainbeat.ts) | 不动 |
| `GROK_BOT_WEBHOOK_URL` | 空 | Grok Bot 外挂的 webhook(往某个网址发通知):每条匹配感知条件的新观察会以 POST 发到这个网址,内容含观察 ID、类型、标题、副标题、项目名、概念标签。源码明确写了:为空则不发(默认就是空)。网址可能带密码参数,网页接口会打码,且只能在文件/环境变量里设置。(GrokBotBrainbeat.ts、SettingsRoutes.ts) | 保持为空 |
| `GROK_BOT_WEBHOOK_SECRET` | 空 | Grok Bot webhook 的共享密钥:非空时会放在请求头 x-claude-mem-shared-secret 里发给接收方做校验。只有 WEBHOOK_URL 设置后才有用;网页接口会打码。(GrokBotBrainbeat.ts) | 保持为空 |
| `NOTION_ENABLED` | `false` | Notion 导出外挂开关:开启后每条新观察会写入你的 Notion 数据库(调用 api.notion.com)。默认 'false';即便开启,没填 TOKEN 和 DATABASE_ID 也什么都不做。(NotionExporter.ts) | 不动 |
| `NOTION_TOKEN` | 空 | Notion 导出外挂:Notion 集成的访问令牌。为空则导出不会运行;填了并启用后,观察内容会发到 Notion。只能在文件/环境变量里设置,网页接口会打码。(NotionExporter.ts、SettingsRoutes.ts) | 保持为空 |
| `NOTION_DATABASE_ID` | 空 | Notion 导出外挂:要写入的 Notion 数据库 ID。为空则导出不会运行。(NotionExporter.ts) | 保持为空 |
| `NOTION_AUTO_CREATE_PROPERTIES` | `true` | Notion 导出外挂:是否自动在你的数据库里补建缺少的列(属性)。默认 'true',只有设成 'false' 才关闭;整个外挂没启用时无影响。(NotionExporter.ts) | 不动 |
| `GROK_BOT_INJECT_ENABLED` | `true` | Grok Bot 外挂的“实时记忆索引”开关,默认开:每有新观察,worker 会把一份索引写成本地文件 zz-claude-mem-inject.md 放到各 Grok Bot 席位的目录里。源码注释:本机没有 Grok Bot 席位时什么都不做,且只写本地文件、不联网。(GrokBotIndexWriter.ts) | 不动 |
| `GROK_BOT_INJECT_AGENT_IDS` | `*` | Grok Bot 外挂:要写索引的席位 ID。默认 '*' 表示自动覆盖所有已发现的席位;空或 'all' 同理;也可填具体 ID 列表(逗号分隔)。(GrokBotIndexWriter.ts) | 不动 |
| `GROK_BOT_INJECT_TIER` | `episode` | Grok Bot 外挂:索引每行前面加的标记类别,可选 episode(默认,加 [episode] )、plain(不加)、note(加 [note] ),填错会退回 episode。(grok-bot-index-format.ts) | 不动 |
| `GROK_BOT_INJECT_WINDOW` | `80` | Grok Bot 外挂:索引里最多放多少条最近的观察,默认 80,上限 100,小于 1 或非数字会退回默认。(grok-bot-index-format.ts) | 不动 |
| `GROK_BOT_INJECT_FALLBACK` | `house` | Grok Bot 外挂:席位自己的项目观察不够条数时的补充策略,'house'(默认)=用所有项目的最新观察补满,'off'=不补。(GrokBotIndexWriter.ts) | 不动 |
| `GROK_BOT_INJECT_PLATFORM_SOURCE` | 空 | Grok Bot 外挂:只取某个平台来源的观察写入索引,默认空 = 不过滤。(GrokBotIndexWriter.ts) | 不动 |
| `GROK_BOT_INJECT_PROJECTS_BY_AGENT` | 空 | Grok Bot 外挂:手动指定“席位 → 项目列表”,格式 '席位ID=项目甲,项目乙;另一席位ID=项目丙'。空 = 从 transcript-watch.json 配置里推断。(GrokBotIndexWriter.ts) | 不动 |
| `GROK_BOT_INJECT_MAX_LINE_CHARS` | `160` | Grok Bot 外挂:索引中每一行最多保留多少字符,默认 160,代码里最高封顶 480。(GrokBotIndexWriter.ts) | 不动 |
| `GROK_BOT_INJECT_DEBOUNCE_MS` | `1500` | Grok Bot 外挂:新观察到来后等待多少毫秒再重写索引文件(合并短时间内的多次写入),默认 1500;负数或非数字会用默认值。(GrokBotIndexWriter.ts) | 不动 |
| `GROK_BOT_INJECT_STANDING_LINE` | 空 | Grok Bot 外挂:想在每个索引文件里固定附带的一句话(长期提示),默认空 = 不加。(GrokBotIndexWriter.ts) | 不动 |
| `CCS_ALIGN_ENABLED` | `true` | CCS Align(与 Grok Bot 席位“规则对齐”的外挂)开关,默认 'true'。它只在本机 ~/.claude-mem/ccs-align/ 下维护缓存文件,源码中没有对外网络请求;没有对应席位时没有实际效果。(CcsAlignMiddleCache.ts) | 不动 |
| `CCS_ALIGN_VIEWER_IDS` | `ccs-align` | CCS Align 外挂:查看者/席位名单,逗号分隔,默认 'ccs-align'。缓存目录以它命名;规则巡检只取第一个。(CcsAlignMiddleCache.ts、CcsAlignRulesWalker.ts) | 不动 |
| `CCS_ALIGN_TRIGGER_TYPES` | `decision,bugfix,security_alert,sensitive` | CCS Align 外挂:哪些类型的观察会被放进本地缓存,默认 'decision,bugfix,security_alert,sensitive'(源码注释:复制自 Grok 的条件列表)。空列表则一条都不匹配。(CcsAlignMiddleCache.ts) | 不动 |
| `CCS_ALIGN_PATCH_SHADOWS` | `false` | CCS Align 外挂:第二阶段规则巡检是否允许“自动修补影子副本”,默认 'false' = 只出报告不改文件(源码注释:这是个提示开关,不会悄悄执行)。只涉及本地文件。(CcsAlignRulesWalker.ts) | 不动 |

### 20. My Work 视图

网页查看器里"我的工作"页的自动刷新与文案生成设置。

| 键 | 默认值 | 注释 | 新手 |
|---|---|---|---|
| `WORK_VIEW_AUTO_REFRESH` | `true` | “我的工作”页是否自动后台刷新,默认 'true'。刷新时只有发现有任务到期才会真的调用 AI agent(会消耗你的模型额度);设成 'false' 就不会自己运行。(WorkViewRoutes.ts) | 按需 |
| `WORK_VIEW_REFRESH_INTERVAL_MIN` | `10` | “我的工作”定时检查的间隔,单位分钟,默认 10,最小 1,1440=一天一次;每次检查只是只读查数据库,到期才启动 agent。worker 启动时读取。(auto-refresh-worker.mjs) | 按需 |
| `WORK_VIEW_SHARED_STATE` | `false` | 是否把“我的工作”的状态记录同步给云端/其他设备读取,默认 'false'。源码注释:所有本地/云端读取方都认识这些保留记录后再开。纯本地请保持关闭。(worker-service.ts、CloudSync.ts) | 不动 |
| `WORK_VIEW_COPY_PROVIDER` | 空 | 生成“我的工作”文案所用的模型提供方:空=仅当 OpenRouter 是主提供方时才用它;openrouter/openai-compatible=明确指定;off=不生成文案。(SettingsDefaultsManager.ts 注释、ContextSettingsModal.tsx) | 按需 |
| `WORK_VIEW_COPY_MODEL` | 空 | 生成“我的工作”文案时的模型覆盖项,空 = 用所选提供方已配置的模型。(SettingsDefaultsManager.ts 注释) | 按需 |
| `WORK_VIEW_AGENT` | 空 | “我的工作”刷新由哪个 agent 来跑:空=跟随 CLAUDE_MEM_PROVIDER;claude-code/codex/gemini=指定一个;off=都不跑;all=依次尝试所有已登录的 agent。(refresh-task.ts) | 按需 |
| `WORK_VIEW_CLAUDE_MODEL` | 空 | “我的工作”刷新在 Claude Code 上使用的模型别名(如 haiku),空=各步骤按默认表(haiku/sonnet)。(refresh-task.ts) | 不动 |
| `WORK_VIEW_CODEX_MODEL` | 空 | “我的工作”刷新在 Codex 上使用的模型,空=各步骤按默认表。(refresh-task.ts) | 不动 |
| `WORK_VIEW_GEMINI_MODEL` | 空 | “我的工作”刷新在 Gemini 上使用的模型,空=各步骤按默认表(flash-lite/flash)。(refresh-task.ts) | 不动 |
| `WORK_VIEW_TEXT_LANGUAGE` | 空 | “我的工作”生成的标题、复盘、故事文本使用的语言,填语言名如 'Chinese (Simplified)' 或 'Turkish';空=由技能按使用者语言自行选择,不会自动检测。想固定输出中文可填它。(refresh-task.ts) | 按需 |


---

## 第四层:进阶

### 配置优先级

**环境变量 > `settings.json` > 默认值。**

| 结论 | 源码位置 |
|---|---|
| `get(key)` 里写的是 `process.env[key] ?? this.DEFAULTS[key]`,环境变量优先于默认值 | `src/shared/SettingsDefaultsManager.ts` |
| `loadFromFile` 默认 `applyEnvOverrides = true`,环境变量会覆盖从文件读到的值 | `src/shared/SettingsDefaultsManager.ts` |
| 默认值集中定义在 `DEFAULTS` | `src/shared/SettingsDefaultsManager.ts` |

实际含义:如果 shell 里导出过同名的 `CLAUDE_MEM_*` 环境变量,改 `settings.json` 会看起来"没生效"。排查时先 `env | grep CLAUDE_MEM`。

### 改完要重启 worker

```bash
npx claude-mem restart
```

这是"已读源码推断",见第一层。涉及模型、提供方、端口、模式的修改尤其要重启。

### 模式文件 `plugin/modes/*.json`

以 `plugin/modes/code--zh.json` 为例(已读源码):

| 部分 | 内容 |
|---|---|
| `name` | `Code Development (Chinese)` |
| `prompts.continuation_instruction` | 含 `LANGUAGE REQUIREMENTS: Please write the observation data in 中文` |
| `prompts.footer`、`prompts.summary_footer` | 含相同的中文输出要求 |
| `xml_*_placeholder` | 各 XML 标签内期望的中文占位说明,例如 `xml_summary_completed_placeholder` 为 `[到目前为止完成了什么工作?发布或更改了什么?]` |

要点:`code--zh` 的做法是**覆盖默认的英文提示词**,让观察者按中文写观察和摘要。它不改变存储和检索逻辑,中文模式下向量嵌入仍是英文模型(见下)。

研究文件把可改的字段列为 `name`、`observation_types`、`observation_concepts` 和 `prompts`;各字段更完整的 JSON 结构、`prompts` 下的完整键名,没有逐个读到。

### 怎么自定义模式

1. 复制现有的 `code.json`。
2. 修改 `name`、`observation_types`、`observation_concepts` 和 `prompts`。
3. 另存为 `plugin/modes/` 下的新 JSON 文件,例如 `my-mode.json`。
4. 在 `settings.json` 里把 `CLAUDE_MEM_MODE` 设为文件名(不含 `.json`),即 `"my-mode"`。
5. 重启 worker。

### 与跨端共享相关的键

| 键 | 默认值 | 说明 |
|---|---|---|
| `CLAUDE_MEM_SESSION_START_INCLUDE_ALL_SOURCES` | `false` | 默认只注入"本工具自己"写的记忆(按 `platform_source` 过滤),所以 OpenCode 看不到 DSH 写的、反之亦然。设为 `"true"` 就不按来源过滤,两端记忆混在一起注入。OpenCode 插件每次请求实时读它,无需重启。**已实测**:开启后 OpenCode 与 DSH 能互相读到对方写的记忆(见 [[claude-mem-跨端共享]] 第 8 节) |
| `CLAUDE_MEM_PROJECT_NAME_SOURCE` | `path` | 决定"记忆算哪个项目"。两端把同一个工作目录交给 worker 算项目名,同目录同设置就落到同一项目 |
| `CLAUDE_MEM_CONTEXT_PROJECTS` | `current` | **对 OpenCode 无效**:OpenCode 插件自己拼请求,没读这个键;只在走 hook 的客户端(如 Claude Code)生效 |

详见 [[claude-mem-跨端共享]]。

### 与中文召回相关的键

| 键 | 默认值 | 说明 |
|---|---|---|
| `CLAUDE_MEM_CHROMA_EMBEDDING_FUNCTION` | `default`(all-MiniLM-L6-v2,源码注释写明英文调优) | 白名单只有 `default`、`openai`、`cohere`、`jina`、`voyageai`、`roboflow`,没有本地多语言选项;换好的中文嵌入只能用云端,会把笔记发给第三方 |
| `CLAUDE_MEM_EMBEDDING_MODEL` | `all-MiniLM-L6-v2` | 已读 `src/services/vector/models.ts`:可选 4 个,其中 3 个是多语言(见下表) |
| `CLAUDE_MEM_SERVER_VECTOR_SEARCH` | `auto` | 控制"服务器模式"的按意思搜索 |

**重要限制:`EMBEDDING_MODEL` 只作用于"服务器模式"(`runtime=server`,Postgres + pgvector),不作用于本机默认的 worker 模式。** 依据:源码里读取它的只有 `src/server/services/ObservationEmbeddingService.ts`,默认的 Chroma 路径用的是 `CHROMA_EMBEDDING_FUNCTION`,白名单里没有本地多语言模型。所以你本机默认安装,**中文向量召回的短板仍在**,换 `EMBEDDING_MODEL` 不会改善它。要用上多语言模型,得走服务器模式,而它强制要求 Postgres,不是轻量本机用法。这是我读源码的判断,没有实测。

`models.ts` 里的 4 个模型:

| 模型名 | 多语言 | 向量维度 | 单条最大 token |
|---|---|---|---|
| `all-MiniLM-L6-v2`(默认) | 否,英文 | 384 | 256 |
| `paraphrase-multilingual-MiniLM-L12-v2` | 是 | 384 | 128 |
| `multilingual-e5-small` | 是 | 384 | 512 |
| `granite-embedding-97m-multilingual-r2` | 是 | 384 | 512 |

源码注释(已读)直接承认:默认模型的 30k 词表会把中日韩文字切成单字或 `[UNK]`,这是 Issue #3422 测出的 CJK 召回差距的来源,对应修复讨论在 #3982。

要点:中文关键词检索靠子串匹配,可用;中文笔记"换个说法"的语义检索,默认配置下偏弱,这一条由上面的源码注释佐证,**具体差多少没实测**。详见 [[claude-mem-存储与读取机制]];检索融合策略(本地模式无 RRF 等)见该篇第五节。

---

## 配置自检清单

装完、改完、重启 worker 之后,打开 `~/.claude-mem/settings.json` 逐项核对:

- [ ] `CLAUDE_MEM_CLOUD_SYNC_HUB_URL` 为空(为空则云同步完全关闭)
- [ ] `CLAUDE_MEM_CLOUD_SYNC_TOKEN` 为空
- [ ] `CLAUDE_MEM_PRO_MEMORY_KEY` 为空
- [ ] `CLAUDE_MEM_PROVIDER` 是 `openai-compatible`,且 `CLAUDE_MEM_OPENAI_COMPAT_BASE_URL` 指向 codebuddy,**不含 `cmem.ai`**
- [ ] `CLAUDE_MEM_OPENAI_COMPAT_MODEL` 已填(自定义地址下留空会报错)
- [ ] `CLAUDE_MEM_PROVIDER` 不是 claude-mem 托管的提供方(登录后选它,每次工具调用的内容会发到第三方)
- [ ] `CLAUDE_MEM_MODE` 是 `code--zh`(或你自己的模式文件名,且该文件存在)
- [ ] `CLAUDE_MEM_REDACT_ENABLED` 为开(本机 `REDACT_ENABLED` 与 `REDACT_GENERIC_ENABLED` 均为 `"true"`)
- [ ] 已执行 `npx claude-mem telemetry disable`
- [ ] `env | grep CLAUDE_MEM` 没有会覆盖上述值的同名环境变量
- [ ] 再用 `lsof -i` 或日志确认 worker 没连 `cmem.ai`、`sync.cmem.ai`

---

## 没读到 / 不确定清单

1. 第三层各表只挑了新手相关的键;其余键的含义以附录里的默认值和源码注释为准,没有逐个解释。
2. 改 `settings.json` 后必须重启 worker:来自"已读源码推断",没有逐键验证。
3. 附录里布尔值全是字符串,是源码默认值的写法;用户手写 JSON 布尔值是否也被接受,没读到,照字符串写最稳。
4. 选 `openai-compatible` 而不是 `openrouter` 来接 codebuddy,依据是读源码:它不带归因请求头、key 独立、安装器不会引导登录 cmem.ai。**已实测**:`openai-compatible` 经公司网关调通(直连 codebuddy 没试)。
5. 观察者接 codebuddy:本机已实测通过,走公司网关;额度限制和笔记质量没系统评估。
6. `host` 提供方:源码确认它依赖本机已在运行的兼容服务,安装器不起;OpenCode、DSH 上有没有现成服务没读到,大概率没有,详见 [[claude-mem-安装部署]] 2.4 节。
7. 模式文件 JSON 的完整字段列表没逐个读到;安装后 `plugin/modes/` 在本机的实际路径,以及升级是否会覆盖自定义模式文件,没读到。
8. `EMBEDDING_MODEL` 只作用于服务器模式,是我读源码的判断;默认 worker 模式是否有别的路径用到它,没做全仓库追踪。
9. 中文向量召回在默认配置下偏弱:**已实测**。中问中 20 条,第 1 名命中从 4 条(默认 MiniLM)升到 8 条(bge-m3),水准是及格、不是达标;英问中样本小,没有明显改善(见 [[claude-mem-本地多语言向量方案]] 5.3)。
10. 匿名统计(PostHog)具体发什么内容没读;关闭靠 `npx claude-mem telemetry disable`。

---

## 附录:完整默认配置(238 个键,分组加注释)

下面是 `SettingsDefaultsManager.ts` 里 `DEFAULTS` 的**全部内容**,用脚本直接从源码提取并转成 JSON,没有手抄。全新安装时,worker 第一次启动会把这一整份写进 `~/.claude-mem/settings.json`(权限 0600),所以装完你看到的文件应该就是这个样子。

提取时对 11 个"运行时才算出来"的默认值,按**这台机器**(macOS,uid 501,用户目录 `/Users/melodycchen`)算成了具体值,换机器会不同:

| 键 | 源码里的写法 | 这里填的值 | 为什么 |
|---|---|---|---|
| `CLAUDE_MEM_WORKER_PORT` | `37700 + 偏移` | `37701` | 偏移 = uid 对 100 取余,uid 501 得 1(`src/shared/install-port.ts`) |
| `CLAUDE_MEM_SERVER_URL`、`CLAUDE_MEM_SERVER_BETA_URL` | `37877 + 偏移` | `http://127.0.0.1:37878` | 同上 |
| `CLAUDE_MEM_QUEUE_REDIS_PREFIX` | `claude_mem_<端口>` | `claude_mem_37701` | 跟着 worker 端口走 |
| `CLAUDE_MEM_DATA_DIR` | `~/.claude-mem` | `/Users/melodycchen/.claude-mem` | 展开了用户目录 |
| `CLAUDE_MEM_TRANSCRIPTS_CONFIG_PATH` | `~/.claude-mem/transcript-watch.json` | 同左,已展开 | 同上 |
| `CLAUDE_MEM_CLOUD_SYNC_DEVICE_NAME` | 本机主机名 | 本机主机名 | 取 `hostname()` |
| `CLAUDE_MEM_API_TIMEOUT_MS` | 30000 毫秒(Windows 会乘系数) | `30000` | `src/shared/hook-constants.ts` |
| `CLAUDE_MEM_SESSION_INIT_TIMEOUT_MS` | 15000 减 5000(Windows 减 8000) | `10000` | 同上 |
| `CLAUDE_MEM_LLM_TIMEOUT_MS`、`CLAUDE_MEM_FIELD_OPTIMIZE_TIMEOUT_MS` | `DEFAULT_LLM_TIMEOUT_MS` | `180000` | 常量定义在 `SettingsDefaultsManager.ts` 第 134 行 |

所有值都是**字符串**,包括 `"true"`、`"false"`、数字、JSON 数组(如 `"[]"`)。这也回答了之前"布尔值能不能写 JSON 布尔"的疑问:源码默认值全是字符串,照这个写法最稳。

附录分两份,内容是同一批键和值:

- **附录一(带注释版)**:按第三层的 20 组排列,每组有标题,每个键上面有一行注释,说明它是干什么的和新手要不要动。**这一份只用来读**。`settings.json` 是标准 JSON,不允许 `//` 注释,整份贴进去会解析失败。
- **附录二(纯 JSON 版)**:没有注释,可直接保存为 `~/.claude-mem/settings.json`。键的顺序是源码里的顺序。

注释是每个键完整说明的第一句话(过长的会截短),完整说明看第三层对应表格。

### 附录一:分组带注释版(只读,不能直接使用)

```jsonc
{
  // ===== 01 Worker 进程与通信 =====
  // 管后台常驻小服务 worker 怎么启动、监听哪里、hook 怎么找到它、多久算超时。
  // worker(后台常驻服务)监听的本地端口号,hook(钩子:agent 某个时刻自动触发的小程序)和 OpenCode/DSH 插件都靠它找到 worker [新手:装完核对]
  "CLAUDE_MEM_WORKER_PORT": "37701",
  // worker 监听的网卡地址 [新手:不动]
  "CLAUDE_MEM_WORKER_HOST": "127.0.0.1",
  // 给客户端(hook/插件)指定的完整 worker 地址,如 https://xxx [新手:保持为空]
  "CLAUDE_MEM_WORKER_URL": "",
  // 远程上报口令:当 hook 在另一台机器、需要通过 HTTP 把事件传给 worker(/api/spool/ingest)时,双方用这个口令做 Bearer 认证 [新手:保持为空]
  "CLAUDE_MEM_WORKER_INGEST_TOKEN": "",
  // 远程上报接口单次请求体的大小上限,单位字节,默认 5242880(5 MiB);填的值不是正整数时回退到 5 MiB [新手:不动]
  "CLAUDE_MEM_WORKER_INGEST_MAX_BYTES": "5242880",
  // hook 把事件交给 worker 的“暂存队列(spool)”走哪条路:'http' 强制走 HTTP 上传,'filesystem' 强制走本地文件…… [新手:不动]
  "CLAUDE_MEM_HOOK_SPOOL_TRANSPORT": "auto",
  // 允许哪些浏览器来源(origin,即网页的 协议+域名+端口)跨域调用 worker 的 API,逗号分隔的完整 origin 列表;本机 localhost/127.0.0.1 默认放行 [新手:保持为空]
  "CLAUDE_MEM_ALLOWED_ORIGINS": "",
  // worker 跑在端口转发/反向代理后面时,界面(viewer,记忆的网页查看器)的链接应该显示成什么浏览器可访问的地址,例如 https://37700.host.<user>.<domain>;留空则按 localhost 生成链接 [新手:保持为空]
  "CLAUDE_MEM_PUBLIC_URL": "",
  // hook 调用 worker API 的超时时间,单位毫秒,默认 30000(30 秒),有效范围 500~300000,越界回退默认值 [新手:不动]
  "CLAUDE_MEM_API_TIMEOUT_MS": "30000",
  // 会话开始时(用户提交第一条提示词那一刻,hook 向 worker 注册会话并取回记忆上下文)的整体超时,单位毫秒,默认 10000(10 秒;Windows 上 7 秒),上限受 hook 的 15 秒总预算限制,最小 500 [新手:不动]
  "CLAUDE_MEM_SESSION_INIT_TIMEOUT_MS": "10000",
  // worker 空闲自动退出的秒数(opt-in,最小 60) [新手:不动]
  "CLAUDE_MEM_IDLE_EXIT_SEC": "0",
  // hook 连续 N 次连不上 worker 后,在该会话里提醒一次“worker 不可用”(只提醒,不会阻塞 agent) [新手:不动]
  "CLAUDE_MEM_HOOK_FAIL_LOUD_THRESHOLD": "3",
  // worker 的“心跳”(定期写下的存活标记)多久没更新才算失联,单位毫秒,默认 120000(2 分钟),范围 10000~3600000 [新手:不动]
  "CLAUDE_MEM_WORKER_HEARTBEAT_STALE_MS": "120000",
  // “Observation TV”(观察笔记远程直播)的访问口令 [新手:保持为空]
  "CLAUDE_MEM_TV_TOKEN": "",
  // hook 选择哪种运行时:'worker'(默认,本机后台服务,你现在用的)或 'server'/'server-beta'(需要另配数据库的服务端形态,Docker 部署用),其它值一律按 worker 处理 [新手:不动]
  "CLAUDE_MEM_RUNTIME": "worker",
  // true(默认)=hook/MCP 需要时会自动启动、重启 worker;false=worker 由外部(如 launchd、容器)管理,hook 只使用已在运行的 worker,绝不启动、杀掉或重建它 [新手:不动]
  "CLAUDE_MEM_WORKER_AUTOSTART": "true",

  // ===== 02 数据、日志与备份 =====
  // 管数据放哪、日志留多久、旧数据清不清、要不要自动快照。
  // claude-mem 所有数据的根目录(settings.json、数据库、日志、transcript-watch.json、modes 等都在这里),默认 ~/.claude-mem [新手:不动]
  "CLAUDE_MEM_DATA_DIR": "/Users/melodycchen/.claude-mem",
  // 日志详细程度,可选 DEBUG / INFO / WARN / ERROR / SILENT,默认 INFO;写入 settings 时会校验,不在此列表会被拒绝 [新手:不动]
  "CLAUDE_MEM_LOG_LEVEL": "INFO",
  // 启动向量检索组件 Chroma(用 Python 的 uvx 运行)时指定的 Python 版本,格式必须是 3.X 或 3.XX,默认 3.13;环境变量同名值优先 [新手:不动]
  "CLAUDE_MEM_PYTHON_VERSION": "3.13",
  // 是否自动给本地数据库做快照备份 [新手:按需]
  "CLAUDE_MEM_BACKUP_ENABLED": "false",
  // 自动快照的间隔,单位小时,默认 24(每天一次) [新手:不动]
  "CLAUDE_MEM_BACKUP_INTERVAL_HOURS": "24",
  // 最多保留最近多少份快照,默认 7,更旧的会被清理 [新手:不动]
  "CLAUDE_MEM_BACKUP_RETAIN_COUNT": "7",
  // tool_uses(记录每次工具调用原始输入输出的备份表)保留天数 [新手:不动]
  "CLAUDE_MEM_TOOL_USES_RETENTION_DAYS": "0",
  // 按天滚动的日志文件保留天数,默认 30;0=永久保留 [新手:不动]
  "CLAUDE_MEM_LOG_RETENTION_DAYS": "30",

  // ===== 03 采集范围与过滤 =====
  // 管"哪些操作会被记下来":总开关、跳过哪些工具和命令、图片和子代理要不要记。
  // 不记录观察笔记(observation:对一次操作的摘要笔记)的工具名,逗号分隔,默认跳过 ListMcpResourcesTool、SlashCommand、Skill、TodoWrite、AskUserQuestion 这类低价值工具 [新手:不动]
  "CLAUDE_MEM_SKIP_TOOLS": "ListMcpResourcesTool,SlashCommand,Skill,TodoWrite,AskUserQuestion",
  // 一个正则表达式,命令行类工具(Bash/PowerShell/Codex exec_command)的命令匹配上就不记录 [新手:按需]
  "CLAUDE_MEM_SKIP_BASH_PATTERNS": "",
  // 设为 'true' 则跳过所有子代理(subagent,主 agent 派出去干活的小 agent)产生的观察笔记,默认 false 不跳过 [新手:按需]
  "CLAUDE_MEM_SKIP_SUBAGENT_OBSERVATIONS": "false",
  // 按子代理类型(agent_type)精确跳过,逗号分隔,默认空=不跳过;源码注释推荐的值是 workflow-subagent,用来去掉 Dynamic Workflows(动态工作流)大量并发子代理产生的噪音 [新手:按需]
  "CLAUDE_MEM_SKIP_AGENT_TYPES": "",
  // 默认 false [新手:不动]
  "CLAUDE_MEM_CAPTURE_ADVISOR_CALLS": "false",
  // 默认 true:Stop hook 会把这一轮产出的交付文件复制到 ~/.claude-mem/deliverables/<项目>/ 并记录,供“My Work”页面链接;设 false 则不再复制和记录,但已在里面的文件保留 [新手:不动]
  "CLAUDE_MEM_DELIVERABLES_ENABLED": "true",
  // 记忆采集总开关 [新手:不动]
  "CLAUDE_MEM_OBSERVER_ENABLED": "true",
  // 是否保存工具调用中出现的图片 [新手:按需]
  "CLAUDE_MEM_MEDIA_CAPTURE_ENABLED": "true",
  // 是否把图片发给“观察者模型”(生成观察笔记的大模型)去理解 [新手:不动]
  "CLAUDE_MEM_MEDIA_INFERENCE_ENABLED": "false",
  // 模式配置名,决定观察笔记的提示词和分类;值对应插件目录里的 plugin/modes/<mode>.json,也可用 ~/.claude-mem/modes/ 下的自定义覆盖(--<name> 形式) [新手:建议改]
  "CLAUDE_MEM_MODE": "code",
  // 默认 false:用户的提示词不单独调一次观察者模型,而是随下一次工具事件那次调用一起带上,省模型调用 [新手:不动]
  "CLAUDE_MEM_OBSERVE_BARE_PROMPTS": "false",

  // ===== 04 项目归属与会话来源 =====
  // 管"这条记忆算哪个项目、来自哪个客户端":项目名怎么算、哪些目录不记、从哪里读会话记录。和 OpenCode、DSH 共用记忆直接相关。
  // 默认 true:agent 读/搜索本地记忆文件(如 MEMORY.md)时,hook 会顺带从 claude-mem 数据库查相关观察笔记作为补充(仅限 worker 运行时、只返回索引字段) [新手:不动]
  "CLAUDE_MEM_MEMORY_SEARCH_HOOK_ENABLED": "true",
  // 默认 true:会话开始注入上下文时,附带一段“如何使用 claude-mem 记忆”的说明文字 [新手:不动]
  "CLAUDE_MEM_MEMORY_INSTRUCTIONS_ENABLED": "true",
  // 显式配置要导入为记忆的文件夹,JSON 数组 [{path, project, platformSource?}],最多 8 项;path 须为绝对路径或 ~/ 开头,project 是这些文件归属的项目名(决定“记忆算哪个项目”)…… [新手:保持为空]
  "CLAUDE_MEM_MEMORY_WATCH_ROOTS": "",
  // 是否启用 transcript(会话记录文件)监视器:worker 通过读取各客户端写在磁盘上的会话记录来采集记忆 [新手:不动]
  "CLAUDE_MEM_TRANSCRIPTS_ENABLED": "true",
  // 监视器配置文件路径,默认 <数据目录>/transcript-watch.json;文件里列出要监视哪些客户端的会话记录目录(每项 watch 的 name 经归一化后就是该条记忆的“来源客户端”,如 dsh、codex) [新手:装完核对]
  "CLAUDE_MEM_TRANSCRIPTS_CONFIG_PATH": "/Users/melodycchen/.claude-mem/transcript-watch.json",
  // 默认 false [新手:不动]
  "CLAUDE_MEM_CODEX_TRANSCRIPT_INGESTION": "false",
  // 默认 false [新手:不动]
  "CLAUDE_MEM_CODEX_SUBAGENT_INGESTION": "false",
  // 不记录的项目路径,逗号分隔的 glob 通配模式(支持 * ** ? 和开头的 ~;同时匹配完整路径和文件夹名) [新手:按需]
  "CLAUDE_MEM_EXCLUDED_PROJECTS": "",
  // 把多个目录归并成同一个“项目”的规则,JSON 数组 [{name, patterns, inherit?}]:目录(路径经 glob 匹配,也会尝试 realpath)命中某环境的 patterns 就用 name 作项目名…… [新手:按需]
  "CLAUDE_MEM_PROJECT_ENVIRONMENTS": "[]",
  // 决定“这条记忆算哪个项目”的命名方式 [新手:按需]
  "CLAUDE_MEM_PROJECT_NAME_SOURCE": "path",

  // ===== 05 观察者:选谁来写笔记 =====
  // 管"记账员"是谁:选哪家提供方、默认模型、额度用完退到谁、按复杂度分流到哪个模型。
  // provider=claude(用 Claude 作观察者)时,给每次工具调用写笔记的模型 [新手:不动]
  "CLAUDE_MEM_MODEL": "haiku",
  // 选择 observer(观察者,给每次工具调用写笔记的模型)走哪家 provider(提供方,即调用哪家接口) [新手:建议改]
  "CLAUDE_MEM_PROVIDER": "claude",
  // 按"来源客户端"分别指定 provider:值是一个 JSON 字符串,如 {"codex":"codex","claude":"claude"},键是会话来源(客户端)名…… [新手:不动]
  "CLAUDE_MEM_PROVIDER_BY_SOURCE": "",
  // "备用观察者":当所选 provider 暂时无法服务(额度用完、限流/过载重试后仍失败、宕机、连续回复不可用)时,观察者的活儿转给谁 [新手:按需]
  "CLAUDE_MEM_QUOTA_FALLBACK_PROVIDER": "claude",
  // 当备用 provider 是 Claude 时,备用那次运行用哪个 Claude 模型;留空=沿用 CLAUDE_MEM_MODEL 与分级路由 [新手:不动]
  "CLAUDE_MEM_QUOTA_FALLBACK_MODEL": "",
  // "订阅额度防护"的一部分:主 Claude 凭据因额度被暂停时,换用哪种 Claude 凭据继续 [新手:不动]
  "CLAUDE_MEM_QUOTA_FALLBACK_AUTH_METHOD": "",
  // "订阅额度防护":Claude 订阅的 5 小时用量窗口,用到这个比例(0~1 的小数,0.95=95%)就停止后台写笔记,免得挤占你正在交互的 Claude 额度 [新手:不动]
  "CLAUDE_MEM_QUOTA_THRESHOLD_FIVE_HOUR": "0.95",
  // "订阅额度防护":Claude 订阅的 7 天(周)用量窗口阈值,0~1 小数,0.93=93%,到了就暂停后台观察 [新手:不动]
  "CLAUDE_MEM_QUOTA_THRESHOLD_SEVEN_DAY": "0.93",
  // "订阅额度防护":Claude 订阅里 Opus 模型的周用量窗口阈值,0~1 小数 [新手:不动]
  "CLAUDE_MEM_QUOTA_THRESHOLD_SEVEN_DAY_OPUS": "0.93",
  // "订阅额度防护":Claude 订阅里 Sonnet 模型的周用量窗口阈值,0~1 小数 [新手:不动]
  "CLAUDE_MEM_QUOTA_THRESHOLD_SEVEN_DAY_SONNET": "0.92",
  // "订阅额度防护":Claude 订阅超出套餐后进入"超额(overage)"计费时的用量阈值,0~1 小数 [新手:不动]
  "CLAUDE_MEM_QUOTA_THRESHOLD_OVERAGE": "0.95",
  // "按复杂度分流模型"总开关:true 时,若队列里的事件都是简单类工具调用,就改用 TIER_SIMPLE_MODEL;含"总结"任务时用 TIER_SUMMARY_MODEL(非空才生效);其余用默认模型 [新手:不动]
  "CLAUDE_MEM_TIER_ROUTING_ENABLED": "true",
  // 分流用:全是简单工具调用时改用的 Claude 模型,默认 haiku(可移植别名,在直连 API、Bedrock、Vertex、Azure 都能用) [新手:不动]
  "CLAUDE_MEM_TIER_SIMPLE_MODEL": "haiku",
  // 分流用:会话总结类任务用的模型 [新手:不动]
  "CLAUDE_MEM_TIER_SUMMARY_MODEL": "",
  // "$TIER:fast"这个别名解析到的实际模型,默认 haiku [新手:不动]
  "CLAUDE_MEM_TIER_FAST_MODEL": "haiku",
  // "$TIER:smart"这个别名解析到的实际模型,默认 sonnet [新手:不动]
  "CLAUDE_MEM_TIER_SMART_MODEL": "sonnet",

  // ===== 06 提供方:Claude =====
  // provider=claude 时用到的设置。
  // provider=claude 时,同一上下文中排队的多个工具调用事件,合并进一次观察者提示词里发送的数量(1~32) [新手:不动]
  "CLAUDE_MEM_CLAUDE_OBSERVATION_BATCH_SIZE": "1",
  // Claude provider 的认证方式:subscription(用已登录的 Claude Code 订阅,默认)、api-key(用 Anthropic API Key)、gateway(走自定义网关)…… [新手:不动]
  "CLAUDE_MEM_CLAUDE_AUTH_METHOD": "subscription",
  // Claude Code 命令行可执行文件的路径 [新手:不动]
  "CLAUDE_CODE_PATH": "",
  // 仅为 claude-mem 覆盖 Claude 的配置目录(CLAUDE_CONFIG_DIR),用于读取钥匙串里的 Claude 凭据和启动 SDK 子进程 [新手:不动]
  "CLAUDE_MEM_CLAUDE_CONFIG_DIR": "",
  // 只给观察者的 Claude 子进程指定一个单独的配置目录,用来把观察者产生的对话记录(transcript)挪出 ~/.claude/projects;凭据仍用默认配置 [新手:不动]
  "CLAUDE_MEM_OBSERVER_CLAUDE_CONFIG_DIR": "",
  // 同时运行的 Claude SDK 代理子进程上限,默认 2 [新手:不动]
  "CLAUDE_MEM_MAX_CONCURRENT_AGENTS": "2",

  // ===== 07 提供方:Codex =====
  // provider=codex 时用到的设置。
  // provider=codex 时使用的 Codex 模型 [新手:不动]
  "CLAUDE_MEM_CODEX_MODEL": "",
  // Codex 命令行可执行文件名或路径,默认 codex(走 PATH 查找) [新手:不动]
  "CLAUDE_MEM_CODEX_PATH": "codex",
  // Codex 的推理强度,合法值:none/minimal/low/medium/high/xhigh/max/ultra,留空=用 Codex 默认 [新手:不动]
  "CLAUDE_MEM_CODEX_REASONING_EFFORT": "low",
  // Codex 并行处理请求的 app-server 客户端数量,范围 1~8,默认 2 [新手:不动]
  "CLAUDE_MEM_CODEX_MAX_CONCURRENT_AGENTS": "2",
  // Codex 一次请求最多合并的排队观察事件数,范围 1~32,默认 8 [新手:不动]
  "CLAUDE_MEM_CODEX_OBSERVATION_BATCH_SIZE": "8",
  // Codex 一次合并请求的字符预算,范围 4000~128000,默认 32000 [新手:不动]
  "CLAUDE_MEM_CODEX_OBSERVATION_BATCH_MAX_CHARS": "32000",

  // ===== 08 提供方:Gemini =====
  // provider=gemini 时用到的设置。
  // provider=gemini 时的 Google Gemini API Key [新手:保持为空]
  "CLAUDE_MEM_GEMINI_API_KEY": "",
  // 额外的 Gemini Key 列表(换行、逗号或空格分隔),某个 Key 限流/额度用尽/认证失败时轮换到下一个 [新手:保持为空]
  "CLAUDE_MEM_GEMINI_API_KEYS": "",
  // provider=gemini 时用的模型,默认 gemini-flash-latest(Google 维护的别名,始终指向当前 Flash 型号) [新手:不动]
  "CLAUDE_MEM_GEMINI_MODEL": "gemini-flash-latest",
  // 是否对 Gemini 请求做客户端限速(防止免费档被限流) [新手:不动]
  "CLAUDE_MEM_GEMINI_RATE_LIMITING_ENABLED": "true",

  // ===== 09 提供方:OpenRouter(可接自定义地址) =====
  // provider=openrouter 时用到的设置。它允许自定义 BASE_URL,是接 codebuddy 的主要路线。
  // provider=openrouter 时发给接口的 API Key,以 Authorization: Bearer 带出 [新手:按需]
  "CLAUDE_MEM_OPENROUTER_API_KEY": "",
  // 额外的 OpenRouter Key 列表(换行/逗号分隔),某个 Key 限流、额度用尽或被拒时轮换 [新手:保持为空]
  "CLAUDE_MEM_OPENROUTER_API_KEYS": "",
  // openrouter 路线使用的模型 ID,原样传给接口 [新手:装完核对]
  "CLAUDE_MEM_OPENROUTER_MODEL": "cohere/north-mini-code:free",
  // openrouter 路线的接口地址,允许自定义(openai-compatible 路线另有自己的 BASE_URL) [新手:装完核对]
  "CLAUDE_MEM_OPENROUTER_BASE_URL": "",
  // 温度(控制回答随机性的参数),取 0~2 的数字时才会作为 temperature 合并进请求体;留空或超出范围=不发送,由接口用自己的默认值 [新手:不动]
  "CLAUDE_MEM_OPENROUTER_TEMPERATURE": "",
  // OpenRouter 归因用的站点地址,作为 HTTP-Referer 请求头发出 [新手:不动]
  "CLAUDE_MEM_OPENROUTER_SITE_URL": "",
  // OpenRouter 归因用的应用名,作为 X-OpenRouter-Title 请求头发出,仅作显示名,默认 claude-mem;设为空则回退成 Claude-Mem [新手:不动]
  "CLAUDE_MEM_OPENROUTER_APP_NAME": "claude-mem",
  // 以 JSON 对象形式给请求体追加厂商特有字段,例如 {"reasoning":{"enabled":false}} [新手:不动]
  "CLAUDE_MEM_OPENROUTER_EXTRA_BODY": "",
  // openrouter 路线的"推理强度"(让模型先思考多少),可选 none/minimal/low/medium/high [新手:不动]
  "CLAUDE_MEM_OPENROUTER_REASONING_EFFORT": "",

  // ===== 10 提供方:OpenAI 兼容 =====
  // provider=openai-compatible 时用到的设置,独立于 OpenRouter,不共用 key。
  // openai-compatible 路线的"预设端点"名,用来自动填默认地址和默认模型 [新手:保持为空]
  "CLAUDE_MEM_OPENAI_COMPAT_PRESET": "",
  // openai-compatible 路线的 API Key,以 Authorization: Bearer 发出 [新手:装完核对]
  "CLAUDE_MEM_OPENAI_COMPAT_API_KEY": "",
  // openai-compatible 路线额外的 Key 列表(换行/逗号分隔),用于限流或失效时轮换 [新手:保持为空]
  "CLAUDE_MEM_OPENAI_COMPAT_API_KEYS": "",
  // openai-compatible 路线的接口地址,同样自动补 /chat/completions [新手:装完核对]
  "CLAUDE_MEM_OPENAI_COMPAT_BASE_URL": "",
  // openai-compatible 路线使用的模型 ID,原样传给接口 [新手:装完核对]
  "CLAUDE_MEM_OPENAI_COMPAT_MODEL": "",
  // 是否让模型"先思考再回答"(reasoning) [新手:不动]
  "CLAUDE_MEM_OPENAI_COMPAT_REASONING": "",
  // openai-compatible 路线下,同上下文的排队事件合并进一次观察者提示词的数量(1~32),默认 1=每个事件单独发,需要时才开启 [新手:不动]
  "CLAUDE_MEM_OPENAI_COMPAT_OBSERVATION_BATCH_SIZE": "1",

  // ===== 11 观察者请求行为 =====
  // 管发给观察者模型的每次请求:等多久、能说多长、一段对话多大就换新的。
  // 一段观察者对话允许累积的字符数,超过就废弃重开新一段(新一段会带上本会话已有的笔记摘要) [新手:不动]
  "CLAUDE_MEM_OBSERVER_MAX_CONVERSATION_CHARS": "400000",
  // Claude 观察者发送的 thinking 参数(是否让模型先思考):disabled(默认,省 token)、adaptive(由模型决定)、enabled 或 enabled:预算、omit…… [新手:不动]
  "CLAUDE_MEM_OBSERVER_THINKING": "disabled",
  // 观察者模型的上下文窗口大小,单位 token(token=模型计费和上下文的计量单位) [新手:装完核对]
  "CLAUDE_MEM_OBSERVER_CONTEXT_WINDOW": "",
  // 每个 HTTP 观察者请求允许模型输出的最大 token 数(max_tokens / max_completion_tokens;Gemini 为 maxOutputTokens),默认 4096,范围 256~1000000 [新手:按需]
  "CLAUDE_MEM_OBSERVER_MAX_OUTPUT_TOKENS": "4096",
  // 每次非流式观察者请求的超时(毫秒,500~300000),默认 180000=3 分钟,用来拦截卡死的请求 [新手:不动]
  "CLAUDE_MEM_LLM_TIMEOUT_MS": "180000",
  // 压缩"过长字段"(某次工具结果太大时先交给模型浓缩)那一步的超时,毫秒,默认 180000 [新手:不动]
  "CLAUDE_MEM_FIELD_OPTIMIZE_TIMEOUT_MS": "180000",
  // 流式请求的"空闲窗口"(毫秒,500~300000),默认 90000:连续这么久既没收到 token 也没收到保活信号,就放弃该请求 [新手:按需]
  "CLAUDE_MEM_LLM_STREAM_IDLE_TIMEOUT_MS": "90000",

  // ===== 12 隐私与脱敏 =====
  // 存之前把密钥、口令之类敏感内容替换掉。
  // 总开关,默认 false(关) [新手:建议改]
  "CLAUDE_MEM_REDACT_ENABLED": "false",
  // 逗号分隔的规则名清单,列在里面的内置规则会被关掉、其余照常生效,例如 "jwt,slack_token" [新手:不动]
  "CLAUDE_MEM_REDACT_DISABLED_BUILTINS": "",
  // 自定义脱敏规则:JSON 数组,每项形如 {"name":"规则名","regex":"正则"};它们排在内置规则之前先跑,匹配到的内容同样被替换成 <redacted type='name'/> [新手:按需]
  "CLAUDE_MEM_REDACT_CUSTOM_PATTERNS": "[]",
  // 为 true 时,每次脱敏扫描命中后在调试日志里写一行“规则名,命中次数”,只记次数,不记被替换的原文 [新手:不动]
  "CLAUDE_MEM_REDACT_LOG_MATCHES": "false",
  // 默认 false [新手:按需]
  "CLAUDE_MEM_REDACT_GENERIC_ENABLED": "false",

  // ===== 13 会话开始时注入什么 =====
  // 新开一个会话时,往上下文里塞哪些旧记忆、塞多少、长什么样。
  // 新会话开始时最多注入多少条“观察”(observation=claude-mem 自动记下的一条工作笔记) [新手:按需]
  "CLAUDE_MEM_CONTEXT_OBSERVATIONS": "50",
  // “来源”指记忆是由哪个工具写入的…… [新手:建议改]
  "CLAUDE_MEM_SESSION_START_INCLUDE_ALL_SOURCES": "false",
  // 决定会话开始时读哪些“项目”的记忆 [新手:按需]
  "CLAUDE_MEM_CONTEXT_PROJECTS": "current",
  // 为 true 时,在注入的每条观察后面显示读它大约要多少 token(模型的计费/长度单位,~Nt) [新手:不动]
  "CLAUDE_MEM_CONTEXT_SHOW_READ_TOKENS": "false",
  // 为 true 时,每条观察后显示当初产生这条记忆所花的“工作量”token 数(研究、构建、决策花掉的) [新手:不动]
  "CLAUDE_MEM_CONTEXT_SHOW_WORK_TOKENS": "false",
  // 为 true 时,在注入的统计行里显示“复用记忆省了多少 token”的绝对数 [新手:不动]
  "CLAUDE_MEM_CONTEXT_SHOW_SAVINGS_AMOUNT": "false",
  // 为 true 时,统计行里显示“复用记忆省了百分之几” [新手:不动]
  "CLAUDE_MEM_CONTEXT_SHOW_SAVINGS_PERCENT": "true",
  // 逗号分隔的观察类型白名单(如 bugfix,decision,discovery),只注入这些类型 [新手:不动]
  "CLAUDE_MEM_CONTEXT_OBSERVATION_TYPES": "",
  // 逗号分隔的“概念”标签白名单(如 how-it-works,gotcha),只注入带这些概念的观察 [新手:不动]
  "CLAUDE_MEM_CONTEXT_OBSERVATION_CONCEPTS": "",
  // 最近的前 N 条观察除了标题,还会展开显示详细字段(由 CONTEXT_FULL_FIELD 决定是 narrative 还是 facts) [新手:按需]
  "CLAUDE_MEM_CONTEXT_FULL_COUNT": "0",
  // 展开详细内容时用哪个字段:narrative=叙述性长文,facts=要点列表 [新手:不动]
  "CLAUDE_MEM_CONTEXT_FULL_FIELD": "narrative",
  // 注入时显示最近多少次“会话总结”(每个会话结束时生成的小结) [新手:按需]
  "CLAUDE_MEM_CONTEXT_SESSION_COUNT": "10",
  // 为 true 时,把最近一次会话的总结(请求/调查/学到/完成/下一步)放进注入内容 [新手:不动]
  "CLAUDE_MEM_CONTEXT_SHOW_LAST_SUMMARY": "true",
  // 为 true 时,把上一个会话里助手最后一条回复(从对话记录文件里读)也注入进来;会排除当前会话 [新手:不动]
  "CLAUDE_MEM_CONTEXT_SHOW_LAST_MESSAGE": "false",
  // 默认 true:注入时不带子代理(subagent,主会话派出去干活的小代理)产生的观察,避免它们的流水账把主会话的长期记忆挤出窗口 [新手:不动]
  "CLAUDE_MEM_CONTEXT_MAIN_AGENT_ONLY": "true",
  // 实验性排序权重(ACT-R 记忆模型) [新手:不动]
  "CLAUDE_MEM_REINFORCE_ALPHA": "0",
  // 默认 true:会话开始时,除了把上下文给模型,还把一份预览作为 systemMessage 显示给用户看(终端里能看到注入了什么) [新手:不动]
  "CLAUDE_MEM_CONTEXT_SHOW_TERMINAL_OUTPUT": "true",
  // 默认 true:当某个项目一条观察都还没有时,会话开始会注入一段“claude-mem status”欢迎提示(说明这个项目还没有记忆、第一条记忆落库后提示就消失) [新手:不动]
  "CLAUDE_MEM_WELCOME_HINT_ENABLED": "true",
  // 默认 true [新手:不动]
  "CLAUDE_MEM_WORK_STATE_ENABLED": "true",
  // 默认 true:仅对 Claude Code,当某代码文件(≥32KB)有观察历史时,拦下“整文件 Read”,引导改用 smart_outline/smart_unfold/get_observations…… [新手:不动]
  "CLAUDE_MEM_FILE_READ_GATE_ENABLED": "true",

  // ===== 14 每次提问时的语义注入与文件夹说明 =====
  // 除了会话开始,还能在每次提问时按意思注入相关旧记忆;也能把记忆写进各文件夹的说明文件。
  // 默认 false [新手:不动]
  "CLAUDE_MEM_FOLDER_CLAUDEMD_ENABLED": "false",
  // 为 true 时,上面那些文件夹说明改写到 CLAUDE.local.md(通常不入 git),而不是 CLAUDE.md [新手:不动]
  "CLAUDE_MEM_FOLDER_USE_LOCAL_MD": "false",
  // JSON 数组,里面的文件夹路径不会生成文件夹说明文件(整个文件夹排除) [新手:不动]
  "CLAUDE_MEM_FOLDER_MD_EXCLUDE": "[]",
  // JSON 数组,元素是 glob 通配符 [新手:不动]
  "CLAUDE_MEM_FOLDER_MD_SKELETON_DENYLIST": "[]",
  // 实验性,默认 false [新手:按需]
  "CLAUDE_MEM_SEMANTIC_INJECT": "false",
  // 每次提问最多注入多少条匹配的观察 [新手:不动]
  "CLAUDE_MEM_SEMANTIC_INJECT_LIMIT": "5",
  // narrative=每条匹配注入标题+完整叙述(默认,模型无需再调用工具即可读到内容);index=每条只注入 id+标题+副标题,模型需要再调用 get_observations 才能展开(省 token,但没展开的只剩标题) [新手:不动]
  "CLAUDE_MEM_SEMANTIC_INJECT_FORMAT": "narrative",

  // ===== 15 向量与检索(Chroma、嵌入模型) =====
  // 管"按意思找"的那一套:Chroma 怎么连、用哪个嵌入模型、搜多久以内的记忆。中文召回的关键在这一组。
  // Chroma 是专门存“向量”的数据库(向量嵌入=把文字变成一串数字,以便按意思找) [新手:不动]
  "CLAUDE_MEM_CHROMA_ENABLED": "true",
  // local(默认):由 worker 通过 uvx 在本机拉起一个持久化的 chroma-mcp 子进程,数据存在数据目录下的 chroma 文件夹,写入串行执行;remote:不自己起,改连一个已经存在的 Chroma 服务…… [新手:不动]
  "CLAUDE_MEM_CHROMA_MODE": "local",
  // 仅 CHROMA_MODE=remote 时使用:远程 Chroma 服务的主机地址 [新手:不动]
  "CLAUDE_MEM_CHROMA_HOST": "127.0.0.1",
  // 仅 remote 模式使用:远程 Chroma 服务的端口 [新手:不动]
  "CLAUDE_MEM_CHROMA_PORT": "8000",
  // 仅 remote 模式使用:连远程 Chroma 是否走 HTTPS [新手:不动]
  "CLAUDE_MEM_CHROMA_SSL": "false",
  // 仅 remote 模式使用:连远程 Chroma 的访问密钥,非空才会传给 chroma-mcp [新手:保持为空]
  "CLAUDE_MEM_CHROMA_API_KEY": "",
  // 仅 remote 模式使用:Chroma 的租户名(tenant,多租户部署里的命名空间) [新手:不动]
  "CLAUDE_MEM_CHROMA_TENANT": "default_tenant",
  // 仅 remote 模式使用:Chroma 里的数据库名 [新手:不动]
  "CLAUDE_MEM_CHROMA_DATABASE": "default_database",
  // 预热超时(毫秒) [新手:不动]
  "CLAUDE_MEM_CHROMA_PREWARM_TIMEOUT_MS": "120000",
  // 单次向 Chroma 写入/建索引的超时(毫秒) [新手:不动]
  "CLAUDE_MEM_CHROMA_MUTATION_TIMEOUT_MS": "600000",
  // 等待写入 Chroma 的队列上限,默认 5000 [新手:不动]
  "CLAUDE_MEM_CHROMA_MAX_PENDING_MUTATIONS": "5000",
  // 新建 Chroma 集合时使用的“嵌入函数”(把文字变成数字的方法) [新手:不动]
  "CLAUDE_MEM_CHROMA_EMBEDDING_FUNCTION": "default",
  // 仅“服务器模式”(runtime=server,Postgres+pgvector)读取,本机默认的 worker 模式不读 [新手:不动]
  "CLAUDE_MEM_SERVER_VECTOR_SEARCH": "auto",
  // 仅服务器模式:服务启动发现有观察还没有当前模型的向量时,会在后台补算(可能耗数小时),本项限制这次补算最多用几个 CPU 线程,直到下次重启 [新手:不动]
  "CLAUDE_MEM_EMBEDDING_BACKFILL_THREADS": "",
  // 仅服务器模式(Postgres+pgvector)的“按意思搜索”使用的嵌入模型,必须是 src/services/vector/models.ts 里的 4 个之一…… [新手:不动]
  "CLAUDE_MEM_EMBEDDING_MODEL": "all-MiniLM-L6-v2",
  // uvx(Python 工具 uv 附带的启动器,用来启动 chroma-mcp)的可执行文件路径 [新手:按需]
  "CLAUDE_MEM_CHROMA_UVX_PATH": "",
  // 不带日期的语义搜索只返回最近 N 天内的匹配,默认 90 [新手:建议改]
  "CLAUDE_MEM_SEARCH_RECENCY_DAYS": "90",

  // ===== 16 去重 =====
  // 把重复的笔记合并或标出来。默认关闭。
  // 去重总开关,默认 false;关闭时行为与旧版完全一致 [新手:不动]
  "CLAUDE_MEM_DEDUP_ENABLED": "false",
  // 判定“相似候选”的最低余弦相似度(按标题词的 IDF 加权,0~1,越高越严格) [新手:不动]
  "CLAUDE_MEM_DEDUP_COSINE_THRESHOLD": "0.80",
  // 否决规则:如果标题里有某个词在该项目里只出现在 ≤N 条记录中(罕见词,说明它能区分事物,如 rdlp-api 与 rdlp-plugin),就否决合并 [新手:不动]
  "CLAUDE_MEM_DEDUP_IDF_VETO_DF": "10",
  // 两条标题至少共享多少个词才会进入相似度计算,默认 2;源码注释:用来滤掉稀疏向量带来的噪声 [新手:不动]
  "CLAUDE_MEM_DEDUP_MIN_SHARED_TOKENS": "2",
  // 冷启动门槛:一个项目的记录少于 N 条时跳过第 1 层相似度判断,因为词频统计(IDF)在记录太少时不可靠 [新手:不动]
  "CLAUDE_MEM_DEDUP_MIN_PROJECT_DOCS": "10",
  // 每插入一条新观察时,最多拿它跟同项目多少条最近标题比较,默认 2000;触顶会写调试日志,更早的行由 dedup-scan 覆盖 [新手:不动]
  "CLAUDE_MEM_DEDUP_MAX_SCAN": "2000",
  // dedup-scan(对已有历史数据做全量去重扫描)遇到记录数超过此值的项目就跳过,出于内存安全 [新手:不动]
  "CLAUDE_MEM_DEDUP_MAX_BACKFILL_ROWS": "50000",

  // ===== 17 云同步、团队与账号 =====
  // 登录 cmem.ai 之后才会用到的设置;不登录就全部保持为空。隐私核对重点看这一组。
  // 云同步(把笔记同步到 cmem.ai 的服务器)的登录令牌,相当于密码;由安装器在浏览器登录 cmem.ai 后写入 [新手:保持为空]
  "CLAUDE_MEM_CLOUD_SYNC_TOKEN": "",
  // 云同步的账号 ID,由安装器登录 cmem.ai 后写入,同步时随请求一起带给服务器标识“是谁的数据”;TeamBrain(团队共享)也复用它作为 X-User-Id [新手:保持为空]
  "CLAUDE_MEM_CLOUD_SYNC_USER_ID": "",
  // 云同步服务器(sync-hub)的网址,例如 https://sync.cmem.ai [新手:保持为空]
  "CLAUDE_MEM_CLOUD_SYNC_HUB_URL": "",
  // 本机在云同步里的设备编号 [新手:不动]
  "CLAUDE_MEM_CLOUD_SYNC_DEVICE_ID": "",
  // 本机在 cmem.ai“设备”面板里显示的名字,默认取本机主机名(hostname),所以你会看到默认值是电脑名 [新手:不动]
  "CLAUDE_MEM_CLOUD_SYNC_DEVICE_NAME": "melodycchens-MacBook-Pro.local",
  // 云同步的“实时通知”开关(WebSocket=保持一条长连接,服务器有新数据时立刻通知) [新手:不动]
  "CLAUDE_MEM_CLOUD_SYNC_WS": "true",
  // 云同步的“空闲时是否继续拉取”开关 [新手:不动]
  "CLAUDE_MEM_CLOUD_SYNC_KEEP_PULLING": "false",
  // 云同步每批推送的内容条数,默认 40 [新手:不动]
  "CLAUDE_MEM_CLOUD_SYNC_CONTENT_BATCH_SIZE": "40",
  // 云同步推送内容时单次请求的超时时间,单位毫秒,默认 90000(90 秒),与服务器端的处理租约时长保持一致 [新手:不动]
  "CLAUDE_MEM_CLOUD_SYNC_REQUEST_TIMEOUT_MS": "90000",
  // TeamBrain(团队大脑:把你的会话信息共享给团队、并在会话开头读到队友在做什么)的服务器网址,例如 https://cmem.ai [新手:保持为空]
  "CLAUDE_MEM_TEAMBRAIN_URL": "",
  // 你这台电脑加入的 TeamBrain 团队 ID,由 `teambrain join` 命令写入;teambrain 的 share/leave 命令默认使用它 [新手:保持为空]
  "CLAUDE_MEM_TEAMBRAIN_TEAM_ID": "",
  // 登录流程的记录字段:安装器在浏览器登录 cmem.ai(试用)时,把登录链接发到的邮箱记在这里,作为“别再重复打扰”的标记 [新手:不动]
  "CLAUDE_MEM_PRO_TRIAL_EMAIL": "",
  // 登录流程的记录字段:最近一次发送登录链接的时间(ISO 时间戳) [新手:不动]
  "CLAUDE_MEM_PRO_TRIAL_AT": "",
  // 试用状态记录:'link_sent'=登录已开始但凭证还没领取,'active'=已完成 [新手:不动]
  "CLAUDE_MEM_PRO_TRIAL_STATE": "",
  // 免费试用的到期日(ISO 日期),由安装器从 cmem.ai 的返回结果里写入 [新手:不动]
  "CLAUDE_MEM_PRO_TRIAL_ENDS_AT": "",
  // 安装时的可选“留邮箱”记录:交互式安装中如果你主动填了邮箱,才会写入这里并提交到 cmem.ai 的候补名单;直接回车跳过则为空 [新手:不动]
  "CLAUDE_MEM_ONLINE_SIGNUP_EMAIL": "",
  // 安装时留邮箱时附带的那句“希望我们怎么帮你”备注,与 ONLINE_SIGNUP_EMAIL 一起由安装器写入;没填就是空 [新手:不动]
  "CLAUDE_MEM_ONLINE_SIGNUP_NOTE": "",
  // 留邮箱那一刻的时间(ISO 时间戳),由安装器写入;没留邮箱就是空 [新手:不动]
  "CLAUDE_MEM_ONLINE_SIGNUP_AT": "",
  // 邮箱是否已成功提交到候补名单:'true'=已提交,'false'=没发出去,下次安装时会静默重试一次 [新手:不动]
  "CLAUDE_MEM_ONLINE_SIGNUP_SENT": "",
  // 登录流程的记录字段:cmem.ai 在登录完成时返回的套餐类型('trial' 试用 / 'pro' 付费 / 'none' 无;TeamBrain 席位会写 'teambrain_seat') [新手:不动]
  "CLAUDE_MEM_PRO_PLAN": "",
  // “降级”记录:cmem 网关(cmem.ai 提供的记忆生成服务)彻底拒绝了你的密钥后,worker 会写入当时的时间,并改回用 Anthropic 套餐来生成记忆;空=没发生过降级 [新手:不动]
  "CLAUDE_MEM_PRO_FALLBACK_AT": "",
  // 降级记录:网关被拒绝时给出的提示文字,会显示在会话上下文的提示里;空=使用通用提示 [新手:不动]
  "CLAUDE_MEM_PRO_FALLBACK_MESSAGE": "",
  // 降级记录:网关给出的“该怎么办”说明,由 worker 在降级时写入,仅用于提示显示 [新手:不动]
  "CLAUDE_MEM_PRO_FALLBACK_ACTION": "",
  // 降级记录:网关给出的处理链接(空=默认指向 cmem.ai/pro 续费页),由 worker 在降级时写入,仅用于提示显示 [新手:不动]
  "CLAUDE_MEM_PRO_FALLBACK_URL": "",
  // 浏览器配对后暂存的“记忆密钥”(cmem.ai 网关的 API 密钥),在你选定记忆生成方(provider)之前先放在这里;一旦被采用,会被搬到 OPENROUTER_API_KEY 并把本键清空 [新手:保持为空]
  "CLAUDE_MEM_PRO_MEMORY_KEY": "",
  // 与 PRO_MEMORY_KEY 配对的网关地址,由 cmem.ai 下发;空时回退为 cmem 官方推理网关地址(/api/inference/v1) [新手:保持为空]
  "CLAUDE_MEM_PRO_MEMORY_BASE_URL": "",
  // 与 PRO_MEMORY_KEY 配对的模型名,由 cmem.ai 下发;空时回退为 'cmem-observer' [新手:保持为空]
  "CLAUDE_MEM_PRO_MEMORY_MODEL": "",

  // ===== 18 服务器模式与队列 =====
  // runtime=server 时用的 Postgres 服务器、鉴权和任务队列。本机默认 worker 模式基本用不到。
  // 任务队列(队列=让任务排队依次处理)的引擎,只能是 'sqlite'(默认,存在本机数据库里)或 'bullmq'(需要 Redis 服务),填别的会报错 [新手:不动]
  "CLAUDE_MEM_QUEUE_ENGINE": "sqlite",
  // Redis(一种常用的内存数据库,BullMQ 队列要靠它)的完整连接地址,必须以 redis:// 或 rediss:// 开头 [新手:保持为空]
  "CLAUDE_MEM_REDIS_URL": "",
  // Redis 的主机地址,默认 127.0.0.1(本机) [新手:不动]
  "CLAUDE_MEM_REDIS_HOST": "127.0.0.1",
  // Redis 的端口,默认 6379,必须是 1–65535 的整数,否则报错 [新手:不动]
  "CLAUDE_MEM_REDIS_PORT": "6379",
  // Redis 的运行方式,只能是 external(用现成的外部 Redis,默认)、managed 或 docker [新手:不动]
  "CLAUDE_MEM_REDIS_MODE": "external",
  // 队列在 Redis 里所有键的名字前缀,用来区分同一个 Redis 上的不同安装;默认值里的数字是每台安装的端口派生值,非字母数字下划线连字符的字符会被替换成下划线 [新手:不动]
  "CLAUDE_MEM_QUEUE_REDIS_PREFIX": "claude_mem_37701",
  // 服务器接口的鉴权方式:'api-key'(默认,必须带 API 密钥)或 'local-dev'(本机开发时免密) [新手:不动]
  "CLAUDE_MEM_AUTH_MODE": "api-key",
  // 服务器运行时的网址,hook(钩子:Claude Code 触发的小程序)在服务器模式下用它找服务器;默认 http://127.0.0.1:37878(本机地址,端口按每次安装派生) [新手:不动]
  "CLAUDE_MEM_SERVER_URL": "http://127.0.0.1:37878",
  // hook 访问本机服务器用的 API 密钥,服务器模式安装时由安装器写入 [新手:不动]
  "CLAUDE_MEM_SERVER_API_KEY": "",
  // hook 在服务器模式下默认使用的 Postgres 项目 ID(服务器端用来区分项目的编号),由安装器写入;为空则回退到旧键 SERVER_BETA_PROJECT_ID [新手:不动]
  "CLAUDE_MEM_SERVER_PROJECT_ID": "",
  // 旧名字的兼容回退:SERVER_URL 为空时才会读它,让早期安装的 settings.json 继续有效 [新手:不动]
  "CLAUDE_MEM_SERVER_BETA_URL": "http://127.0.0.1:37878",
  // 旧名字的兼容回退:SERVER_API_KEY 为空时才会读它 [新手:不动]
  "CLAUDE_MEM_SERVER_BETA_API_KEY": "",
  // 旧名字的兼容回退:SERVER_PROJECT_ID 为空时才会读它 [新手:不动]
  "CLAUDE_MEM_SERVER_BETA_PROJECT_ID": "",

  // ===== 19 通知与外部集成 =====
  // Telegram 通知、Notion 导出、Grok Bot、CCS 对齐等可选外挂。默认基本都是空的或关的。
  // Telegram(聊天软件)通知的总开关,默认 'true',但这只是“允许”:没有填 BOT_TOKEN(机器人密钥)和 CHAT_ID(接收人)就不会发任何消息 [新手:不动]
  "CLAUDE_MEM_TELEGRAM_ENABLED": "true",
  // Telegram 机器人的密钥,属于 Telegram 外挂 [新手:保持为空]
  "CLAUDE_MEM_TELEGRAM_BOT_TOKEN": "",
  // Telegram 外挂:接收提醒的聊天/群 ID [新手:保持为空]
  "CLAUDE_MEM_TELEGRAM_CHAT_ID": "",
  // Telegram 外挂:“会话结束总结”通知的开关,默认 'true';但源码注释说明必须给项目配置了明确的路由(WRAPUP_ROUTES)才会发送,默认路由为空,所以实际不发 [新手:不动]
  "CLAUDE_MEM_TELEGRAM_WRAPUPS_ENABLED": "true",
  // Telegram 外挂:单条观察即时提醒的开关,默认 'false'(需主动开启) [新手:不动]
  "CLAUDE_MEM_TELEGRAM_OBSERVATION_ALERTS_ENABLED": "false",
  // Telegram 外挂:“项目 → Telegram 路由”的 JSON 对象,每个项目可配 chat_id,也可覆盖机器人密钥 [新手:保持为空]
  "CLAUDE_MEM_TELEGRAM_WRAPUP_ROUTES": "{}",
  // Telegram 外挂:哪些类型的观察会触发提醒,逗号分隔,默认 'security_alert,sensitive'(安全告警与敏感信息) [新手:不动]
  "CLAUDE_MEM_TELEGRAM_TRIGGER_TYPES": "security_alert,sensitive",
  // Telegram 外挂:按“概念标签”触发提醒的列表,逗号分隔,默认空 [新手:不动]
  "CLAUDE_MEM_TELEGRAM_TRIGGER_CONCEPTS": "",
  // Grok Bot 外挂(一个本地的 AI 助手产品)的“感知推送”总开关,默认 'false' [新手:不动]
  "CLAUDE_MEM_GROK_BOT_AWARENESS_ENABLED": "false",
  // Grok Bot 外挂:允许被写入的席位(agent)ID 白名单,逗号分隔 [新手:保持为空]
  "CLAUDE_MEM_GROK_BOT_AWARENESS_AGENT_IDS": "",
  // Grok Bot 外挂:哪些类型的观察算“值得感知”,默认 'decision,bugfix,security_alert,sensitive' [新手:不动]
  "CLAUDE_MEM_GROK_BOT_AWARENESS_TRIGGER_TYPES": "decision,bugfix,security_alert,sensitive",
  // Grok Bot 外挂:按概念标签筛选“值得感知”的观察,逗号分隔,默认空;与 TRIGGER_TYPES 一起被感知推送和 webhook 共用 [新手:不动]
  "CLAUDE_MEM_GROK_BOT_AWARENESS_TRIGGER_CONCEPTS": "",
  // Grok Bot 外挂的 webhook(往某个网址发通知):每条匹配感知条件的新观察会以 POST 发到这个网址,内容含观察 ID、类型、标题、副标题、项目名、概念标签 [新手:保持为空]
  "CLAUDE_MEM_GROK_BOT_WEBHOOK_URL": "",
  // Grok Bot webhook 的共享密钥:非空时会放在请求头 x-claude-mem-shared-secret 里发给接收方做校验 [新手:保持为空]
  "CLAUDE_MEM_GROK_BOT_WEBHOOK_SECRET": "",
  // Notion 导出外挂开关:开启后每条新观察会写入你的 Notion 数据库(调用 api.notion.com) [新手:不动]
  "CLAUDE_MEM_NOTION_ENABLED": "false",
  // Notion 导出外挂:Notion 集成的访问令牌 [新手:保持为空]
  "CLAUDE_MEM_NOTION_TOKEN": "",
  // Notion 导出外挂:要写入的 Notion 数据库 ID [新手:保持为空]
  "CLAUDE_MEM_NOTION_DATABASE_ID": "",
  // Notion 导出外挂:是否自动在你的数据库里补建缺少的列(属性) [新手:不动]
  "CLAUDE_MEM_NOTION_AUTO_CREATE_PROPERTIES": "true",
  // Grok Bot 外挂的“实时记忆索引”开关,默认开:每有新观察,worker 会把一份索引写成本地文件 zz-claude-mem-inject.md 放到各 Grok Bot 席位的目录里 [新手:不动]
  "CLAUDE_MEM_GROK_BOT_INJECT_ENABLED": "true",
  // Grok Bot 外挂:要写索引的席位 ID [新手:不动]
  "CLAUDE_MEM_GROK_BOT_INJECT_AGENT_IDS": "*",
  // Grok Bot 外挂:索引每行前面加的标记类别,可选 episode(默认,加 [episode] )、plain(不加)、note(加 [note] ),填错会退回 episode [新手:不动]
  "CLAUDE_MEM_GROK_BOT_INJECT_TIER": "episode",
  // Grok Bot 外挂:索引里最多放多少条最近的观察,默认 80,上限 100,小于 1 或非数字会退回默认 [新手:不动]
  "CLAUDE_MEM_GROK_BOT_INJECT_WINDOW": "80",
  // Grok Bot 外挂:席位自己的项目观察不够条数时的补充策略,'house'(默认)=用所有项目的最新观察补满,'off'=不补 [新手:不动]
  "CLAUDE_MEM_GROK_BOT_INJECT_FALLBACK": "house",
  // Grok Bot 外挂:只取某个平台来源的观察写入索引,默认空 = 不过滤 [新手:不动]
  "CLAUDE_MEM_GROK_BOT_INJECT_PLATFORM_SOURCE": "",
  // Grok Bot 外挂:手动指定“席位 → 项目列表”,格式 '席位ID=项目甲,项目乙;另一席位ID=项目丙' [新手:不动]
  "CLAUDE_MEM_GROK_BOT_INJECT_PROJECTS_BY_AGENT": "",
  // Grok Bot 外挂:索引中每一行最多保留多少字符,默认 160,代码里最高封顶 480 [新手:不动]
  "CLAUDE_MEM_GROK_BOT_INJECT_MAX_LINE_CHARS": "160",
  // Grok Bot 外挂:新观察到来后等待多少毫秒再重写索引文件(合并短时间内的多次写入),默认 1500;负数或非数字会用默认值 [新手:不动]
  "CLAUDE_MEM_GROK_BOT_INJECT_DEBOUNCE_MS": "1500",
  // Grok Bot 外挂:想在每个索引文件里固定附带的一句话(长期提示),默认空 = 不加 [新手:不动]
  "CLAUDE_MEM_GROK_BOT_INJECT_STANDING_LINE": "",
  // CCS Align(与 Grok Bot 席位“规则对齐”的外挂)开关,默认 'true' [新手:不动]
  "CLAUDE_MEM_CCS_ALIGN_ENABLED": "true",
  // CCS Align 外挂:查看者/席位名单,逗号分隔,默认 'ccs-align' [新手:不动]
  "CLAUDE_MEM_CCS_ALIGN_VIEWER_IDS": "ccs-align",
  // CCS Align 外挂:哪些类型的观察会被放进本地缓存,默认 'decision,bugfix,security_alert,sensitive'(源码注释:复制自 Grok 的条件列表) [新手:不动]
  "CLAUDE_MEM_CCS_ALIGN_TRIGGER_TYPES": "decision,bugfix,security_alert,sensitive",
  // CCS Align 外挂:第二阶段规则巡检是否允许“自动修补影子副本”,默认 'false' = 只出报告不改文件(源码注释:这是个提示开关,不会悄悄执行) [新手:不动]
  "CLAUDE_MEM_CCS_ALIGN_PATCH_SHADOWS": "false",

  // ===== 20 My Work 视图 =====
  // 网页查看器里"我的工作"页的自动刷新与文案生成设置。
  // “我的工作”页是否自动后台刷新,默认 'true' [新手:按需]
  "CLAUDE_MEM_WORK_VIEW_AUTO_REFRESH": "true",
  // “我的工作”定时检查的间隔,单位分钟,默认 10,最小 1,1440=一天一次;每次检查只是只读查数据库,到期才启动 agent [新手:按需]
  "CLAUDE_MEM_WORK_VIEW_REFRESH_INTERVAL_MIN": "10",
  // 是否把“我的工作”的状态记录同步给云端/其他设备读取,默认 'false' [新手:不动]
  "CLAUDE_MEM_WORK_VIEW_SHARED_STATE": "false",
  // 生成“我的工作”文案所用的模型提供方:空=仅当 OpenRouter 是主提供方时才用它;openrouter/openai-compatible=明确指定;off=不生成文案 [新手:按需]
  "CLAUDE_MEM_WORK_VIEW_COPY_PROVIDER": "",
  // 生成“我的工作”文案时的模型覆盖项,空 = 用所选提供方已配置的模型 [新手:按需]
  "CLAUDE_MEM_WORK_VIEW_COPY_MODEL": "",
  // “我的工作”刷新由哪个 agent 来跑:空=跟随 CLAUDE_MEM_PROVIDER;claude-code/codex/gemini=指定一个;off=都不跑;all=依次尝试所有已登录的 agent [新手:按需]
  "CLAUDE_MEM_WORK_VIEW_AGENT": "",
  // “我的工作”刷新在 Claude Code 上使用的模型别名(如 haiku),空=各步骤按默认表(haiku/sonnet) [新手:不动]
  "CLAUDE_MEM_WORK_VIEW_CLAUDE_MODEL": "",
  // “我的工作”刷新在 Codex 上使用的模型,空=各步骤按默认表 [新手:不动]
  "CLAUDE_MEM_WORK_VIEW_CODEX_MODEL": "",
  // “我的工作”刷新在 Gemini 上使用的模型,空=各步骤按默认表(flash-lite/flash) [新手:不动]
  "CLAUDE_MEM_WORK_VIEW_GEMINI_MODEL": "",
  // “我的工作”生成的标题、复盘、故事文本使用的语言,填语言名如 'Chinese (Simplified)' 或 'Turkish';空=由技能按使用者语言自行选择,不会自动检测 [新手:按需]
  "CLAUDE_MEM_WORK_VIEW_TEXT_LANGUAGE": ""
}
```

### 附录二:纯 JSON 版(可直接使用)

```json
{
  "CLAUDE_MEM_MEMORY_SEARCH_HOOK_ENABLED": "true",
  "CLAUDE_MEM_MEMORY_INSTRUCTIONS_ENABLED": "true",
  "CLAUDE_MEM_MEMORY_WATCH_ROOTS": "",
  "CLAUDE_MEM_MODEL": "haiku",
  "CLAUDE_MEM_CONTEXT_OBSERVATIONS": "50",
  "CLAUDE_MEM_SESSION_START_INCLUDE_ALL_SOURCES": "false",
  "CLAUDE_MEM_CONTEXT_PROJECTS": "current",
  "CLAUDE_MEM_WORKER_PORT": "37701",
  "CLAUDE_MEM_WORKER_HOST": "127.0.0.1",
  "CLAUDE_MEM_WORKER_URL": "",
  "CLAUDE_MEM_WORKER_INGEST_TOKEN": "",
  "CLAUDE_MEM_WORKER_INGEST_MAX_BYTES": "5242880",
  "CLAUDE_MEM_HOOK_SPOOL_TRANSPORT": "auto",
  "CLAUDE_MEM_ALLOWED_ORIGINS": "",
  "CLAUDE_MEM_PUBLIC_URL": "",
  "CLAUDE_MEM_API_TIMEOUT_MS": "30000",
  "CLAUDE_MEM_SESSION_INIT_TIMEOUT_MS": "10000",
  "CLAUDE_MEM_IDLE_EXIT_SEC": "0",
  "CLAUDE_MEM_SKIP_TOOLS": "ListMcpResourcesTool,SlashCommand,Skill,TodoWrite,AskUserQuestion",
  "CLAUDE_MEM_SKIP_BASH_PATTERNS": "",
  "CLAUDE_MEM_SKIP_SUBAGENT_OBSERVATIONS": "false",
  "CLAUDE_MEM_SKIP_AGENT_TYPES": "",
  "CLAUDE_MEM_CAPTURE_ADVISOR_CALLS": "false",
  "CLAUDE_MEM_DELIVERABLES_ENABLED": "true",
  "CLAUDE_MEM_PROVIDER": "claude",
  "CLAUDE_MEM_PROVIDER_BY_SOURCE": "",
  "CLAUDE_MEM_OBSERVER_ENABLED": "true",
  "CLAUDE_MEM_MEDIA_CAPTURE_ENABLED": "true",
  "CLAUDE_MEM_MEDIA_INFERENCE_ENABLED": "false",
  "CLAUDE_MEM_CODEX_MODEL": "",
  "CLAUDE_MEM_CODEX_PATH": "codex",
  "CLAUDE_MEM_CODEX_REASONING_EFFORT": "low",
  "CLAUDE_MEM_CODEX_MAX_CONCURRENT_AGENTS": "2",
  "CLAUDE_MEM_CODEX_OBSERVATION_BATCH_SIZE": "8",
  "CLAUDE_MEM_CODEX_OBSERVATION_BATCH_MAX_CHARS": "32000",
  "CLAUDE_MEM_CLAUDE_OBSERVATION_BATCH_SIZE": "1",
  "CLAUDE_MEM_CLAUDE_AUTH_METHOD": "subscription",
  "CLAUDE_MEM_GEMINI_API_KEY": "",
  "CLAUDE_MEM_GEMINI_API_KEYS": "",
  "CLAUDE_MEM_GEMINI_MODEL": "gemini-flash-latest",
  "CLAUDE_MEM_GEMINI_RATE_LIMITING_ENABLED": "true",
  "CLAUDE_MEM_OPENROUTER_API_KEY": "",
  "CLAUDE_MEM_OPENROUTER_API_KEYS": "",
  "CLAUDE_MEM_OPENROUTER_MODEL": "cohere/north-mini-code:free",
  "CLAUDE_MEM_OPENROUTER_BASE_URL": "",
  "CLAUDE_MEM_OPENROUTER_TEMPERATURE": "",
  "CLAUDE_MEM_OPENROUTER_SITE_URL": "",
  "CLAUDE_MEM_OPENROUTER_APP_NAME": "claude-mem",
  "CLAUDE_MEM_OPENROUTER_EXTRA_BODY": "",
  "CLAUDE_MEM_OPENROUTER_REASONING_EFFORT": "",
  "CLAUDE_MEM_OPENAI_COMPAT_PRESET": "",
  "CLAUDE_MEM_OPENAI_COMPAT_API_KEY": "",
  "CLAUDE_MEM_OPENAI_COMPAT_API_KEYS": "",
  "CLAUDE_MEM_OPENAI_COMPAT_BASE_URL": "",
  "CLAUDE_MEM_OPENAI_COMPAT_MODEL": "",
  "CLAUDE_MEM_OPENAI_COMPAT_REASONING": "",
  "CLAUDE_MEM_OPENAI_COMPAT_OBSERVATION_BATCH_SIZE": "1",
  "CLAUDE_MEM_QUOTA_FALLBACK_PROVIDER": "claude",
  "CLAUDE_MEM_QUOTA_FALLBACK_MODEL": "",
  "CLAUDE_MEM_QUOTA_FALLBACK_AUTH_METHOD": "",
  "CLAUDE_MEM_QUOTA_THRESHOLD_FIVE_HOUR": "0.95",
  "CLAUDE_MEM_QUOTA_THRESHOLD_SEVEN_DAY": "0.93",
  "CLAUDE_MEM_QUOTA_THRESHOLD_SEVEN_DAY_OPUS": "0.93",
  "CLAUDE_MEM_QUOTA_THRESHOLD_SEVEN_DAY_SONNET": "0.92",
  "CLAUDE_MEM_QUOTA_THRESHOLD_OVERAGE": "0.95",
  "CLAUDE_MEM_DATA_DIR": "/Users/melodycchen/.claude-mem",
  "CLAUDE_MEM_LOG_LEVEL": "INFO",
  "CLAUDE_MEM_PYTHON_VERSION": "3.13",
  "CLAUDE_CODE_PATH": "",
  "CLAUDE_MEM_CLAUDE_CONFIG_DIR": "",
  "CLAUDE_MEM_OBSERVER_CLAUDE_CONFIG_DIR": "",
  "CLAUDE_MEM_MODE": "code",
  "CLAUDE_MEM_CONTEXT_SHOW_READ_TOKENS": "false",
  "CLAUDE_MEM_CONTEXT_SHOW_WORK_TOKENS": "false",
  "CLAUDE_MEM_CONTEXT_SHOW_SAVINGS_AMOUNT": "false",
  "CLAUDE_MEM_CONTEXT_SHOW_SAVINGS_PERCENT": "true",
  "CLAUDE_MEM_CONTEXT_OBSERVATION_TYPES": "",
  "CLAUDE_MEM_CONTEXT_OBSERVATION_CONCEPTS": "",
  "CLAUDE_MEM_CONTEXT_FULL_COUNT": "0",
  "CLAUDE_MEM_CONTEXT_FULL_FIELD": "narrative",
  "CLAUDE_MEM_CONTEXT_SESSION_COUNT": "10",
  "CLAUDE_MEM_CONTEXT_SHOW_LAST_SUMMARY": "true",
  "CLAUDE_MEM_CONTEXT_SHOW_LAST_MESSAGE": "false",
  "CLAUDE_MEM_CONTEXT_MAIN_AGENT_ONLY": "true",
  "CLAUDE_MEM_REINFORCE_ALPHA": "0",
  "CLAUDE_MEM_CONTEXT_SHOW_TERMINAL_OUTPUT": "true",
  "CLAUDE_MEM_WELCOME_HINT_ENABLED": "true",
  "CLAUDE_MEM_WORK_STATE_ENABLED": "true",
  "CLAUDE_MEM_FILE_READ_GATE_ENABLED": "true",
  "CLAUDE_MEM_FOLDER_CLAUDEMD_ENABLED": "false",
  "CLAUDE_MEM_FOLDER_USE_LOCAL_MD": "false",
  "CLAUDE_MEM_TRANSCRIPTS_ENABLED": "true",
  "CLAUDE_MEM_TRANSCRIPTS_CONFIG_PATH": "/Users/melodycchen/.claude-mem/transcript-watch.json",
  "CLAUDE_MEM_CODEX_TRANSCRIPT_INGESTION": "false",
  "CLAUDE_MEM_CODEX_SUBAGENT_INGESTION": "false",
  "CLAUDE_MEM_MAX_CONCURRENT_AGENTS": "2",
  "CLAUDE_MEM_OBSERVER_MAX_CONVERSATION_CHARS": "400000",
  "CLAUDE_MEM_OBSERVER_THINKING": "disabled",
  "CLAUDE_MEM_OBSERVER_CONTEXT_WINDOW": "",
  "CLAUDE_MEM_OBSERVER_MAX_OUTPUT_TOKENS": "4096",
  "CLAUDE_MEM_OBSERVE_BARE_PROMPTS": "false",
  "CLAUDE_MEM_HOOK_FAIL_LOUD_THRESHOLD": "3",
  "CLAUDE_MEM_REDACT_ENABLED": "false",
  "CLAUDE_MEM_REDACT_DISABLED_BUILTINS": "",
  "CLAUDE_MEM_REDACT_CUSTOM_PATTERNS": "[]",
  "CLAUDE_MEM_REDACT_LOG_MATCHES": "false",
  "CLAUDE_MEM_REDACT_GENERIC_ENABLED": "false",
  "CLAUDE_MEM_EXCLUDED_PROJECTS": "",
  "CLAUDE_MEM_PROJECT_ENVIRONMENTS": "[]",
  "CLAUDE_MEM_FOLDER_MD_EXCLUDE": "[]",
  "CLAUDE_MEM_FOLDER_MD_SKELETON_DENYLIST": "[]",
  "CLAUDE_MEM_SEMANTIC_INJECT": "false",
  "CLAUDE_MEM_SEMANTIC_INJECT_LIMIT": "5",
  "CLAUDE_MEM_SEMANTIC_INJECT_FORMAT": "narrative",
  "CLAUDE_MEM_TIER_ROUTING_ENABLED": "true",
  "CLAUDE_MEM_TIER_SIMPLE_MODEL": "haiku",
  "CLAUDE_MEM_TIER_SUMMARY_MODEL": "",
  "CLAUDE_MEM_TIER_FAST_MODEL": "haiku",
  "CLAUDE_MEM_TIER_SMART_MODEL": "sonnet",
  "CLAUDE_MEM_CHROMA_ENABLED": "true",
  "CLAUDE_MEM_CHROMA_MODE": "local",
  "CLAUDE_MEM_CHROMA_HOST": "127.0.0.1",
  "CLAUDE_MEM_CHROMA_PORT": "8000",
  "CLAUDE_MEM_CHROMA_SSL": "false",
  "CLAUDE_MEM_CHROMA_API_KEY": "",
  "CLAUDE_MEM_CHROMA_TENANT": "default_tenant",
  "CLAUDE_MEM_CHROMA_DATABASE": "default_database",
  "CLAUDE_MEM_CHROMA_PREWARM_TIMEOUT_MS": "120000",
  "CLAUDE_MEM_CHROMA_MUTATION_TIMEOUT_MS": "600000",
  "CLAUDE_MEM_CHROMA_MAX_PENDING_MUTATIONS": "5000",
  "CLAUDE_MEM_CHROMA_EMBEDDING_FUNCTION": "default",
  "CLAUDE_MEM_SERVER_VECTOR_SEARCH": "auto",
  "CLAUDE_MEM_EMBEDDING_BACKFILL_THREADS": "",
  "CLAUDE_MEM_EMBEDDING_MODEL": "all-MiniLM-L6-v2",
  "CLAUDE_MEM_CHROMA_UVX_PATH": "",
  "CLAUDE_MEM_SEARCH_RECENCY_DAYS": "90",
  "CLAUDE_MEM_CLOUD_SYNC_TOKEN": "",
  "CLAUDE_MEM_CLOUD_SYNC_USER_ID": "",
  "CLAUDE_MEM_CLOUD_SYNC_HUB_URL": "",
  "CLAUDE_MEM_CLOUD_SYNC_DEVICE_ID": "",
  "CLAUDE_MEM_CLOUD_SYNC_DEVICE_NAME": "melodycchens-MacBook-Pro.local",
  "CLAUDE_MEM_CLOUD_SYNC_WS": "true",
  "CLAUDE_MEM_CLOUD_SYNC_KEEP_PULLING": "false",
  "CLAUDE_MEM_CLOUD_SYNC_CONTENT_BATCH_SIZE": "40",
  "CLAUDE_MEM_CLOUD_SYNC_REQUEST_TIMEOUT_MS": "90000",
  "CLAUDE_MEM_TEAMBRAIN_URL": "",
  "CLAUDE_MEM_TEAMBRAIN_TEAM_ID": "",
  "CLAUDE_MEM_LLM_TIMEOUT_MS": "180000",
  "CLAUDE_MEM_FIELD_OPTIMIZE_TIMEOUT_MS": "180000",
  "CLAUDE_MEM_LLM_STREAM_IDLE_TIMEOUT_MS": "90000",
  "CLAUDE_MEM_WORKER_HEARTBEAT_STALE_MS": "120000",
  "CLAUDE_MEM_TV_TOKEN": "",
  "CLAUDE_MEM_PRO_TRIAL_EMAIL": "",
  "CLAUDE_MEM_PRO_TRIAL_AT": "",
  "CLAUDE_MEM_PRO_TRIAL_STATE": "",
  "CLAUDE_MEM_PRO_TRIAL_ENDS_AT": "",
  "CLAUDE_MEM_ONLINE_SIGNUP_EMAIL": "",
  "CLAUDE_MEM_ONLINE_SIGNUP_NOTE": "",
  "CLAUDE_MEM_ONLINE_SIGNUP_AT": "",
  "CLAUDE_MEM_ONLINE_SIGNUP_SENT": "",
  "CLAUDE_MEM_PRO_PLAN": "",
  "CLAUDE_MEM_PRO_FALLBACK_AT": "",
  "CLAUDE_MEM_PRO_FALLBACK_MESSAGE": "",
  "CLAUDE_MEM_PRO_FALLBACK_ACTION": "",
  "CLAUDE_MEM_PRO_FALLBACK_URL": "",
  "CLAUDE_MEM_PRO_MEMORY_KEY": "",
  "CLAUDE_MEM_PRO_MEMORY_BASE_URL": "",
  "CLAUDE_MEM_PRO_MEMORY_MODEL": "",
  "CLAUDE_MEM_WORK_VIEW_AUTO_REFRESH": "true",
  "CLAUDE_MEM_WORK_VIEW_REFRESH_INTERVAL_MIN": "10",
  "CLAUDE_MEM_WORK_VIEW_SHARED_STATE": "false",
  "CLAUDE_MEM_WORK_VIEW_COPY_PROVIDER": "",
  "CLAUDE_MEM_WORK_VIEW_COPY_MODEL": "",
  "CLAUDE_MEM_WORK_VIEW_AGENT": "",
  "CLAUDE_MEM_WORK_VIEW_CLAUDE_MODEL": "",
  "CLAUDE_MEM_WORK_VIEW_CODEX_MODEL": "",
  "CLAUDE_MEM_WORK_VIEW_GEMINI_MODEL": "",
  "CLAUDE_MEM_WORK_VIEW_TEXT_LANGUAGE": "",
  "CLAUDE_MEM_BACKUP_ENABLED": "false",
  "CLAUDE_MEM_BACKUP_INTERVAL_HOURS": "24",
  "CLAUDE_MEM_BACKUP_RETAIN_COUNT": "7",
  "CLAUDE_MEM_TELEGRAM_ENABLED": "true",
  "CLAUDE_MEM_TELEGRAM_BOT_TOKEN": "",
  "CLAUDE_MEM_TELEGRAM_CHAT_ID": "",
  "CLAUDE_MEM_TELEGRAM_WRAPUPS_ENABLED": "true",
  "CLAUDE_MEM_TELEGRAM_OBSERVATION_ALERTS_ENABLED": "false",
  "CLAUDE_MEM_TELEGRAM_WRAPUP_ROUTES": "{}",
  "CLAUDE_MEM_TELEGRAM_TRIGGER_TYPES": "security_alert,sensitive",
  "CLAUDE_MEM_TELEGRAM_TRIGGER_CONCEPTS": "",
  "CLAUDE_MEM_GROK_BOT_AWARENESS_ENABLED": "false",
  "CLAUDE_MEM_GROK_BOT_AWARENESS_AGENT_IDS": "",
  "CLAUDE_MEM_GROK_BOT_AWARENESS_TRIGGER_TYPES": "decision,bugfix,security_alert,sensitive",
  "CLAUDE_MEM_GROK_BOT_AWARENESS_TRIGGER_CONCEPTS": "",
  "CLAUDE_MEM_GROK_BOT_WEBHOOK_URL": "",
  "CLAUDE_MEM_GROK_BOT_WEBHOOK_SECRET": "",
  "CLAUDE_MEM_NOTION_ENABLED": "false",
  "CLAUDE_MEM_NOTION_TOKEN": "",
  "CLAUDE_MEM_NOTION_DATABASE_ID": "",
  "CLAUDE_MEM_NOTION_AUTO_CREATE_PROPERTIES": "true",
  "CLAUDE_MEM_GROK_BOT_INJECT_ENABLED": "true",
  "CLAUDE_MEM_GROK_BOT_INJECT_AGENT_IDS": "*",
  "CLAUDE_MEM_GROK_BOT_INJECT_TIER": "episode",
  "CLAUDE_MEM_GROK_BOT_INJECT_WINDOW": "80",
  "CLAUDE_MEM_GROK_BOT_INJECT_FALLBACK": "house",
  "CLAUDE_MEM_GROK_BOT_INJECT_PLATFORM_SOURCE": "",
  "CLAUDE_MEM_GROK_BOT_INJECT_PROJECTS_BY_AGENT": "",
  "CLAUDE_MEM_GROK_BOT_INJECT_MAX_LINE_CHARS": "160",
  "CLAUDE_MEM_GROK_BOT_INJECT_DEBOUNCE_MS": "1500",
  "CLAUDE_MEM_GROK_BOT_INJECT_STANDING_LINE": "",
  "CLAUDE_MEM_CCS_ALIGN_ENABLED": "true",
  "CLAUDE_MEM_CCS_ALIGN_VIEWER_IDS": "ccs-align",
  "CLAUDE_MEM_CCS_ALIGN_TRIGGER_TYPES": "decision,bugfix,security_alert,sensitive",
  "CLAUDE_MEM_CCS_ALIGN_PATCH_SHADOWS": "false",
  "CLAUDE_MEM_QUEUE_ENGINE": "sqlite",
  "CLAUDE_MEM_REDIS_URL": "",
  "CLAUDE_MEM_REDIS_HOST": "127.0.0.1",
  "CLAUDE_MEM_REDIS_PORT": "6379",
  "CLAUDE_MEM_REDIS_MODE": "external",
  "CLAUDE_MEM_QUEUE_REDIS_PREFIX": "claude_mem_37701",
  "CLAUDE_MEM_AUTH_MODE": "api-key",
  "CLAUDE_MEM_RUNTIME": "worker",
  "CLAUDE_MEM_SERVER_URL": "http://127.0.0.1:37878",
  "CLAUDE_MEM_SERVER_API_KEY": "",
  "CLAUDE_MEM_SERVER_PROJECT_ID": "",
  "CLAUDE_MEM_SERVER_BETA_URL": "http://127.0.0.1:37878",
  "CLAUDE_MEM_SERVER_BETA_API_KEY": "",
  "CLAUDE_MEM_SERVER_BETA_PROJECT_ID": "",
  "CLAUDE_MEM_DEDUP_ENABLED": "false",
  "CLAUDE_MEM_DEDUP_COSINE_THRESHOLD": "0.80",
  "CLAUDE_MEM_DEDUP_IDF_VETO_DF": "10",
  "CLAUDE_MEM_DEDUP_MIN_SHARED_TOKENS": "2",
  "CLAUDE_MEM_DEDUP_MIN_PROJECT_DOCS": "10",
  "CLAUDE_MEM_DEDUP_MAX_SCAN": "2000",
  "CLAUDE_MEM_DEDUP_MAX_BACKFILL_ROWS": "50000",
  "CLAUDE_MEM_TOOL_USES_RETENTION_DAYS": "0",
  "CLAUDE_MEM_LOG_RETENTION_DAYS": "30",
  "CLAUDE_MEM_WORKER_AUTOSTART": "true",
  "CLAUDE_MEM_PROJECT_NAME_SOURCE": "path"
}
```
