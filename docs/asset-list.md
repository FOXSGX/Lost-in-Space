# 共振星高细节资产清单

更新时间：2026-10-16

本批资产以 `resonance-grounded-factory-concept.png` 为形体和颜色参考，Blender 源文件保留在 `art-source/editable/resonance/`，运行时 GLB 保留在 `game/assets/resonance/models/`。GLB 只提供视觉网格和材质；碰撞体、交互锚点、移动、网络状态仍由 Godot 维护。

| 资产 ID | 用途 | Blender 源文件 | 运行时 GLB | 预览图 | Godot 接入 |
| --- | --- | --- | --- | --- | --- |
| `resonance_module_hero` | 三节移动能源模块英雄资产，分层底盘、控制舱、管线、检修板、螺栓、液压夹具、散热片 | [resonance_module_hero.blend](../art-source/editable/resonance/resonance_module_hero.blend) | [resonance_module_hero.glb](../game/assets/resonance/models/resonance_module_hero.glb) | [preview](../art-source/editable/resonance/resonance_module_hero-preview.png) | 已接入三节模块节点 |
| `resonance_rail_system` | 主能源轨道、枕木、固定螺栓、夹具、检修猫道、信号灯 | [blend](../art-source/editable/resonance/resonance_rail_system.blend) | [glb](../game/assets/resonance/models/resonance_rail_system.glb) | [preview](../art-source/editable/resonance/resonance_rail_system-preview.png) | 已接入四段轨道视觉节点 |
| `resonance_processing_zone` | 进料、升降分流和反应堆甲板的多层平台、液压升降井、货箱架、管线 | [blend](../art-source/editable/resonance/resonance_processing_zone.blend) | [glb](../game/assets/resonance/models/resonance_processing_zone.glb) | [preview](../art-source/editable/resonance/resonance_processing_zone-preview.png) | 已接入三处工业分区 |
| `resonance_reactor_tower` | 反应堆塔、四角支撑、垂直加强筋、环形能源管线、检修甲板 | [blend](../art-source/editable/resonance/resonance_reactor_tower.blend) | [glb](../game/assets/resonance/models/resonance_reactor_tower.glb) | [preview](../art-source/editable/resonance/resonance_reactor_tower-preview.png) | 已接入远景地标 |
| `resonance_energy_core` | 防护笼、分层容器、环形线圈、动态能源场、双人握把和服务终端 | [blend](../art-source/editable/resonance/resonance_energy_core.blend) | [glb](../game/assets/resonance/models/resonance_energy_core.glb) | [preview](../art-source/editable/resonance/resonance_energy_core-preview.png) | 已替换中央核心视觉网格 |
| `resonance_drone_dock` | 无人机充能环、折叠机械臂、维护终端、起降平台 | [blend](../art-source/editable/resonance/resonance_drone_dock.blend) | [glb](../game/assets/resonance/models/resonance_drone_dock.glb) | [preview](../art-source/editable/resonance/resonance_drone_dock-preview.png) | 已接入停机区 |
| `resonance_extraction_platform` | 绿色返航对接平台、护栏、导航灯、信标和能源接口 | [blend](../art-source/editable/resonance/resonance_extraction_platform.blend) | [glb](../game/assets/resonance/models/resonance_extraction_platform.glb) | [preview](../art-source/editable/resonance/resonance_extraction_platform-preview.png) | 已接入返航平台 |
| `resonance_surface_set` | 红褐异星岩土、岩层、裂缝带、碎石、磨损压痕 | [blend](../art-source/editable/resonance/resonance_surface_set.blend) | [glb](../game/assets/resonance/models/resonance_surface_set.glb) | [preview](../art-source/editable/resonance/resonance_surface_set-preview.png) | 已接入远端地表装饰 |
| `resonance_support_safety_gate` | 支援安全闸、机械门、控制终端和警示灯 | [blend](../art-source/editable/resonance/resonance_support_safety_gate.blend) | [glb](../game/assets/resonance/models/resonance_support_safety_gate.glb) | [preview](../art-source/editable/resonance/resonance_support_safety_gate-preview.png) | 已接入支援安全闸视觉节点 |
| `resonance_maintenance_facility` | 岩层旁废弃维修仓、观察平台、检修门和支线探索入口 | [blend](../art-source/editable/resonance/resonance_maintenance_facility.blend) | [glb](../game/assets/resonance/models/resonance_maintenance_facility.glb) | [preview](../art-source/editable/resonance/resonance_maintenance_facility-preview.png) | 已接入西侧支线区域 |
| `resonance_cavern_shell` | 山洞洞壁、拱顶、钟乳石、垂直井、悬空维护桥和高位观察台 | [blend](../art-source/editable/resonance/resonance_cavern_shell.blend) | [glb](../game/assets/resonance/models/resonance_cavern_shell.glb) | [preview](../art-source/editable/resonance/resonance_cavern_shell-preview.png) | 已接入共振星视觉壳体 |

## 统一命名

- 根节点：`RES_<功能>`，例如 `RES_Reactor_Tower`。
- 分件：`功能/子系统/零件`，导出到 GLB 后 `/` 会转为 `_`，但前缀保持可检索。
- 发光材质只使用 `RS_Energy_Cyan`、`RS_Track_Blue`、`RS_Warning_Amber`、`RS_Extraction_Green` 和 `RS_Lift_Violet`。
- 运行时接入节点使用 `Art<功能>`，并写入 `resonance_visual_asset` 元数据。
- Blender 源文件以米为单位，Y 轴向上；导出脚本在 GLB 导出前对根节点施加一次 X 轴 90° 补偿，保证 Godot 中 Y 轴仍为高度。

## 材质与纹理

- `RS_Steel_Scuffed`：工业面板纹理、金属度高、粗糙度中低。
- `RS_Steel_Edges`：倒角和分件边缘。
- `RS_Rubber_Hose`：液压软管与握把。
- `RS_Optical_Glass`：观察窗和反应器内筒。
- `RS_Red_Rock` / `RS_Basalt` / `RS_Foundation_Concrete`：地表、岩层、基座。
- 运行时纹理位于 `game/assets/resonance/textures/`，由 Godot 导入设置生成 `.import` 旁车文件。

