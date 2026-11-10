---
type: concept
status: developing
area: growth
title: "claude-mem mode 文件与覆盖机制"
created: 2026-11-10
updated: 2026-11-10
tags:
  - learning
  - opencode
  - claude-mem
  - mode
  - 配置
related:
  - "[[claude-mem-调教清单]]"
  - "[[claude-mem-配置详解]]"
  - "[[claude-mem-存储与读取机制]]"
---

# claude-mem mode 文件与覆盖机制

> 一句话:**`CLAUDE_MEM_MODE` 不是"选一个文件",而是一个"配方":worker 按 `--` 把它拆成几个文件,从左到右依次叠加(后面的盖前面的),叠出来的结果就是观察者(observer)模型的完整系统提示词。想改 observer 的行为,新建一个只写要改的那几个键的 JSON 放到用户目录即可,不用碰插件文件。**
>
> 本篇的结论来自读 `plugin/scripts/worker-service.cjs`(约 v15.12.x)和 `plugin/modes/*.json`。标"推断"或"没实测"的地方,是读代码得出、还没跑过 worker 验证的。

---

## 1. 先弄清:mode 是什么

claude-mem 把每条工具调用交给一个后台模型(observer)总结成"观察"。**observer 看到什么提示词、被要求输出什么格式、该记什么该跳过什么,全部来自 mode。**

| 概念 | 说明 |
|---|---|
| mode 文件 | 一个 JSON,描述提示词文本、观察类型表、概念表 |
| `CLAUDE_MEM_MODE` | `settings.json` 里的一个键,值是 mode 的 ID(配方),默认 `code` |
| 当前值 | 本机是 `code--zh`(中文输出) |
| 看当前生效的是谁 | 开场注入第一行 `Mode: <name> (<id>)`,例如 `Mode: Code Development (Chinese) (code--zh)` |

---

## 2. 加载原理

### 2.1 ID 怎么拆

worker 的 `parseInheritance` 把 ID 按 `--` 切开:

```js
const [parentId, ...rest] = id.split("--");
overrideIds = rest.map(x => `${parentId}--${x}`);
```

实际跑出来(照抄源码逐字执行):

| `CLAUDE_MEM_MODE` | 底座(parent) | 叠加文件(按顺序) |
|---|---|---|
| `code` | `code` | 无 |
| `code--zh` | `code` | `code--zh` |
| `code--zh--lean` | `code` | `code--zh`、`code--lean` |
| `code--zh--lean--recv` | `code` | `code--zh`、`code--lean`、`code--recv` |

规则:**第一个 `--` 之前的词是底座;后面每一段 `X` 都变成 `底座--X`,各是一个叠加文件。**

所以会出现"`MODE` 里写 `code--zh--lean`,磁盘上却是 `code--lean.json`"这种名字对不上的现象:`lean` 是 `MODE` 的最后一段,对应的文件名要补上底座前缀。

### 2.2 去哪找这些文件

`loadModeFile` 的查找规则:

| 文件 | 是否内置 | 去哪找 |
|---|---|---|
| `code.json`(底座) | 内置 | 插件 `plugin/modes/` |
| `code--zh.json` 等语言文件 | 内置 | 插件 `plugin/modes/` |
| `code--lean.json`(自己建的) | 非内置 | **用户目录 `~/.claude-mem/modes/`** |

- 内置 mode 若同名文件也放在用户目录,会被**忽略并报错**(`bundled mode cannot be shadowed`),所以自建文件的名字不能和内置的重复。
- 环境变量 `CLAUDE_MEM_MODES_DIR` 可以指定另一个搜索目录,优先于用户目录。本机没设。
- 用户目录由数据目录算出,默认 `~/.claude-mem`。本机 `~/.claude-mem/modes` 是软链,指向 `~/.config/opencode/claude-mem/modes/`(和 `settings.json`、`.env` 一样随配置仓库走)。

### 2.3 怎么叠加(deepMerge)

```js
r = overrides.reduce((acc, m) => deepMerge(acc, m.mode), parent.mode);
validateMode(r);          // 合并之后才校验完整性
```

`deepMerge` 的行为:

| 被覆盖的值类型 | 行为 |
|---|---|
| 字符串(如 `prompts.skip_guidance`) | **整段替换**,不拼接 |
| 对象(如 `prompts`) | 递归合并:覆盖方写了的键盖掉,没写的沿用 |
| 数组(如 `observation_types`) | **整个数组替换**,不按元素合并(源码里数组被当作"非普通对象",直接取覆盖方的值) |

这三条决定了"能怎么写"。

### 2.4 校验发生在合并之后

`validateMode` 校验的是**叠完之后的整体**,所以叠加文件**不用写全**,只写要改的键就行。合并后必须满足:

