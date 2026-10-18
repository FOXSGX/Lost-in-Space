# 共振星美术导入说明

## 重新生成

在仓库根目录运行：

```powershell
tools/blender-5.2.2-windows-x64/blender.exe -b --python art-source/editable/resonance/build_resonance_factory_assets.py
tools/blender-5.2.2-windows-x64/blender.exe -b --python art-source/editable/resonance/build_resonance_aux_assets.py
tools/blender-5.2.2-windows-x64/blender.exe -b --python art-source/editable/resonance/build_resonance_core_facility_assets.py
tools/blender-5.2.2-windows-x64/blender.exe -b --python art-source/editable/resonance/build_resonance_cavern_asset.py
tools/blender-5.2.2-windows-x64/blender.exe -b --python art-source/editable/resonance/build_resonance_master_scene.py
tools/blender-5.2.2-windows-x64/blender.exe -b --python art-source/editable/resonance/build_resonance_helper_drone.py
```

第一条生成主资产批次；第二条只生成支援安全闸和废弃维修仓；第三条只生成反应堆塔和返航平台；第四条生成洞穴壳体，适合继续扩展垂直桥和洞穴支线。脚本同时写入 `.blend`、预览 PNG 和 `game/assets/resonance/models/*.glb`。

`build_resonance_master_scene.py` 生成共振星 Blender 视觉主场景，包含洞穴工业骨架、熔岩峡谷、分层岩台、热阀站和反应堆协作机关；`build_resonance_helper_drone.py` 生成单人模式的 Blender 辅助无人机。开启 `USE_BLENDER_MASTER_VISUALS` 后，Godot 只维护碰撞、交互锚点、状态和网络逻辑，不再绘制对应的程序化静态外壳。

## Godot 接入

`game/scripts/resonance_stage.gd` 的 `_build_art_asset_overlays()` 负责加载 GLB。视觉节点位置与阶段数据保持分离，`module_nodes`、`station_nodes`、`core_node`、`extraction_node` 和原有交互接口不改。GLB 不携带碰撞体，避免网格遮挡玩家或改变联机交互距离。

Godot 加载后会把视觉节点写入 `art_asset_nodes`，每个节点含 `resonance_visual_asset` 元数据。替换单项资产时只需保持资产 ID、GLB 路径和根节点尺度。

## 检查顺序

```powershell
tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --import --quit
tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script tests/resonance_model_import_check.gd
tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script tests/resonance_scene_diagnostic.gd
tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script tests/resonance_runtime.gd
tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --rendering-method gl_compatibility --path game --script tests/resonance_art_capture.gd -- C:/Users/ASUS/Desktop/迷失太空/work/gameplay-iterations/20261016-resonance-art/planet-review
```

最后一条需要真实图形设备，用于生成 `resonance-near-module.png`、`resonance-mid-reactor-tower.png`、`resonance-far-overview.png` 和 `resonance-near-extraction.png`。

