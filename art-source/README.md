# 美术源文件索引

## 当前使用

- `ai-generated/protagonist/current/protagonist-faceted-simple-c-teal.png`：已选的青绿色主角概念图。
- `ai-generated/protagonist/current/protagonist-faceted-simple-c-teal-turnaround.png`：该主角的正面、侧面、背面三视图。

## 归档试稿

- `ai-generated/protagonist/archive/`：此前的角色探索图，保留供回看，不与当前方案混放。

## 参考图

- `references/characters/`：人物低多边形切面风格参考。
- `references/scenes/`：用户提供的场景方向参考，与本次人物设计分开存放。

`editable/` 用于后续可编辑原稿，`licenses/` 用于素材授权记录。

## 主角 3D 实现

- `editable/protagonist/protagonist_model.json`：可编辑的部件结构、位置、尺寸与配色源文件，正面朝 `-Z`。
- `editable/protagonist/godot-preview.png`、`editable/protagonist/godot-topdown-preview.png`：Godot 实际渲染的三视角与正交俯视预览；它们是检查图，不是网格原稿。
- 游戏内副本：`../game/assets/characters/protagonist_model.json`，调整源文件后需同步复制。
- 网格由 `../game/scripts/protagonist_visual.gd` 按数据生成，为可动部件的真实 3D 三角形网格；场景入口为 `../game/scenes/protagonist_visual.tscn`。