- 顶层 `name`、`description`、`version` 是非空字符串;
- `prompts` 下 32 个必填键都存在且非空(`format_examples`、`xml_file_placeholder` 允许为空字符串);
- `observation_types` 至少 1 项,每项有 `id`、`label`、`description`、`emoji`、`work_emoji`;
- `observation_concepts` 至少 1 项,每项有 `id`、`label`、`description`;
- 每个 `id` 只能是小写字母、数字、连字符、下划线,且不能重复;
- `prompts.type_guidance` 必须**提到**每个类型的 `id`,`prompts.concept_guidance` 必须提到每个概念的 `id`(否则报错)。

### 2.5 失败时会怎样

| 失败原因 | 结果 |
|---|---|
| 叠加文件找不到、JSON 语法错误、合并后缺键 | 记一条错误日志,**回退到内置 `code`(英文)**,不是崩溃 |
| 文件内容类型不对(顶层不是对象) | 同上,抛 `Jw` 类错误,直接失败不回退 |
| 连内置 `code` 也读不到 | 抛 `Critical` 错误,worker 起不来 |

所以写错文件的后果通常是"observer 突然变回英文",看 `Mode:` 行就能发现。

### 2.6 `MODE` 里的名字校验

校验正则只允许**单个文件名**里出现一个 `--`:

```
/^[a-z0-9]+(?:-[a-z0-9]+)*(?:--[a-z0-9]+(?:-[a-z0-9]+)*)?$/
```

它校验的是拆开后的每个文件名(`code--zh`、`code--lean`),不是整串 `MODE`。所以 `code--zh--lean--recv` 这种多段串合法(已拿同一个正则逐个验证)。

---

## 3. 最终提示词是怎么拼出来的

observer 每次拿到一条工具调用,系统提示词由 `QGe` 按**固定顺序**拼接:

```
system_identity        你是谁(claude-mem 的观察者)
observer_role          你的职责
spatial_awareness      工作目录等路径提示
recording_focus        ★ 该记什么
skip_guidance          ★ 该跳过什么
output_format_header   输出格式标题
<observation> 模板
  type            ← observation_types 的 id 列表自动生成
  type_guidance   ← 类型说明(必须提到每个 id)
  title / subtitle / facts / narrative / concepts / files 的占位符
  field_guidance
format_examples        示例(可为空)
footer                 收尾约束
```

另外还有"继续观察""进度摘要"等场景用的另一批键(`header_*`、`continuation_*`、`summary_*`)。

**observer 回复只有两类被认可:**
- 一个或多个 `<observation>…</observation>`;
- `<skip_summary reason="…" />`(解析器看到它就返回空观察列表,不写库)。

别的格式会被再问一次,仍不对就丢弃。

---

## 4. 一个 mode JSON 里能写什么

### 4.1 顶层键

| 键 | 类型 | 作用 | 叠加文件要不要写 |
|---|---|---|---|
| `name` | 字符串 | 显示名,出现在 `Mode:` 行 | 建议写,否则显示底座或上一个文件的名字,分不清是否生效 |
| `description` | 字符串 | 说明 | 不用 |
| `version` | 字符串 | 版本 | 不用 |
| `observation_types` | 数组 | 观察的**类型表** | 只在要改类型时写,且要写**完整数组** |
| `observation_concepts` | 数组 | 观察的**概念标签表** | 同上 |
| `prompts` | 对象 | 32 个提示词键,见 4.3 | 写要改的那几个 |

### 4.2 类型表和概念表(`observation_types` / `observation_concepts`)

默认 `code` 里:

**9 种类型**(每项 `id`、`label`、`description`、`emoji`、`work_emoji`):

| id | 含义 | emoji |
|---|---|---|
| `bugfix` | 修好了坏掉的东西 | ● |
| `feature` | 新增能力 | ◆ |
| `refactor` | 重构,行为不变 | ↻ |
| `change` | 一般修改(文档、配置等) | ✓ |
| `discovery` | 了解到现有系统的情况 | ○ |
| `decision` | 带理由的架构/设计选择 | ⚖ |
| `security_alert` | 需要先处理的安全问题 | ⚠ |
| `security_note` | 值得记录但不紧急的安全观察 | ⚷ |
| `sensitive` | 不算隐私、但不该在错误场景外泄的信息 | ⊘ |

**7 种概念**(每项 `id`、`label`、`description`):`how-it-works`、`why-it-exists`、`what-changed`、`problem-solution`、`gotcha`、`pattern`、`trade-off`。

**这两个表影响三处:**
1. 提示词里的 `<type>[ a | b | c ]</type>` 自动按表生成;
2. 开场注入的图例(`●bugfix ◆feature …`)和每条记忆前的图标;
3. 校验:`type_guidance` 必须提到每个类型 id,`concept_guidance` 必须提到每个概念 id。

