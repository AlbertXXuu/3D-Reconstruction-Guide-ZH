# VGGT：相机、深度与点云导出

[返回项目首页](../../README.md) · [安装教程](../windows-setup.md) · [环境定义](../environments/README.md) · [验证基线](../validation.md)

本页运行仓库的中文 VGGT 网页：上传同一场景的照片，用相机／深度预测重建点云，下载 GLB 场景和 NPZ 数组。首次使用官方 kitchen 双图、宽度 294，便于和已验证基线对照。

## 支持范围与来源

当前本地实现使用官方 VGGT-1B 的相机与深度分支，通过深度反投影生成点云，调用官方 GLB 导出函数。Transformer 使用 bfloat16，预测头使用 float32；推理后将模型移回 CPU 以释放 GPU 权重占用。需要支持 bfloat16 的 CUDA GPU，当前入口未提供 CPU 运行路径。

页面接受 **1–4 张**图片，宽度可选 294／392／518。本轮只验证了 kitchen 双图 294×196；更高宽度、更多照片需在你的机器上单独测试。没有启用独立点预测、跟踪、天空分割、视频或训练分支，完整上游功能需另行安装和验证。结果的尺度没有物理单位。

| 项目 | 来源或位置 |
|---|---|
| 官方实现 | [facebookresearch/vggt](https://github.com/facebookresearch/vggt/tree/a288dd0f14786c93483e45524328726ab7b1b4ce) |
| 固定源码 revision | `a288dd0f14786c93483e45524328726ab7b1b4ce` |
| 当前源码目录 | `repos/vggt` |
| 官方模型与使用说明 | [facebook/VGGT-1B](https://huggingface.co/facebook/VGGT-1B) |
| 固定权重 revision | `860abec7937da0a4c03c41d3c269c366e82abdf9` |
| 官方权重 | [固定版本 model.pt](https://huggingface.co/facebook/VGGT-1B/resolve/860abec7937da0a4c03c41d3c269c366e82abdf9/model.pt) |
| 权重存放位置 | `checkpoints/vggt/model.pt` |
| 环境定义 | [requirements-vggt-core.txt](../environments/requirements-vggt-core.txt)，新环境名称 `vggt-demo` |

完整来源和 SHA-256 见 [model-sources.json](../model-sources.json)。代码、模型权重与样例素材各自的许可需要按官方说明使用，阅读[固定源码许可证](https://github.com/facebookresearch/vggt/blob/a288dd0f14786c93483e45524328726ab7b1b4ce/LICENSE.txt)及上述模型说明。

## 开始前

先按[安装教程](../windows-setup.md)准备源码、独立 `vggt-demo` 环境、校验权重并生成本机 `workspace.json`。`models.vggt.python` 应填写实际 VGGT 解释器；其 Gradio 5.17.1 与另外两套页面的 Gradio 4.44.1 分开安装。

在对应环境确认 CUDA 与 bfloat16 支持：

```powershell
conda run -n vggt-demo python -c "import torch; print('CUDA:', torch.cuda.is_available()); print('bfloat16:', torch.cuda.is_available() and torch.cuda.is_bf16_supported())"
if ($LASTEXITCODE -ne 0) { throw 'VGGT runtime check failed' }
```

两项都应为 `True`。后续命令均从仓库根目录执行。

## 启动与样图操作

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -Model vggt
if ($LASTEXITCODE -ne 0) { throw 'VGGT demo startup failed; inspect outputs/runtime logs' }
```

默认地址为 `http://127.0.0.1:7862/`。追加 `-NoBrowser` 可自行打开页面；也可双击 `启动VGGT.cmd`。

1. 点击 **官方 kitchen 双视图样例**，或在 **场景照片** 中同时上传 `repos/vggt/examples/kitchen/images/00.png` 和 `01.png`。
2. 保持 **输入宽度 = 294**、**过滤最低置信度点的百分比 = 50**、**显示相机位置** 勾选。
3. 点击 **开始重建**，等待运行结果显示输入尺寸、场景顶点数、显存和输出位置，并确认三维窗口能旋转查看。
4. 从三维窗口下载 **GLB**，从 **下载预测数据 NPZ** 下载数组。下载完成后确认 GLB 非空，NPZ 可读；下面的 smoke 提供自动检查。

置信度控件是过滤百分比，不是几何误差或成功概率。提高值会滤掉更多低置信度点，可能使场景变稀疏；不要仅靠点的数量选参数。

每次任务保存在 `outputs/vggt/<时间>_<任务标识>/`：

| 文件 | 内容 |
|---|---|
| `images/` | 本次输入图片副本 |
| `scene.glb` | 三维点云与可选相机几何 |
| `predictions.npz` | 输入、姿态编码、深度、置信度、相机外参／内参、深度反投影点云 |
| `metrics.json` | 分辨率、分支、显存、耗时与相机约定；外参采用 OpenCV `camera_from_world` |

启动日志在 `outputs/runtime/vggt-*.stdout.log` 与 `*.stderr.log`。输入副本也属于个人数据，Git 忽略输出目录；分享结果前自行确认要公开的内容。

结束运行时执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -Stop
if ($LASTEXITCODE -ne 0) { throw 'Could not stop the managed demo' }
```

启动器切换模型时会先停止上一套受管理服务；其他终端手动启动的服务在原终端用 `Ctrl+C` 结束。

## 无页面验证

先停止网页服务，再运行真实 GPU smoke。它使用 `vggt-demo` 解释器、官方 kitchen 双图、宽度 294 和置信度百分比 50，不依赖启动器的解释器选择。

```powershell
conda run -n vggt-demo python -B scripts/vggt_smoke.py
if ($LASTEXITCODE -ne 0) { throw 'VGGT smoke failed; inspect the traceback' }
```

成功要求 GLB 可读回且含非空几何，NPZ 中相机外参为 `(2,3,4)`、内参为 `(2,3,3)`，所有预测数组数值有限。检查摘要保存于 `outputs/setup/vggt-smoke.json`，任务目录还保留 GLB、NPZ 与 metrics。

2026-10-14 在 RTX 4060 Laptop 8 GB 上，这个样例峰值分配显存为 2.77 GiB。它不是驱动、显示与其他进程占用后的总量，也不代表所有 8 GB 显卡／输入都适用。完整数组形状及网页验收见[验证基线](../validation.md)。

## 遇到问题

| 现象 | 检查与处理 |
|---|---|
| `requires a CUDA GPU with bfloat16 support` | 检查上面的两项能力、JSON 解释器和 NVIDIA 驱动；此入口不能通过切换为 CPU 继续运行。 |
| `VGGT checkpoint is missing` | 权重应在 `checkpoints/vggt/model.pt`；按安装教程从固定来源下载并核对字节数／SHA-256。 |
| `Select 1–4 photographs` | 上传数必须在 1–4 之间；首次使用两张样图。更多图片不属于本入口已支持范围。 |
| 显存不足 | 停止其他 GPU 服务，以双图、宽度 294 重试；392／518 会增加输入尺寸，不是已验证的 8 GB 配置。 |
| 场景为空或很稀疏 | 降低过滤百分比，先验证官方样图；个人照片需同一静态场景、有重叠且曝光清楚。 |
| 页面退出或包冲突 | 查看本次 stderr 首个异常，在 `vggt-demo` 运行 `python -m pip check`；不要把 DUSt3R／MASt3R 的页面依赖装进该环境。 |
