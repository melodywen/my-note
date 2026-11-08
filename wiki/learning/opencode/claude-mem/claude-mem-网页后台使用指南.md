---
type: concept
status: developing
area: growth
title: "claude-mem 网页后台使用指南"
created: 2026-11-08
updated: 2026-11-08
tags:
  - learning
  - opencode
  - claude-mem
  - 后台
  - 使用指南
related:
  - "[[claude-mem-安装部署]]"
  - "[[claude-mem-配置详解]]"
  - "[[claude-mem-调教清单]]"
  - "[[claude-mem-存储与读取机制]]"
  - "[[claude-mem-跨端共享]]"
---

# claude-mem 网页后台使用指南

> 一句话:**worker 进程自带一个网页,打开 [http://127.0.0.1:37701/viewer](http://127.0.0.1:37701/viewer) 就能看记忆、改设置、看日志。它没有任何新手引导,这篇补上。**

> 证据说明:界面功能来自 `src/ui/viewer/` 的前端源码和本机接口实测([/api/stats](http://127.0.0.1:37701/api/stats)、[/api/projects](http://127.0.0.1:37701/api/projects)、[/api/processing-status](http://127.0.0.1:37701/api/processing-status)),以及一张你截的 `/viewer#/sessions` 截图。**我没有看过每个弹窗渲染出来的样子**,标"未证实"的地方是从源码推的。

## 1. 先认地址

| 地址                                             | 是什么                      | 现在对你有用吗                                      |
| ---------------------------------------------- | ------------------------ | -------------------------------------------- |
| [/viewer](http://127.0.0.1:37701/viewer)                | **记忆查看器**,看记忆、改设置、看日志都在这 | 有用,本篇主角                                      |
| [/](http://127.0.0.1:37701/)                      | "My Work" 工作看板,按"请求"分组   | 暂时用处不大。源码里它的 README 自称"线框加示例数据",偏任务管理,不是记忆本身 |
| [/tv](http://127.0.0.1:37701/tv)                    | 流式展示页(对应 `/stream`)      | 没读它做什么,先不管                                   |
| [/api/health](http://127.0.0.1:37701/api/health)            | 健康检查,返回 JSON             | 排错时用                                         |
| [/api/stats](http://127.0.0.1:37701/api/stats)             | 统计:观察数、会话数、数据库大小         | 排错时用                                         |
| [/api/projects](http://127.0.0.1:37701/api/projects)          | 已登记的项目和来源                | 排错时用                                         |
| [/api/processing-status](http://127.0.0.1:37701/api/processing-status) | 观察者是否在处理、队列积压数           | 排错时用                                         |

三点要知道:

- **只能本机访问**。默认监听 `127.0.0.1`(`CLAUDE_MEM_WORKER_HOST`),别的机器打不开。我读到设置接口 `POST /api/settings` 没有身份验证,源码注释写的是"worker 信任回环地址",所以**不要把它改成对外开放**。
- **worker 没启动就打不开**。起不来时用 `npx claude-mem start`。
- 页面右上角可切 **简体中文 / English**(`Header.tsx` 里的语言下拉)。你截图里已经是中文。

## 2. 顶栏每个东西是什么

对照你的截图,从左到右:

| 位置 | 是什么 | 怎么用 |
|---|---|---|
| 我的工作 | 链接回 `/`(My Work 看板) | 不用管 |
| logo 和右上角的数字(你截图里是 4) | 观察者的**队列积压数** | 数字大于 0,说明有对话等着被提炼成记忆。logo 在转,说明观察者正在处理。**数字一直不减少,说明观察者没在工作** |
| 免费试用 30 天 | CMEM Pro 的推广按钮 | **不是限制**,不点不影响。详见第 7 节 |
| TeamBrain | 另一个官方云服务的推广链接 | 同上,只在本机没加入任何团队时显示 |
| Feed connected / Cloud freshness unknown | 左半句:网页和本机 worker 的实时连接;右半句:云同步状态 | `Feed connected` 是正常。`Cloud freshness unknown` 是因为没用云同步,不是错误(云同步字段在 `settings.json` 里是空的) |
| 书、X、Discord、GitHub 图标 | 官方文档、推特、社区、仓库的外链 | 文档地址是 [https://docs.claude-mem.ai](https://docs.claude-mem.ai) |
| 所有项目 | 按项目过滤的下拉框 | 选 `my-note` 就只看这个项目 |
| English / 简体中文 | 界面语言 | 改后保存在浏览器里 |
| 主题切换 | 亮色、暗色、跟随系统 | 随意 |
| 圆圈问号按钮 | 重新打开欢迎卡片 | 想看官方"怎么工作"的介绍时点 |
| 齿轮按钮 | **设置弹窗**,这是最重要的一个 | 见第 4 节 |

页面右下角还有一个按钮,用来打开**日志抽屉**(源码里 `LogsDrawer`,提示文字是"打开记忆日志")。见第 5 节。

## 3. 两个标签:时间线和会话

页面中间有两个标签,在 `ViewTabs.tsx` 里就两个值:`timeline` 和 `sessions`。

### 3.1 会话(你截图里这页)

每个会话一张卡片,显示:

- 项目名(`my-note`)
- 会话 ID(`opencode-ses_...`,前缀说明来源是 OpenCode)
- 来源(`Opencode`)和开始时间
- **"N 条记忆"**:见下面的坑

操作:

- 点卡片或卡片菜单里的"打开",进入会话详情页(地址是 `#/sessions/...`),顶部有"返回会话"。
- 卡片菜单里还有"删除"。

**坑:这个"N 条记忆"数得不准。** 你截图里是 12 条,但我查数据库,真正的观察(observations)是 0 条,你的提问原文(user_prompts)有 13 条。所以这个数很可能把**提问**也算进去了。这是我的推测,没读到计数函数。判断记忆有没有真的生成,看 [/api/stats](http://127.0.0.1:37701/api/stats) 里的 `observations`,别看这个数。

### 3.2 时间线

按时间倒序列出所有条目。每种条目长这样:

| 卡片类型 | 是什么 | 谁产生的 |
|---|---|---|
| Prompt(提问) | 你发给 AI 的原话,长了会折叠,点"显示更多" | **插件直接记录,不需要观察者** |
| Session Summary(会话总结) | 一个会话结束后的总结 | 观察者 |
| 观察(多种类型) | 一条条提炼出来的记忆,有标题、事实(facts)、叙述(narrative)、读过哪些文件、改过哪些文件 | 观察者 |

观察分这几类,顶部有**分类筛选条**,每个标签后面带数量,点一下只看这一类:

| 分类 | 大意 |
|---|---|
| discovery | 发现了什么(读代码、查资料得到的信息) |
| decision | 做了什么决定 |
| bugfix | 修了什么 bug |
| feature | 加了什么功能 |
| refactor | 重构 |
| change | 其他改动 |
| security_alert / security_note | 安全相关 |
| other | 不认识的类型 |

分类名和顺序来自 `utils/category.ts`。筛选条只显示"有内容的分类",所以**现在是空的,因为没有观察**。

每张卡片右上角有删除按钮,点了会弹确认"此操作不可撤销"。

## 4. 齿轮:设置弹窗(最有价值的部分)

点齿轮,弹出"设置——选择你下一个会话会收到的上下文"。**这里的设置和 `~/.claude-mem/settings.json` 是同一份**:保存时网页调 `POST /api/settings`,worker 写回 `settings.json`。

我们的 `settings.json` 是软链指向 `~/.config/opencode/claude-mem/settings.json`。这次保存会不会把软链冲掉,我只读了 `atomic-json.ts` 推断不会,**没实测**。建议你第一次点保存后,在终端执行 `ls -l ~/.claude-mem/settings.json` 确认还是软链。

### 4.1 弹窗顶部:来源和项目

两个下拉:**来源**(所有来源、opencode 等)和**项目**。下面的"已保存上下文预览"会按你选的来源和项目,显示**下一个会话开头会被注入什么**。这是调"注入多少记忆"时的实时参照。

### 4.2 分区一览

| 分区 | 能调什么 | 对应的配置键方向(详见[[claude-mem-配置详解]]) |
|---|---|---|
| 加载(Loading) | 注入多少条观察(1-200)、取多少个最近会话(1-50)、是否在会话开头包含所有来源 | `CONTEXT_OBSERVATIONS`、`SESSION_START_INCLUDE_ALL_SOURCES` 等 |
| 显示(Display) | 完整观察的显示字段(叙述或事实)、Token 经济学表格的显示 | `CONTEXT_FULL_FIELD`、`CONTEXT_SHOW_*_TOKENS` 等 |
| 备份(Backups) | 数据库自动快照开关、上次备份状态 | 改完要**重启 worker** 才生效。恢复命令界面里给了:`npx claude-mem restore <文件>` |
| 高级(Advanced) | **AI 提供方和模型选择**,观察者就是在这里换 | `CLAUDE_MEM_PROVIDER` 等 |

### 4.3 在这里把观察者换成 codebuddy

高级分区里"AI 提供方"下拉有:

- Claude(默认)
- Gemini(要 API key)
- OpenRouter / claude-mem observer
- Codex(用 ChatGPT 订阅)
- **OpenAI 兼容端点(自带 key)**:我们要选这个

选它之后出现四个输入:

| 输入 | 填什么 |
|---|---|
| 端点预设(Endpoint preset) | 下拉里有 NVIDIA NIM、DeepSeek、Groq、Together、MiniMax、Ollama、LM Studio、vLLM 等 20 项。**codebuddy 不在里面,选"自定义 OpenAI 兼容端点(custom)"** |
| Base URL | codebuddy 的 OpenAI 兼容地址(**我们还缺**) |
| Model | 模型名(**我们还缺**) |
| Reasoning | 关(默认)或开(由端点决定) |

**API key 不能在网页里填。** 界面上直接写了:"API key 在网页外设置:`~/.claude-mem/settings.json` 里的 `CLAUDE_MEM_OPENAI_COMPAT_API_KEY`,或 `~/.claude-mem/.env` 里的 `OPENAI_COMPAT_API_KEY`。本地服务器不需要。"

这对我们是好消息:**密钥可以放 `.env`,不用写进已入库的 `settings.json`**。但 `.env` 是否真的优先读,界面这句话只说"可以设",我没验证。

另外,本地服务不需要 key(Ollama 等)这条,对 codebuddy 不适用,它要 key。

### 4.4 保存

底部有"保存设置"按钮。**写入 `settings.json` 后,哪些要重启 worker 才生效,界面只对"备份"明确写了要重启,其他我没读到**,保险起见改完提供方后重启一次:

```bash
npx claude-mem restart
```

(`restart` 这个子命令在 `src/npx-cli` 的命令分支里存在,和 `start`、`stop`、`status`、`restore` 并列;具体参数没读。)

### 4.5 网页改不了的东西

源码里明确写了"只能改文件或环境变量,网页不让改":

- 启动子进程用的可执行路径:`CLAUDE_CODE_PATH`、`CLAUDE_MEM_CODEX_PATH`、`CLAUDE_MEM_CHROMA_UVX_PATH`。理由是"这些值是 worker 会拉起的程序,不能让 HTTP 可写"。
- 云同步、Chroma、Telegram、Redis 的令牌。

所以前面讨论的"用 `CHROMA_UVX_PATH` 换 chroma-mcp"那条绕路,即使将来要试,也只能手改文件,不能在网页里点。

## 5. 日志抽屉

右下角按钮打开。顶部有两组筛选芯片:

- **级别**:Debug、Info、Warn、Error 等,点哪个只看哪个。
- **组件**:Hook(钩子)、Parser(解析)、DB(数据库)、System(系统)、HTTP、Session(会话)、Chroma(向量库)、Other(其他)。

还有"清空日志"按钮(会弹确认)。

**什么时候用**:观察者没产出记忆时,先打开日志,级别选 Error 和 Warn,组件选 Session、System,看有没有"找不到 claude 可执行文件"这类提示。我们现在的情况就是这样。

日志文件本体在 `~/.claude-mem/logs/`,抽屉只是读它。

## 6. 现在这个后台里能看到什么(实测快照)

2026-11-08 15:40 左右的实测:

| 项 | 值 | 来源 |
|---|---|---|
| 观察(observations) | 0 | [/api/stats](http://127.0.0.1:37701/api/stats) 和直接查库 |
| 总结 | 0 | 同上 |
| 会话 | 1 | 同上 |
| 你的提问原文 | 13 | 直接查 `user_prompts` 表 |
| 项目 | `my-note` | [/api/projects](http://127.0.0.1:37701/api/projects) |
| 来源 | `opencode` | [/api/projects](http://127.0.0.1:37701/api/projects) |
| 队列积压 | 11 | [/api/processing-status](http://127.0.0.1:37701/api/processing-status) |

**这组数字说明什么**:

1. OpenCode 插件在工作:来源 `opencode` 已登记,你的提问被原文记录。这同时证明 **`claude-mem.js` 被 OpenCode 自动加载了**,之前我没验证过的点现在有证据。
2. 观察者没工作:观察 0 条、队列积压 11 条且没被消费。原因我们已知,找不到 `claude` 可执行文件,没配好 codebuddy。
3. 积压的 11 条,等观察者配好后会不会被补处理,我没验证。

## 7. 关于"免费试用 30 天"

很多人会误以为本地版只能用 30 天,**不是**。

| 项 | 情况 |
|---|---|
| 许可证 | Apache-2.0(`LICENSE`、`package.json`),开源,本地运行,无时限 |
| 这个按钮 | 推广 **CMEM Pro**(官方付费托管服务)的位置。点了打开 [https://cmem.ai/pro?from=viewer](https://cmem.ai/pro?from=viewer)。卖点文案是"记忆走它的服务,不占你的套餐额度,套餐用量最多提升 100%" |
| 对你的影响 | 我读到的只有文案和链接,没有读到"到期后停用本地功能"的代码 |

推广还会出现在会话开头的横幅、安装器提示里(源码 `pro-promo.ts` 注释列了五处)。**关掉推广的开关我没查**。

**真正要警惕的是:不要在页面上登录 cmem.ai。** 登录后记忆可能走官方云端同步,会把你的提问原文外发。我们前面的文档([[claude-mem-安装部署]])里专门提过这个风险。装的时候用 `--provider claude` 就是为了避免触发登录。

## 8. 日常怎么用:四个场景

| 想做的事 | 去哪 | 怎么做 |
|---|---|---|
| 确认记忆有没有在写 | [/viewer](http://127.0.0.1:37701/viewer) 时间线 | 在 OpenCode 里干几轮活,刷新页面,看有没有新的观察卡片(现在会是空) |
| 观察者坏了查原因 | 日志抽屉,或 [/api/health](http://127.0.0.1:37701/api/health) | 级别选 Error,看 `dependencies` 里的 `claude_cli` 之类的提示 |
| 调一次注入多少记忆 | 齿轮、加载分区 | 先看"已保存上下文预览"确认效果,再保存 |
| 删一条不想要的记忆 | 时间线卡片右上角 | 点删除并确认,**不可撤销** |
| 换观察者的模型 | 齿轮、高级分区 | 提供方选 OpenAI 兼容,预设选 custom,填地址和模型,key 放 `.env` 或 `settings.json` |

## 9. 没证实的清单

- 各弹窗的实际观感、按钮位置,我没渲染过。
- "N 条记忆"到底怎么数,没读计数函数。
- 保存设置后哪些键要重启 worker,只有备份确认。
- 网页保存是否保持 `settings.json` 软链,没实测。
- `.env` 里的 `OPENAI_COMPAT_API_KEY` 是否优先读,界面只说"可以设"。
- 观察者配好后,已积压的 11 条会不会被补处理。
- 推广位能不能关。
- `/tv` 页面做什么。

## 10. 下一步

1. 先打开 [/viewer](http://127.0.0.1:37701/viewer),点齿轮,看"高级"分区的真实样子,把和本文不符的地方告诉我,我来订正。
2. 拿到 codebuddy 的 OpenAI 兼容地址和模型名后,可以在网页里填(预设选 custom),也可以我直接改 `settings.json`,密钥放 `.env`。
3. 配好后重启 worker,观察 [/api/stats](http://127.0.0.1:37701/api/stats) 里 `observations` 是否从 0 开始增长,同时队列积压数是否下降。

相关:[[claude-mem-安装部署]]、[[claude-mem-调教清单]]、[[claude-mem-存储与读取机制]]。
