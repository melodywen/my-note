---
type: reference
status: done
area: growth
tags: [learning, dsh, 社区插件, 视觉, 多模态, modlens, 对比分析, 有出处]
created: 2026-09-26
updated: 2026-09-26
---

# 02 modlens 视觉插件——为什么 dsh-learn 不需要它

> [!info] 版本锚点
> - dsh-learn：master `97914d7`（含 codebuddy-web-search 插件）
> - codebuddy-llm-v2：37 个模型，35 个 `supportsImages: true`
> - modlens：`@liustack/modlens@3.26.1`（截至 2026-09 最新）
> - 调研来源：[modlens GitHub README](https://github.com/liustack/modlens)、[dsh-plugin.org 页面](https://dsh-plugin.org/plugins/liustack/modlens)、[SkillHub 页面](https://skillhub.cloud.tencent.com/plugins/liustack/modlens)

## 这篇在讲什么

[[00 社区插件全景——4312 个插件、23 个分类|上一篇]] 把社区插件摊开成 23 类地图，其中第 15 类是 **视觉与多模态（Vision & Multimodal, 111 个）**。这个类别的头牌就是 **modlens**——自称"dsh 最强视觉插件"。

本文回答一个问题：**dsh-learn 需不需要装 modlens？**

结论先行：**不需要**。原因是 dsh-learn 走 CodeBuddy IOA 通道，后端模型已原生支持视觉；modlens 解决的是"纯文本模型看不见图"的问题，而 dsh-learn 没有这个问题。

---

## 一、modlens 是什么

> **出处**：[modlens GitHub README](https://github.com/liustack/modlens)—— *"Give a text-only model sight, and just paste the image."*

modlens 是 [@liustack](https://github.com/liustack) 开发的 dsh 视觉插件，解决的问题非常明确：

**dsh 官方后端的 DeepSeek-V4-Flash/Pro 是纯文本模型，`supportsImages: false`，不能处理图片。** modlens 给这类模型"外挂"一双眼睛——把图片发送给外部视觉引擎（Gemini / Antigravity CLI / 复用其他 harness 的登录），转成结构化 JSON 文本（OCR + 版面 + 实体 + 关系），再喂给纯文本模型。

### 工作流程

```
用户粘贴图片
     │
     ▼
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  modlens    │────▶│  外部视觉引擎     │────▶│  结构化 JSON    │
│  拦截图片   │     │  (Gemini / 等)   │     │  (OCR+版面+实体) │
└─────────────┘     └──────────────────┘     └────────┬────────┘
                                                      │
                                                      ▼
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  纯文本模型回答 │◀────│  JSON 文本注入   │◀────│  模型上下文     │
│  (DeepSeek 等)  │     │  替换原始图片    │     │                 │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

### 两种粘贴模式

| 模式 | 交互 | 原理 |
| --- | --- | --- |
| **① 直接粘贴** | 图片落临时文件，路径进 composer | `modlens_read_image` 工具接管，调视觉引擎转写 |
| **② 选 (modlens vision) 模型** | 缩略图保留在消息里 | 请求时自动转结构化证据，模型直接收到文本 |

> **出处**：modlens README—— *"Pasting an image works two ways. ① Just paste… ② Pick a `(modlens vision)` entry in the model selector…"*

### 核心卖点

1. **零配置启动**：默认用 Antigravity CLI 免费通道，无需 API key；有 Gemini key 可加速到 5-10 秒
2. **结构化证据**：不是一句话描述，而是完整转写 + 阅读顺序版面区域 + 实体关系列表——"证据而非猜测"
3. **跨 harness 复用**：可复用 Claude Code / Codex / OpenCode / Pi 已配置的视觉模型登录
4. **自动发现**：安装后自动扫描所有纯文本模型路由，逐个加 `(modlens vision)` 包装条目；原生视觉模型自动排除
5. **Install once, use everywhere**：在 Claude Code、Codex、Pi、OpenCode 四个 harness 验证通过

---

## 二、dsh-learn 的图片能力

dsh-learn 用 `codebuddy-llm-v2` 插件接入 CodeBuddy IOA，后端模型的情况：

```
codebuddy-llm-v2/codebuddy-llm.ts L125-163
```

| 模型 | supportsImages | 备注 |
| --- | :---: | --- |
| auto | ❌ | 自动路由，不保证视觉 |
| **claude-sonnet-5** | ✅ | |
| **claude-sonnet-5-1m** | ✅ | |
| **claude-sonnet-4.6** / **-1m** | ✅ | |
| **claude-opus-5** | ✅ | |
| **claude-opus-4.8** / **-1m** | ✅ | |
| **claude-opus-4.7** / **-1m** | ✅ | |
| **claude-opus-4.6** / **-1m** | ✅ | |
| **gemini-3.1-pro** | ✅ | |
| **gemini-3.5-flash** | ✅ | |
| **gpt-6-astra** | ✅ | |
| **gpt-5.6-sol/terra/luna** | ✅ | |
| **gpt-5.5** / **gpt-5.4** / **gpt-5.3-codex** | ✅ | |
| **glm-5.3-flash** / **glm-5.3** / **glm-5.2** | ✅ | |
| **glm-5v-turbo** | ✅ | 专用视觉模型 |
| **minimax-m3** / **m2.7** | ✅ | |
| **kimi-k3** / **k2.8** / **k2.7** / **k2.6** | ✅ | |
| **hy4-preview** / **hy3** | ✅ | |
| **deepseek-v4.1-flash** / **v4-pro** | ✅ | |
| echo | ❌ | 回显模型，不处理图片 |

**37 个模型里 35 个 `supportsImages: true`**。图片处理链路已完整实现：

- 用户上传图片 → attachment 服务存字节 → 构造 OpenAI `image_url` base64 格式（L449-456）
- 模型收到 `inputModalities: ['text', 'image']` 声明（L851/862）
- 工具返回的图片也会序列化进消息（L480-502）

**模型原生看图，没有中间转写层，信息零损耗。**

---

## 三、直接对比

| 维度 | dsh-learn（codebuddy-llm-v2） | modlens |
| --- | --- | --- |
| **目标模型** | CodeBuddy IOA 后端模型（35/37 带视觉） | dsh 官方 DeepSeek/GLM 等纯文本模型 |
| **模型是否真的看图** | ✅ 是，原生多模态 | ❌ 不是，看的是转写文本 |
| **图片处理方式** | base64 `image_url` 直送模型 | 外部视觉引擎转 JSON 文本，再注入上下文 |
| **信息损耗** | 无 | 有（转写丢色温、模糊区域、细微布局等） |
| **额外依赖** | 无，CodeBuddy token 手搓搞定 | 需要视觉引擎（Gemini key / Antigravity / 复用其他 harness） |
| **输出格式** | 模型自由回答 | 结构化 JSON（OCR + 版面 + 实体 + 关系） |
| **延迟** | 一次模型调用 | 视觉引擎调用 + 模型调用（两跳） |
| **安装复杂度** | 已内置 | 需 `dsh plugin --profile web add @liustack/modlens@3.26.1` |

### 关键差异：modlens 是给"看不见的模型"加眼睛

modlens 的全部设计前提是——**后端模型 `supportsImages: false`**。它的自动发现逻辑只接管"元数据确认纯文本"的模型，视觉模型一律跳过。

> **出处**：modlens README—— *"only a model its metadata positively confirms text-only is taken over, anything unconfirmed is left alone, so vision models keep their native paste."*

dsh-learn 的模型**绝大多数已经 `supportsImages: true`**。modlens 装上去以后会扫描一圈，发现没有可接管的纯文本模型，等于白装。

### 关键差异：转写 vs 原生看图

modlens 的转写是"二次手"——视觉引擎先理解一遍图片，输出 JSON 文本，纯文本模型再基于这个文本回答。原始图片中的色彩渐变、模糊区域的文字、细微的 UI 间距等信息都会在转写中丢失。

dsh-learn 是模型直接看原图，像素级信息完整送达，模型自己理解。

---

## 四、什么情况下 modlens 才有意义

| 场景 | modlens 有用？ | 原因 |
| --- | :---: | --- |
| 你用 dsh 官方后端的 DeepSeek-V4-Flash/Pro | ✅ | 纯文本模型，确实看不见图 |
| 你用 dsh 官方后端的 GLM-5.3（非 Flash） | ✅ | 纯文本模型 |
| 你用 dsh-learn + CodeBuddy IOA | ❌ | 35/37 模型带视觉 |
| 你只选 `auto` 模式 | ⚠️ | auto 不保证视觉，但直接换一个带视觉的模型更简单 |
| 你需要 OCR + 版面 + 实体的结构化输出 | ⚠️ | modlens 的结构化 JSON 有独特价值，但日常对话不需要 |

> [!tip] 如果某天 CodeBuddy 后端某个纯文本模型没有视觉版本
> 更简单的做法是**直接选一个带视觉的模型**（Claude / GPT / Gemini 都行），而不是装 modlens 外挂视觉引擎。modlens 的"外挂转写"只在**所有可用模型都是纯文本**时才不可替代——而 dsh-learn 不存在这个情况。

---

## 五、结论

**dsh-learn 不需要 modlens。** 原因一句话：

> modlens 给纯文本模型外挂视觉，而 dsh-learn 的 CodeBuddy 通道 35/37 模型已原生支持视觉——问题不存在，解法自然也不需要。

modlens 是一个设计精良的插件，它解决的是**原厂 dsh + DeepSeek 纯文本模型**的真实痛点。但 dsh-learn 走的是 CodeBuddy IOA 通道，模型本身就带视觉能力，图片直接以 base64 送给模型，信息零损耗、零额外依赖。

---

## 出处汇总

| 内容 | 链接 |
| --- | --- |
| modlens GitHub 仓库 | <https://github.com/liustack/modlens> |
| dsh-plugin.org 页面 | <https://dsh-plugin.org/plugins/liustack/modlens> |
| SkillHub 页面 | <https://skillhub.cloud.tencent.com/plugins/liustack/modlens> |
| dsh-learn codebuddy-llm-v2 源码 | `~/ai-work/dsh/dsh-learn/plugins/codebuddy-llm-v2/codebuddy-llm.ts` |
| 上一篇：社区插件全景 | [[00 社区插件全景——4312 个插件、23 个分类]] |