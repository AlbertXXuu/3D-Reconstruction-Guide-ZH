# 验证记录与支持范围

记录日期：2026-10-14。这里记录实际执行的条件和结果。数据仅对应所列样图与设置，不是模型精度或性能排名；其他机器应完成自己的验收。

## 环境与安装

Windows x64、Windows PowerShell 5.1、Conda 25.5.1；RTX 4060 Laptop 8 GB，NVIDIA 驱动 596.49。三套环境为 `dust3r-demo`、`mast3r-demo`、`vggt-demo`，均为 Python 3.11.13、pip 25.1.1、Torch 2.5.1+cu121、torchvision 0.20.1+cu121、NumPy 2.0.1。DUSt3R / MASt3R 使用 Gradio 4.44.1，VGGT 使用 Gradio 5.17.1。

验证分为两步：先按照相同依赖定义从干净 conda-forge Python 基础分别创建并安装三个环境；再用本社区版的官方固定源码与显式补丁回归样例。社区源码回归复用上述已验证环境，未重复创建同名环境。

完整安装、`pip check`、模块来源隔离、NumPy / Torch 两种导入顺序与数据互转、CPU 矩阵计算、CUDA 和 bfloat16 检查均通过。直接解释器与 `conda run` 检查通过；移除 Conda 激活变量、仅保留 Windows 系统 PATH 时启动所需模块也可导入。没有修包、修改 OpenMP DLL 或设置 `KMP_DUPLICATE_LIB_OK`。

首套正常下载官方约 2.45 GB Torch wheel，后两套使用 pip HTTP 缓存。三份原有 checkpoint 核对字节数与 SHA-256 后复用，校验基线在 [model-sources.json](model-sources.json)，未在本轮重复下载约 9.38 GiB 权重。

## 社区版官方源码路线

默认子模块只有官方 DUSt3R、MASt3R、VGGT，没有私有源码依赖。固定提交见[来源清单](model-sources.json)；四个上游仓库的匿名 Git refs 查询通过。部分官方 Git 对象复用已有完整缓存后执行 dissociate，六个 checkout 均通过连接性检查，不依赖原缓存。

DUSt3R 固定 `a53d073bb07455f5a3e7fcbeaaea240c159c4f08`，CroCo 为 `743ee71a2a9bf57cea6832a9064a70a0597fcfcb`，应用 [Gradio 4 网页补丁](../patches/dust3r-gradio4.patch)。补丁后 `dust3r/demo.py` blob 为 `856ff0100a3e1060fabab818b032692a2df7854a`，CroCo tree 为 `068d7ec950333ff1d90b4f88bf70411f229c4805`，与此前完整安装验收使用的模型运行代码一致。

MASt3R 固定 `f5209afc300cec36239a7ac992263f36847bbba0`，其 DUSt3R / CroCo 与独立 DUSt3R 不同；VGGT 固定 `a288dd0f14786c93483e45524328726ab7b1b4ce`。完整文件存在、Git 对象无损、补丁首次应用/重复应用/冲突停止/保留无关源修改检查通过。

## 社区副本真实 GPU 回归

三模型依次执行，均使用真实本地权重并导出后重新读取 GLB。下表耗时包含脚本中的模型加载、推理和导出，只记录这一轮，不作为速度承诺。

| 模型 | 输入与设置 | 场景顶点数 | 峰值分配显存 | 本轮耗时 | 结果 |
|---|---|---:|---:|---:|---|
| DUSt3R | Chateau 双图，512 DPT，cosine / 100，点云 | 321,772 | 2.58 GiB | 7.78 秒 | 有限相机与深度、6 张图库图、GLB 读回 |
| MASt3R | Chateau 双图，512，coarse 30 / refinement 20 | 117,532 | 3.07 GiB | 15.74 秒 | 2 个相机、5 个几何对象、GLB 读回 |
| VGGT | kitchen 双图，294×196，camera / depth 分支 | 57,652 | 2.77 GiB | 10.24 秒 | GLB 读回、NPZ 数组形状与有限值 |

此前三套干净环境已完成网页文件上传、运行、三维显示、实际下载与磁盘读回。本轮又复验社区版改动的 DUSt3R 网页补丁及 VGGT 相对结果路径：DUSt3R 上传双图、linear / 100 重建、3D 显示、GLB 实际下载与读回通过（20,828,460 字节、321,394 顶点）；VGGT 点击官方 kitchen 样例、重建、3D 显示、GLB / NPZ 下载与读回通过（926,188 / 4,486,635 字节、57,652 顶点，预测数组全部有限），界面仅显示仓库内相对输出路径。MASt3R 网页源码未变，复用此前同固定提交和环境的验收结果。

## 文档与操作保护

环境创建前检查全部 Conda envs_dirs 的目标名称；任何同名目录存在就停止。每步安装和检查失败后停止；生成本机配置前完整备份已有 `workspace.json`，备份失败不覆盖。目录保护、备份成功与失败的隔离验证通过，原有环境和配置保留。

本仓库包含 [Python / JSON / 文档链接检查](../scripts/check-project.py)与 [PowerShell 语法检查](../scripts/check-powershell.ps1)。GitHub Actions 执行这两项静态检查，不安装模型依赖，不加载权重，也不代表云端 GPU 验收。

完整本机日志、freeze、GLB、NPZ 与验证 JSON 保留在被 Git 忽略的 `outputs/`。不把个人绝对路径、环境文件或权重上传作为教程附件；后续贡献应提供可公开的命令、版本、输入设置和结果摘要。

## 尚未验证

Linux / macOS、CPU 推理、其他 GPU、训练、更多或更高分辨率输入、透明物体精度以及完整定位/跟踪未在本轮验证。VGGT 入口只启用相机与深度分支，深度反投影点云的尺度没有物理单位。顶点数和页面观感不能替代几何精度评价。

直接依赖版本固定，传递依赖仍由 pip 解析。更换源码或依赖后应重新验证受影响流程，不能把此记录当作所有机器的安装保证。
