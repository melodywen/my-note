---
type: concept
status: developing
area: growth
tags: [learning, 微调, 实战, ms-swift, 安装, modelscope]
created: 2026-06-01
updated: 2026-06-01
---

# 02 ms-SWIFT 安装部署

> 本页是**实战演练篇**:把 [[04 ms-SWIFT|ms-SWIFT]] 装到本地/服务器,为后续微调做准备。一句话记住:**最简单一行 `pip install ms-swift` 就能用;真要跑全流程,加装对应 extras 或直接用官方 Docker 镜像最省心。**

## 安装前:先确认基础环境

ms-SWIFT 是建立在 PyTorch 生态上的框架,装它之前先备好底座:

| 依赖 | 要求 | 说明 |
|---|---|---|
| **操作系统** | Linux(推荐)/ Windows WSL / macOS | 生产环境基本都是 Linux |
| **Python** | 3.10 ~ 3.11 | 太新太旧都可能踩坑 |
| **CUDA** | 12.x(用 NVIDIA 卡时) | 对应显卡驱动要装好 |
| **PyTorch** | 2.9 / 2.10(较新版本) | 框架核心底座 |
| **GPU** | NVIDIA A10/A100/H100、RTX 20/30/40 系等 | 也支持昇腾 NPU、Apple MPS、CPU |

> [!key-insight] 强烈建议用 conda 建独立环境
> 微调框架的依赖链很复杂(torch / transformers / peft / accelerate / vllm 互相有版本约束),**别直接装到系统 Python 里**。先建一个干净环境再装,出问题能随时删掉重来:
> ```bash
> conda create -n swift python=3.11 -y
> conda activate swift
> ```

## 方式一:pip 安装(最常用)

最简单的安装,一行搞定:

```bash
pip install ms-swift
```

如果要用**特定功能**,装对应的 extras(额外依赖包):

| 命令 | 用途 |
|---|---|
| `pip install ms-swift` | 基础安装 |
| `pip install 'ms-swift[llm]'` | LLM 相关功能 |
| `pip install 'ms-swift[eval]'` | 评测功能(配合 [[01 EvalScope\|EvalScope]]) |
| `pip install 'ms-swift[all]'` | **全功能**(图省事直接装这个) |

> [!key-insight] extras 里的 `[...]` 是什么
> `ms-swift[all]` 中括号里的就是"可选依赖组"。基础包只装核心,**用到哪个能力(LLM / 评测 / 全量)就装哪个组**,把对应的额外依赖一并拉进来。不确定就 `[all]`,省得缺包。

## 方式二:源码安装(想改代码/用最新特性)

想跟最新主分支、或要改源码调试,用源码安装:

```bash
git clone https://github.com/modelscope/ms-swift.git
cd ms-swift
pip install -e .
```

> `pip install -e .` 里的 `-e` 是 **editable(可编辑)模式** —— 装的是源码目录本身,你改了源码立即生效,不用重装。适合开发/调试。

## 方式三:Docker 镜像(最省心,环境一把梭)

最怕踩"装了半天依赖还跑不起来"的坑,**官方 Docker 镜像把 CUDA / torch / vLLM / ms-swift 全打包好了**,拉下来就能用:

```bash
# 以 swift 4.0.2 镜像为例(含 cuda12.8 + torch2.10 + vllm0.17)
docker pull modelscope-registry.cn-hangzhou.cr.aliyuncs.com/modelscope-repo/modelscope:ubuntu22.04-cuda12.8.1-py311-torch2.10.0-vllm0.17.1-modelscope1.34.0-swift4.0.2
```

> [!key-insight] 三种方式怎么选
> | 你是谁 | 推荐方式 |
> |---|---|
> | 只想快速用框架训模型 | **pip install ms-swift[all]** |
> | 要改源码/追最新特性 | **源码 `pip install -e .`** |
> | 环境老踩坑 / 要在干净机器一键起 | **Docker 镜像** |
> 镜像名里 `cuda12.8 / torch2.10 / vllm0.17 / swift4.0.2` 这串,就是把整套版本锁死打包 —— 这正是 Docker"环境即代码、避免版本地狱"的价值。

## 验证安装

装完跑一下 CLI,能打印出帮助/版本就说明 OK:

```bash
swift --help
```

ms-SWIFT 的命令是 `swift xxx` 的形式(对应 [[04 ms-SWIFT|ms-SWIFT 全流程]]):`swift sft`(微调)、`swift infer`(推理)、`swift eval`(评测)、`swift export`(量化导出)、`swift deploy`(部署)。

## 继续学习

- [[04 ms-SWIFT|ms-SWIFT(魔搭生态全家桶)]](装好之后,看它能干什么)
- [[01 Qwen3 高效微调环境准备|Qwen3 高效微调环境准备]](实战环境四件套总览)
- [[06 微调所需软硬件环境|微调所需软硬件环境]](装框架前先确认显卡显存够不够)