**改它的代价:**
- 是**整数组替换**:想加一种类型,必须把原来 9 个连同新的一起写;
- 同时要改 `type_guidance`,让它提到新 id,否则校验失败;
- 库里已有的旧类型值不会被改写,但旧类型若不在新表里,图标会回退成默认的 📝(`getTypeIcon` 找不到时的兜底)。
- 本机的整理脚本用到的 `decision`、`discovery`、`problem-solution`、`gotcha`、`trade-off` 都来自这两个表,**别删**。

内置还有 `law-study`(6 类型 6 概念)、`email-investigation`(6 类型 6 概念)两个**非代码领域**的 mode,可以对照看别人怎么改类型表。

### 4.3 `prompts` 下的 32 个键

按用途分组。"改它能干什么"是我根据拼装位置的**推断**,没逐个实测。

**A. 角色与任务(每次都进系统提示词)**

| 键 | 默认内容 | 改它能干什么 |
|---|---|---|
| `system_identity` | 你是 claude-mem 的观察者 | 换身份口吻 |
| `observer_role` | 监视另一个会话、生成观察 | 调整职责范围 |
| `spatial_awareness` | 工具执行带工作目录,用来判断路径 | 一般不动 |

**B. 该记什么、该跳过什么(最常改)**

| 键                 | 默认内容                                                                                    | 改它能干什么              |
| ----------------- | --------------------------------------------------------------------------------------- | ------------------- |
| `recording_focus` | `WHAT TO RECORD`:只记持久的技术信号,附好/坏例子;"本会话已记过的事实不要再记"                                       | 收紧或放宽记录标准,比如只记决策和踩坑 |
| `skip_guidance`   | `WHEN TO SKIP`:已记过的、空状态检查、无错误的安装、无后续发现的文件列表、查无结果的研究;回 `<skip_summary reason="noise" />` | 加入"某类操作一律跳过"        |

`code--chill.json` 就是靠重写这两个键,把 observer 改成"只记痛苦才能重新发现的东西"的选择性模式,可作写法参照(该文件是语言变体之外的风格变体,按 `code--<风格>` 命名)。

**C. 输出格式**

| 键 | 作用 |
|---|---|
| `output_format_header` | 输出格式标题 |
| `type_guidance` | `type` 字段的取值说明(必须提到每个类型 id) |
| `concept_guidance` | `concepts` 字段的取值说明(必须提到每个概念 id) |
| `field_guidance` | `facts`、`narrative` 等字段怎么写 |
| `format_examples` | 示例(默认空;可放示例引导风格) |
| `footer` | 收尾约束:只生成观察,别干别的 |
| `xml_title_placeholder` 等 8 个 | 各 XML 字段里的占位提示,如标题长度、一句话说明 ≤24 词 |

**D. 摘要与续接场景**

| 键 | 作用 |
|---|---|
| `header_memory_start`、`header_memory_continued`、`header_summary_checkpoint` | 各阶段的标题行 |
| `continuation_greeting`、`continuation_instruction` | 续接观察时的开场与要求 |
| `summary_instruction`、`summary_context_label`、`summary_format_instruction`、`summary_footer` | 会话摘要的写法 |
| `xml_summary_request_placeholder` 等 6 个 | 摘要各字段的占位提示 |

**E. 语言(中文 mode 就是改这一批)**

`code--zh.json` 只覆盖 15 个键,全是"输出语言"相关:`footer`、`continuation_instruction`、`summary_footer`,以及 12 个 `xml_*_placeholder`。其中 `continuation_instruction` 末尾追加了 `Please write the observation data in 中文`。其余键沿用底座英文。

---

## 5. 怎么新建一个叠加文件

### 5.1 步骤

1. 文件放 `~/.claude-mem/modes/code--<名字>.json`(本机即 `~/.config/opencode/claude-mem/modes/`)。名字用小写字母、数字、连字符,且不能和内置文件重名。
2. 只写要改的键,外加一个 `name`。
3. 把 `CLAUDE_MEM_MODE` 改成 `code--<语言>--<名字>`(想要中文就带上 `zh`,放在前面)。
4. 重启 worker(推断:`loadMode` 在启动时加载,没验证是否热读)。
5. 验证:看开场注入的 `Mode:` 行,再观察新记忆的数量和内容。

### 5.2 最小例子:让 observer 跳过"记忆维护调用"和"操作回执"

文件 `~/.claude-mem/modes/code--lean.json`(**已建并已启用**,2026-11-10)。

**磁盘上写的是英文,中文只是给人审的对照。** observer 的底座提示词是英文,规则也写英文,风格统一;中文版在本节后面,改规则时先改中文版审定,再译成英文写进文件。

