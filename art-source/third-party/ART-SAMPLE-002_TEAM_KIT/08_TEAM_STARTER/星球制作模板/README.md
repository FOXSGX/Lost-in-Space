# 星球制作模板（怎么开一颗新星球）

## 1. 复制骨架

```
08_TEAM_STARTER/星球制作模板/   ← 本目录
game/assets/models/<星球英文名>/     ← 你的 GLB
game/assets/textures/<星球英文名>/   ← 你的贴图
game/shaders/                        ← 直接复用 aqs2_*.gdshader（不要复制改）
```

## 2. 三份必须写的文档（用本目录的模板）

| 模板 | 写成 | 必须回答 |
|---|---|---|
| `星球美术说明模板.md` | `docs/design/planets/planet-XX-<星球名>.md` | 视觉 DNA 七条怎么落地？可变元素选了什么？ |
| `材质映射约定模板.md` | 你星球目录下的 `MATERIALS.md` | 每个 GLB 用了哪些材质名？对应材质库哪个键？ |
| `验收清单` | 直接抄 `05_ART_STYLE_GUIDE/星球验收清单.md` | 技术/视觉/交付三栏逐条打勾 |

## 3. 命名约定（必须遵守，否则工具链找不到）

```
GLB      : <星球前缀>_<部件>_<变体>.glb        例：aqs002_press_static.glb
材质名   : M_<家族><用途>                       例：M_PaintCream / M_CastSteelBaked
贴图     : <家族>_<通道>.png（法线/粗糙/掩膜）   例：paint_normal.png / rock_mask.png
测试场景 : <星球前缀>_<用途>.tscn / .gd          例：aqs002_regress.tscn
截图目录 : captures/<前缀>_<轮次>/               例：captures/s_final_new/
```

## 4. 起步顺序（别反了）

1. **体块**：先用 BoxMesh/CylinderMesh 摆比例与构图，出 4 机位灰模；
2. **结构**：把主视觉件换成放样 + 倒角 + 紧固件（Blender）；
3. **材质**：接上 `hero_lib.gd`，先调 albedo，再调 roughness，最后加磨损；
4. **灯光**：先只留主光，确认形体能读；再加副光/轮廓光/掠射；
5. **烘焙**：主视觉件走一遍高模 → 法线/AO；
6. **验收**：跑清单，出图，写报告。

## 5. 常见返工点

- 体块阶段就上材质 → 后面改结构时材质全废；
- 灯光一次上满 → 分不清"是材质问题还是灯的问题"；
- 没有中景过渡资产 → 英雄区与背景出现精度断崖；
- 只做 Forward+ → Compatibility 下交付时全崩。
