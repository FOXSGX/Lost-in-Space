# 第三方工具与素材接入

本目录记录随项目一起维护的外部/团队工具包位置与接入方式。

## LIS Physics

- 版本：`1.0.0-rc1`（候选版，不是正式稳定版）
- 运行库：`game/addons/lis_physics/`
- 完整文档/示例/测试：`docs/third-party/lis-physics/`
- 入口文档：`docs/third-party/lis-physics/README.md`
- 接入文档：`docs/third-party/lis-physics/INTEGRATION_GUIDE.md`
- 工程检查：

```powershell
$godot = "D:\develop\lost_in_space\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path game --script res://addons/lis_physics/tools/lis_project_check.gd
```

项目接入：

- Godot 4.7.2，`physics/3d/physics_engine = "Jolt Physics"`
- `physics/common/physics_ticks_per_second = 60`
- 3D 碰撞层：1 Players、2 World、3 interactable、4 machines
- 腐墟星能源站 1F 的维护门是 `LISHingeDoor`：玩家按 E 推门，门由 `RigidBody3D + HingeJoint3D` 真实转动。

## ART-SAMPLE-002 TEAM KIT

- 完整团队包（模型/贴图/shader/Blender 源文件/规范/验收图）：
  `art-source/third-party/ART-SAMPLE-002_TEAM_KIT/`
- 游戏运行时用的子集：
  `game/assets/art-sample-002/`
  - `models/`：7 个 GLB
  - `textures/`：2K 金属/岩石/晶体/混凝土/喷漆贴图
  - `shaders/`：`aqs2_*.gdshader`
  - `hero_lib.gd`：已把贴图/shader 路径改到 `res://assets/art-sample-002/`
- 已接入腐墟星能源站的资产：
  - `aqs002_bell_crystal.glb`：B2 星髓结晶
  - `aqs002_console.glb`：1F 控制室操作台
  - `aqs002_press_static.glb`：B1 泵房工业压机
- 接入代码：`game/scripts/ruin_art_sample.gd`
- GLB 原包说明：`art-source/third-party/ART-SAMPLE-002_TEAM_KIT/03_GAME_READY_ASSETS/README.md`
- 材质规范：`art-source/third-party/ART-SAMPLE-002_TEAM_KIT/04_MATERIAL_LIBRARY/material_guide.md`

## 维护约定

- 不直接修改 `art-source/third-party/` 中的源包；需要改材质/模型时先在 Blender/源文件里改，再重新导出到 `game/assets/art-sample-002/`。
- LIS Physics 的 `addons/` 是运行库，不在游戏脚本里复制一份；所有使用都通过 `LISHingeDoor` / `LIS*` 类。
- 两个包都来自团队内部制作，压缩包内未附第三方开源许可证；如对外发布，需按团队资产授权流程确认。
