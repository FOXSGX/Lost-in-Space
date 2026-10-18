# 主角形象（Blender 版本 · 第二版：科幻侦察兵）

## 文件

| 文件 | 内容 |
| --- | --- |
| `build_protagonist.py` | 生成主角模型的 Blender 脚本（当前为第二版设计） |
| `../../game/assets/characters/protagonist_blender.glb` | 游戏内使用的模型 |
| `../../game/assets/characters/protagonist_model.json` | 配色表与程序化兜底模型 |

## 第二版设计（2026-10-18，完全重做）

第一版是方块拼的矮胖宇航员，观感僵硬。第二版按“科幻侦察兵”重建：

- **比例**：1.82 米瘦长体型，肩宽 0.42、腰宽 0.30，不再是等宽方块。
- **分层护甲**：胸甲、肩甲、大腿护板、腰带与挂包、靴底，全部倒角。
- **圆柱关节**：上臂/前臂/大腿/小腿用锥台圆柱（上粗下细），肘膝用球体，去掉“盒子感”。
- **发光件**：面罩光缝、胸核、躯干脉冲条、背部推进口、靴底灯。
- **配色**：钢蓝主体 + 深色内衬 + 琥珀色肩标 + 青色发光。

## 重新生成

```powershell
tools\blender-5.2.2-windows-x64\blender.exe --background --python art-source\editable\characters\build_protagonist.py
tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path game --editor --quit
```

> **坑：`--import` 有时不会刷新已有的 `.glb`**，会继续用旧的烘焙场景（表现为“改了模型但游戏里没变”）。
> 换成 `--editor --quit` 触发完整扫描；仍不生效时删掉 `game/.godot/imported/protagonist_blender.glb-*` 再导入。

## Godot 侧契约（换模型时必须保留）

`game/scripts/protagonist_visual.gd` 依赖以下结构：

- 节点 `Body`：所有部件与枢轴的父节点，动画直接改它的 position/rotation/scale。
- 四肢关节（名字固定，全部按 X 轴旋转）：
  - `LeftArmPivot` / `RightArmPivot`：肩
  - `LeftElbowPivot` / `RightElbowPivot`：肘
  - `LeftLegPivot` / `RightLegPivot`：髋
  - `LeftKneePivot` / `RightKneePivot`：膝
  - `HeadPivot`：颈
- 网格名字：`Helmet` / `Visor` / `Backpack` / `YellowShoulder` 等会被测试与配色表按名字查找（测试用 `find_child` 递归找，不写死层级）。
- `CarriedBattery`、`PlayerIdentifier` 由 Godot 运行时创建，不在 GLB 里。

## 走路循环（第二版：不再僵硬）

第一版只有四个枢轴，整条手臂/腿整体摆动，看起来像木棍。现在：

| 关节 | 动作 |
| --- | --- |
| 髋 | `sin(phase) × 0.60` 交替前后 |
| 膝 | 摆动腿弯曲（`max(0, -sin) × 0.95`），支撑腿伸直 |
| 肩 | 与同侧腿反向摆动（`-hip × 0.75`） |
| 肘 | 常驻 −0.35 弯曲，摆动时再多弯 0.30 |
| 躯干 | 前倾 0.10、侧摆 0.05，迈步时下沉 0.09 保证支撑脚贴地 |
| 颈 | 反向补偿 −0.7×前倾，头部保持水平 |

下蹲而非上浮很关键：`_keep_above_ground()` 只会往上抬，如果迈步时抬高身体，支撑脚会悬空并让 `protagonist_grounding_check.gd` 报“离地过高”。

## 坐标换算（踩过的坑）

Blender 是 Z-up、正面朝 -Y；Godot 是 Y-up、正面朝 -Z。脚本里统一用两个函数换算：

```python
gv(x, y, z) -> (x, -z, y)   # 位置
gs(x, y, z) -> (x,  z, y)   # 尺寸
```

**位置、尺寸、以及枢轴子部件的局部偏移都必须走 `gv()`**。第一版只转换了顶层位置，结果腿和手臂向后倒、躯干尺寸在 Y/Z 上互换，角色看起来像被拆散的方块。

导出时用 `export_yup=True`（默认），**不要再手动给根节点加 90° 旋转**——工具资产就是因为多转了一次，才需要在 Godot 里反向补偿。

## 比例参考

| 部位 | 高度（米） |
| --- | --- |
| 靴底 | 0.00 |
| 髋枢轴 | 0.80 |
| 肩枢轴 | 1.26 |
| 头盔中心 | 1.52 |
| 头盔顶 / 天线 | 1.78 / 1.88 |

脚必须正好落在 0：`_keep_above_ground()` 只会把模型往上抬，不会往下压，脚悬空或陷入地面都会让 `protagonist_grounding_check.gd` 失败。
