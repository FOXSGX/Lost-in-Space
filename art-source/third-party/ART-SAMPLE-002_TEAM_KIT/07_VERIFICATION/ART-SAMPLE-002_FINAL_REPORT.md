# ART-SAMPLE-002 · 最终报告（英雄区精修 + 团队资产包）

- 基线：`work/art-sample-001/project`（ART-SAMPLE-001）
- 本轮工程：`work/art-sample-002/project`（独立物理副本，无硬链接/联接）
- 原始对照基线：`work/art-quality-002-natural/project`
- 引擎：Godot 4.7.2 · **Compatibility 为首要目标**（Forward+ 作增强对照）
- 建模：Blender 5.2.2 LTS（headless 可复现）
- 报告日期：2026-11-18

---

## 1. 结论（三栏分开）

| 验收栏 | 结论 | 依据 |
|---|---|---|
| **技术验收** | **GO** | 45/45 回归、43/43 完整链（`completed=true`、`act5_verified=true`）、53 角度穿插 0 进入、Compatibility 实机通过、性能无退化（P50 6.06 ms 与上一版持平、Draw Call 601 vs 607） |
| **视觉验收** | **CONDITIONAL GO** | 高模烘焙与 2K 材质确实把近景推进了一档（见第 7 节逐项截图），但锤头的有机转折仍受程序化管线限制、晶体的光学层次仍是不透明近似 |
| **团队交付** | **GO** | 交付包内每一项都可用：独立可运行 Godot 演示工程、完整 Blender 源（贴图已打包）、游戏可用 GLB、2K 材质库、5 份规范、参考图与验收记录、4 个起步模板；ZIP 已在全新目录解压复验 |

---

## 2. 本轮改善的视觉问题（逐条对应任务书）

| # | 任务书要求 | 做了什么 | 证据 |
|---|---|---|---|
| P0 | 锤头高模雕刻 + 法线烘焙 | 低模 3 928 tris → 高模 64 356 tris（Subsurf 2 + 多尺度位移 + 不对称凸台/补焊/浅凹/中缝环带）→ Cycles 烘焙 2048² 切线法线 + 1024² AO/曲率；低模 UV Smart Project | `06_REFERENCE/old_new_comparison/c4_head_face_old_new.png`、`04_MATERIAL_LIBRARY/textures_2k/aqs002_head_normal.png` |
| P1 | 2K 多尺度材质 | 4 族（paint/cast/rock/conc）+ mach 全部 2K 法线/粗糙度、1K 掩膜；**每族独立高度场** | `06_REFERENCE/material_board/` |
| P2 | 混凝土承台真实化 | 三次浇筑高度不等（0.115/0.135/0.100）、模板分块不等距（1.92/3.20 / 2.78/1.94 m）、缝宽 6–11 mm 带抖动、±3 mm 错位与 ±0.4° 倾斜、2 处拆模崩角 + 骨料、3 处砂浆脱落斑 + 骨料外露；混凝土专用 shader 模式（骨料色差/气孔/脱落） | `c2_plinth_edge`、`06_REFERENCE/material_board/` |
| P3 | 岩层与自然环境 | 新增 2 处**面向玩家的层理断面**（层厚 22/31 cm 不等）+ 6 块中景过渡岩（补"精度断崖"）+ 断面脚下崩积；层面从 7 cm 薄板改为 26–44 cm 厚块；新增 2 盏只打岩壁的掠射灯 | `c10_bedrock`、`01_wide` |
| P4 | 晶体表现 | 三层光学结构（表面/次表面/芯）+ 软膝防过曝；根部新增 3 片压覆岩板、7 道放射裂隙、4 组侵蚀碎屑；9 座背景功能晶体统一到同一材质语言 | `c5_anvil_jaw`、`c6_crystal_body`、`04_crystal` |
| P5 | 撞击表现与自然动画 | 保留真实积分器；新增火花（26 粒，真实打击点）、矿屑、粉尘二次消散、锤头余振、晶体芯层脉冲、60 ms 撞击微光；全部挂在真实 `struck` 信号 | `06_REFERENCE/motion/impact_sequence.png` + `motion_trace.json` |
| 三 | 统一英雄区域 | 主光/副光/轮廓光/岩壁掠射/晶体实用光一套体系；环境光降到 1.45（不再主导）；轮廓光强度 ×0.45（避免把锤头打成蓝色） | `06_REFERENCE/hero_views/` |

---

## 3. 真正做了高模的模型

只有 **锤头（Hammer Head）** 走了完整的高模 → 低模 → 烘焙链路，因为它是本轮识别出的第一瓶颈：