磁盘文件原文(实际生效):

```json
{
  "name": "Code Development (Chinese, lean)",
  "prompts": {
    "skip_guidance": "WHEN TO SKIP\n------------\nSkip routine operations:\n- A fact, decision, or fix status you have already recorded earlier in this session, even if phrased differently. This especially applies to iterative loops (PR review rounds, retry cycles, polling) that re-confirm the same outcome multiple times - record it ONCE on first confirmation, then skip all later re-confirmations of the identical fact.\n- Empty status checks\n- Package installations with no errors\n- Simple file listings with no follow-on finding\n- File related research that comes back empty or not found\n- Memory-maintenance calls whose content is already stored as a memory: writing a merged memory (write_memory.py, save_memory, /api/import), archiving or deleting old memories (archive_delete.py), restoring from an archive (restore_archive.py), and lookups that only confirm those memory IDs exist or are gone. Skip them even if the output contains detailed facts: those facts are already in the stored memory, so recording them again only duplicates it. Record such a call only if it FAILED (non-zero exit, error, or rejected input) or revealed a bug in the tooling itself.\n- Other operation receipts that only state a step was performed, or that its result matched expectations (e.g. a commit or push completed). Record such a receipt only if its result was unexpected, or if it contains a decision, root cause, or gotcha.\n\nIf skipping, reply with exactly <skip_summary reason=\"noise\" /> (a short reason in the attribute) and nothing else. Never reply with an empty response or explain the skip in prose."
  }
}
```

中文对照(**不放进配置**,只给人审):

```text
何时跳过
------------
跳过例行操作:
- 本会话中你已经记录过的事实、决策或修复状态,即使换了说法也不要再记。尤其是反复确认同一结果的循环(评审轮次、重试、轮询):只在第一次确认时记一次,之后对同一事实的再次确认一律跳过。
- 空的状态检查
- 没有报错的软件包安装
- 没有后续发现的简单文件列表
- 查无结果的文件相关调研
- 内容已存进记忆库的记忆维护类调用:写入融合记忆(write_memory.py、save_memory、/api/import)、归档或删除旧记忆(archive_delete.py)、从归档恢复(restore_archive.py),以及只为确认这些记忆 ID 存在或已消失的查询。即使输出里有很详细的事实也跳过:这些事实已经在写入的记忆里了,再记一遍只是重复。只有调用失败(退出码非零、报错、输入被拒),或暴露了工具本身的缺陷时才记。
- 其他只说明"做了某一步"或"结果符合预期"的操作回执(例如提交或推送完成)。这类回执只有在结果出乎意料,或其中包含决策、根因、踩坑时才记。

如果要跳过,请严格只回复 <skip_summary reason="noise" />(reason 属性里写一句简短理由),不要回复其他任何内容。不要回复空内容,也不要用文字解释为什么跳过。
```

**要点:**
- `skip_guidance` 是字符串,覆盖是**整段替换**,所以默认的 5 条要自己抄一遍,只在后面追加新条(现在是第 6、7 条);
- 末尾 `<skip_summary reason="noise" />` **必须原样保留**:worker 用正则 `/<skip_summary(?:\s+reason="([^"]*)")?\s*\/>/i` 解析,写错一个字符就会被当成格式错误,再问一次,仍不对就丢弃。`reason` 属性里的理由可以写中文;
- `MODE` 要写 `code--zh--lean`(带 `zh` 才保留中文)。

**第 6 条第一版的实测结果(2026-11-10 11:08,失败):** 一次整理三组共 8 条旧记忆,新增 7 条过程记忆。其中 #1813、#1815、#1817 各自紧跟一条真融合记忆(同一秒生成,标题几乎一字不差,正文是"第 N 组融合为 #XXXX……"),#1818 是"三组均完成并归档"。这 4 条正是第 6 条点名要跳过的回执,**一条都没跳**。判断原因(推断,没法区分):回执正文夹着具体细节(如"created_at 置为当前时间规避相同时间戳跳过"),observer 把它当成"含踩坑"走了例外口子。

**所以改成第二版(现行):** 不再让 observer 判断"内容有没有踩坑",改成按**调用类型**一刀切——记忆维护类调用(write_memory.py、archive_delete.py、restore_archive.py、保存/查询记忆)内容已存进记忆库,**即使输出有详细事实也跳过**,只有**调用失败**或**暴露工具本身的缺陷**才记;提交推送类回执保留原来的判断标准,拆成第 7 条。风险:调试这些脚本本身时,真实发现也可能被跳过;规则依赖脚本名,脚本改名要同步改。第二版效果见下一节的复测。

---

