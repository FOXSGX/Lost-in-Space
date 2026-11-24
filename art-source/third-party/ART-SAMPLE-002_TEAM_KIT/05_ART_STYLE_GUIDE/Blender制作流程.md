# Blender 制作流程（高模 → 低模 → 烘焙）

> 对应源工程：`02_BLENDER_SOURCE/*.blend`　对应脚本：`02_BLENDER_SOURCE/scripts/*.py`
> 全部可在 headless 下重跑：`blender -b --factory-startup -P <脚本>.py`

---

## 1. 环境与坐标约定

| 项 | 约定 |
|---|---|
| Blender | 5.2.2 LTS（headless 也能跑烘焙） |
| 坐标 | 脚本里用 **Godot 坐标**（x 右 / y 上 / z 深），导出时由 `g()` 转到 Blender（z 上） |
| 单位 | 米 |
| 导出 | glTF 2.0（GLB），`export_yup=True`、`export_apply=True`、`export_tangents=True` |

---

## 2. 五个脚本的分工

| 脚本 | 产出 | 说明 |
|---|---|---|
| `aqs_kit.py` | 工具库 | 圆角截面 / 放样 / 旋转体 / 螺栓 / 焊缝 / 薄板 / 岩石解理 / **顶点遮罩烘焙** |
| `hero_mats.py` | 材质表 | GLB 里的材质名 = Godot 材质库的键 |
| `build_press.py` | 平台 / 静部件 / 摆臂 / 操作台 | 混凝土浇筑、承力链、紧固件 |
| `build_head.py` | **锤头高模 + 低模 + 烘焙** | 本轮 P0 的核心 |
| `build_crystal_hero.py` | 主晶体 + 根部融合 | |
| `build_rock_hero.py` | 相邻岩层 / 断面 / 崩积 | |
| `export_head.py` | 重新导出锤头低模 | 三角化 + 改回材质名（避免重烘焙） |

---

## 3. 高模 → 低模 → 烘焙（锤头为例）

```
① build_low()     低模：按关键尺寸放样（1.80 m 宽 / 收腰 / 侧板 0.88），圆角 10 段
② unwrap_low()    Smart UV Project（island_margin 0.006）
③ build_high()    复制低模 → Subsurf(2) → 多尺度位移（低频下垂 / 中频型砂 / 高频砂粒）
                  → 追加不对称特征：左右凸台、补焊补丁、顶部浅凹、中缝环带
④ bake()          Cycles selected-to-active（cage 35 mm）：
                  NORMAL(2048², tangent) / AO(1024²) / CURVATURE(1024², Pointiness→EMIT)
⑤ pack_maps()     AO + 曲率打包成 aqs002_head_mask.png（R=曲率 G=AO）
⑥ export_head.py  三角化 → 导出 GLB（必须三角化，否则没有 TANGENT）
```

### 三条必须遵守的规则（都踩过坑）

1. **位移必须"以向内为主"**（外扩 ≤ 2.5 mm），否则会破坏已经验证过的机械净空。
2. **不要做全局 Smooth 收缩**：高模整体缩小十几毫米后，烘焙会给出大范围倾斜的法线，
   低模上呈现"球面高光"的假象（本轮第一次烘焙就是这样失败的）。
3. **烘焙前必须三角化**（或在导出前），否则 glTF 无法生成 TANGENT，Godot 里法线贴图整片失效。

### 烘焙参数

| 参数 | 值 | 说明 |
|---|---|---|
| `cage_extrusion` | 0.035 | 35 mm，够包住 2 mm 级位移 |
| `margin` | 12 px | 防止 UV 岛边缘渗色 |
| NORMAL 采样 | 4 | 法线不需要高采样 |
| AO 采样 | 24 | 有噪点可接受（后面会与顶点色并联） |
| 曲率 | EMIT + `Geometry.Pointiness` → ColorRamp(0.42–0.58) | 记到掩膜 R 通道 |

---

## 4. 顶点遮罩（每件资产都要）

```python
obj = hero.finish(smooth=True, split_angle=30.0,
                  bake=dict(ao_rays=9, ao_dist=0.17, seed=23,
                            mat_gain=hero_mats.WEAR_GAIN))
```

- 通道：R=凸棱磨损、G=自遮挡、B=起皮斑、A=朝上程度；
- **必须在 EdgeSplit 之前烘焙**（切开顶点后 1-ring 断裂，曲率恒为 0）；
- AO 距离 0.15–0.18 m：太大会把相邻零件的接触遮蔽算成"整面脏"。

---

## 5. 重跑 / 改参数

| 想改什么 | 改哪里 |
|---|---|
| 锤头的铸造起伏幅度 | `build_head.py::_displace_multi()` 的三个系数 |
| 锤头的不对称特征 | `build_head.py::build_high()` 里的凸台/补丁/浅凹列表 |
| 混凝土模板分块 | `build_press.py::build_platform()` 的 `xcuts / zcuts / pour_h` |
| 岩层层厚 | `build_rock_hero.py` 里 `slab(..., strata=(period, amp))` |
| 晶体数量的粗细 | `build_crystal_hero.py` 的 `cols` 列表 |
| 材质观感 | **不要在 Blender 调**，去 Godot 的 `hero_lib.gd`（Blender 里只给基准色） |

---

## 6. 保存源工程

`K.save_blend(...)` 会写 `.blend`；贴图通过 `img.pack()` 打包进文件。
交付前检查：打开 `.blend` → File → External Data → 不应出现红色缺失贴图。
