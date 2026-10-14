# 模型操作目录

先完成[共用 Windows 安装教程](../windows-setup.md)，再从下面选择一个模型。所有命令在仓库根目录运行。

| 模型 | 本指南的用途 | 官方样图 | 结果 |
|---|---|---|---|
| [DUSt3R](dust3r.md) | 双图全局对齐与网格/点云查看 | Chateau1 / Chateau2 | GLB、RGB/深度/置信度图库 |
| [MASt3R](mast3r.md) | 匹配与 sparse global alignment | Chateau1 / Chateau2 | GLB 点云与相机 |
| [VGGT](vggt.md) | 相机/深度预测与反投影点云 | kitchen 00 / 01 | GLB、NPZ 预测 |

目前验收条件见[验证记录](../validation.md)。显存、耗时和顶点数只对应记录的样图及设置；模型选择不能仅凭顶点数或画面观感判断精度。

新增模型按照[贡献指南](../../CONTRIBUTING.md)补齐来源、独立依赖、配置、入口、操作页及验证记录。仅列出官方链接或安装命令时应标注为“待验证”，不要加入已支持列表。