**第一版的设计思路(保留作参考):** 写成"判断标准"而不是"清单"。
- 判断标准:这条记录**只说明做了某一步,或结果符合预期**吗?是就跳过;
- 保留口子:**这类回执**如果结果出乎意料,或包含**决策、根因、踩坑**,仍然要记。(措辞曾写成"只有出乎意料的结果……才记",没限定"这类回执",可能被 observer 读成"所有观察都只有这几种才记"而过度跳过,所以改成现在的写法,把范围锁在第 6 条(第一版)自己身上。)比如"复查发现删除没生效"是坑,会被记下来;"复查确认删除生效"只是回执,会被跳过;
- 覆盖面比"只管记忆整理"更宽:提交、推送完成也算回执。代价是误伤风险更高,上线后要观察几天,看有没有真正有价值的修复被跳过。

**英文对照**(给以后对照用,**不放进提示词**,放进去每次调用都多读一遍):

默认英文原文(`code.json` 的 `skip_guidance`):

```text
WHEN TO SKIP
------------
Skip routine operations:
- A fact, decision, or fix status you have already recorded earlier in this session, even if phrased differently. This especially applies to iterative loops (PR review rounds, retry cycles, polling) that re-confirm the same outcome multiple times - record it ONCE on first confirmation, then skip all later re-confirmations of the identical fact.
- Empty status checks
- Package installations with no errors
- Simple file listings with no follow-on finding
- File related research that comes back empty or not found

If skipping, reply with exactly <skip_summary reason="noise" /> (a short reason in the attribute) and nothing else. Never reply with an empty response or explain the skip in prose.
```

加了第 6、7 条之后的英文版本(**就是磁盘文件里的内容**,中文对照与它逐条对应):

```text
WHEN TO SKIP
------------
Skip routine operations:
- A fact, decision, or fix status you have already recorded earlier in this session, even if phrased differently. This especially applies to iterative loops (PR review rounds, retry cycles, polling) that re-confirm the same outcome multiple times - record it ONCE on first confirmation, then skip all later re-confirmations of the identical fact.
- Empty status checks
- Package installations with no errors
- Simple file listings with no follow-on finding
- File related research that comes back empty or not found
- Memory-maintenance calls whose content is already stored as a memory: writing a merged memory (write_memory.py, save_memory, /api/import), archiving or deleting old memories (archive_delete.py), restoring from an archive (restore_archive.py), and lookups that only confirm those memory IDs exist or are gone. Skip them even if the output contains detailed facts: those facts are already in the stored memory, so recording them again only duplicates it. Record such a call only if it FAILED (non-zero exit, error, or rejected input) or revealed a bug in the tooling itself.
- Other operation receipts that only state a step was performed, or that its result matched expectations (e.g. a commit or push completed). Record such a receipt only if its result was unexpected, or if it contains a decision, root cause, or gotcha.

If skipping, reply with exactly <skip_summary reason="noise" /> (a short reason in the attribute) and nothing else. Never reply with an empty response or explain the skip in prose.
```

中英逐条对应:

| #     | 英文(默认)                                                                                                          | 中文版                                             |
| ----- | --------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| 1     | A fact, decision, or fix status you have already recorded earlier in this session, even if phrased differently… | 本会话中你已经记录过的事实、决策或修复状态,即使换了说法也不要再记…              |
| 2     | Empty status checks                                                                                             | 空的状态检查                                          |
| 3     | Package installations with no errors                                                                            | 没有报错的软件包安装                                      |
| 4     | Simple file listings with no follow-on finding                                                                  | 没有后续发现的简单文件列表                                   |
| 5     | File related research that comes back empty or not found                                                        | 查无结果的文件相关调研                                     |
| 6(新增,第二版) | Memory-maintenance calls whose content is already stored as a memory… Record such a call only if it FAILED… | 内容已存进记忆库的记忆维护类调用…只有调用失败…才记 |
| 7(新增) | Other operation receipts that only state a step was performed, or that its result matched expectations… | 其他只说明"做了某一步"或"结果符合预期"的操作回执… |
| 末尾    | If skipping, reply with exactly `<skip_summary reason="noise" />`…                                              | 如果要跳过,请严格只回复 `<skip_summary reason="noise" />`… |

### 5.3 一个文件只做一件事,多个文件按需组合

| 文件 | 管哪个键 | 效果 |
|---|---|---|
| `code--lean.json` | `skip_guidance` | 记忆维护类调用(写入/归档/恢复记忆)一律跳过,除非失败;其他操作回执(提交推送等)结果符合预期就跳过 |
| `code--focus.json`(设想) | `recording_focus` | 只记决策、踩坑、已发布的修复 |
| `code--tags.json`(设想) | `observation_concepts` + `concept_guidance` | 增加自定义概念标签 |