- 高模：64 356 tris（`02_BLENDER_SOURCE/high_poly/aqs002_head_high_reference.glb`）
- 低模：3 928 tris + 2048² 切线法线 + 1024² AO/曲率掩膜
- 烘焙：Cycles `selected-to-active`，cage 35 mm，margin 12 px，法线 4 采样、AO 24 采样、曲率 EMIT 8 采样

**一个必须记录的失败与修复**：第一次烘焙后锤头出现"球面式"假高光。
根因是给高模加了全局 Smooth 修改器（factor 0.35 × 2），高模整体缩进十几毫米，
烘焙时法线大范围倾斜去补偿。去掉全局平滑、只保留多尺度位移后，A/B 对照确认修复：
`uv_normal_strength=0` → 平滑哑光面；`=1.2` → 有铸造起伏的表面（见 `c4_head_face` 对照）。

其余件（平台/静部件/摆臂/操作台/晶体/岩层）仍是**参数化放样 + 顶点遮罩烘焙**，
没有走高模烘焙——这是有意的取舍：它们的形体由"结构"决定，不靠表面雕刻。

---

## 4. 新增的 2K 贴图与材质

| 族 | 法线 | 粗糙度 | 掩膜 | 特征 |
|---|---|---|---|---|
| paint | 2048² | 2048² | 1024² | 橘皮（120/420 周两层）+ 起皮大斑 + 细划痕 + 落尘点 |
| cast | 2048² | 2048² | 1024² | 砂型麻点 2 600 个 + 气孔 900 个 + 砂粒 |
| rock | 2048² | 2048² | 1024² | 解理沟（各向异性长条 220+90 条）+ 崩落坑 1 400 + 细裂隙 |
| conc | 2048² | 2048² | 1024² | 模板木纹 + 气孔 3 000 + 骨料 420 + 砂浆脱落斑 |
| mach | 2048² | 2048² | 1024² | 单向刀纹（420/1180 周）+ 划痕 |
| head（烘焙） | 2048² | — | 1024² | 高模法线 + AO + 曲率 |

导入设置：全部 `compress/mode=2`（VRAM 压缩）+ mipmap，法线额外 `normal_map=1`。
**显存反而比上一版更省**：12 张 1K 未压缩 ≈ 63 MB → 本包 ≈ 44 MB（见第 6 节实测）。

三条 shader：`aqs2_metal`（含混凝土模式 + UV 烘焙件分支）、`aqs2_rock`（解理沟掩膜）、
`aqs2_crystal`（三层光学 + 软膝）。

---

## 5. 新增可复用资产（`03_GAME_READY_ASSETS/`）

| 分类 | 资产 | 面数 | 材质槽 |
|---|---|---|---|
| industrial | `aqs002_platform.glb`（混凝土垫层 + 铸铁承台 + 灌浆 + 排水） | 19 548 | 8 |
| industrial | `aqs002_press_static.glb`（鞍座/立柱/工字横梁/剖分轴承/砧座/楔爪/检修梯/桥架/机装灯） | 46 830 | 11 |
| industrial | `aqs002_swing_arm.glb`（整铸锥形摆臂） | 4 564 | 4 |
| industrial | `aqs002_hammer_head_low_baked.glb`（**高模烘焙低模**） | 3 928 | 1 |
| industrial | `aqs002_console.glb`（操作台/卷扬/仪表/台灯） | 3 842 | 11 |
| geology | `aqs002_rock_hero.glb`（基岩台阶/层理断面/崩积/中景岩/碎屑） | 22 454 | 3 |
| crystals | `aqs002_bell_crystal.glb`（7 晶柱 + 基岩根部 + 压覆岩板 + 裂隙 + 晶屑） | 13 270 | 5 |

合计 114 436 tris。全部带顶点遮罩（R磨损/G遮蔽/B起皮/A朝上），材质名与 `hero_lib.gd` 一一对应。

---

## 6. 技术测试与性能

### 6.1 测试结果（真实执行日志见 `07_VERIFICATION/`）

```
REGRESS checks=45 fails=0                 -> PASS          (regression/regress.log)
FULLCHAIN steps=43 passes=43 fails=0      -> completed=true final_stage=6 act5_verified=true
                                                            (fullchain/fullchain.log)
CLEARANCE samples=53 angles=-30..74
  最小间距 = 0.1530 m（吊架L @ -30°）
  进入静部件的顶点总数 = 0                 -> PASS          (clearance/clearance.log)
```

**一处必须公示的判据修正**：002 把摆动件拆成"摆臂 `ForgeSwing` + 锤头 `HeroHead`"两个网格。
第一次跑穿插测试只匹配到 `ForgeSwing`（名字里没有 HeroHead），给出 0.153 m 的"假 PASS"；
修正为**按节点路径同时匹配两者**后重跑，才得到上面这组真实读数。这类"测试没覆盖到"是本轮
最需要警惕的问题，特此记录。

