---
type: concept
status: developing
area: growth
title: "claude-mem 跨端共享:OpenCode 和 DSH 怎么共用一份记忆"
created: 2026-11-08
updated: 2026-11-09
tags:
  - learning
  - opencode
  - dsh
  - claude-mem
  - 跨端共享
related:
  - "[[claude-mem-配置详解]]"
  - "[[claude-mem-安装部署]]"
  - "[[claude-mem-调教清单]]"
  - "[[claude-mem-存储与读取机制]]"
  - "[[claude-mem-深入调研]]"
---

# claude-mem 跨端共享:OpenCode 和 DSH 怎么共用一份记忆

> 一句话:**两个端各自接一个小插件,把事件发给同一个本机 worker 进程,存进同一个数据库。能不能互相看到,取决于三件事:项目名算得一不一致、来源过滤开没开、两端是不是都真的接上了。**
>
> 前半部分依据读源码(claude-mem 约 v15.12.0);**2026-11-09 已在本机实测 DSH 这一端,结果见第 8 节**。标"未证实"的是没读到或没验证的部分。

---

## 先搞清几个词

| 词 | 白话 |
|---|---|
| worker | claude-mem 在本机常驻的一个后台进程,所有端都往它这儿发数据、从它这儿取记忆 |
| 来源(platform source) | 每条记忆打的标签,说明是哪个端产生的,如 `claude`、`opencode`、`dsh` |
| 项目名(project) | 每条记忆归属的项目,查询时几乎总按它过滤 |
| transcript 监听 | worker 不靠插件,而是直接盯着某个目录里的会话日志文件,读到新内容就入库 |

---

## 1. 整体结构

```
OpenCode  --插件(钩子)-->  HTTP  -->
                                      worker(同一个进程)--> 同一个数据库
DSH  --会话日志文件--> worker 监听 -->
DSH  <--插件(只负责读)-- HTTP <------
```

要点:

- 只有一个 worker、一个数据库。两端不是各存各的,是往同一处写。
- OpenCode 的写和读都走插件。
- DSH 的写走"worker 监听会话日志",读走 DSH 插件。这是我读源码得出的判断,见第 3 节。

---

## 2. OpenCode 端

插件源码在 `src/integrations/opencode-plugin/`(`index.ts`、`core.ts`、`v1.ts`、`v2.ts`)。

| 做什么 | 用的钩子 | 说明 |
|---|---|---|
| 记录工具调用 | `tool.execute.after` | 每次工具跑完发一条给 worker |
| 记录用户提问 | `chat.message` | 只取 user 角色 |
| 注入记忆 | `experimental.chat.system.transform` | 每次请求构建系统提示词时把记忆塞进去 |
| 压缩会话时清缓存 | `experimental.session.compacting` | 压缩后重新取一次记忆 |
| 一轮结束、会话删除 | 事件 `session.idle`、`session.deleted` | 触发总结、清理映射 |

出处:`v1.ts` 约 79 到 151 行,`contract.ts` 开头的对照表。V2 版本把这些钩子换成了另一套名字,`contract.ts` 和 `v2.ts` 里有一一对应表。

几个细节:

- 所有请求都带 `platform_source: "opencode"`(`core.ts:85`),worker 才不会把它记成默认的 `claude`。
- 记忆注入走的是系统提示词钩子,**不是改项目里的 `AGENTS.md`**。
- 取记忆的接口是 `/api/context/inject?cwd=...`(`core.ts:334`),默认再追加 `&platformSource=opencode`。
- 搜索工具 `claude_mem_search` 调的是 `/api/search/observations?query=...&limit=10`(`core.ts:440`),**不带来源参数**。

---

## 3. DSH 端

claude-mem 有官方的 DSH 集成,不是社区拼凑。

