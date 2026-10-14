# 三套本地 demo 的环境定义

更新日期：2026-10-14。安装定义面向 Windows x64、Python 3.11、NVIDIA CUDA 12.1 版 PyTorch 2.5.1，范围是本工程的三套本地 demo。源码、子模块与本地 checkpoint 仍按 [来源记录](../model-sources.json)准备，环境定义不下载模型权重。

从 GitHub 克隆到完成页面运行的完整顺序见[Windows 环境配置与操作步骤](../windows-setup.md)。先还原固定源码，再安装依赖、下载校验权重、生成本机解释器配置；仅完成本页的 pip 步骤不能视为 Demo 已通过。

| 模型 | Python 基础定义 | 直接运行依赖 | 新建环境默认名称 |
|---|---|---|---|
| DUSt3R | [environment-dust3r.yml](environment-dust3r.yml) | [requirements-dust3r-core.txt](requirements-dust3r-core.txt)，16 项 | `dust3r-demo` |
| MASt3R | [environment-mast3r.yml](environment-mast3r.yml) | [requirements-mast3r-core.txt](requirements-mast3r-core.txt)，17 项 | `mast3r-demo` |
| VGGT | [environment-vggt.yml](environment-vggt.yml) | [requirements-vggt-core.txt](requirements-vggt-core.txt)，14 项 | `vggt-demo` |

这三套定义都建立独立 Python 基础环境。YAML 只包含 Python 和 pip，完成环境安装还需要下列两个 pip 步骤。新建名称与当前已配置的运行环境区分；不覆盖现有环境。

## 从干净环境安装

在本仓库根目录的 PowerShell 中执行。以下先示范 DUSt3R；另外两个模型只需将 `$model` 改为 `mast3r` 或 `vggt`。

```powershell
$model = 'dust3r'
$demoEnvironment = "$model-demo"
$condaInfoText = @(conda info --json)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Conda environment directories' }
$condaInfo = ($condaInfoText -join "`n") | ConvertFrom-Json
if (-not $condaInfo.envs_dirs) { throw 'Conda did not report environment directories' }
foreach ($environmentDirectory in $condaInfo.envs_dirs) {
    $candidatePrefix = Join-Path $environmentDirectory $demoEnvironment
    if (Test-Path -LiteralPath $candidatePrefix) {
        throw "Directory already exists; preserve it and inspect first: $candidatePrefix"
    }
}
conda create --name $demoEnvironment --override-channels --channel conda-forge --no-default-packages python=3.11.13 pip=25.1
if ($LASTEXITCODE -ne 0) { throw "Create failed: $demoEnvironment" }
conda run -n $demoEnvironment python -m pip install -r docs/environments/requirements-torch-cu121.txt
if ($LASTEXITCODE -ne 0) { throw "PyTorch install failed: $demoEnvironment" }
conda run -n $demoEnvironment python -m pip install --index-url https://pypi.org/simple -r "docs/environments/requirements-$model-core.txt"
if ($LASTEXITCODE -ne 0) { throw "Core dependency install failed: $demoEnvironment" }
conda run -n $demoEnvironment python -m pip check
if ($LASTEXITCODE -ne 0) { throw "pip check failed: $demoEnvironment" }
conda run -n $demoEnvironment python -c "import sys,torch; print(sys.executable); print(torch.__version__, torch.version.cuda, torch.cuda.is_available())"
if ($LASTEXITCODE -ne 0) { throw "Runtime import failed: $demoEnvironment" }
```

先确认上一步成功再执行下一步。目录检查不能省略，特别是添加 `-y` 时：Conda 可以移除已有同名环境后重建。已有可用环境应跳过创建，直接检查。需要代理时，pip 可在对应命令后追加 `--proxy http://127.0.0.1:7890`，只对这次命令有效；已有可用网络无需该参数。更换重建环境后，将上面打印的解释器路径写入工程 `workspace.json` 对应模型，再使用既有启动器或 smoke 入口验证。安装依赖与导入通过仍不能替代实际模型运行验证。

