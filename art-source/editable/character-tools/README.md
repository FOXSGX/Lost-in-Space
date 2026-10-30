# 角色专属工具（Blender 源）

## 文件

| 文件 | 内容 |
| --- | --- |
| `build_character_tools.py` | 生成四件工具与护盾罩的 Blender 脚本 |
| `../../game/assets/characters/tools/tool_conduit.glb` | 导能枪 |
| `../../game/assets/characters/tools/tool_hook.glb` | 磁力钩索 |
| `../../game/assets/characters/tools/tool_scanner.glb` | 广域扫描仪 |
| `../../game/assets/characters/tools/tool_shield.glb` | 便携护盾发射器 |
| `../../game/assets/characters/tools/shield_dome.glb` | 护盾罩（半透明球 + 发光底环） |

## 重新生成

```powershell
tools\blender-5.2.2-windows-x64\blender.exe --background --python art-source\editable\character-tools\build_character_tools.py
tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path game --editor --quit
```

## 坐标与朝向约定（踩过的坑）

- 脚本里按 **Y 轴向上**建模，导出时根节点绕 X 旋转 +90°，因此 Godot 里得到的模型会**多转 90°**。
- `protagonist_visual.gd` 的 `set_tool_model()` 用 `rotation_degrees = (-90, 0, 12)` 把这次旋转补偿回来，让工具呈水平握持姿态。
- 工具挂点：角色背包右侧腰间 `(0.46, 1.04, 0.34)`，缩放 1.7。之前试过握在手心，第三人称背后视角几乎看不见，所以改为腰挂。
- 角色本体是程序化生成的（`protagonist_model.json`），没有骨骼动画，因此工具只能是刚体挂件，不做握持动画。

## 材质

- 外壳 `CT_Shell` 亮铁灰、边条 `CT_Edge` 浅钢、握把 `CT_Grip` 深灰。
- 发光件：`CT_Cyan`（导能枪/护盾）、`CT_Amber`（钩索）、`CT_Teal`（扫描仪）。
- 第一版外壳过暗（0.12/0.15/0.20），在深色背包前几乎看不见，后来提到 0.30/0.36/0.44。
