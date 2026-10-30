# 共振星资产工作流

这是共振星高细节建模的第一条落地管线。当前已确认的运行链路是：

```text
art-source/generated/resonance/resonance-grounded-factory-concept.png
        ↓ 形体拆分、材质拆分、交互点标记
art-source/editable/resonance/*.blend
        ↓ Blender 便携版脚本化导出
game/assets/resonance/models/*.glb + textures/*.png
        ↓ Godot 导入与场景绑定
game/scripts/resonance_stage.gd
        ↓ 近景、远景、运行时逻辑回归
work/gameplay-iterations/*/planet-review/
```

## 资产分层

1. **概念层**：确定共振星的地表、工业设施、移动模块、反应堆塔和颜色语言。参考图只作为方向依据，不能直接当运行时模型。
2. **源文件层**：在 `art-source/editable/resonance/` 中保留 `.blend` 与生成脚本。英雄资产先做真实分件，再制作中远景 LOD。
3. **运行时层**：GLB 放入 `game/assets/resonance/models/`，PBR 纹理放入 `game/assets/resonance/textures/`。Godot 的移动、碰撞、交互和网络状态仍由脚本控制。
4. **验证层**：每一批资产必须同时通过 Blender 预览、Godot 画面检查、场景诊断、逻辑回归和资源路径检查。

## 当前英雄资产批次

`resonance_module_hero.glb` 对应游戏里的移动模块，尺寸保持约 `10m × 6m`。当前批次同时包含轨道系统、进料/升降/甲板工业区、反应堆塔、能源核心、无人机停机台、返航平台、岩土地表、支援安全闸和废弃维修仓：

- `resonance_rail_system.glb`
- `resonance_processing_zone.glb`
- `resonance_reactor_tower.glb`
- `resonance_energy_core.glb`
- `resonance_drone_dock.glb`
- `resonance_extraction_platform.glb`
- `resonance_surface_set.glb`
- `resonance_support_safety_gate.glb`
- `resonance_maintenance_facility.glb`
- `resonance_cavern_shell.glb`
- `resonance_factory_spine.glb`

每个资产都保留独立 `.blend` 和 `-preview.png`。导出脚本会在 GLB 导出前对根节点施加 X 轴 90° 坐标补偿，修正 Blender 到 Godot 的 Y-up 轴向转换；Godot 中的视觉节点不携带碰撞体。

英雄模块保留以下近景验证目标：

- 近景：边缘倒角、面板凹凸、螺栓、液压缸、发光条和轨道夹具是否有层次；
- 中景：控制舱、管线、电池散热片和四角夹具是否能读出“可操作设施”；
- 远景：移动模块轮廓是否仍然清晰，是否与共振星红色地表和工业设施匹配；
- 逻辑：移动模块的路线、锁定、货箱、稳定器和三人协作机制不因替换网格而失效。

## 当前边界

视觉批次已接入实际共振星场景，并增加洞穴背景、深层熔岩、独立安全甲板、垂直井、悬空维护桥和 Blender 主工厂脊柱；碰撞体、交互锚点、玩法状态和网络快照仍由 Godot 单独维护。材质色彩和局部造型保留可调整空间，后续优先根据近景截图和联机试玩反馈做 LOD、遮挡和光照微调。

## Blender 视觉主场景

当前运行时的静态视觉权威资产为：

- `art-source/editable/resonance/build_resonance_factory_assets.py`
- `art-source/editable/resonance/build_resonance_master_scene.py`
- `art-source/editable/resonance/resonance_master_scene.blend`
- `game/assets/resonance/models/resonance_master_scene.glb`

主场景包含洞穴工厂脊柱、深层熔岩峡谷、分层岩台、岩层断面、热阀站、支援接力终端，以及升降接力、镜面反射、冷却接驳和垂直安全闸的静态机械结构。Godot 在 `USE_BLENDER_MASTER_VISUALS` 开启时不再生成对应的地表、轨道、岩台、工厂骨架和机关外观，只创建玩法碰撞、状态节点、交互范围与网络同步对象。

单人辅助无人机也由 Blender 资产提供：

- `art-source/editable/resonance/build_resonance_helper_drone.py`
- `art-source/editable/resonance/resonance_helper_drone.blend`
- `game/assets/resonance/models/resonance_helper_drone.glb`

新增资产必须先在 Blender 中保存 `.blend` 和可重复执行脚本，再导出 GLB；Godot 不得用程序化 MeshInstance3D 取代该资产的可见外壳。碰撞、交互锚点、动态状态和多人逻辑仍分离维护。