用法:`MODE` 写成 `code--zh--lean--focus`,想关掉哪个就删掉那一段名字,不用改文件。

**冲突规则:** 两个文件都写了同一个键,**后面的整段盖掉前面的**,不拼接。所以多个叠加文件应该管**不同的键**;若必须改同一个键,后一个要把前一个的内容也写全。

---

## 6. 它能做什么、不能做什么

| 能做 | 不能做 |
|---|---|
| 改 observer 的语气、记录标准、跳过规则 | 改"哪些工具调用会进入 observer"(那是 `SKIP_TOOLS`、`SKIP_BASH_PATTERNS`,在入队前拦) |
| 改观察的类型表、概念表、字段写法 | 改观察存哪、怎么检索 |
| 改输出语言 | 保证 observer 一定照做:提示词是给 LLM 的文字,是**软规则** |
| 不碰插件文件,插件升级不会被覆盖 | 区分主会话和子会话(OpenCode 插件不传 `agentId`) |

**有一句硬编码的话 mode 改不了。** 每次发给 observer 的指令里,在 `skip_guidance` 之外还有一段写死在 worker 里的文字:

> Return either one or more `<observation>` blocks, or `<skip_summary reason="noise" />` if this tool use should be skipped. **Concrete debugging findings from logs, queue state, database rows, session routing, or code-path inspection count as durable discoveries and should be recorded.**

意思是:读日志、读数据库、读源码得到的具体发现,算持久发现,应当记录。它和 `skip_guidance` 并存,mode 覆盖不到。实测的后果:调研类的工具调用(读源码、读配置)大多被它放行,是 my-note 过程记忆里最大的一类。所以 `skip_guidance` 加的第 6、7 条,**主要想压"记忆维护调用"和"操作回执"这两类,压不住"调研发现"这一类**。

**和 `SKIP_TOOLS` 的区别:**
- `SKIP_TOOLS`:门口的保安,按工具名拦,**硬规则**,但只能按工具名;
- mode 的 `skip_guidance`:记账员的规则本,看到内容后自己判断,能按"这件事是不是整理回执"来跳过,但**不保证**。

两者可以同时用。

---

## 7. 风险与注意

1. **`MODE` 是全局的。** 改了影响所有项目、所有会话,不是只影响 `my-note`。
2. **改完要重启 worker(推断)。** 重启会中断正在被记录的会话,包括别的窗口。
3. **写错的后果是回退英文,不是崩溃。** 但也可能是静默的:observer 变成英文,内容照记,只有看 `Mode:` 行才知道。
4. **数组整体替换。** 改类型表、概念表时漏写原有项,等于删了它们。
5. **别删本机整理脚本依赖的类型和概念。** `decision`、`discovery`、`problem-solution`、`gotcha`、`trade-off` 要保留。
6. **自建文件不要和内置重名。** 内置有 `code--ar`、`code--zh`、`code--chill` 等 30 多个语言/风格文件(用 `ls plugin/modes` 看全),重名会被忽略并报错。
7. **提示词越长越贵。** observer 每条工具调用都要读一遍系统提示词,叠加的内容越多,每次调用的 token 越多(推断,没测)。

---

## 8. 回退

- 改回 `CLAUDE_MEM_MODE` 原值(`code--zh`),重启 worker;
- 叠加文件可以留在目录里,不被引用就不起作用;
- 想彻底去掉,删 `~/.config/opencode/claude-mem/modes/` 下对应文件(软链指向这里)和 `~/.claude-mem/modes` 软链。

---

## 9. 本机现状(2026-11-10)

| 项 | 状态 |
|---|---|
| `CLAUDE_MEM_MODE` | `code--zh--lean`(2026-11-10 10:56 启用;11:13 第二版规则写入后再次重启 worker) |
| `~/.config/opencode/claude-mem/modes/code--lean.json` | 已建,**英文**,内容见 5.2 |
| `~/.claude-mem/modes` | 软链到上面的目录 |
| 是否启用 | **是**。开场注入第一行为 `Mode: Code Development (Chinese, lean) (code--zh--lean)`,worker 日志有 `Mode loaded: code--zh--lean`,无回退报错 |
| 重启时的警告 | 日志有 `Self-replacing worker handoff did not verify in time — falling back to CLI spawn`:旧 worker 没能自己交接,退回命令行拉起了新的(pid 74935);mode 已正常加载,没深究原因 |
| 启用前基线 | my-note 最大观察 ID 1787,共 1256 条 |
| 第一版规则测试 | 11:03–11:08 测两次,结果见 9.2 |
| 第二版规则 | 11:13 重启后生效,此时 my-note 最大观察 ID 1824,效果见 9.3 |
| 硬规则 `SKIP_BASH_PATTERNS` | 已写进 `settings.json` 与 `settings.example.jsonc`,**对 OpenCode 无效**(见 9.4) |

