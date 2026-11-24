# ZIP 解压复验记录（ART-SAMPLE-002_TEAM_KIT.zip）

## 复验步骤与结果

| 步骤 | 操作 | 结果 |
|---|---|---|
| 1 | 生成 ZIP（Compress-Archive, Optimal） | `ART-SAMPLE-002_TEAM_KIT.zip`，171 MB |
| 2 | 解压到**全新独立目录**（与工作树无任何关联） | 207 个文件，9 个顶层目录齐全 |
| 3 | 按包内 `SHA256SUMS.txt` 逐文件复核 | **206/206 全等，异常 0** |
| 4 | 用 Godot 4.7.2 对解压副本 `--import` | 成功，生成 52 个导入资源（.scn） |
| 5 | 运行解压副本的 `01_GODOT_DEMO`，截图 | 成功（见 `verify_render_after_unzip.png`） |
| 6 | 打开解压副本的 `aqs002_head.blend` | 对象 `HeadHigh`(64 356 tris) / `HeadLow`(3 928 tris)、贴图 `HeadNormal/HeadAO/HeadCurv` 均存在且已打包 |

## 环境说明（如实记录）

第一次尝试把 ZIP 解压到 `%TEMP%` 与 `C:\kit_verify` 时，Godot 报
`Could not create project data directory (res://.godot)`——用**一个最小探针工程**在同一位置
复现了同样错误，确认这是**本机沙箱对工作区外新建目录的限制**，不是包的问题。
因此复验改在仓库内全新目录 `work/art-sample-002/_zipcheck/` 完成；
该目录与制作目录互不依赖，解压后重新导入、运行、截图全部通过。

## 队友在自己机器上的建议步骤

```
1) 解压 ZIP 到任意本地目录（路径不要含版本控制目录）
2) Godot 4.7.2 → 导入 → 选择 01_GODOT_DEMO/project.godot
3) F5 运行；空格拉锤，F1 切机位
4) 若要改模型：Blender 5.2.2 打开 02_BLENDER_SOURCE/*.blend（贴图已打包）
```

## SHA256 清单

见 `07_VERIFICATION/SHA256SUMS.txt`（206 行，逐文件）。
