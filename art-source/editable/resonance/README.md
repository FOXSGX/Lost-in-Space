# 共振星高细节资产源文件

这里保存 Blender 可编辑源文件和审阅预览。共振星的资产按“概念图 → Blender 分件建模 → GLB → Godot 导入 → 近景/远景验证”流转。

## 当前资产批次

- `build_resonance_module_hero.py`：可重复执行的 Blender 生成脚本。
- `build_resonance_factory_assets.py`：轨道、工业分区、反应堆、能源核心、停机台、返航平台和地表资产批次生成脚本。
- `build_resonance_master_scene.py`：共振星 Blender 视觉主场景，组合洞穴、熔岩峡谷、岩台、热阀、三节模块机关和反应堆协作设备。
- `build_resonance_helper_drone.py`：单人模式辅助无人机的独立 Blender 资产生成脚本。
- `build_resonance_aux_assets.py`：支援安全闸和废弃维修仓的独立迭代脚本。
- `build_resonance_core_facility_assets.py`：反应堆塔和返航平台的独立迭代脚本。
- `build_resonance_cavern_asset.py`：洞穴壳体、垂直井、维护桥和观察台脚本。
- `resonance_module_hero.blend`：可继续手工细化的源文件。
- `resonance_module_hero-preview.png`：不进入游戏的建模审阅图。
- `game/assets/resonance/models/resonance_module_hero.glb`：Godot 运行时资源。
- `resonance_master_scene.blend` / `resonance_master_scene-preview.png` / `game/assets/resonance/models/resonance_master_scene.glb`：运行时静态视觉主场景。
- `resonance_helper_drone.blend` / `resonance_helper_drone-preview.png` / `game/assets/resonance/models/resonance_helper_drone.glb`：单人辅助无人机。

当前批次的所有根节点都保留 `RES_<功能>` 命名和 `asset_id` 自定义属性，方便与交互锚点、碰撞和 LOD 对接。导出脚本会在 GLB 导出前补偿 Blender 与 Godot 的 Y-up 轴转换；`.blend` 和预览图仍保持 Blender 建模坐标。

## 约定

- 单位使用米，Y 轴向上；游戏中的原点和移动模块脚本保持一致。
- Blender 源文件只放在 `art-source/editable/`，运行时 GLB 只放在 `game/assets/`。
- 贴图源和可编辑材质保留在 Blender；运行时需要的 PBR 贴图放在 `game/assets/resonance/textures/`。
- 可见细节用真实分件表达；碰撞体、交互锚点和移动逻辑由 Godot 单独维护，避免把玩法耦合进美术网格。
- 资产命名使用 `功能/部件` 前缀，例如 `RailClamp/1_-1.72/jaw`，便于后续做选择性替换、材质变体和 LOD。
- 每次导出后必须做三类验证：Blender 预览、Godot 近景/远景截图、场景逻辑回归测试。
- 开启 `USE_BLENDER_MASTER_VISUALS` 后，Godot 不再生成地表、轨道、岩台、洞穴、工厂骨架和机关外壳的可见 Mesh；这些静态外壳全部来自 Blender GLB。Godot 只保留碰撞、交互锚点、动态状态、网络同步和必要的 UI 指引。

## 生成命令

在仓库根目录执行：

```powershell
tools/blender-5.2.2-windows-x64/blender.exe -b --python art-source/editable/resonance/build_resonance_module_hero.py
```

Blender 便携版不写入系统安装目录，便于团队固定版本并重复导出。