---

### 9.1 启用前的基线(拿来对比效果)

按标题关键词粗分(不精确),`my-note` 项目 #1505 之后新增 121 条观察:

| 类型 | 大致条数 | 规则能不能挡(第一版的预期) |
|---|---|---|
| 整理回执(已写入、已归档、已删除) | 约 10 | 能,正是它针对的 |
| 提交推送回执 | 约 8 | 能(第一版写了"提交或推送完成";第二版挪到第 7 条) |
| 复核确认某事实 | 约 15 | 只挡"结果符合预期"的一部分 |
| 读源码、读配置的调研发现 | 约 47 | **不能**(被上面那句硬编码放行) |
| 改 SKILL.md 的改动记录 | 约 15 | 不能 |
| 其他 | 约 37 | 不确定 |

另一个基线:一次整理产生约 3 到 4 条过程记忆。

启用后的对比方法:同样做一次整理,数新增条数;再看前三类的条数有没有明显下降。**预期只会压住前两类和第三类的一部分,不会压住调研发现**,如果调研类也少了,说明 observer 把规则理解得比字面更宽。

### 9.2 第一版规则的实测(11:03 与 11:08)

规则:单条"操作回执"(含记忆整理回执与提交推送回执),按"结果符合预期就跳过,出乎意料或含决策/根因/踩坑才记"判断。