| 项 | 内容 | 出处 |
|---|---|---|
| 安装命令 | `npx claude-mem install --ide dsh --dsh-profile <名字>` | `npx-cli/index.ts:37` |
| 插件包名 | `@claude-mem/dsh` | `DeepSeekHarnessInstaller.ts:10` |
| 安装做的事 | 调 `dsh plugin --profile <名字> add` 装插件,再给 worker 加一条 transcript 监听 | `DeepSeekHarnessInstaller.ts:67、89` |
| 监听的目录 | `$DSH_HOME/sessions`,默认 `~/.dsh/sessions` | `DeepSeekHarnessInstaller.ts:48` |
| 插件配置 | `injectContext: true`,`ingest: false`,`summarize: false` | `dsh/cordis.patch.yml` |
| 运行时限制 | DSH 目前必须配 `--runtime worker`,不能用 server 模式 | `install.ts:1058` |

从这些推出的分工:

- 插件里 `ingest: false`、`summarize: false`,所以插件**只负责把记忆注入 DSH**,不负责写。
- 写入靠 worker 监听 `~/.dsh/sessions` 下的会话日志(`.jsonl.zstd`),按 `dsh/transcript-schema.json` 解析出用户消息、助手消息、工具调用、工具结果。
- 监听条目的名字是 `dsh`,而 worker 把"来源"取自监听名(`processor.ts:197`,经 `normalizePlatformSource`)。所以 DSH 写入的来源是 `dsh`。**已实测确认**(第 8 节)。

没读到的部分:

- DSH 插件本体 `dsh/lib/index.js` 在源码树里不存在(是构建产物),所以 DSH 取记忆时带不带来源参数,**未证实**。
- 本机 `desktop` profile 不能用官方安装器装,原因和手动做法见第 8 节。

---

## 4. 两端能不能互相看到:三道关卡

### 关卡一:项目名要一致

项目名怎么算(`src/utils/project-name.ts` 的 `getProjectName`),按优先级:

1. 命中了你配置的"命名环境"(`CLAUDE_MEM_PROJECT_ENVIRONMENTS`),用环境名。
2. 在 git 仓库里:默认用**仓库根目录的文件夹名**(`CLAUDE_MEM_PROJECT_NAME_SOURCE=path`);设成 `git-remote` 则用 origin 地址算出的 `组织/仓库`。
3. 不在 git 仓库里:找 claude-mem 标记目录,再不行用当前目录名。

结论和坑:

| 情况 | 结果 |
|---|---|
| 两端在同一个 git 仓库里启动(哪怕子目录不同) | 项目名一致,能共享 |
| 两个不同仓库恰好文件夹同名 | 项目名也相同,记忆会混在一起 |
| 一端在仓库里,另一端在仓库外的目录 | 项目名可能不同,互相看不到 |
| 仓库目录改名 | 默认模式下项目名跟着变,旧记忆对不上 |

想避开后两个坑,可以考虑 `CLAUDE_MEM_PROJECT_NAME_SOURCE=git-remote`。这是否对你的仓库合适,**未实测**。

### 关卡二:来源过滤要放开

默认情况下取记忆是"按来源过滤"的:OpenCode 只看到 `opencode` 来源的记忆,看不到 DSH 写的。

放开的开关是 `CLAUDE_MEM_SESSION_START_INCLUDE_ALL_SOURCES`,默认 `false`:

- 设成 `true` 后,OpenCode 插件取记忆时不再追加 `platformSource` 参数(`core.ts:334`)。
- 它是两端共用的开关,改了对 Claude Code 路径也生效(`handlers/context.ts:379`)。
- OpenCode 插件每次请求都重读这个文件,改完不用重启 OpenCode(`core.ts:70` 前的注释)。

另外两点:

- 搜索工具 `claude_mem_search` 本来就不带来源参数,所以搜索默认跨来源。这一条只读了插件侧,worker 侧是否另有默认过滤,**未证实**。
- `CLAUDE_MEM_CONTEXT_PROJECTS` 对 OpenCode 无效(插件不读这个键)。