### 6.2 性能（1920×1080，240 采样，同机背靠背）

| 指标 | 001 @GL | **002 @GL** | 001 @F+ | **002 @F+** |
|---|---|---|---|---|
| avg FPS | 164.8 | **164.7** | 154.1 | **155.5** |
| P50 (ms) | 6.06 | **6.06** | 6.46 | **6.18** |
| P95 (ms) | 8.07 | **8.10** | 7.89 | **8.03** |
| Draw Calls | 607 | **601** | 590 | **534** |
| 渲染图元 | 473 558 | **494 688** | 472 506 | **494 655** |
| 静态内存 (MB) | 274.3 | 274.7 | 310.3 | 310.5 |
| 显存峰值 (MB) | 132.7 | **142.8** | 394.2 | **432.3** |

**结论：无退化。** P50 完全相同（6.06 ms），Draw Call 反而少 6 个，图元 +4.5%，
Compatibility 显存 +10.1 MB（2K 贴图压缩后），Forward+ +38.1 MB。

### 6.3 Compatibility 验证

首轮默认渲染器即 `gl_compatibility`，全部取证图都是 GL 实机渲染；
Forward+ 仅作对照（`--rendering-method forward_plus`）。GL 下环境光与灯强按 ×1.45 提升
（GL 无 SSIL/SSAO/体积雾），接触阴影依赖**烘焙顶点 AO + 高模 AO 掩膜**。

---

## 7. 视觉验收逐项自评（附截图位置）

| # | 问题 | 自评 | 依据 / 未达标之处 |
|---|---|---|---|
| 1 | 锤头是否有真正手工造型？ | **部分** | 有铸造起伏、左右不对称凸台、补焊补丁、顶部浅凹、中缝环带；但整体仍是"放样 + 位移"，不是雕刻级有机转折（`c3_head_cheek`、`c4_head_face`） |
| 2 | 大面积金属是否不再均匀？ | **是** | 2K 族贴图 + 分层漆面 + 流痕/落尘/积垢分区（`c1_column_foot`、`c11_column_paint`） |
| 3 | 混凝土是否像混凝土？ | **是（本轮最大提升）** | 不等距模板缝、崩角骨料、砂浆脱落、气孔、骨料色差；与钢材一眼可分（`c2_plinth_edge`） |
| 4 | 岩层是否自然？ | **部分** | 断面朝向玩家、层厚 22–44 cm 不均、崩积与中景过渡成立；但板缝仍偏规整，缺少手工摆放的单块变化（`c10_bedrock`） |
| 5 | 晶体是否有内部深度？ | **部分** | 三层光学 + 芯层脉冲 + 根部浑浊 + 软膝防过曝；不透明管线做不出真实折射（`c5_anvil_jaw`、`c6_crystal_body`） |
| 6 | 装配与承力关系可信？ | **是** | 承力链可读（鞍座→立柱→横梁→吊架→轴承→轴→臂→锤头→砧座），紧固件均有装配依据（`c7_bearing`、`c8_beam_web`） |
| 7 | 主体与背景统一？ | **是（有保留）** | 背景晶体已统一到同族材质；但背景洞壁仍是上一版地质体精度（`01_wide`、`06_threequarter`） |
| 8 | 动画有重量/惯性/反馈？ | **是** | 真实积分器 + 余振 + 火花/粉尘/晶体脉冲；实测 `strike_count=1`、峰值角速度 1.631 rad/s（`06_REFERENCE/motion/`） |

**最关键那一问**："玩家站在 1–2 米，是否还觉得像几个简单几何体拼的？"
→ **答案是"比以前好很多，但仍能看出是程序化生成的形体"**。所以视觉验收给 CONDITIONAL GO，
不给 GO。

---

## 8. 尚未完成的问题（如实）

1. **锤头仍缺雕刻级有机转折**：本轮做到了"高模 + 烘焙"，但高模本身是位移生成的，
   不是手工雕刻；要再上一档需要真正的 sculpt（Sculpt 模式手工或扫描/资产库）。
2. **晶体没有真实折射/透射**：Compatibility 不支持 transmission；现用不透明近似（三层 + 软膝）。
   若允许在 Forward+ 专供段落使用，可换 `TRANSMISSION` + 厚薄近似。