| 测试 | 整理量 | 新增过程记忆 | 其中本该被跳过的回执 | 被跳过 |
|---|---|---|---|---|
| 11:03 一组(#1735+#1760) | 2 条合 1 | #1803(#1804 是准备素材时产生,不算) | #1803 一条 | 0 |
| 11:08 三组(8 条合 3 条) | 3 组 | 7 条:#1809–#1811(判断与决策)、#1813、#1815、#1817(融合记忆的转述)、#1818(完成并归档) | #1813、#1815、#1817、#1818 共 4 条 | **0** |

另有 2 条(#1819、#1820)属于另一个窗口的无关工作,不计。

**结论:** 规则已加载,但 4 次该跳的回执 0 次被跳,没有可见效果。每次融合记忆写入后,observer 紧跟着再记一条转述(时间戳同一秒),这是最稳定的过程记忆来源。原因推断:回执正文夹着具体细节,observer 把它当成"含踩坑"走了例外口子。没法区分是"规则太弱"还是"例外口子被滥用"。

### 9.3 第二版规则(11:13 起)的复测

第二版把记忆维护类调用单独拆成第 6 条,按**调用类型**一刀切,例外只留给调用失败。复测方法:

1. 新窗口发一个会触发多组整理的任务;
2. 记下发任务前 my-note 的最大观察 ID(第二版生效时为 1824,可用作起点,但要排除之后产生的无关条目);
3. 数新增条数,逐条判断是不是"融合记忆的转述"或"整理完成回执";
4. 对比 9.2:同样 3 组整理,第一版产生 7 条,看第二版能降到几条;
5. 同时检查有没有误伤:调试 `write_memory.py` 等脚本本身时,有价值的发现是否被跳过。


**第二版实测结果(11:17,1 组融合):** ID 1831 之后 7 条,其中 #1832 是准备测试时产生的不计;#1837 是真融合记忆;**#1838「将 #182 与 #256 融合为 #1837……」是转述,该被第 6 条跳过,没跳**。整理完成回执这次没出现(不知道是被跳过还是没生成)。累计两版:该跳的转述 0/4 被跳。样本小(这次只融合一组),但方向一致:`skip_guidance` 对这类按调用类型写的规则,flash 级 observer 基本不遵守。

### 9.4 改用硬规则 `SKIP_BASH_PATTERNS`:对 OpenCode 无效

想法:转述的源头是 observer 看到 `write_memory.py` 等脚本的 Bash 调用,用 `CLAUDE_MEM_SKIP_BASH_PATTERNS` 在入队前按命令文本拦,不靠模型听话。

**探针实测(2026-11-10):** 规则 `memory-consolidate/scripts/(write_memory|archive_delete|restore_archive)\.py`,往 `/api/sessions/observations` 发三条完全相同的命令,只改 `tool_name`:

| tool_name | 结果 |
|---|---|
| `Bash` | `skipped`,`bash_pattern_excluded` |
| `bash` | `queued` |
| `shell` | `queued` |

**原因(读源码确认):** worker 里取命令文本的函数只认 `Bash`、`PowerShell`(取 `command`)和 `exec_command`(取 `cmd`),是严格相等判断;OpenCode 的命令工具叫小写 `bash`,拿不到命令文本,正则根本没被检查。插件 `~/.config/opencode/plugins/claude-mem.js` 上报前只把 `read/write/edit` 改成首字母大写,没有 `bash`。库里 `tool_uses` 139 条全是小写 `bash`,0 条 `Bash`。

**这条旧结论其实早就在了**(调教清单第 3 轮已写"无效"),这次是重复验证。

**没打补丁的原因:** 插件文件与官方 `dist/opencode-plugin/index.js` 逐字节相同,是安装时拷过来的压缩产物,没进配置仓库的 git,升级或重装会被覆盖且无提示。

**现状:** 规则已配上,对 OpenCode 不生效,留着无害,上游若让 worker 或插件认小写 `bash` 就会自动生效。已向上游提 issue:https://github.com/thedotmack/claude-mem/issues/5666(同类的 PowerShell 问题是 #4745,已由 #4762 修复)。

## 10. 没验证的清单

1. 多段 `MODE`(如 `code--zh--lean`)在真实 worker 里合并后的效果:只读了代码、跑了拆分函数,**没启动 worker 看合并结果**。
2. 改 `MODE` 后是否必须重启 worker:`loadMode` 看起来在启动时调用,**没验证**是否热读。
3. `skip_guidance` 能压住多少整理回执类的观察:第一版 0/3、第二版 0/1,累计 0/4(见 9.2、9.3),样本小。
4. 数组类键(`observation_types`)整体替换的行为:读 `deepMerge` 得出("数组不是普通对象,取覆盖方"),**没实测**。
5. 叠加文件数量上限、提示词变长对成本的影响:源码里没找到上限,成本没测。
6. 本机两份配置(`~/.claude-mem/settings.json` 与 `~/.config/opencode/claude-mem/settings.json`):已确认前者是软链指向后者,是同一个文件。
7. DSH 端是否读同一个用户 mode 目录:没查。
9. 第 6、7 条只管"记忆维护调用"和"回执",**不管"中间步骤"**(如"撰写合并记忆正文""精简正文"这类为得出结论而做的中间一步)。内置 `code--chill` 的 `recording_focus` 有"Incremental steps toward a goal (just record the final result)",是同一个意思。已想好第 8 条草稿(见 12 节),**暂不加**,先测第二版第 6、7 条的效果。
8. 第 6、7 条与那句硬编码的"调试发现应当记录"冲突时,observer 听谁的:没测。基线表里的分类是按标题关键词粗分的,不是读全文判定。

---

## 11. 速查

```
CLAUDE_MEM_MODE = code--zh--lean
                   │     │    └─ 叠加 code--lean.json   (用户目录,自建)
                   │     └────── 叠加 code--zh.json     (插件内置,中文)
                   └──────────── 底座 code.json         (插件内置,32 个键齐全)

合并:底座 ← zh ← lean,后者盖前者;字符串整段换,对象递归合并,数组整体换
校验:合并之后才校验;缺键/类型错 → 回退到内置 code(英文)
看生效:开场注入第一行 "Mode: <name> (<id>)"
```

---

## 12. 候选第 8 条:中间步骤(暂不启用)

**为什么有这条:** 第 6、7 条管的是"记忆维护调用"和"回执",不管"中间步骤"(为得出结论而做的草稿、修改、复查)。库里 #1508「撰写合并记忆正文」、#1509「精简合并记忆中退出码测法建议」就属于后者。

**难点:** observer 逐条看工具调用,能看到之前的调用(日志里 `messagesInContext` 在涨),但**看不到后面还有没有**,没法判断"这是不是最终结论"。所以不能写成"只记最终结果",要写成它当场能判断的标准。

英文(写进配置的版本):

```text
- Intermediate steps toward a goal (drafting or editing a text, trying a variant, re-checking, preparing inputs). Record the outcome once it is finished or a stable conclusion is reached; skip the steps in between unless a step by itself reveals a new fact, decision, or gotcha.
```

中文(给人审):

> 为达成某个目标而做的中间步骤(起草或修改文本、尝试某个写法、复查、准备输入)。等结果完成或得出稳定结论时再记一次;中间各步不记,除非某一步本身就揭示了新的事实、决策或踩坑。

**风险:**
- 比第 6、7 条更容易误伤:一次真正的发现,如果 observer 觉得"还没到稳定结论",可能被跳过;
- 那句写死在 worker 里的"调试发现应当记录"会和它冲突,调研类仍可能被放行;
- "稳定结论"observer 自己也未必判断得准。

**怎么上:** 先只用第二版第 6、7 条测一轮,数条数;再决定加不加第 8 条。一次只加一条,否则条数下降时分不清是哪条起的作用。加了要再重启一次 worker。
