# 主角 3D 资源与接入

当前角色参照 `art-source/ai-generated/protagonist/current/` 的青绿色概念图与三视图。`game/assets/characters/protagonist_model.json` 是可编辑原稿 `art-source/editable/protagonist/protagonist_model.json` 的游戏副本。修改颜色、比例或部件后，复制源文件覆盖游戏副本，再运行 Godot 检查。

`scenes/protagonist_visual.tscn` 在运行时从 JSON 生成真实低多边形网格。头盔、身体和四肢使用朝外的平滑法线与不透明三角网格；部件分开挂在枢轴下，以便移动和动作动画。`SpacePlayer3D` 仍负责输入、碰撞、移动、扫描与联机位置同步；视觉脚本只读取角色状态。主场景向所有玩家广播攻击与救援视觉事件，生命值、倒地和携带状态继续使用原有状态快照。

`export_presets.cfg` 已把 `assets/characters/*.json` 纳入 Windows 导出包。导出 PCK 后曾直接从包内运行主角场景检查，确认角色数据、场景及脚本能够加载。

验证命令（在仓库根目录执行，把 Godot 可执行文件替换为本机路径）：

```powershell
godot --headless --path game --editor --quit
godot --headless --path game --script res://tests/protagonist_visual_check.gd
godot --path game --rendering-method gl_compatibility --script res://tests/render_protagonist_preview.gd
```

第三条生成 `art-source/editable/protagonist/godot-preview.png` 与 `godot-topdown-preview.png`，用于从实际渲染检查正面、侧面、背面及俯视辨识度。还应在单人与两个实例的联机试玩中检查角色朝向、动作同步、倒地救援及交互键。

联机冒烟检查需要同时启动两个进程，分别运行 `godot --headless --path game --script res://tests/protagonist_network_check.gd -- host` 和 `godot --headless --path game --script res://tests/protagonist_network_check.gd -- client`。它检查双方均生成角色外观，以及客户端收到救援动作事件。完整手工试玩仍用于检查手感与美术尺寸。

角色技能、单人复活资源和最终救援规则尚未由团队确认，当前实现没有替这些规则做决定。

## 2026-10-12：漏面与脚部穿地修复

自建 ArrayMesh 的正面顶点顺序按 Godot 的顺时针规则输出，光照法线仍朝外，修复因外壳被剔除而产生的透明/空壳观感。保持当前不透明材质和已有顶点色设置。

原靴子静态最低点为 `0.61 - 0.52 - 0.18 = -0.09`，走路摆腿、身体起伏与倒地动画会进一步改变高度。现在每次更新姿态后，根据真实网格顶点与部件变换计算最低点，调整视觉身体高度，确保不低于角色局部地面上方 0.035；使用真实顶点而非包围盒，减少摆腿时的额外悬浮。碰撞体与镜头位置保持原有逻辑。

新增 `protagonist_grounding_check.gd` 检查网格正面、不透明材质，以及站立、行走、扫描、救援、受伤、倒地和救起七种状态的地面接触；新增 `protagonist_grounding_capture.gd` 生成站立、迈步、倒地三种实机近景。检查使用主舱地面高度 0.005。

修复版试玩包：`builds/ship-cabin-v0.1.4.zip`。此前 v0.1.3 包内仍是旧脚本。
