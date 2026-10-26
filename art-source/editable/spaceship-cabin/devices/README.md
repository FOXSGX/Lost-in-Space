# 主舱实体设备与四驾驶台

2026-10-22。沿用已登记的 Kenney CC0 资产，没有新增下载或覆盖 Blender 原稿。

- `game/scripts/ship_hub_kenney_art.gd`：四套 `computer-wide.glb` 驾驶台、座椅与仪表。
- `game/scripts/ship_devices_3d.gd`：28 个设备交互点，新增操作终端使用 `computer-system.glb`，状态文字贴在有实际厚度的屏幕上，关闭 billboard 和穿透显示。所有新终端均有碰撞体，驾驶台保留原舰桥平台碰撞。
- 原包、运行副本、SHA-256 与 CC0 记录继续使用 `../kenney-layout/asset-manifest.json` 及 `art-source/licenses/kenney-2026-10-22.md`。
- `previews/`：`game/tests/ship_devices_input.gd` 通过有画面的实际输入流程生成，依次展示四驾驶台、就位、航线终端、装备终端、倒数和离舰确认。

设备排布与实体屏幕由 Godot 源码维护；全局玩法与联机验证见 `game/docs/ship-devices.md`。
