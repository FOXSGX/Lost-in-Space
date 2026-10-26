# 实体物品与物品栏原稿

2026-10-22。用于主舱、训练室和星球共用的两格物品栏。

## 模型

`game/scripts/item_prop_3d.gd` 组合现有 Kenney `container.glb`、`container-wide.glb`、`pipe.glb`，分别制作医疗补给、电池箱和氧气瓶；医疗十字、能量条、样本晶体是代码定义的几何细节。欢乐道具使用有区别的面板颜色表示收纳设备，使用后继续生成原有实际效果。大型合作货物继续显示原关卡模型，同时占用物品格。

原包和 CC0 授权位于 `art-source/third-party/kenney/`，对应运行副本和 SHA-256 已在 `../kenney-layout/asset-manifest.json` 登记。本轮没有新增下载源或修改原始模型。

## 图标与预览

- `generate_icons.py`：项目内编写的矢量图标生成器，从任意目录执行可重建源 SVG 与游戏副本。
- `icons/`：12 个 SVG 原稿；游戏副本位于 `game/assets/items/icons/`。
- `previews/`：由 `game/tests/inventory_input.gd` 在真实图形运行中生成，包含共享架实体、满格图标物品栏、空格留白、训练室全景、两侧出入口落点及精简设置页，共 7 张。

训练室的原生模块排布维护在 `game/scripts/ship_tutorial_3d.gd`，没有独立 Blender 合并场景。原有 Blender 工程继续保留。

## 实现边界

小物品为可拾取的静态实体；放下时向下检测地面/台面，不采用滚动物理或投掷模拟。手持模型、世界实体与图标使用同一物品 ID；实体数量、两格容量和消耗由主机确认。没有空中悬浮名称牌。
