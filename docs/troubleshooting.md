# 安装与 Demo 排错

[返回安装教程](windows-setup.md) · [模型操作](models/README.md)

先找到本次日志的第一个异常，确认失败发生在源码、环境、权重、启动还是重建阶段。`pip install` 成功不能替代真实推理和下载验收。

| 现象 | 优先检查与处理 |
|---|---|
| Git 子模块目录为空 | 从仓库根目录执行 `git submodule update --init --recursive`，检查命令退出码。源码均来自官方公开仓库；ZIP 不展开子模块。 |
| DUSt3R 返回值解包报错，或 GLB 下载控件缺失 | 执行 `scripts/apply-source-patches.ps1`。确认官方 DUSt3R / CroCo 固定提交未被升级；补丁失败时保留自己的源码修改，不强制覆盖。 |
| `conda` 找不到 | 用安装工具的 Prompt 检查 Conda，按官方说明初始化 PowerShell 后重开终端。 |
| 同名环境目录已存在 | 教程会在创建前停止。确认已有环境用途和实际解释器，保留可用环境；不要为了重跑教程删除它。 |
| Required file missing / `workspace.json` 不存在 | 先按安装教程生成本机配置，核对解释器、源码与 checkpoint。克隆不包含个人配置或权重。 |
| CUDA 为 False | 检查 `nvidia-smi`、实际解释器与 Torch `+cu121`，运行 doctor；终端的 `(base)` 标签不是 Demo 的环境证据。 |
| VGGT 不支持 bfloat16 | 当前入口要求支持 bfloat16 的 CUDA GPU。该硬件路径未通过时，不应视为配置成功。 |
| CUDA out of memory | 先停止另一套模型与手工 GPU 服务，用两张图、VGGT 宽度 294 验收，再逐步增加输入。 |
| 端口占用 | 检查监听进程；停止自己的服务或调整本机配置端口，不随意结束其他 Python。 |
| 页面退出或启动超时 | 查看本次 stderr 的首个异常，执行对应环境的 `pip check`。不要盲目升级 Gradio、Pydantic 或 Torch。 |
| 权重 SHA / 字节数不一致 | 保留下载文件，检查来源是否返回 HTML、下载是否完整；不要绕过校验后加载。 |
| OpenMP Error #15 / 重复包元数据 | 先确认是否混用了旧环境。本项目干净安装基线未出现该问题，不要套用历史 DLL 改名经验或设置 `KMP_DUPLICATE_LIB_OK` 掩盖错误。 |

## 查日志和端口

启动器将 stdout / stderr 保存在 `outputs/runtime/`，服务状态在 `demo-process.json`。手工启动的服务需在原终端用 `Ctrl+C` 停止，统一启动器只管理自己记录的服务。

```powershell
Get-NetTCPConnection -LocalPort 7860 -State Listen -ErrorAction SilentlyContinue
# 按模型将 7860 替换为 7861 或 7862。
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -Stop
```

## 依赖与网络

`workspace.json` 决定启动器的解释器。使用对应环境执行检查，不把依赖安装到 `base`：

```powershell
conda run -n dust3r-demo python -m pip check
if ($LASTEXITCODE -ne 0) { throw 'Dependency check failed' }
conda run -n dust3r-demo python -c "import sys,torch; print(sys.executable, torch.__version__, torch.cuda.is_available())"
if ($LASTEXITCODE -ne 0) { throw 'Runtime check failed' }
```

必要时为单次 Git、pip 或 curl 命令传入真实可用的代理；不要关闭证书校验。localhost 应绕过代理，启动器已设置排除。没有代理时不要照搬 `127.0.0.1:7890`。

如果仍无法定位，使用[问题模板](../.github/ISSUE_TEMPLATE/bug_report.yml)提供实际版本、输入设置、复现命令和相关错误片段。发布前移除 token、私有凭据和不希望公开的个人信息。
