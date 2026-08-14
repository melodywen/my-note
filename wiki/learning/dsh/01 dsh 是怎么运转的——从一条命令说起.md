---
type: concept
status: developing
area: growth
tags: [learning, dsh, DeepSeek, cordis, 入门]
created: 2026-08-14
updated: 2026-08-14
---

# 01 dsh 是怎么运转的——从一条命令说起

## 你执行的那条命令到底发生了什么

当你敲下 `dsh web` 的时候，背后发生了这些事：

1. **`dsh` 程序启动**——它是一个 Node.js 脚本，入口在 `lib/bin.js`
2. **解析命令**——看到 `web` 这个子命令，知道你要启动 Web Profile
3. **找到配置目录**——去 `~/.dsh/profiles/web/` 找配置
4. **首次运行？**——如果是第一次，从模板自动创建配置文件
5. **装依赖**——在 Profile 目录下跑 `pnpm install`，把所有插件链接进来
6. **合成配置树**——把多层 YAML 配置叠加在一起，得到最终的插件列表
7. **启动 Cordis**——按配置树加载插件，启动 Web 服务器
8. **打开浏览器**——`http://127.0.0.1:3080` 就能用了

其中第 6 步"合成配置树"是 dsh 最核心的设计。接下来一步步讲。

## 一个关键比喻：积木

dsh 的整个设计可以用一个比喻来理解：**搭积木**。

- 每一块积木 = 一个**插件**（plugin）
- 不同积木搭出来的东西 = 一个 **Profile**
- 一袋配套的积木 = 一个 **Bundle**

dsh 官方给了你两袋配套积木：
- **dsh-base**：基础积木袋，里面有约 70 块积木（LLM 调用、会话管理、文件系统、Bash 执行、沙箱安全……）
- **dsh-web-app**：Web 积木袋，在基础之上加上 Web 服务器和前端 UI 组件

你搭出来的 Web Profile = 先把 dsh-base 的积木全部摆上，再把 dsh-web-app 的积木叠上去（有些会替换掉 base 的同名积木），最后加上你自己的修改。

## 什么是 Plugin（插件）

插件是 dsh 里**最小的功能单位**。每一个能力——不管是调模型、跑命令、读文件——都是一个插件。

比如：
- `dsh-llm` 这个插件负责调用大模型
- `dsh-tool-bash` 这个插件负责执行 Bash 命令
- `dsh-sandbox` 这个插件负责安全沙箱
- `dsh-session` 这个插件负责会话管理

插件之间不直接互相调用，而是通过一个**共享的上下文（Context）**来找到彼此。这就像一个集市——每个插件把自己的能力挂在集市的某个摊位上，需要用的人去摊位上找。

这个"摊位"就是一个 `ctx.xxx` 键，比如：
- `ctx.llm`——模型调用服务
- `ctx.tools`——工具注册表
- `ctx.sessions`——会话存储
- `ctx.fs`——文件系统
- `ctx.shell`——Shell 执行

> 官方文档原文：*"plugins contribute services, typed events, and reversible effects to a shared context"*
> 翻译：插件向共享上下文贡献服务、类型化事件和可逆副作用。

## 什么是 Bundle（积木袋）

Bundle 是**一组配套插件的分发格式**。它不是一个技术概念，而是一个打包概念——把一堆相关的插件和它们的配置打成一个 npm 包，方便分发。

一个 Bundle 包含：
1. 一堆插件代码（npm 依赖）
2. 一个 `cordis.patch.yml` 文件（声明要加载哪些插件、每个插件的配置）

dsh 目前有三个 Bundle：

| Bundle | 作用 | 对应的积木袋 |
|---|---|---|
| `dsh-base` | 基础能力：LLM、工具、会话、沙箱、凭据 | "基础袋"——每个 Profile 都必须用 |
| `dsh-web-app` | Web UI：服务器、前端 React 组件 | "Web 袋"——叠在 base 之上 |
| `dsh-headless` | 无界面运行器 | "Headless 袋"——替代 Web 袋 |

## 什么是 Profile（配置组合）

Profile 是**你最终搭出来的东西**。它决定用哪些 Bundle、怎么叠加、加什么自定义配置。

一个 Profile 就是一个目录，位于 `~/.dsh/profiles/<名字>/`，里面有：

```
~/.dsh/profiles/web/
├── package.json          ← 声明用哪些 Bundle
├── cordis.yml             ← 根配置（空壳，不用管）
├── cordis.patch.yml       ← 你的自定义修改（编辑这个！）
├── pnpm-workspace.yaml   ← pnpm 配置
└── node_modules/          ← 插件符号链接
```

其中 `package.json` 里写着：

```json
{
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",      // 先加载基础袋
        "@deepseek-ai/dsh-web-app"     // 再叠加 Web 袋
      ]
    }
  }
}
```

## 配置是怎么叠加的

这是 dsh 最精妙的设计：**配置不是写死的，是多层叠出来的**。

想象你在画一幅画：

```
第 1 层：空画布（cordis.yml，是个空数组 []）
    ↓
第 2 层：dsh-base 的积木摆上去（约 70 个插件）
    ↓
第 3 层：dsh-web-app 的积木叠上去（替换一些、新增一些）
    ↓
第 4 层：你的修改（cordis.patch.yml）
    ↓
第 5 层：命令行临时参数（--patch）
```

**后画的覆盖先画的**。如果第 3 层和第 2 层都有同一个插件，第 3 层的配置生效。

### 举个例子

dsh-base 里配了默认人设：
```yaml
- id: system-prompt
  config:
    persona: ''
```

dsh-web-app 覆盖了它：
```yaml
- id: system-prompt
  config:
    persona: 'You are a coding agent powered by the {{model}} model.'
```

如果你想在 `cordis.patch.yml` 里改成中文人设：
```yaml
- id: system-prompt
  config:
    persona: '你是一个由 {{model}} 驱动的编程助手。'
```

> [!warning] 注意：覆盖是整体替换，不是合并
> 如果一个插件有 3 个配置项，你只想改其中 1 个，也必须把 3 个都写出来。否则另外 2 个会丢失。

## 怎么看最终的配置

不用猜，直接看：

```bash
# 查看最终合成后的完整配置（含你的修改）
dsh --profile web --dump-config

# 只看默认配置（不含你的修改）
dsh --profile web --dump-default-config
```

这会打印出所有插件的完整列表和配置。大约 490 行、80+ 个插件。

## 小结

| 概念 | 一句话 | 比喻 |
|---|---|---|
| **Plugin** | 最小功能单位，提供某个能力 | 一块积木 |
| **Bundle** | 一组配套插件的分发包 | 一袋积木 |
| **Profile** | 你搭出来的最终配置 | 搭好的作品 |
| **ctx.xxx** | 插件之间找彼此的"摊位" | 集市摊位 |
| **Patch** | 对配置的修改，后层覆盖前层 | 画上的修改 |
| **cordis.patch.yml** | 你自己的修改入口 | 你的画笔 |

## 下一篇

- [[02 Cordis 框架入门——五个核心概念|02 Cordis 框架入门]]——理解 dsh 底层的插件机制
