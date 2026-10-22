# Kenney 主舱排布

日期：2026-10-22。按用户要求，采用新下载的 Space Station Kit 和 Modular Space Kit 优化第一人称主舱。

## 编辑与来源

- 原包：`art-source/third-party/kenney/`，包含原始 GLB、调色板、预览与 CC0 授权。
- 排布源码：`game/scripts/ship_hub_kenney_art.gd`，可调整模型种类、位置、底部高度、目标尺寸、朝向和材质。
- 游戏副本：`game/assets/ship-hub/kenney/`，保留原始 GLB 与外置贴图路径。
- `asset-manifest.json`：28 个模型副本的原包路径、游戏路径和 SHA-256。
- `instrument-panel.svg`：本项目编写的仪表矢量原稿，运行副本为 `game/assets/ship-hub/ship_instrument_panel.svg`。
- `previews/`：Godot 4.7.2 第一人称实机画面，包含主舱、舰桥、维修台、维修面板、地面区域文字、训练舱、生活侧舱与后部气闸。
- `capture.gd`：实机截图脚本。用 Godot 的 `--path game --script art-source/editable/spaceship-cabin/kenney-layout/capture.gd` 运行（脚本路径需使用绝对路径，且不能使用 `--headless`），自动创建临时主机并保存八张预览，不写入玩家存档。

运行 `game/project.godot` 并创建主机即可查看完整排布。场景由 Godot 原生实例组成；本目录不是新的 Blender 合并模型。上一轮 Blender 工程仍在 `../blender-v2/`，保留其星空窗与植物。

## 尺度约定

Y 为高度，驾驶台位于 -Z，气闸位于 +Z。地面顶面为 Y=0，中央舱顶约 4.85 米、两侧约 3.5 米，第一人称眼高 1.6 米。`_asset()` 从模型层级包围盒计算底部中心与缩放；默认等比缩放，墙板、地板及部分底座按指定目标尺寸缩放。

中央星图组合原包桌座、行星和星环；通过移除原星图模型的低矮底座网格保留子节点，再应用青色扫描线投影材质。新增肋架、斜面顶棚、隔舱壁和门框围合中央通道，生活区改为双层卧铺。各原包文件没有回写。

验证范围与已知问题见 `game/docs/ship-hub-kenney-art.md`。
