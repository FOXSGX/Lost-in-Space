# 太空舱 Blender 美术优化 · 2026-10-22

延续用户已选择的精致卡通方向：清晰轮廓、圆润设备、奶油白与青蓝配色，暖橙区分维修和储物。

## 原稿与导出

- `ship_hub.blend`：Blender 4.5 原生可编辑工程，按功能区组织 Collection，含预览相机和摄影棚灯光。
- `build_blender.py`：Blender Python 重建脚本，从上一版 `game/assets/ship-hub/ship_hub.glb` 导入，生成本版原稿、GLB 和预览。
- `blender-overview.png`：Blender 摄影棚渲染；不代表游戏运行光照。
- `godot-center.png`、`godot-workshop.png`、`godot-bridge.png`、`godot-overview.png`：Godot 实机截图。
- `asset-stats.json`：源模型与运行模型网格统计。
- 游戏导出：`game/assets/ship-hub/ship_hub_blender_v2.glb`，与旧版并存。

Windows 重建示例：

```powershell
& 'C:\Program Files\Blender Foundation\Blender 4.5\blender.exe' --background --python '.\art-source\editable\spaceship-cabin\blender-v2\build_blender.py'
```

## 制作范围

- 原 GLB 的重复顶点焊接与面法线整理。
- 中央走道的大面板、低位引导灯、分区地垫和编号。
- 星图台的分层底座、环形控制面、投影光环、星球与轨道。
- 舱壁分层护板、观察窗边框、检修槽、通风格栅。
- 储物架显示条、维修台抽屉/诊断细节、补给柱结构圈和医疗标识、座椅滚边。

舱室仍约 42×33 米；设施、可移动范围、碰撞与交互点沿用原有实现。新几何仅为原设施内的细节、贴地面板或贴墙装饰，不新增不可见的阻挡。

运行导出按功能区和材质合并网格，保留 `panorama_glass` 与 `Airlock` 特殊节点命名，兼容游戏里的星空窗材质替换和近侧气闸隐藏。

## 来源与权限

基于项目已有舱室 GLB，在 Blender 中通过本目录脚本加工；新增几何、材质和文字均由脚本创建，没有下载外部模型、贴图或字体。原有 GLB、生成脚本、预览均保留。摄影棚灯光和相机仅在 `.blend` 内，未导出到游戏。

游戏实机图与验证记录见 `game/docs/ship-hub-art-blender-v2.md`。
