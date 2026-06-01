---
type: concept
status: developing
area: growth
tags: [learning, 微调, 框架, ms-swift, modelscope]
created: 2026-06-01
updated: 2026-06-01
---

# ms-SWIFT(魔搭生态全家桶)

> 本页讲 **ms-SWIFT**:它是什么、为什么叫"全家桶"、与 [[03 LLaMA-Factory|LLaMA-Factory]] 怎么区分。一句话记住:**模型最多、方法最全、训→推→评→量→部一条龙,且深度绑定魔搭(ModelScope)生态。**

## 一句话定位

**ms-SWIFT(Scalable lightWeight Infrastructure for Fine-Tuning)是由魔搭社区(ModelScope)开发的高效微调和部署框架,为研究人员和开发者提供一站式的「大模型 + 多模态大模型」训练、推理、评测、量化和部署解决方案。**

- 官方仓库:`github.com/modelscope/swift`
- 关键词:**一站式、超大模型库、深度国产生态、全流程闭环**。

> [!key-insight] 它和 [[03 LLaMA-Factory|LLaMA-Factory]] 怎么区分
> 两者都是"大而全 + 带 UI",高度重叠。差异在**生态归属**:
> - **ms-SWIFT** 出自**魔搭(ModelScope,阿里)**,对 **Qwen 系列等国产模型 Day0 支持**最及时,且打通了 `vLLM / LMDeploy / EvalScope` 等魔搭周边,**训完能直接评测、量化、部署**。
> - **LLaMA-Factory** 是社区独立项目,UI(LlamaBoard)更轻、上手更直观。
> 用国产模型 / 要端到端上线 → ms-SWIFT;想要最简单的图形界面入门 → LLaMA-Factory。

## 主要功能特点

### 1. 模型支持(最大卖点)

支持 **450+(README 最新已 600+)大语言模型 + 150+(已 400+)多模态大模型**的训练和部署,涵盖最新版本:

- **纯文本**:Qwen2.5、InternLM3、GLM4、Llama3.3、Mistral、DeepSeek-R1、Yi1.5、Baichuan2、Gemma2 等。
- **多模态**:Qwen2.5-VL、Qwen2-Audio、Llama3.2-Vision、Llava、InternVL2.5 等。

> [!key-insight] "模型最多"是它最硬的护城河
> 四套框架里 ms-SWIFT 的模型覆盖最广,尤其**国产模型 Day0 跟进**最快 —— 新模型刚发布就能用它微调。

### 2. 多样化的训练技术

集成大量前沿微调技术,满足不同需求:[[03 LoRA 与 QLoRA|LoRA]]、LLaMA-Pro、LongLoRA、GaLore、Q-GaLore、LoRA+、LISA、DoRA、FourierFt、ReFT,以及 **UnSloth 和 Liger** 等加速内核。

### 3. 轻量级微调

支持多种轻量级方法降低显存和计算消耗:[[03 LoRA 与 QLoRA|LoRA、QLoRA]]、DoRA、Adapter、GaLore、Q-GaLore、LISA、UnSloth、Liger-Kernel 等(7B 模型训练最低约 9GB 显存)。

### 4. 分布式训练

支持 **分布式数据并行(DDP)、DeepSpeed ZeRO2/ZeRO3、FSDP、Megatron** 等技术,可扩展到多机多卡集群。

> [!key-insight] 这点比 [[02 Unsloth|Unsloth]] 强
> Unsloth 只能单卡;ms-SWIFT 支持 ZeRO/FSDP/Megatron **多机多卡并行**,能训更大的模型、扩更高的吞吐。

### 5. 推理加速与量化

- **量化方法**:BNB、GPTQ、AWQ、AQLM、HQQ、EETQ 等。
- **推理/部署**:支持用 **vLLM、LMDeploy** 对推理、评测和部署做加速。

### 6. 多模态全任务

支持图像、视频、语音等多种模态的训练,覆盖 **OCR、Grounding(视觉定位)** 等任务,并支持多模态 RLHF。

### 7. 用户友好的界面

提供基于 **Gradio 的 Web-UI**,把训练、推理、评测、量化、部署的全链路操作图形化,简化大模型的全流程操作。也提供 CLI(`swift sft / infer / deploy / eval / export`)和 Python API。

## 全流程闭环:它的"一站式"是什么意思

```text
训练(SFT/RLHF) → 推理(vLLM/LMDeploy) → 评测(EvalScope) → 量化(GPTQ/AWQ) → 部署(OpenAI 兼容 API)
        └──────────────── 全程一套工具、一致接口 ────────────────┘
```

> [!key-insight] "全家桶"的真正价值
> 别的框架可能只管"训",训完你还要自己找推理、评测、量化、部署工具拼起来。ms-SWIFT 把这**整条链路**用一套 CLI / UI 串好了 —— 这是它面向**生产落地**的核心优势。

## 适用场景

- ✅ **主用国产模型(Qwen / GLM / InternLM / DeepSeek 等)** —— Day0 支持。
- ✅ **需要从微调一路走到部署上线**(训→推→评→量→部全流程)。
- ✅ **多模态(图/视频/语音)+ OCR / Grounding 任务**。
- ✅ **多机多卡分布式**(ZeRO/FSDP/Megatron)。
- ⚠️ **只想单卡极速微调** → [[02 Unsloth|Unsloth]] 更直接(ms-SWIFT 也内置了 UnSloth/Liger 加速)。

## 继续学习

- [[01 四大微调框架概述|四大微调框架概述]](ms-SWIFT 在四套工具中的定位)
- [[03 LLaMA-Factory|LLaMA-Factory]](对比:同为大而全 + UI,生态归属不同)
- [[02 Unsloth|Unsloth]](对比:单卡极致 vs 全流程闭环)
- [[03 LoRA 与 QLoRA|LoRA 与 QLoRA]]
- 参考:ms-SWIFT GitHub(`github.com/modelscope/swift`)
