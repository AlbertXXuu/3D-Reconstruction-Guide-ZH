# 新文章、新项目和新模型怎样接入

本指南持续接收三类内容：原创阅读文章、可复现的项目操作、可运行的模型 Demo。先选对应入口，不必把每篇论文都做成模型，也不必让每个工具接入网页启动器。

| 新内容 | 公开内容的位置 | 起步模板 | 本地资源 |
|---|---|---|---|
| 论文、文章、方法解释 | [docs/articles](articles/README.md) | [文章模板](templates/article.md) | 原文、阅读附件和内部笔记保留个人研究目录 |
| 数据集、工具、评测或组合实验 | [docs/projects](projects/README.md) | [项目模板](templates/project.md) | 独立项目源码、环境、输入与实验输出 |
| 模型网页 Demo | [docs/models](models/README.md) | [模型模板](templates/model.md) | 固定官方源码、独立环境、本地权重和样图 |

新内容可以标注“待阅读”或“待验证”先进入文章/项目目录；只有实际完成文中流程，才标为已验证。公开页链接一手来源，用原创表达整理方法、命令和结果。第三方原文、内部材料和个人数据不随 Guide 上传。

## 1. 发现内容后先记录

记录标题、官方论文/仓库链接、发布日期、核查日期、源码版本和与你当前任务的关系。文章先记录作者主张与尚未核实的部分；项目先说明输入、输出和你需要完成的操作。

把笔记或操作页复制到对应目录，再在目录 README 添加一条链接、状态和用途。以下是占位文件名，使用自己的简称替换，并确认目标不存在：

```powershell
$entryPath = 'docs/articles/my-reading-note.md'
if (Test-Path -LiteralPath $entryPath) { throw 'Entry exists; edit the existing article' }
Copy-Item -LiteralPath 'docs/templates/article.md' -Destination $entryPath -ErrorAction Stop
```

项目和模型同样使用 `docs/templates/project.md`、`docs/templates/model.md`，分别复制到对应目录。只补充当前确实需要的段落，不把填写提示和预期结果当作成品。

## 2. 本地资源怎样复用

源码按模型使用 `repos/<model>`，权重按模型使用 `checkpoints/<model>`，输入在 `data/`，每次运行的产物在 `outputs/`。这些数据目录和本机 `workspace.json` 不提交；Python 环境也不进 Git。研究 PDF、内部汇报和私人实验留在各自研究项目中。

已有权重无需重复下载。`workspace.json` 的 `checkpoint` 可以填本机共享文件的绝对路径，也可以使用指向共享目录的 Junction。启动器和 doctor 都区分绝对路径与仓库相对路径，包含空格的路径也可检查。公开 `workspace.example.json` 保持占位或仓库相对路径。

`repository` 是启动时的工作目录。现有三个包装器仍从本 Guide 的固定 `repos/<model>` 导入官方代码；仅修改该字段不会替换包装器内部的源码导入。新入口要明确自己的导入位置，避免把已经验证的源码换成另一份未验版本。

本地实验成熟后，只将可公开的原创说明、安装定义、维护脚本和验证摘要整理进 Guide，不把整个私人项目复制进来。文章与实验各保留自己的状态，结果条件改变时新增记录，保留之前的适用范围。

## 3. 接入一个新的模型 Demo

当前统一启动器适用于接受 `--port` 与 `--weights` 的 Python 网页包装器。训练程序、命令行工具或不符合此约定的项目，使用自己的入口并在项目页说明。

新增模型时补齐：固定官方源码与子模块、独立环境依赖、权重来源与校验、包装器、配置、模型操作页和验证记录。具体要求见[贡献指南](../CONTRIBUTING.md)。启动器按本机配置读取模型名称，新增名称不需要修改固定枚举。

在 `workspace.example.json.models` 中增加配置。下面仅说明字段，不代表新增模型已经支持：

```json
{
  "example-model": {
    "environment": "example-model-demo",
    "python": "C:/path/to/conda/envs/example-model-demo/python.exe",
    "script": "scripts/example_model_demo.py",
    "repository": "repos/example-model",
    "port": 7863,
    "checkpoint": "checkpoints/example-model/model.pth",
    "checks": {"imports": ["torch", "numpy", "gradio"], "cuda": true, "bf16": false}
  }
}
```

模型键使用小写字母开头，后接字母、数字、短横线或下划线，最多 64 字符。`environment` 指定已有的命名 Conda 环境；省略时配置生成器使用 `<model>-demo`。`checks.imports` 是需要导入的模块名，省略时使用现有三个模型的公共依赖；`cuda` 默认要求可用，`bf16` 默认不要求。CPU 入口可明确写 `cuda: false` 并填写自身模块列表。

生成配置前先建立对应环境；以下命令只查询解释器，不安装包或创建环境。已有本机配置会先完整备份：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-workspace.ps1
if ($LASTEXITCODE -ne 0) { throw 'Configuration failed; inspect the error' }
```

生成器面向命名 Conda 环境。使用 venv 等环境时可直接编辑本机配置的 `python`，然后进行以下检查。新模型不必先检查其他模型环境：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -Model example-model -Check
if ($LASTEXITCODE -ne 0) { throw 'Model preflight failed' }
conda run -n example-model-demo python -B scripts/doctor.py --model example-model --output outputs/setup/example-model-doctor.json
if ($LASTEXITCODE -ne 0) { throw 'Model environment check failed' }
```

`-Check` 不启动模型、不修改运行状态、不停止当前服务；`port_available: false` 表示需要在启动前处理端口。doctor 检查选定模型的文件、依赖导入、pip 依赖关系与配置要求。两者均不能替代真实推理、网页操作和结果读回。

## 4. 发布一份可复现内容

运行与修改相关的检查，再按文件提交。文章修改不必重跑三个 GPU 模型；入口或依赖变化需要验证对应的实际流程：

```powershell
python -B scripts/check-project.py
if ($LASTEXITCODE -ne 0) { throw 'Project checks failed' }
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-powershell.ps1
if ($LASTEXITCODE -ne 0) { throw 'PowerShell checks failed' }
git status --short
```

更新对应文章/项目/模型索引。增加实际支持时更新[来源清单](model-sources.json)、[验证记录](validation.md)及必要入口，再提交 Pull Request 或有写权限的分支。GitHub Actions 检查文档、脚本及配置扩展逻辑；它不监控新论文，不自动导入第三方项目，也不执行 GPU 验收。
