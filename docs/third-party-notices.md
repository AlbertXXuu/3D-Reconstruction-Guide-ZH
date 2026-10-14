# 第三方来源与使用许可

本项目整理中文安装步骤、Windows 启动入口和本地验收流程。DUSt3R、MASt3R、VGGT 的算法、预训练模型和官方样例由原作者提供；本项目不声明拥有这些内容，也不改变它们的许可。固定源码与权重地址、字节数、SHA-256 见 [model-sources.json](model-sources.json)。

## 源码与本地适配

| 内容 | 固定来源 | 许可与归属 |
|---|---|---|
| DUSt3R | [naver/dust3r，a53d073](https://github.com/naver/dust3r/tree/a53d073bb07455f5a3e7fcbeaaea240c159c4f08) | NAVER；[CC BY-NC-SA 4.0](https://github.com/naver/dust3r/blob/a53d073bb07455f5a3e7fcbeaaea240c159c4f08/LICENSE)，保留原 LICENSE、NOTICE 与版权头 |
| DUSt3R 的 CroCo | [naver/croco，743ee71](https://github.com/naver/croco/tree/743ee71a2a9bf57cea6832a9064a70a0597fcfcb) | NAVER；[原 LICENSE](https://github.com/naver/croco/blob/743ee71a2a9bf57cea6832a9064a70a0597fcfcb/LICENSE) 与 NOTICE；此提交由 DUSt3R 自身固定 |
| MASt3R | [naver/mast3r，f5209af](https://github.com/naver/mast3r/tree/f5209afc300cec36239a7ac992263f36847bbba0) | NAVER；[CC BY-NC-SA 4.0](https://github.com/naver/mast3r/blob/f5209afc300cec36239a7ac992263f36847bbba0/LICENSE)，其嵌套 DUSt3R／CroCo 保留各自许可 |
| VGGT 代码 | [facebookresearch/vggt，a288dd0](https://github.com/facebookresearch/vggt/tree/a288dd0f14786c93483e45524328726ab7b1b4ce) | Meta；[VGGT License，2025-07-29](https://github.com/facebookresearch/vggt/blob/a288dd0f14786c93483e45524328726ab7b1b4ce/LICENSE.txt)，包含使用条件，不等同于 MIT 或 Apache-2.0 |

[DUSt3R 页面补丁](../patches/dust3r-gradio4.patch) 只修改 `dust3r/demo.py`：指定 viewer 显示高度、增加 GLB 下载控件，并同步输出绑定。它基于 NAVER 的第三方代码，适用原 CC BY-NC-SA 4.0；补丁由本项目维护，不修改推理或模型参数。脚本 [apply-source-patches.ps1](../scripts/apply-source-patches.ps1) 检查固定提交和补丁冲突后应用，已应用时跳过，不重置源码。

CC BY-NC-SA 4.0 包含署名、非商业和相同方式共享要求。以原 [完整许可](https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode) 为准；本页的说明不替代许可正文。

## 预训练权重

源码许可与 checkpoint 使用条件分别核对。安装教程直接从官方地址获取权重，不在本仓库重新分发权重文件。

| 权重 | 使用说明 |
|---|---|
| DUSt3R 512 DPT | 遵循 DUSt3R 的 CC BY-NC-SA 4.0，并阅读官方说明列出的训练数据集和基础 checkpoint 条件，见 [官方 Checkpoints 说明](https://github.com/naver/dust3r/tree/a53d073bb07455f5a3e7fcbeaaea240c159c4f08#checkpoints) |
| MASt3R 512 metric | 阅读 [CHECKPOINTS_NOTICE](https://github.com/naver/mast3r/blob/f5209afc300cec36239a7ac992263f36847bbba0/CHECKPOINTS_NOTICE) 与各项对应许可 |
| 原版 VGGT-1B | 本项目使用 [VGGT-1B](https://huggingface.co/facebook/VGGT-1B/tree/860abec7937da0a4c03c41d3c269c366e82abdf9)，原版 checkpoint 保持非商业条件；2025-07 的代码许可更新不使该旧权重自动成为商业版。商业权重是另一份 [VGGT-1B-Commercial](https://huggingface.co/facebook/VGGT-1B-Commercial)，需按其申请与许可流程获取，本项目没有配置它 |

## 样图与可选数据工具

Chateau 样图来自 CroCo 官方 `assets/`，kitchen 样图来自 VGGT 官方 `examples/`；本项目通过官方固定源码获取，不提供个人研究数据。样例和重建结果应保留其来源；使用其他照片时核对照片、场景与数据集的授权。

CO3D 不属于三套 Demo 的必需依赖，因此不随默认子模块拉取。后续数据教程如使用 [facebookresearch/co3d](https://github.com/facebookresearch/co3d)，应另外说明版本、[CC BY-NC 4.0 许可](https://github.com/facebookresearch/co3d/blob/main/LICENSE) 和数据下载条件。

## 本项目自己的内容

本项目原创中文文档采用 [CC BY 4.0](../LICENSE-DOCS.md)，独立编写的维护脚本采用 [MIT](../LICENSE)。这些授权不覆盖第三方源码、第三方代码的改编补丁、模型权重、数据集或官方样图；其中 `patches/dust3r-gradio4.patch` 适用 CC BY-NC-SA 4.0。对第三方许可的事实说明也不重新授权被说明的内容。

公开可见不自动等于允许任意再分发，见 [GitHub 的许可说明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)。引用或修改时保留适用范围、第三方版权和许可信息。