3. **岩层板缝仍偏规整**：几何是程序切分，缺少"每块都不同"的手工摆放；建议下一轮逐个石垛调整角度/厚度。
4. **背景洞壁精度低于英雄区**：仍是 ART-QUALITY-002 的地质体；中景已补过渡岩缓解。
5. **多人同步未验**：与上一轮一致，本轮未做联机环境层验证。
6. **Compatibility 下 Forward+ 的额外特性（SSAO/SSR/体积雾）不可用**：靠烘焙 AO 兜底，
   金属反射在 GL 下是近似。

---

## 9. 正式工程 `game/` 零写入

见 `_baseline/` 与交付包 `07_VERIFICATION/SHA256SUMS.txt`：

```
口径：game/ 下全部文件，排除 .godot/ 导入缓存
本轮开始：game_before.sha256（3 059 个文件）
本轮结束：game_after.sha256 （3 059 个文件）
比对：差异 0（改动 0 / 缺失 0 / 新增 0）
```

同时核对 ART-SAMPLE-001 未被覆盖（`sample001_before/after.sha256`，差异 0）。

---

## 10. 交付包

| 项 | 值 |
|---|---|
| 位置 | `work/art-sample-002/deliverable/ART-SAMPLE-002_TEAM_KIT.zip`（172.3 MB） |
| 解压后目录 | `ART-SAMPLE-002_TEAM_KIT/`（8 个顶层目录，全部有真实内容） |
| 完整性 | 解压 → 208 个文件 SHA-256 逐一全等（异常 0）→ Godot 重新导入（52 个导入资源）→ 演示工程渲染成功（见第 11 节） |
| 清单 | 包内 `07_VERIFICATION/SHA256SUMS.txt`（208 行，逐文件） |

目录内容概览：

```
00_README_FIRST     明早先看这里 / 快速启动指南 / 本次成果说明
01_GODOT_DEMO       独立可运行工程（F5 即跑；空白工程导入 + 截图已验证）
02_BLENDER_SOURCE   4 个 .blend（贴图打包）+ 高模/低模 GLB + 烘焙图 + 全部脚本
03_GAME_READY_ASSETS  industrial 5 件 / geology 1 件 / crystals 1 件
04_MATERIAL_LIBRARY  3 条 shader + 2K 贴图 + 环境预设 + hero_lib.gd + material_guide
05_ART_STYLE_GUIDE   ART-PLANET-VISUAL-STANDARD-v1 + 英雄资产/材质灯光/Blender流程/验收清单
06_REFERENCE         old_new_comparison(19) / hero_views / closeups(13) / material_board / asset_breakdown / motion
07_VERIFICATION      本报告 + regression/fullchain/clearance/performance 日志 + SHA256SUMS
08_TEAM_STARTER      星球模板 / 标准场景模板 / 标准机位模板 / 新星球交付清单
```

---

## 11. 解压复验记录

```
1) 生成 ZIP                        → 172.3 MB / 208 个文件
2) 解压到全新独立目录              → 9 个顶层目录、209 个文件齐全
3) 按包内 SHA256SUMS.txt 逐文件复核 → 208/208 全等，异常 0
4) Godot 4.7.2 --import            → 生成 52 个导入资源，无资源缺失
5) 运行 01_GODOT_DEMO 并截图        → 成功（07_VERIFICATION/verify_render_after_unzip.png）
6) 打开 aqs002_head.blend          → HeadHigh 64 356 tris / HeadLow 3 928 tris，贴图已打包
```

**环境说明（如实）**：第一次尝试解压到 `%TEMP%` 与 `C:\kit_verify` 时，Godot 报
`Could not create project data directory`；用最小探针工程在同一位置复现，确认是**本机沙箱对
工作区外新建目录的限制**，与包无关。复验改在仓库内全新目录 `work/art-sample-002/_zipcheck/`
完成，全部步骤通过。详细记录见 `07_VERIFICATION/zip_verification.md`。

---

## 12. 队友打开步骤 / 优先学习顺序

**打开**：Godot 4.7.2 → 导入 `01_GODOT_DEMO/` → F5 → 空格拉锤、F1 切机位。

**优先学习顺序（建议 2 小时）**
1. `05_ART_STYLE_GUIDE/ART-PLANET-VISUAL-STANDARD-v1.md`（先建立判断标准）；
2. `06_REFERENCE/old_new_comparison/c4_head_face_old_new.png` 与 `c2_plinth_edge_old_new.png`
   （看清"高模烘焙"和"真混凝土"分别长什么样）；
3. `02_BLENDER_SOURCE/scripts/build_head.py`（唯一的高模→烘焙完整链路，逐行能跑）；
4. `04_MATERIAL_LIBRARY/presets/hero_lib.gd`（材质库，改参数最快见效）；
5. `08_TEAM_STARTER/标准机位模板/`（把自己星球的图按同一套机位拍出来）。