### 关卡三:两端都得真的接上

| 检查项 | 怎么确认 |
|---|---|
| OpenCode 插件装上了 | 见 [[claude-mem-安装部署]] 里的自检清单 |
| DSH 插件装上了,监听加上了 | 看 `~/.claude-mem/` 下的 transcript 配置里有没有名为 `dsh` 的监听 |
| 都连的是同一个 worker | 两端的 `CLAUDE_MEM_WORKER_HOST` 和端口要一致,默认端口按 uid 算,你本机是 37701 |

---

## 5. 并发和重复

- 只有一个 worker 进程,所有端经它写库,没有"多进程抢着写数据库"的问题。worker 怎么发现和复用已有进程,见 `HealthMonitor.ts`,细节我没逐行读,**未证实**。
- 同一个项目里同时装 claude-mem 和别的记忆插件(包括已卸载的 opencode-mem),会各自注入一份,重复占上下文。opencode-mem 已经从本机卸掉,不再有这个问题。
- 如果 DSH 同时被 transcript 监听和别的路径写入,会不会重复记录:仓库里有 `tests/integrations/dsh-dedupe.test.ts`,说明作者处理过去重,具体逻辑我没读,**未证实**。

---

## 6. 想让两端共用,按这个顺序做

1. 先装 OpenCode 端,确认一条记忆能写进去、能搜到。
2. 再装 DSH 端:`npx claude-mem install --ide dsh --dsh-profile desktop --runtime worker`。
3. 两端在同一个 git 仓库里各开一次会话,各问一个有区别的问题。
4. 把 `CLAUDE_MEM_SESSION_START_INCLUDE_ALL_SOURCES` 改成 `true`,重启 DSH,看它的上下文里能不能出现 OpenCode 写的记忆。
5. 看不到就按三道关卡倒着查:先看 worker 是不是同一个,再看开关,最后看项目名。

查项目名和来源的办法:打开 worker 的网页界面(`http://127.0.0.1:37701`),记忆条目上有来源标签,项目名在筛选里。**网页具体入口是否如此,未实测。**

---

## 7. 未证实清单

| 项 | 状态 |
|---|---|
| DSH 写入的来源名是 `dsh` | **已实测**(第 8 节) |
| DSH 插件取记忆时带不带来源参数 | 插件本体是构建产物,没读到 |
| 搜索接口在 worker 侧是否默认按来源或项目过滤 | 只读了插件侧 |
| 两端同目录算出的项目名是否一致 | **已实测一致**(都是 `my-note`) |
| `git-remote` 模式对你的仓库是否合适 | 没实测 |
| DSH 去重逻辑 | 只看到有测试文件,没读实现 |
| DSH 的 `mem_search` 工具能否搜到 OpenCode 写的记忆 | 没测。只确认了"启动时注入"这一路 |
| DSH 会话末尾报 `Missing last_assistant_message`,导致那轮没有摘要 | 日志里见到,原因没查 |

---

## 8. 2026-11-09 本机实测(DSH 这一端)

**一句话:读、写、搜索三个方向都在本机通了。但 `desktop` 这个 profile 不能用官方安装器装,要手动做两件事。**

### 8.1 为什么官方安装器对 `desktop` 必败

- `npx claude-mem install --ide dsh --dsh-profile desktop` 内部会执行 `dsh plugin --profile desktop add …`。
- `dsh` 命令行把 `desktop` 这个名字写死拒绝:`@deepseek-ai/dsh/lib/bin.js` 第 36 行 `rejectElectronProfile`,报错 `profile "desktop" is managed exclusively by the Electron application`。**按名字判断,与桌面应用是否在运行无关。**
- 所以安装器会把 DSH 判为失败;只选了 DSH 一项时整体 `all-ides-failed` 中止。
- **副作用:这个失败的安装器仍然先把 claude-mem 本体升级了(15.12.0 到 15.12.1)并停掉了 worker**,要手动 `worker-service.cjs start` 拉起来。别对 `desktop` 反复跑它。
- 能装的只有其他名字的 profile(`web`、`headless` 等)。DSH 官方有没有给桌面版装插件的正规入口,**没查**。

