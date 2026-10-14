# DUSt3R：双图重建到 GLB

[返回项目首页](../../README.md) · [安装教程](../windows-setup.md) · [环境定义](../environments/README.md) · [验证基线](../validation.md)

本页带你使用仓库的 DUSt3R 启动入口，上传两张官方样图，得到可旋转的三维场景并下载 GLB。先跑通样例，再尝试自己的同一静态场景照片。

## 支持范围与来源

当前入口使用本地 `512_dpt` checkpoint，默认在 NVIDIA CUDA GPU 上运行，保留 DUSt3R 网页的全局对齐、网格／点云导出及 RGB／深度／置信度图。已验证的是 Windows x64 的双图流程；训练、大规模输入和特殊材质精度不在本轮验证范围。输出顶点数不能用来判断几何精度，模型输出也不能直接当作已校准的实物尺寸。

| 项目 | 来源或位置 |
|---|---|
| 官方实现与论文入口 | [naver/dust3r](https://github.com/naver/dust3r) |
| 当前源码目录 | `repos/dust3r` |
| 固定官方版本 | `a53d073bb07455f5a3e7fcbeaaea240c159c4f08`，CroCo `743ee71a2a9bf57cea6832a9064a70a0597fcfcb` |
| 网页补丁 | [dust3r-gradio4.patch](../../patches/dust3r-gradio4.patch)，按安装教程应用 |
| 官方权重 | [DUSt3R_ViTLarge_BaseDecoder_512_dpt.pth](https://download.europe.naverlabs.com/ComputerVision/DUSt3R/DUSt3R_ViTLarge_BaseDecoder_512_dpt.pth) |
| 权重存放位置 | `checkpoints/dust3r/DUSt3R_ViTLarge_BaseDecoder_512_dpt.pth` |
| 环境定义 | [requirements-dust3r-core.txt](../environments/requirements-dust3r-core.txt)，新环境名称 `dust3r-demo` |

固定来源、权重字节数与 SHA-256 见 [model-sources.json](../model-sources.json)。独立 DUSt3R 使用自己的官方提交与 CroCo，不能直接换成 MASt3R 的内嵌源码。补丁只调整网页展示和显式 GLB 下载，使用前阅读[第三方归属说明](../third-party-notices.md)、[官方许可证](https://github.com/naver/dust3r#license)与 checkpoint 使用限制。

## 开始前

按[安装教程](../windows-setup.md)完成源码准备、独立环境安装、权重校验和 `workspace.json` 配置。配置中 `models.dust3r.python` 必须指向自己的 `dust3r-demo` 解释器，权重路径保持上表的相对位置。已有可用环境也可使用，但应填写实际解释器，不能照抄他人的用户目录。

下列命令都从仓库根目录运行。启动器读取 `workspace.json`；PowerShell 提示符显示 `(base)` 不会改变它使用的环境。

## 启动与样图操作

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -Model dust3r
if ($LASTEXITCODE -ne 0) { throw 'DUSt3R demo startup failed; inspect outputs/runtime logs' }
```

默认地址为 `http://127.0.0.1:7860/`。需要自己打开页面时，在启动命令末尾添加 `-NoBrowser`。也可以双击根目录的 `启动DUSt3R.cmd`。

1. 在上传区域同时选择 `repos/dust3r/croco/assets/Chateau1.png` 和 `Chateau2.png`。
2. 首次按网页验收设置运行：`schedule = linear`，将 `num_iterations` 从页面默认的 **300** 改为 **100**，`Scenegraph` 保持 `complete`，其余先保持默认。
3. 点击 **Run**，等待三维场景及 `rgb,depth,confidence` 图库出现。两张输入对应六张图库图。
4. 拖动三维窗口查看场景，通过 **Download scene.glb** 下载；打开下载文件，确认包含非空几何。`As pointcloud` 可切换为点云导出，输出类型与顶点数会随设置变化。

结果保存在 `outputs/dust3r/demo-<时间>/`；启动日志在 `outputs/runtime/dust3r-*.stdout.log` 与 `*.stderr.log`。下载到浏览器默认目录的文件是另一个副本。

结束运行时执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -Stop
if ($LASTEXITCODE -ne 0) { throw 'Could not stop the managed demo' }
```

启动器管理一套服务，切换模型时会先停止上一套受管理服务。手动在其他终端启动的模型，需在原终端用 `Ctrl+C` 停止。

## 无页面验证

先停止网页服务，再运行真实 GPU smoke。该命令使用 `dust3r-demo` 环境，加载相同的本地权重和 Chateau 双图；它独立于启动器的解释器选择。

```powershell
conda run -n dust3r-demo python -B scripts/dust3r_smoke.py
if ($LASTEXITCODE -ne 0) { throw 'DUSt3R smoke failed; inspect the traceback' }
```

smoke 使用 `cosine / 100 iterations` 与点云导出，和上面的网页网格设置不同。它检查相机位姿、深度有限值、六张图库图及 GLB 读回；成功记录位于 `outputs/setup/dust3r-smoke.json`，场景位于 `outputs/dust3r/smoke-<时间>/scene.glb`。

2026-10-14 的 RTX 4060 Laptop 8 GB 验证中，这个样例峰值分配显存为 2.58 GiB。它不包含驱动和其他进程占用，也不是任意输入都能在 8 GB 显存运行的保证。完整设置与结果见[验证基线](../validation.md)。

## 遇到问题

| 现象 | 检查与处理 |
|---|---|
| 找不到 `croco` 或 Chateau 样图 | 检查 `repos/dust3r/croco/` 是否完整；按安装教程递归初始化官方子模块。独立 DUSt3R 固定 CroCo `743ee71`，不要以 MASt3R 的内嵌源码覆盖这里。 |
| `Local weights missing` 或 `Required file missing` | 核对 checkpoint 相对位置，以及 `workspace.json` 中的解释器和权重路径；先完成字节数／SHA-256 校验。 |
| `CUDA unavailable` | 在对应环境检查 Torch 带 `+cu121`、`torch.cuda.is_available()` 为真，并检查 `nvidia-smi`；详细操作见安装教程。 |
| 显存不足 | 停止其他模型服务和 GPU 任务，先恢复两张样图。减少优化迭代不保证解决模型推理的显存问题。 |
| 页面报错或下载场景为空 | 查看本次 stderr 的首个异常；先复现上面的固定样例，不要通过盲目升级 Gradio／Torch 改变验证环境。 |