所有 YAML 指定 `conda-forge` 和 `nodefaults`，不继承用户配置中的 `defaults`。这符合 [Conda 环境文件规范](https://conda.org/learn/specifications/exchange/environment-yml/)。本机 Conda 25.5.1 的 ToS 插件会在 `conda env create` 读取 YAML 之前检查全局 channels，已观察到其仍要求 `defaults` 条款，因此上面用显式 `--override-channels --channel conda-forge` 创建与 YAML 完全相同的 Python 基础依赖。这只选择本次安装实际使用的 channel，不修改全局配置、不接受条款、不禁用插件。若所选 channel 自身要求另行接受条款，应停止并处理实际请求。

共同的 [requirements-torch-cu121.txt](requirements-torch-cu121.txt)使用 PyTorch 官方 CUDA 12.1 wheel 索引及 `torch==2.5.1`、`torchvision==0.20.1`，对应 [PyTorch 历史版本安装说明](https://pytorch.org/get-started/previous-versions/#v251)。三套视觉 demo 不使用 torchaudio；RoPE 使用已有 PyTorch 回退，不要求编译 CUDA 扩展。

## 定义范围和版本依据

直接依赖来自已保存的 [DUSt3R](https://github.com/naver/dust3r/blob/a53d073bb07455f5a3e7fcbeaaea240c159c4f08/requirements.txt)、[MASt3R](https://github.com/naver/mast3r/blob/f5209afc300cec36239a7ac992263f36847bbba0/requirements.txt)及其 [DUSt3R 子模块](https://github.com/naver/dust3r/blob/3cc8c88c413bb9e34c41db0e0eef99c2ee010b12/requirements.txt)、[VGGT](https://github.com/facebookresearch/vggt/blob/a288dd0f14786c93483e45524328726ab7b1b4ce/requirements.txt)与 [demo 依赖](https://github.com/facebookresearch/vggt/blob/a288dd0f14786c93483e45524328726ab7b1b4ce/requirements_demo.txt)，并按当前实际 demo 的导入和使用范围筛选。核心版本来自本机已经完成推理验证的有效环境：DUSt3R／MASt3R 固定 Gradio 4.44.1 与 Pydantic 2.10.6；VGGT 固定 Gradio 5.17.1 与 Pydantic 2.10.6。FastAPI 和 huggingface-hub 也固定为与当前页面兼容的版本。

VGGT 官方基础文件使用较旧的 Torch 和 NumPy；本工程定义采用已经在本机运行验证的 Torch 2.5.1、NumPy 2.0.1，并针对本地相机／深度分支和官方 GLB 导出。定义没有加入训练、COLMAP、Viser、ASMK 检索、天空分割 ONNX 或完整视觉定位依赖。需要这些功能时应另行补充对应官方依赖，并验证具体功能。DUSt3R／MASt3R 保留当前 HEIF 图像支持依赖。

这些是固定直接依赖版本的最小安装定义，传递依赖仍由 pip 解析，不是全量传递依赖锁。2026-10-14 已在本机新建三个干净环境，按这套定义完成安装、模块隔离检查和真实双图 GPU 推理；实际结果与验证范围见[验证基线](../validation.md)。其他机器仍需完成自己的验收。

## 安装定义与验收

本仓库分发可安装的 Python 基础和 core 依赖文件，不分发个人环境的 freeze 或 Conda 构建路径。YAML 与命令使用 conda-forge 基础环境，再分别安装官方 Torch wheel 与模型依赖。

2026-10-14 已从干净基础建立三套环境，完成依赖检查、模块隔离、NumPy / Torch 数据互转、真实双图 GPU 推理与网页流程。首套实际下载官方 Torch wheel，另两套复用 pip HTTP 缓存；已有权重经字节数与 SHA-256 复核后复用。没有复制旧环境的 Python 包，也没有执行历史 DLL 修复。

完整条件和实测结果见[验证记录](../validation.md)。新的直接依赖或源码提交变更需重新验收受影响模型。安装教程会保护同名环境，并在生成本机 `workspace.json` 前备份已有配置。