### 8.2 手动做法(等价于安装器干的两件事)

| 步骤 | 做什么 | 备注 |
|---|---|---|
| 读:让 DSH 加载插件 | 在 DSH 配置仓库的 `desktop/package.json` 加依赖 `"@claude-mem/dsh": "link:../plugins/claude-mem-dsh"`,并把 `@claude-mem/dsh` 加进 `dsh.profile.bundles`,再 `pnpm install`、重启 DeepSeek Harness | 插件包从 `~/.claude/plugins/marketplaces/thedotmack/dsh/` 复制到配置仓库的 `plugins/claude-mem-dsh/`。**这份是复制品,claude-mem 升级后不会自动更新** |
| 写:让 worker 采集 DSH 会话 | 新建 `~/.claude-mem/transcript-watch.json`:监听名 `dsh`、路径 `~/.dsh/sessions`、`startAtEnd: true`、内嵌 `transcript-schema.json`;重启 worker | 本机的真文件放配置仓库 `~/.config/opencode/claude-mem/transcript-watch.json`,软链到 `~/.claude-mem/`。文件里没有密钥 |
| 放开来源过滤 | `settings.json` 设 `CLAUDE_MEM_SESSION_START_INCLUDE_ALL_SOURCES="true"` | OpenCode 插件每次实时读,不用重启 |

- `~/.claude/plugins/...` 这个目录是 claude-mem 本体的统一安装位置(源码 `shared/paths.ts:53`),不管装哪个客户端都会建。OpenCode 的 `claude-mem.js` 是单独打包放在 `~/.config/opencode/plugins/` 的,升级本体后要重跑 `npx claude-mem install --ide opencode` 才会更新。
- 想让 DSH 插件随 claude-mem 自动更新,可以把 `link:` 改成指向 `~/.claude/plugins/marketplaces/thedotmack/dsh` 的绝对路径。代价:换机器会失效,且升级后要重启 DSH。**没采用,仍是复制品。**

### 8.3 实测结果

| 项 | 结果 |
|---|---|
| DSH 会话被采集 | 通。库里出现 `platform_source=dsh` 的会话 |
| 来源名 | `dsh`,与源码推断一致 |
| DSH 提示词入库 | 通。"你好啊""你是有加载长期记忆的吗"都能搜到 |
| DSH 工具调用产生观察 | 通。让 DSH 查武汉天气(搜索网页、访问网页)后,出现观察 466、467,来源 `dsh` |
| 项目名与 OpenCode 一致 | 通,**但取决于在哪个目录开 DSH**:在 `~/ai-work/my-note` 开,项目是 `my-note`;在 `~/.config/opencode` 开,项目是 `opencode` |
| OpenCode 端能搜到 DSH 写的内容 | 通。搜"武汉天气",观察 466、467 排第 1、2 名 |
| DSH 能读到 OpenCode 写的记忆 | 通,**只确认"启动时注入"这一路**。DSH 自己回答"会话启动时注入了近期上下文摘要,即 50 条观察的概览";库里当时的观察全部来自 OpenCode,所以它读到的是 OpenCode 写的 |
| 只有问答、没有工具调用的会话 | 只产生摘要,**不产生观察** |

### 8.4 两个顺带发现

- DSH 当时联网搜索失败,观察 466 记的是"web_search 因 CodeBuddy API 返回 401 失败"。这是 DSH 自己的问题,与 claude-mem 无关。
- 日志出现 `ERROR Missing last_assistant_message in session for summary prompt`,在 DSH 会话第 4 轮结束时,该轮没生成摘要。不影响观察写入,原因没查。
