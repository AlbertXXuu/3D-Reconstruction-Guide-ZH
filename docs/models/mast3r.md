# MASt3R：双图对齐与场景导出

[返回项目首页](../../README.md) · [安装教程](../windows-setup.md) · [环境定义](../environments/README.md) · [验证基线](../validation.md)

本页使用固定版本的官方 MASt3R 网页，完成 Chateau 双图上传、粗对齐与细化、三维查看和 GLB 下载。MASt3R 和 DUSt3R 各有自己的源码及 Python 环境；MASt3R 包含 DUSt3R 子模块，不需要在 DUSt3R 环境里覆盖安装它的页面依赖。

## 支持范围与来源

当前入口加载本地 `512_catmlpdpt_metric` checkpoint，运行官方重建与导出函数。已验证 Windows x64、CUDA、512 双图输入与 `refine+depth`。训练、检索模型、完整视觉定位、COLMAP 流程以及大规模输入未纳入当前环境定义。checkpoint 名称含 `metric`，本轮样例验收仍没有测量真实长度误差，不能据此承诺尺寸精度。

| 项目 | 来源或位置 |
|---|---|
| 官方实现 | [naver/mast3r](https://github.com/naver/mast3r/tree/f5209afc300cec36239a7ac992263f36847bbba0) |
| 固定 revision | `f5209afc300cec36239a7ac992263f36847bbba0` |
| 当前源码目录 | `repos/mast3r` |
| 内含 DUSt3R revision | `3cc8c88c413bb9e34c41db0e0eef99c2ee010b12`，位于 `repos/mast3r/dust3r` |
| 内含 CroCo revision | `d7de0705845239092414480bd829228723bf20de`，位于 `repos/mast3r/dust3r/croco` |
| 官方权重 | [MASt3R_ViTLarge_BaseDecoder_512_catmlpdpt_metric.pth](https://download.europe.naverlabs.com/ComputerVision/MASt3R/MASt3R_ViTLarge_BaseDecoder_512_catmlpdpt_metric.pth) |
| 权重存放位置 | `checkpoints/mast3r/MASt3R_ViTLarge_BaseDecoder_512_catmlpdpt_metric.pth` |
| 环境定义 | [requirements-mast3r-core.txt](../environments/requirements-mast3r-core.txt)，新环境名称 `mast3r-demo` |

来源及权重校验值见 [model-sources.json](../model-sources.json)。使用前阅读[官方许可证](https://github.com/naver/mast3r/blob/f5209afc300cec36239a7ac992263f36847bbba0/LICENSE)与 [CHECKPOINTS_NOTICE](https://github.com/naver/mast3r/blob/f5209afc300cec36239a7ac992263f36847bbba0/CHECKPOINTS_NOTICE)。

## 开始前

按[安装教程](../windows-setup.md)完成固定子模块、独立环境、权重校验和本机配置。`workspace.json` 的 `models.mast3r.python` 应指向自己的 `mast3r-demo` 解释器。已有可用环境可继续使用，填入实际解释器即可。

后续命令在仓库根目录运行。若缺 `mast3r/dust3r/croco`，先补全递归子模块；仅下载顶层 ZIP 可能缺少这些目录。

## 启动与样图操作

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -Model mast3r
if ($LASTEXITCODE -ne 0) { throw 'MASt3R demo startup failed; inspect outputs/runtime logs' }
```

默认地址为 `http://127.0.0.1:7861/`。启动命令追加 `-NoBrowser` 可自行打开页面，也可双击 `启动MASt3R.cmd`。

1. 同时上传 `repos/mast3r/dust3r/croco/assets/Chateau1.png` 与 `Chateau2.png`。
2. 页面有两个都叫 **Iterations** 的控件：将 **For coarse alignment** 的值改为 **30**，将 **For refinement** 的值改为 **20**。两者默认都是 300；30／20 是本仓库的首次验证设置。
3. 保持 `OptLevel = refine+depth`、`Scenegraph = complete`、`As pointcloud` 勾选，其余先保持默认，然后点击 **Run**。
4. 等待三维场景出现，旋转查看点云及两个相机，通过三维查看器下载 GLB。再次用本地三维查看器打开，确认场景非空。

网页缓存及导出保存在 `outputs/mast3r/demo/` 的权重标识子目录；日志在 `outputs/runtime/mast3r-*.stdout.log` 与 `*.stderr.log`。网页和 smoke 使用不同输出目录，便于区分。

使用结束后：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -Stop
if ($LASTEXITCODE -ne 0) { throw 'Could not stop the managed demo' }
```

启动器切换模型时会停止上一套受管理服务。它不会停止其他终端手动运行的 Python；那些服务在原终端用 `Ctrl+C` 结束。

## 无页面验证

先停止网页服务，再执行真实 GPU smoke。默认使用 512、coarse 30、fine 20，与上面的首次网页操作一致：

```powershell
conda run -n mast3r-demo python -B scripts/mast3r_smoke.py
if ($LASTEXITCODE -ne 0) { throw 'MASt3R smoke failed; inspect the traceback' }
```

该命令使用 `mast3r-demo` 环境，独立于 `workspace.json` 的解释器选择。它检查 GLB 非空且可读回、两个相机位姿及内参数值有限；产物位于 `outputs/mast3r/smoke/`：

- `chateau_scene.glb`：导出的场景。
- `cameras.npz`：相机位姿与内参。
- `smoke-result.json`：设置、耗时、显存及检查结果。

默认 smoke 复用这个目录，请勿在里面存放个人原始文件。2026-10-14 的 RTX 4060 Laptop 8 GB 样例峰值分配显存为 3.07 GiB；这不等于总显存占用，也不保证任意数量／分辨率的图片能运行。详细记录见[验证基线](../validation.md)。

## 遇到问题

| 现象 | 检查与处理 |
|---|---|
| 找不到 `dust3r`／`croco` 模块 | 在仓库根目录执行安装教程的 `git submodule update --init --recursive`；保留 MASt3R 所固定的子模块版本。 |
| 为什么仍然导入 DUSt3R | 这是 MASt3R 的官方代码依赖，不表示它在复用另一个项目的环境；核对导入路径应落在 `repos/mast3r/dust3r`。 |
| `CUDA is unavailable` | 核对 JSON 解释器、对应环境的 Torch CUDA 版本与 `nvidia-smi`。`--check` 只检查导入／文件，不替代实际推理。 |
| 运行比样例慢很多 | 确认两个 Iterations 已分别改为 30／20；默认 300／300 与本页设置不同。耗时仍随设备和输入变化。 |
| 显存不足或页面异常 | 停止其他模型进程，恢复双图样例，查看本次 stderr 首个异常；不混装 VGGT 的 Gradio 依赖。 |
