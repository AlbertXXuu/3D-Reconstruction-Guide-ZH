# Windows 环境配置与操作步骤

本教程面向 Windows x64、PowerShell、NVIDIA GPU，准备 DUSt3R、MASt3R 和 VGGT 的本地网页 Demo。更新日期：2026-10-14。已从 GitHub 递归克隆的源码按本教程建立三个干净环境，完成真实双图 GPU 推理及网页上传、显示、下载验收，详见[验证基线](validation.md)。验证发生在现有 Windows / RTX 4060 Laptop 机器上，未验证另一台机器或其他操作系统。

## 1. 系统工具与完整源码

安装 [Git for Windows](https://git-scm.com/downloads/win) 和 [Miniforge Windows x86_64](https://github.com/conda-forge/miniforge#requirements-and-installers)，已有 Git 和 Conda 时复用。初次安装 Miniforge 后，可从 Miniforge Prompt 执行下列命令，再打开新的 PowerShell。初始化会修改当前用户 shell 配置，已有 conda 可用时无需执行。[Miniforge 官方说明](https://github.com/conda-forge/miniforge#condamamba-usable-in-any-terminals)

```powershell
conda init powershell
```

安装适合显卡的 [NVIDIA 驱动](https://www.nvidia.com/en-us/drivers/)，确认下面三个命令成功：

```powershell
git --version
conda --version
nvidia-smi
```

本教程安装 PyTorch CUDA 12.1 wheel，日常 Demo 不编译 CUDA 扩展，不要求另装完整 CUDA Toolkit。当前 VGGT 省显存实现要求 CUDA GPU 支持 bfloat16，环境检查会确认。

本项目独立使用三个公开的官方源码子模块，不需要作者的研究工作区或私有源码仓库。下面在自己的项目目录中执行，路径可替换：

```powershell
$projectDirectory = Join-Path $env:USERPROFILE 'Projects'
New-Item -ItemType Directory -Path $projectDirectory -Force | Out-Null
Set-Location -LiteralPath $projectDirectory
git clone --recurse-submodules https://github.com/AlbertXXuu/3D-Reconstruction-Guide-ZH.git
if ($LASTEXITCODE -ne 0) { throw 'Clone failed; check network and repository access' }
Set-Location -LiteralPath '.\3D-Reconstruction-Guide-ZH'
```

后续命令都在仓库根目录运行。三份默认权重合计约 9.38 GiB，环境与下载缓存另计，先确认磁盘空间充足。模型权重、自己的照片与运行结果不随 Git 克隆下载。GitHub ZIP 不包含源码子模块，应使用 Git 克隆。

## 2. 确认源码与固定子模块

首次未加 `--recurse-submodules`，或子模块下载中断时，在本目录运行：

```powershell
git submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { throw 'Submodule update failed' }
git submodule status --recursive
```

`submodule status` 的 `-` 前缀表示未初始化，`+` 表示当前版本与父仓库记录不一致。日常还原固定版本用上面的命令；不要用 `--remote` 自动升级源码。

| 目录 | 版本与来源 |
|---|---|
| `repos/dust3r` | 官方 `naver/dust3r`，固定 `a53d073bb07455f5a3e7fcbeaaea240c159c4f08`；另应用本项目明确列出的网页补丁 |
| `repos/dust3r/croco` | 官方 CroCo，随该 DUSt3R 提交固定为 `743ee71a2a9bf57cea6832a9064a70a0597fcfcb` |
| `repos/mast3r` | 官方 `naver/mast3r`，固定 `f5209afc300cec36239a7ac992263f36847bbba0` |
| `repos/mast3r/dust3r` | MASt3R 的官方 DUSt3R 子模块，固定 `3cc8c88c413bb9e34c41db0e0eef99c2ee010b12` |
| `repos/mast3r/dust3r/croco` | 官方 CroCo 子模块，固定 `d7de0705845239092414480bd829228723bf20de` |
| `repos/vggt` | 官方 `facebookresearch/vggt`，固定 `a288dd0f14786c93483e45524328726ab7b1b4ce` |

来源详见 [model-sources.json](model-sources.json)。MASt3R 自带的 DUSt3R/CroCo 与独立 DUSt3R 固定版本不同，不能互换目录。先应用 DUSt3R 的 Gradio 4 网页补丁，再继续源码检查；该补丁提供可见的 GLB 下载和一致的事件返回值。重复执行会检查已应用状态，不覆盖其他源码修改。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-source-patches.ps1
if ($LASTEXITCODE -ne 0) { throw 'Source patch failed; preserve changes and inspect the error' }

$requiredSources = @(
    'repos/dust3r/dust3r/demo.py',
    'repos/dust3r/croco/assets/Chateau1.png',
    'repos/mast3r/mast3r/demo.py',
    'repos/mast3r/dust3r/croco/assets/Chateau2.png',
    'repos/vggt/vggt/models/vggt.py',
    'repos/vggt/visual_util.py',
    'repos/vggt/examples/kitchen/images/00.png'
)
foreach ($source in $requiredSources) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Source missing: $source" }
}
```

## 3. 建立三个独立环境

[环境定义说明](environments/README.md)解释基础 YAML 与固定直接依赖的区别。以下创建 `dust3r-demo`、`mast3r-demo`、`vggt-demo`。先检查全部目标目录；任何同名目录已存在就停止，已有可用环境可直接跳到配置和验证步骤。Conda 25.5.1 的 `create -y` 会确认移除同名环境，不能依靠创建命令本身保护旧环境，见[该版本官方实现](https://github.com/conda/conda/blob/25.5.1/conda/cli/main_create.py)。

```powershell
$models = @('dust3r', 'mast3r', 'vggt')
$condaInfoText = @(conda info --json)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Conda environment directories' }
$condaInfo = ($condaInfoText -join "`n") | ConvertFrom-Json
if (-not $condaInfo.envs_dirs) { throw 'Conda did not report environment directories' }
foreach ($model in $models) {
    $demoEnvironment = "$model-demo"
    foreach ($environmentDirectory in $condaInfo.envs_dirs) {
        $candidatePrefix = Join-Path $environmentDirectory $demoEnvironment
        if (Test-Path -LiteralPath $candidatePrefix) {
            throw "Directory already exists; preserve it and inspect first: $candidatePrefix"
        }
    }
}
foreach ($model in $models) {
    $demoEnvironment = "$model-demo"
    conda create --name $demoEnvironment --override-channels --channel conda-forge --no-default-packages python=3.11.13 pip=25.1 -y
    if ($LASTEXITCODE -ne 0) { throw "Create failed: $demoEnvironment" }
    conda run -n $demoEnvironment python -m pip install -r docs/environments/requirements-torch-cu121.txt
    if ($LASTEXITCODE -ne 0) { throw "PyTorch install failed: $demoEnvironment" }
    conda run -n $demoEnvironment python -m pip install --index-url https://pypi.org/simple -r "docs/environments/requirements-$model-core.txt"
    if ($LASTEXITCODE -ne 0) { throw "Core dependency install failed: $demoEnvironment" }
    conda run -n $demoEnvironment python -m pip check
    if ($LASTEXITCODE -ne 0) { throw "pip check failed: $demoEnvironment" }
    conda run -n $demoEnvironment python -c "import sys,torch; print(sys.executable); print(torch.__version__, torch.version.cuda, torch.cuda.is_available()); print('bf16:', torch.cuda.is_available() and torch.cuda.is_bf16_supported())"
    if ($LASTEXITCODE -ne 0) { throw "Runtime import failed: $demoEnvironment" }
}
```

期望 Torch 为 `2.5.1+cu121`、CUDA runtime 为 `12.1`、CUDA 可用为 `True`；VGGT 还需 `bf16: True`。基础 `pip=25.1` 表示 Conda 版本前缀，本次实际求解为 25.1.1。`conda run` 使用指定环境，不受 `(base)` 标签影响。不要用带 `file:///C:/b/...` 的历史 freeze 安装，也不要混装三套页面依赖。Torch 命令对应 [PyTorch 官方 2.5.1 说明](https://pytorch.org/get-started/previous-versions/#v251)。

## 4. 下载官方权重并核对 SHA-256

权重不提交 GitHub。SHA-256 对应当前保存的文件基线；DUSt3R 是原有本地保留权重，官方链接来自上游 README，尚未重新下载对比。VGGT 固定 Hugging Face revision，避免 `main` 后续变化。

| 模型 | 相对路径 | 字节数 | SHA-256 |
|---|---|---:|---|
| DUSt3R | `checkpoints/dust3r/DUSt3R_ViTLarge_BaseDecoder_512_dpt.pth` | 2,285,005,731 | `9f194a32e34fc124ed10f64115b8e848b7da87c2d1ed131d34b4806721c19dbd` |
| MASt3R | `checkpoints/mast3r/MASt3R_ViTLarge_BaseDecoder_512_catmlpdpt_metric.pth` | 2,754,910,614 | `e28f91b488554653e2b46ddae9c78c1143e0bcb2e27d3e26cdb0b717f1568eb2` |
| VGGT | `checkpoints/vggt/model.pt` | 5,026,874,952 | `d15bf50a8615c8225ed48b51ea5cac673d82442ec0309036df555a053253afe0` |

下载前阅读模型许可及数据集限制：[DUSt3R](https://github.com/naver/dust3r#license)、[MASt3R checkpoint notice](https://github.com/naver/mast3r/blob/f5209afc300cec36239a7ac992263f36847bbba0/CHECKPOINTS_NOTICE)、[VGGT-1B 模型说明](https://huggingface.co/facebook/VGGT-1B)。下面使用 `curl.exe` 下载到 `.partial`，校验成功再改为正式文件名。已有正式文件一致则跳过，不一致则停止并保留。

```powershell
$weights = @(
    @{ Path = 'checkpoints/dust3r/DUSt3R_ViTLarge_BaseDecoder_512_dpt.pth'; Bytes = 2285005731; Sha = '9f194a32e34fc124ed10f64115b8e848b7da87c2d1ed131d34b4806721c19dbd'; Url = 'https://download.europe.naverlabs.com/ComputerVision/DUSt3R/DUSt3R_ViTLarge_BaseDecoder_512_dpt.pth' },
    @{ Path = 'checkpoints/mast3r/MASt3R_ViTLarge_BaseDecoder_512_catmlpdpt_metric.pth'; Bytes = 2754910614; Sha = 'e28f91b488554653e2b46ddae9c78c1143e0bcb2e27d3e26cdb0b717f1568eb2'; Url = 'https://download.europe.naverlabs.com/ComputerVision/MASt3R/MASt3R_ViTLarge_BaseDecoder_512_catmlpdpt_metric.pth' },
    @{ Path = 'checkpoints/vggt/model.pt'; Bytes = 5026874952; Sha = 'd15bf50a8615c8225ed48b51ea5cac673d82442ec0309036df555a053253afe0'; Url = 'https://huggingface.co/facebook/VGGT-1B/resolve/860abec7937da0a4c03c41d3c269c366e82abdf9/model.pt' }
)
foreach ($weight in $weights) {
    New-Item -ItemType Directory -Path (Split-Path $weight.Path -Parent) -Force | Out-Null
    $downloadPath = if (Test-Path -LiteralPath $weight.Path) { $weight.Path } else { "$($weight.Path).partial" }
    if ($downloadPath.EndsWith('.partial')) {
        curl.exe --fail --location --retry 3 --continue-at - --output $downloadPath $weight.Url
        if ($LASTEXITCODE -ne 0) { throw "Download failed: $downloadPath" }
    }
    $actualBytes = (Get-Item -LiteralPath $downloadPath).Length
    $actualSha = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualBytes -ne $weight.Bytes -or $actualSha -ne $weight.Sha) { throw "Checkpoint mismatch; keep file for inspection: $downloadPath" }
    if ($downloadPath -ne $weight.Path) { Move-Item -LiteralPath $downloadPath -Destination $weight.Path }
    Write-Output "Verified: $($weight.Path)"
}
```

不要加载校验不一致的 checkpoint。来源内容变化或下载返回 HTML 时也会失败；先检查来源和字节数，不要删去校验。需要代理时给 curl 命令添加 `--proxy http://127.0.0.1:7890`，端口改为实际值。下载完成后 Demo 使用本地文件。

## 5. 生成本机配置并选择解释器

[workspace.example.json](../workspace.example.json)只含占位解释器路径；本步生成本机 `workspace.json`，该文件不随仓库分发。用模板与各环境实际 `sys.executable` 生成配置。已有可用配置时先备份再调整，不必重新生成。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-workspace.ps1
if ($LASTEXITCODE -ne 0) { throw 'Configuration generation failed; inspect the error' }
```

已有 `workspace.json` 会先完整备份到被 Git 忽略的 `outputs/setup/workspace-before-*.json`，备份失败则停止；需要恢复时将该文件复制回 `workspace.json`。新配置使用无 BOM 的 UTF-8，兼容 `doctor.py` 的读取。源码/权重相对路径不随盘符修改；启动器使用 JSON 解释器，编辑器选择不会改变启动器环境。

生成器按模板中的模型遍历，使用每个模型的 `environment`，省略时为 `<model>-demo`，只查询已有环境解释器。新增模型无需修改生成器；对应环境的创建和依赖安装仍按该模型教程执行。已有配置只需局部修改时可直接编辑本机文件，不必重新生成。共享权重可填本机绝对路径，公开模板不写入个人路径，见[扩展指南](extending.md)。

在 VS Code 中打开本仓库文件夹，安装 Python 扩展，再用 **Python: Select Interpreter → Enter interpreter path** 选择当前模型环境的实际 `python.exe`。启动器始终使用本机 `workspace.json`，编辑器选择不会自动切换 Demo 环境。[VS Code Python 设置说明](https://code.visualstudio.com/docs/python/settings-reference)

## 6. 检查、启动、停止

创建未上传的工作目录，检查解释器、源码、权重、模块导入、CUDA 与包依赖：

```powershell
New-Item -ItemType Directory -Path outputs/setup, outputs/runtime, data/photos -Force | Out-Null
conda run -n dust3r-demo python -B scripts/doctor.py --output outputs/setup/doctor.json
if ($LASTEXITCODE -ne 0) { throw 'Environment check failed; inspect doctor.json before inference' }
```

最低验收条件是检查总体 `passed: true`，再完成至少一次样图重建和下载验证。doctor 不加载模型，不替代推理。

新增或单独排查一个模型时可用 `doctor.py --model <name>`。启动前用 `start-demo.ps1 -Model <name> -Check` 检查配置与路径，它不会启动模型或停止当前服务；实际使用的名称来自本机配置。

双击 `启动DUSt3R.cmd`、`启动MASt3R.cmd`、`启动VGGT.cmd`，或执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -Model dust3r
# 将 dust3r 改为 mast3r 或 vggt 可切换模型。
```

DUSt3R 为 `http://127.0.0.1:7860/`，MASt3R 为 `http://127.0.0.1:7861/`，VGGT 为 `http://127.0.0.1:7862/`。启动器等页面就绪后打开浏览器，追加 `-NoBrowser` 可只启动。默认管理一套服务，切换时停止上一套受管理进程。它不会停止其他终端手工启动的 Python；手工服务在原终端用 `Ctrl+C` 结束。

结束后双击 `停止Demo.cmd`，或执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -Stop
```

执行策略仅用于该进程，不用修改用户/系统策略。页面只监听本机，不创建公开分享。日志在 `outputs/runtime/` 的 stdout/stderr 文件；结果在 `outputs/<模型>/`。

## 7. 首次体验与真实推理检查

| 模型 | 样例操作 | 期望结果 |
|---|---|---|
| DUSt3R | 上传 `repos/dust3r/croco/assets/Chateau1.png` 和 `Chateau2.png`，点击 Run | 可旋转场景、RGB/深度/置信度图、GLB 下载 |
| MASt3R | 上传 `repos/mast3r/dust3r/croco/assets/` 的两张 Chateau 图，coarse iterations 30、refinement 20，点击 Run | 含两相机的场景、GLB 下载并可重新打开 |
| VGGT | 点击 kitchen 双图样例，再点“开始重建”；首次宽度 294 | GLB 场景与 NPZ 预测可下载 |

个人照片先选同一静态场景的两张，有重叠、不同视角、清楚纹理且不过曝。VGGT 限 1–4 张；更高分辨率和更多照片的显存需求要逐步验证。

无页面的 smoke 使用真实样图和权重。先停止 Demo，再依次运行：

```powershell
conda run -n dust3r-demo python -B scripts/dust3r_smoke.py
if ($LASTEXITCODE -ne 0) { throw 'DUSt3R smoke failed' }
conda run -n mast3r-demo python -B scripts/mast3r_smoke.py
if ($LASTEXITCODE -ne 0) { throw 'MASt3R smoke failed' }
conda run -n vggt-demo python -B scripts/vggt_smoke.py
if ($LASTEXITCODE -ne 0) { throw 'VGGT smoke failed' }
```

DUSt3R/VGGT 生成运行目录；MASt3R smoke 复用 `outputs/mast3r/smoke/`，不要放个人原始数据。成功要求有效预测、导出与 GLB 读回，VGGT 还检查 NPZ 有限值。完整训练、玻璃专用加载、定位、天空分割、视频与跟踪不在当前验证范围。

## 8. 排错与维护

安装报错、显存、端口和下载问题集中在[排错手册](troubleshooting.md)。模型各自的操作及设置见[模型目录](models/README.md)。

Git 只管理原创脚本、教程、通用模板、补丁和官方子模块版本。`workspace.json`、权重、数据和输出保留本机。更新时先查看 [model-sources.json](model-sources.json) 与[验证记录](validation.md)，不要运行 `git submodule update --remote` 自动升级源码。新增模型与文档按[贡献指南](../CONTRIBUTING.md)补齐验收。
