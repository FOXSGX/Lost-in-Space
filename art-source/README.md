# 美术源文件索引

## 当前使用

- `ai-generated/protagonist/current/protagonist-faceted-simple-c-teal.png`：已选的青绿色主角概念图。
- `ai-generated/protagonist/current/protagonist-faceted-simple-c-teal-turnaround.png`：该主角的正面、侧面、背面三视图。

## 归档试稿

- `ai-generated/protagonist/archive/`：此前的角色探索图，保留供回看，不与当前方案混放。

## 飞船舱探索

- `ai-generated/spaceship-cabin/concepts/ship-hub-v2.png`：当前主枢纽舱概念图；过小的早期舱室图放在 `archive/`。
- `ai-generated/spaceship-cabin/README.md`：需求、布局建议与待讨论事项。
- `editable/spaceship-cabin/`：对应的可编辑 3D 源脚本、GLB 模型、预览和交互位置建议。

## 共振星高细节资产

- `generated/resonance/resonance-grounded-factory-concept.png`：行星地表工业工厂概念参考，确定地面、轨道、移动模块和反应堆的空间关系。
- `editable/resonance/build_resonance_module_hero.py`：Blender 5.2.2 便携版生成器，负责导出第一个高细节移动模块。
- `editable/resonance/resonance_module_hero.blend`：可继续手工修改的 Blender 源文件。
- `editable/resonance/resonance_module_hero-preview.png`：独立建模审阅图，不进入游戏运行时。
- `../game/assets/resonance/models/resonance_module_hero.glb`：Godot 使用的运行时模型；具体导入和验证规则见 `../game/docs/resonance-asset-pipeline.md`。

## 团队交付包（2026-11-21）

- `deliveries/ART-SAMPLE-002_TEAM_KIT/`：队友交付的第一套可复用美术母版。`01_GODOT_DEMO/` 是独立可运行工程，`02_BLENDER_SOURCE/` 是高模到低模的烘焙源，`03_GAME_READY_ASSETS/` 是可直接导入的 GLB，`04_MATERIAL_LIBRARY/` 是 2K 材质库与材质脚本，`05_ART_STYLE_GUIDE/` 是规范，`06_REFERENCE/` 是新旧对照与四机位，`07_VERIFICATION/` 是测试与校验记录，`08_TEAM_STARTER/` 是新星球模板。
- 该包保持原始结构，不在 `art-source/` 内拆散；某颗星球真正采用某件资产时，再把对应 GLB 复制到 `../game/assets/` 并在该星球说明里登记来源。原始压缩包存于 `../work/incoming-20261121/`。
- `01_GODOT_DEMO/` 已导入过一次，`.godot/` 缓存保留（约 52 MB，Git 忽略）。如果这个缓存被删掉，直接用 Godot 运行会因为缺 `.ctex` 报一串 `Unable to open file` —— 用编辑器打开一次，或先跑 `godot --headless --path <该目录> --import` 再运行即可。

## 参考图

- `references/characters/`：人物低多边形切面风格参考。
- `references/scenes/`：用户提供的场景方向参考，与本次人物设计分开存放。

`editable/` 用于后续可编辑原稿，`licenses/` 用于素材授权记录。

## 主角 3D 实现

- `editable/protagonist/protagonist_model.json`：可编辑的部件结构、位置、尺寸与配色源文件，正面朝 `-Z`。
- `editable/protagonist/godot-preview.png`、`editable/protagonist/godot-topdown-preview.png`：Godot 实际渲染的三视角与正交俯视预览；它们是检查图，不是网格原稿。
- 游戏内副本：`../game/assets/characters/protagonist_model.json`，调整源文件后需同步复制。
- 网格由 `../game/scripts/protagonist_visual.gd` 按数据生成，为可动部件的真实 3D 三角形网格；场景入口为 `../game/scenes/protagonist_visual.tscn`。
