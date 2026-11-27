# 《迷失太空》美术制作与 AI 协作权威指南（风格 × 质量 × 工程实现方法）

> **文档定位**：本手册是项目面向所有星球的**统一美术权威执行指南**（整理自项目既定设计文档、美术样本 `ART-SAMPLE-002`、`ART-QUALITY-001` 与共振星整合管线，不越权改动团队分工或未定设计决策）。  
> **核心价值**：读这一份文档，队友与 AI 就能同时掌握 **① 什么是全游戏统一的画风（风格）**、**② 做到什么程度才合格（质量）**，以及 **③ 从零建模、贴图烘焙到 Godot 实机布光与验收的具体代码级方法（如何实现）**。不论制作哪颗新星球，产出的资产都能既有本星特色、又与共振星标杆保持完全同一套画风与水准。  
> **配套深挖**：建模代码详例与多生态配方副本见同目录 [AI精细3D建模分步制作指南.md](file:///d:/迷失太空/docs/AI精细3D建模分步制作指南.md)。

---

## 第一部分 · 风格规范（STYLE：决定“像不像同一款游戏”）

### 1.1 一句话风格总纲

- **已确认核心画风**：**「精致卡通」——清晰轮廓、圆润设备、统一色彩**。
- **技术表达落地**：**硬朗清晰的几何切面与物理倒角（非圆球堆砌、非零厚度片） + 工业/生态结构分层 + 多层旧化质感 + 严格的功能语义色板比**。
- **明确排斥**：明确**排除像素风**；明确**排除纯写实高频杂乱肉瘤/噪点脏脸**；明确**禁止悬浮在空中的 3D 文字（`Label3D` / Billboard）**。

### 1.2 跨星球不变的 5 条核心风格基因 & 功能色板比例

无论新星球是极寒冰原、风沙废墟、酸性菌沼还是太空站，以下 5 条视觉法则跨星球保持不变：

1. **几何秩序与“圆润硬朗”美学**：大形体剪影干脆、体块明确、转折利落，主体大转角带明显圆角（`40–60 mm`），次级机械/装备带有手办般的精致厚度感与物理倒角（`0.8–3 mm`）。
2. **高度克制的功能色板分配（65–75 / 15 / 10 / 8 / 2 法则）**：

| 色彩层级 | 面积占比 | 跨星球定位与常见取值参考 | 视觉职责（不可越界） |
|---|---|---|---|
| **主骨架/地貌中性底色** | **65–75%** | 共振星参考：深石墨 `#29303B` / 蓝灰 `#5C7085` / 红褐岩棕；其他星球换成与生态一致的**低饱和暗灰/冷灰/泥炭褐/风蚀灰** | 压住全画面调性，把高亮交互区和角色“托”出来 |
| **高明度识别外壳** | **10–15%** | 奶油白 `Color(0.615, 0.578, 0.488)` / `#EFE6CE` / 极地浅灰 / 旧米白（**PBR 反照率严控 `<= 0.62`**） | 机器主外壳、建筑门柱、货箱腰线，防高光下炸成死白 |
| **青绿（安全/引导/我方）** | **5–10%** | 深青 `#1E3B44` / 钢青 `#41627A` / 激活青光 `#28DBFF` | 角色主视觉、飞船与轨道引导线、已就绪/已接通状态 |
| **工业橙/琥珀（交互专色）** | **5–8%（严控）** | 工业橙 `Color(0.700, 0.268, 0.062)` / 安全黄 `Color(0.95, 0.70, 0.14)` | **只能出现在手柄、阀门、可抓扶栏杆、卡箍、操作按钮与警示边界上**，严禁刷满整台设备或墙面 |
| **警示红（故障/未解锁）** | **< 2%** | 告警红光 `Color(1.0, 0.20, 0.12)` | 急停按钮、未解除闭锁、告警状态灯 |

3. **人机尺度统一（世界空间真实比例）**：以玩家第一/第三人称眼高 **`1.55 – 1.65 m`**、三头身主角身高 **`~1.85 m`（头盔占 ~1/3）** 为全宇宙唯一尺子——操作台/手柄高 `1.00–1.08 m`、护栏上杆高 `1.00–1.05 m`、踢脚板高 `0.10–0.12 m`、直梯踏步 `0.26–0.28 m`、通行净宽 `>= 2.0 m`、大厅门高 `>= 4.2–4.7 m`。
4. **物理叙事取代空中飘字**：所有交互与引导必须长在实体世界上——靠贴地/贴墙物理导管、实时摆动表盘指针、遮光状态灯和贴壳 `<= 2–3 cm` 的纯图标铭牌（`① → ② → ③`）交代规则；操作按键提示走简洁 HUD。
5. **非写实碎噪点概括**：哪怕刻画冰层、珊瑚、真菌或生物外壳，也用干净的**几何/分段体块 + 局部高对比微细纹理**，避免满屏写实肉质皱褶。

### 1.3 跨星球风格迁移矩阵（如何做出本星特色又不跑偏）

> 下表以常见异星生态作参考示例（不预设未定星球玩法决定），说明**什么随星球改、什么全游戏死守不变**：

| 迁移项 | 共振星（已实装标杆） | 极寒冰原类星球（示例） | 腐蚀菌沼 / 废墟类星球（示例） | 荒漠裂谷类星球（示例） |
|---|---|---|---|---|
| **70% 基底色（改）** | 深石墨 + 红褐矿岩 | 冷板岩灰蓝 + 暗冻土 | 暗泥炭绿褐 + 氧化铅灰 | 风蚀暖灰褐 + 玄武深灰 |
| **15% 明度壳（微调）** | 暖奶油白工业涂装 | 极地浅灰白（带寒霜蓝调） | 旧殖民站浅米灰 | 褪色象牙白工程壳 |
| **8% 交互亮色（不变）** | 工业橙 / 安全黄 | **仍用工业橙 / 琥珀** | **仍用工业橙 / 琥珀** | **仍用工业橙 / 安全黄** |
| **地貌与能源载体（改）** | 解理页岩 + 棱面青紫晶簇 | 陡切蓝冰崖 + 地热喷汽口 | 饱满分段菌伞 + 几丁质荧光囊 | 风蚀砂岩台 + 聚光琥珀阵 |
| **表面风化层语义（改）** | 橘皮漆→底漆→亮铁→矿尘 | 防冻漆→铝底→**霜雪(`A`通道)** | 涂层→铜底→**湿苔孔蚀(`G/B`)** | 砂砾漆→钢底→**黄沙积层(`A`)** |
| **物理连线载体（改形不改规）** | 三轨装甲能量导管 | 保温棉伴热高压蒸汽管 | 透明脉冲输液软管 + 压环 | 铠装耐高温埋沙电缆桥架 |

---

## 第二部分 · 质量标尺（QUALITY：做到什么程度才算合格）

### 2.1 三距验收标准（每件资产与场景必须同时通过 3 个距离）

- **远距（> 10 m）看构图与剪影**：30 米外纯黑剪影也能一眼分辨“这是反应堆、大门还是采集信标”，不能全是“方块台子 + 一根发光柱”；主灯光把主体从背景岩壁剥离。
- **中距（3–10 m）看结构与承力**：每一个悬挂物、管线、箱体都能说出“谁承重、拧在哪里、往哪走”；没有悬空方块或违背重力的斜插穿模。
- **近距（1–2 m）看工艺与微表面**：绝对看不到光滑“数学平面”或锐死直棱——必须看得见物理倒角、零件拼缝阴影、螺母/焊道工艺细节、4 层磨损落尘以及明显的粗糙度高光反差。

### 2.2 资产分级与引擎硬指标

| 资产级别 | 典型视距 | 三角面预算 | 贴图与合批标准 | 必须具备的工艺度 |
|---|---|---|---|---|
| **英雄件（Hero）** | `0 – 3 m`（主交互设备/主角/地标中心） | 高模 `>= 50k`；运行时低模 `3k–15k`（大型组合结构 `<= 60k`） | `2048²` Tangent 法线 + `2048²` 粗糙 + `1024²` Mask（VRAM 压缩） | 自定义截面放样 + 多段倒角 + `2–3mm` 装配缝 + 四件套螺栓/焊道 + **高烘低法线与曲率/AO** |
| **中景件（Mid）** | `3 – 10 m`（廊道/岩壁/管网/护栏） | `2k – 15k / 件` | 共享 `1K–2K` 家族图集 + 4 通道顶点色 `Col` | 真厚度与折边 + 承力梁/管卡 + 解理切面岩体，允许免单件 Cycles 烘焙 |
| **远景件（Far）** | `> 10 m`（远山/外围碎石/穹顶壳） | `<= 2k / 件`（按材质合批或 `MultiMesh`） | `512–1K` 或三平面程序化材质 | 强轮廓剪影与冷暖色调分离，**不建螺母、小焊道或小倒角** |

### 2.3 十条绝对红线（触犯任一条即判定返工）

1. **禁悬浮 3D 文字**：禁止漂浮或朝向相机的 `Label3D`；教学与顺序做在贴合实体的图解铭牌（`<= 2–3 cm`），按键提示走 HUD。
2. **禁裸几何成品**：`BoxMesh`/`CylinderMesh`/`SphereMesh` 只能当白盒草稿，成品必须用自定义轮廓、倒角、底座与筋板替换。
3. **禁无承力悬浮件**：架子必落地/入墙，管道必带法兰和固定管卡，灯具必带挂架与遮光罩。
4. **禁漏三角化与漏遮罩标志**：GLB 导出未三角化会导致无 `TANGENT` 法线失效；无顶点色的网格进 Godot **必须**设 `vertex_mask_valid = false`（否则默认 `COLOR=1` 整件变黑烂漆）。
5. **禁全场景共用同一张噪声**：喷漆（`paint`）、铸件（`cast`）、机加工（`mach`）、混凝土（`conc`）、地貌（`rock`/`ice`/`bio`）必须分家族独立高度场与粗糙通道。
6. **禁拉满环境光充数**：必须在关闭环境光下先用主光把体块打立起来，禁止靠平铺环境光掩盖没有层次的结构。
7. **禁改动玩法碰撞与触发器**：美术包裹外壳严格贴合既有碰撞盒（外扩 `<= 2.5 mm`），视觉与物理碰撞分离。
8. **禁无意义堆砌螺母**：螺栓/焊缝只放在真实受力与检修节点，不乱撒。
9. **禁发光过曝炸死白**：任何晶体/孢子/灯条必须保留色相变化并用软膝限幅（`emit / (1 + emit * 0.62)`）。
10. **禁跳过 `gl_compatibility` 实机验收**：Godot 4.7 运行基线为 **`gl_compatibility`（无 SSR / SSIL / VolumetricFog）**，Blender Viewport 好看完全不算通过。

---

## 第三部分 · 实现该风格与质量的具体工程方法（HOW-TO）

> 本部分精确规定 AI 必须如何通过 **① Blender 建模烘焙 ② 分层材质贴图 ③ Godot Compatibility 布光与接地因果 ④ 双端渲染自检** 四步落地，做到既保持“精致卡通”画风，又有 1–2 米经得起贴脸看的质量。

---

### 方法一：Blender 5.2.2 LTS 精细 3D 建模与烘焙 9 步流水线

> 开源脚本模板：[aqs_kit.py](file:///d:/迷失太空/work/art-sample-002/deliverable/ART-SAMPLE-002_TEAM_KIT/02_BLENDER_SOURCE/scripts/aqs_kit.py)、[aq2kit.py](file:///d:/迷失太空/work/art-sample-002/deliverable/ART-SAMPLE-002_TEAM_KIT/02_BLENDER_SOURCE/scripts/aq2kit.py)、[build_head.py](file:///d:/迷失太空/work/art-sample-002/deliverable/ART-SAMPLE-002_TEAM_KIT/02_BLENDER_SOURCE/scripts/build_head.py)；可执行路径：[blender.exe](file:///d:/迷失太空/tools/blender-5.2.2-windows-x64/blender.exe)

| 步骤 | AI 必须执行的具体做法 | 关键参数与防坑要点 |
|---|---|---|
| **Step 0 · 初始化与坐标** | 清空场景设为米制；脚本内全部按 **Godot 坐标（`X` 右、`Y` 上、`-Z` 前）** 算位置尺寸，合入 Mesh 时乘矩阵 `GB` 转 Blender（`Z` 上） | `GB = ((1,0,0,0), (0,0,-1,0), (0,1,0,0), (0,0,0,1))`；先锁定交互件在 `y=1.00–1.08m` 及原碰撞盒最大包络 |
| **Step 1 · 轮廓先于细节** | 用 **`rrect_r(w, d, r, seg)` 真圆角截面 + `bm_loft` 多剖面插值放样**造机壳，用 **`bm_lathe` 剖面车削**造圆筒/法兰/手轮，确立 30m 剪影 | 拐角 `seg = 4`（中景）或 `seg = 10`（英雄件）；控制点列按高度 `y` 写出“扩底→收腰→宽肩→斜顶”工业节奏，**绝不用 Cube 缩放硬凑** |
| **Step 2 · 承力结构网** | 造地脚承台/铸铁靴（斜坡扩底嵌入 `y=0`）、直角**三角形加强肋（厚 `14–24 mm`）**、**工字钢 `i_profile` 梁柱**与挂壁托架 | 所有立柱、管架、控制台都看得出受重力支撑；悬垂灯头加防眩金属罩 `_LampHood` |
| **Step 3 · 分层与 `2–3mm` 缝** | 拆成**内骨架 + 外护壳 + 功能嵌件（百叶/表框/胶条）**；壳板之间留 **`2–3 mm` 实体凹槽缝**；薄板带真实厚度（`8–20 mm`）和折边；全外棱加真实倒角 | 机加工棱 `bevel = 0.8–3 mm`（`>=2` 段），主骨架大圆角 `8–35 mm`（`clamp_overlap=True`）；若保留修改器则配 `WEIGHTED_NORMAL(keep_sharp=True)` |
| **Step 4 · 次级工艺件** | **仅在法兰、检修门角、支座根部**加紧固件；焊角加带起伏焊道；线缆用**平行传输防翻转**扫掠（`bm_tube`）并在两端挂金属卡箍 | **紧固件四件套**：沉座凸台 + 垫圈(`1.42r`) + 45° 倒棱六角头 + **每颗独立随机旋转 `phase`**；**焊道**：`r=5–7 mm` 加 **`±28%`** 半径噪点；指示物做实体指针/灯罩/贴壳纯图铭牌 |
| **Step 5 · UV 与材质命名** | 用 `M_` 前缀命名占位材质作 Godot 绑定键（如 `M_CastMetal`/`M_PaintMain`/`M_PaintAccent`/`M_Terrain`）；低模执行 Smart UV 展开 | `bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.006)`；**致命顺序：必须先把拓扑焊接合并、展 UV，下一步烘完顶点色后，最后才能做 `EdgeSplit`** |
| **Step 6 · 4 通道顶点色 `Col`** | 调用 `bake_masks()` 在拆边前把物理风化信息写入顶点色（Blender 5 禁用旧 `use_auto_smooth`，改用 `p.use_smooth=True` + **`EDGE_SPLIT(30°–32°)`**） | **`R`**：1-ring 离散曲率×`fbm` 边缘磨损；**`G`**：BVH 余弦半球 AO（**`ao_dist=0.15–0.18 m`**，`ao_rays=9–12`）+贴地暗带；**`B`**：碎漆/孔蚀斑；**`A`**：法线朝上度（积尘/霜/沙） |
| **Step 7 · 高模与 Cycles 烘焙** | （0–3m 英雄件）复制低模 `Subsurf(2)` 至 `>=50k` 面；施加**以向内为主的三频铸造/风化位移** + **2–3 处非对称历史痕迹**（单侧凸台/补焊/擦凹）→ `Cycles` 高烘低 | 位移 `d = min(低2.2mm+中1.1mm+高0.4mm, +0.8~2.5mm)`；**严禁全局负向 Shrink 整体缩小高模**；`selected_to_active` (`cage_extrusion=0.035, margin=12px`) 烘 `2048² Tangent Normal`、`1024² AO`、`1024² Pointiness(0.42..0.58)→Emit`，NumPy 将 Curv(`R`)+AO(`G`) 合进 `*_mask.png` |
| **Step 8 · 清洗与 GLB 导出** | 检查 `scale==(1,1,1)` 无负缩放；**导出前强制 `Triangulate` 全三角化**（否则缺 `TANGENT` 法线贴图全废）；打包贴图保存 `.blend` 源工程 | `export_format="GLB", export_apply=True, export_yup=True, export_normals=True, export_tangents=True, export_vertex_color="ACTIVE"`（`Col`） |

#### 附：4 类非机械通用资产的建模实现公式（直接复用 Step 0–8 后半程）

- **① 自然地质体（岩崖 / 冰崖 / 砂岩 / 玄武岩）**——严禁“平滑球 + 噪点”或“立方体堆砌”：
  - **单体岩块（`rock_from_planes`）**：立方体细分 3 级并轻柔化 → 执行 **`7–14` 刀倾斜平面切割 `bisect_plane(clear_outer=True)`** 切出清晰解理锐面（第 1 刀削底放稳）→ 面内双频凹凸 → 水平/斜向层理错台 `strata=(层厚 period, 错台 amp)` → 加 `3–18 mm` 单段微倒角（页岩 `6mm`、锋利蓝冰 `3–4mm`、风蚀砂岩 `12–18mm`）。
  - **大跨度峡谷壁 / 洞壳**：外轮廓放样 → `REMESH(VOXEL)` → 手写地质断裂折线 `joints` 与斜削凹面 `scoops` 刻痕 → `DECIMATE` 减面；若从内部观看，执行 `orient_toward(me, center)` 把法线翻向室内。
- **② 异星能源物 / 晶体 / 卡通概括菌囊**：
  - **硬质晶体/冰柱**：手写**不等边 `5–7` 边形**截面并在侧边捏出约 `9%` 凹槽（放高光内芯材质），沿 9 环粗细曲线微弯斜切放样 + `3–6 mm` 倒角；
  - **有机菌伞/生物囊**：保持“精致卡通”的饱满圆润分节放样，**在根颈、菌褶、甲片处做硬朗箍环和 `2 mm` 镶嵌槽**；
  - **统一破土绑定**：用 `BVHTree.ray_cast()` 把根部**深埋进基岩以下 `15–25%` 高度**，压出一圈碎岩/蚀变槽，写入顶点属性 `growth(0..1)` 驱动根浊到顶亮。
- **③ 模块化建筑与废墟**：按 `2.5–4.0 m` 间距插工字钢肋柱 + `0.10–0.12 m` 防撞踢脚线打破白墙；做废墟时**先建完整标准建筑框，再用 3–5 刀斜向 `bisect_plane` 削出断茬**并外露折弯钢筋与碎块。
- **④ 环境交互小道具与角色皮肤**：中小型物件按 `ExplorePropKit` 关键词命名（`*Crystal*`/`*Valve*`/`*Pipe*`/`*Lamp*`/`*Panel*`/`*Crate*`/`*Barrel*`），接入关卡即可自动全场景按 `E` 探索反应；角色严格保持 `~1.85m` 三头身（头盔 `~1/3`）及 `HeadPivot`/`*ArmPivot`/`*LegPivot` 挂点契约。

---

### 方法二：四层表面分化、2K 多频纹理与 Godot 着色器绑定

**为什么同类几何别人像塑料、共振星像重工成品？** 因为材质必须做足 **4 层物理叠合 + 家族级粗糙度差异（`>= ±0.15`）**：

1. **三频程序化可平铺 2K 贴图制作（[make_textures_2k.py](file:///d:/迷失太空/work/art-sample-002/deliverable/ART-SAMPLE-002_TEAM_KIT/02_BLENDER_SOURCE/scripts/make_textures_2k.py) 算法）**：
   - 使用 **FFT 频域粉红噪声** + 环形绕边绘制（`ox, oy in (-S, 0, S)`）生成绝对无接缝四方连续贴图；
   - 每类材质单独合成 **低频大斑块（20–60 周）+ 中频工艺肌理（200–600 周）+ 高频颗粒/拉丝（2000+ 周）**，经中心差分转为 `2048² Normal` 与 `2048² Roughness` + `1024² Mask`：
     - `paint`（橘皮 + 起皮边 + 细擦痕，`R ~0.38–0.58`）
     - `cast`（砂型麻点 + 气孔 + 浇铸波纹，`R ~0.46–0.72`）
     - `mach`（各向异性金属拉丝，`R ~0.18–0.34`）
     - `rock`/`conc`（解理裂沟 + 骨料坑蚀，`R ~0.72–0.92`）
     - 新星球扩展参考：`ice`（直线刮痕 + 浊斑，`R ~0.08–0.28`）、`bio`（同心生长波纹 + 局部湿润脉络，`R ~0.55–0.75 / 0.15`）。
2. **Godot 着色器挂载与 4 层融合规范**：
   - 优先调用仓库 [ArtPbrLib](file:///d:/迷失太空/work/resonance-art-integrated-001/project/scripts/world/art_pbr_lib.gd)（底层着色器 [aqs2_metal.gdshader](file:///d:/迷失太空/work/resonance-art-integrated-001/project/shaders/aqs2_metal.gdshader)、[aenv8_rock.gdshader](file:///d:/迷失太空/work/resonance-art-integrated-001/project/shaders/aenv8_rock.gdshader)、[aqs2_crystal.gdshader](file:///d:/迷失太空/work/resonance-art-integrated-001/project/shaders/aqs2_crystal.gdshader)）；
   - 四层混合逻辑：**面漆/表壳 → 露底漆/原胚（`Col.R` + `Col.B`） → 凹缝/接地污垢（`Col.G` + `Mask.G`） → 朝上尘/霜/沙（`Col.A`）**；
   - 导入清单强制项：法线贴图设为 `compress/mode = 2`（VRAM Compressed）、`compress/normal_map = 1`、`mipmaps/generate = true`；无 `Col` 设 **`vertex_mask_valid = false`**；室内大型洞壳/穹顶必用 `ArtPbrLib.rock_shell(...)`（`cull_disabled`）；多件静态小装饰按材质合并网格合批。

---

### 方法三：Godot 4.7 `gl_compatibility` 五层布光、接地氛围与物理因果实现

**`gl_compatibility` 下没有 SSIL / SSR / 实时体积雾，质感全靠以下四项硬配比拉起**：

1. **`WorldEnvironment` Compatibility 安全配置**（参照 [aenv003_env.gd](file:///d:/迷失太空/work/resonance-art-integrated-001/project/tests/aenv003_env.gd#L386-L426)）：
   - 必须显式关闭 `ssr_enabled = false`、`ssil_enabled = false`、`volumetric_fog_enabled = false`；
   - 环境光能量控制在适中底座（如 GL 下按主光压一档、`~1.8–2.4` 补偿无间接弹射暗部，**绝不能反客为主淹没亮暗交界**）；雾色匹配本星球背景暗调。
2. **五层通用布光蓝图**（每层各司其职）：

| 光层 | 节点与阴影设置 | 角度与能量要点 | 解决的画面问题 |
|---|---|---|---|
| **1. 主故事光 Key** | `SpotLight3D` / `DirectionalLight3D`（**全厅唯一 1–2 盏开阴影**） | 暖白/本星主题主光，张角 `42–48°`，`15–25°` 斜向掠射主体 | 建立体积明暗交界与清晰地面投影 |
| **2. 补光 Fill** | `SpotLight3D` / `OmniLight3D`（关阴影） | 主光能量 `40–55%`，偏冷灰或环境色 | 让背光面依然能看清结构线条不死黑 |
| **3. 轮廓光 Rim** | `SpotLight3D`（**必关阴影，高对比**） | 主体斜后上方 `32–38°` 照边缘 | 把机械和角色剪影从深色背景岩壁/废墟强力“剥离”出来 |
| **4. 表面掠射 Graze** | 窄角 `SpotLight3D`（关阴影） | 贴近岩崖/冰壁/建筑墙 `10–20°` 擦面 | 在无 SSAO 时靠掠射高光把岩石层理与墙肋打出立体起伏 |
| **5. 实用状态光 Practical** | 小半径 `OmniLight3D`（关阴影，`omni_range 3–6 m`） | 直接挂在可见灯罩、晶体、控制台屏前 | 让环境光随机关激活/锁定切换色温，兼顾美学与玩法读图 |

3. **接地、悬垂软管与环境微动态（消除“模型展览馆摆拍感”，[ArtAtmosphereKit](file:///d:/迷失太空/game/scripts/core/art_atmosphere_kit.gd)）**：
   - `build_ground_skirt()`：在每座重型设备/立柱底面 `y + 0.012` 铺程序化径向暗晕贴片，立竿见影消除“生硬直角插进地里”；
   - `build_gravel_cluster()`：沿底座与岩脚围一圈微倒角碎石/冰碴/残片；
   - `build_catenary_hose()`：在机柜与墙框间拉自然重力悬链线软管+金属箍，打破方方正正的呆板外轮廓；
   - `build_ambient_motes()` / `build_steam_vent()`：用轻量 `CPUParticles3D` 制造缓飘尘雾、孢子或脉冲泄压蒸汽；
   - `build_godray_cone()`（[walle_godray.gdshader](file:///d:/迷失太空/game/shaders/walle_godray.gdshader)）：在天井、闸门、反应堆上方挂极淡（`intensity 0.09–0.12`）渐变假光束，补足 GL 兼容性模式的空间纵深空气感。
4. **物理因果机械表达（[PhysicalLinkKit](file:///d:/迷失太空/game/scripts/core/physical_link_kit.gd) + [conduit_flow.gdshader](file:///d:/迷失太空/game/shaders/conduit_flow.gdshader)）**：
   - 机关连线用贴地/贴墙倒角三轨装甲导管（绕过门洞通道，端面加法兰，颜色脉冲区分未通电/琥珀就绪/青光激活）；
   - 进度/参数用可动实体表盘 `build_live_dial()` + 遮光状态灯 `build_status_lamp()` + 贴壳纯图标铭牌 `build_diagram_plaque()`。

---

### 方法四：双端无头渲染 + AI 读图排雷闭环（验证方法）

1. **Blender 灰模构型快检**：跑 [render_preview.py](file:///d:/迷失太空/work/art-sample-002/deliverable/ART-SAMPLE-002_TEAM_KIT/02_BLENDER_SOURCE/scripts/render_preview.py) 出 `front` / `three_quarter` / `side` / `detail` 四向图，脱离贴图单独审视剪影、倒角、缝隙和承力关系。
2. **Godot `gl_compatibility` 实机 4 机位截图**：编写临时 headless 场景截图脚本输出：
   - `A_wide.png`（FOV 50，审整体地标轮廓与 70/15/10/8 色彩比例）
   - `B_player_eye.png`（眼高 1.60m 玩家实机走过视角，FOV 65）
   - `C_interaction.png`（核心机关 1.3–1.8m 近距特写，FOV 44，审倒角/接缝/法线细节）
   - `D_threequarter.png`（设备/建筑底座与自然地貌接地交界，FOV 52）
   - 若带交互开关，再补 `locked` 与 `active` 状态双图。
3. **常见翻车秒查修复**：
   - Blender 5.2 报 `use_auto_smooth` 错误 → 改用 `p.use_smooth=True` + `EDGE_SPLIT`；
   - Godot 法线完全没凹凸 → 导出前忘 `Triangulate` 或 `.import` 漏开 `compress/normal_map=1`；
   - 低模像膨胀反光球 → 高模误加整体 `Shrink/Smooth` 收缩；
   - 全黑/全掉漆 → 漏设 `vertex_mask_valid=false` 或在 `EdgeSplit` 之后才烘顶点色；
   - 内视黑洞破面 → Blender 未朝内定向且 Godot 未挂 `rock_shell(cull_disabled)`。

---

## 第四部分 · 可直接复制发给 AI 的跨星球提示词包

> 新开对话让 AI 制作**任意新星球**时，先发 **【0 号总控】** 锁定“风格+质量+实现方法”，再按阶段依次发送 **【1～4 号执行提示词】**；若只需单件资产，直接使用 **【5 号单资产全流程工单】**。

### 0 号提示词：跨星球风格、质量与实现法则总控（新对话第一条必发）

```text
你正在协助制作多人合作游戏《迷失太空》的新星球：[星球名称与生态主题]。
核心要求：**同时做到“与共振星（K-17 / ART-SAMPLE-002）完全同一套画风与质量标准”以及“属于本星球的独特地貌和题材”——既不能抄共振星的红褐洞穴与蓝晶，也不能退化成粗糙方块、纯写实碎噪点或低劣玩具。**

你必须同时遵守项目《美术制作与AI协作指南》（docs/美术制作与AI协作指南.md）里的【风格 × 质量 × 实现方法】：
1. 风格不变量（精致卡通：清晰轮廓、圆润设备、统一色彩）：
   - 造型：干净硬朗的几何块面 + 真实厚度折边（>=8mm）+ 主角大圆角（40–60mm）+ 加工件多段物理倒角（0.8–3mm）+ 2–3mm 实体阴影装配缝；严禁裸 BoxMesh/CylinderMesh 当成品，严禁“平滑球+噪点”当自然岩体，严禁像素风。
   - 色板比例（跨星球死守不变）：65–75% 低饱和与本星相符的基底色 + 10–15% 高明度识别外壳（albedo<=0.62防死白）+ 5–10% 安全青绿引导 + <=8% 工业橙/琥珀（严格限定只给手柄/阀门/卡箍/按钮等可操作件）+ <2% 警报红；发光必用软膝限幅保留色相梯度。
   - 绝对禁止悬浮 3D 文字（Label3D / Billboard）；读数与顺序必须做成实体表盘、状态灯或贴壳<=2cm的纯图铭牌，提示走 HUD。

2. 质量与人机工程基线：
   - 眼高 1.55–1.65 m 为尺度锚点（操作台/栏杆高 1.0–1.08 m，通道净宽 >= 2.0 m）。
   - 1–2 m 内拒绝“数学平面”与“单色塑料漆”：必须有 4 层表面演化（基质→外涂/覆层→凸棱/破损露底→凹缝AO与朝上积尘/霜/沙）+ 分族粗糙度变化（>= ±0.15）。
   - 机械必有落地承台/加强筋/法兰管卡；自然物/菌簇必须深埋地形 15–25% 并伴生碎屑压边。

3. 实现方法与 Godot 4.7 `gl_compatibility` 硬约束：
   - Blender 5.2.2 LTS（D:/迷失太空/tools/blender-5.2.2-windows-x64/blender.exe）用 Godot 坐标计算后矩阵转换，先截面放样/切面雕刻，Smart UV (margin=0.006)，**必须在 EdgeSplit(30°) 之前**烘焙 4 通道顶点色 Col，英雄件高烘低严禁高模全局负向收缩，导出前必须 Triangulate 并开 export_tangents=True。
   - Godot 侧必须适配 `gl_compatibility`（禁用 SSR/SSIL/VolumetricFog），复用 ArtPbrLib / PhysicalLinkKit / ArtAtmosphereKit，无顶点色必设 vertex_mask_valid=false，内视大壳用双面 rock_shell，静态装饰按材质合批，视觉外观不得越界改动既有玩法碰撞盒。

收到请先复述本星球“风格怎么体现、质量如何达标、技术路线怎么走”，再等我派发任务。
```

### 1 号提示词：制定新星球【美术设计单】（定调色板、轮廓与地貌语言）

```text
请先基于上面约束，为我的新星球出一份可直接写进代码的【跨星球美术设计单】，不要急着乱改关卡。

【星球基本信息】
- 星球名称：[填写]
- 地貌与气候：[例如：极寒裂冰峡谷 / 被遗弃的孢子殖民废墟 / 高温风沙能源裂谷]
- 核心环境危险 & 核心合作机关：[填写]

请输出以下 5 项精确可落地规范：
1. 配色表（给出线性 RGB 与 Hex，严格遵循 70%基底 / 15%明度外壳(albedo<=0.62) / <=10%青绿引导 / <=8%工业橙可操作件 / <2%红警报）：
   - 地表/岩冰三层色（主面/断裂暗面/朝上堆积物）
   - 设施结构三层色（深骨架/高明度罩壳/橡胶密封）
   - 本星球特色能源物或生物生态色彩（必须区别于共振星红褐洞穴+青紫水晶）
2. 4 个以上远/近景主地标独立剪影规范（确保 30m 外不靠发光也能区分功能）。
3. 材质家族分配方案：哪些走 paint / cast / mach / conc / rock，本星是否需要扩展冰面(ice)或生物(bio)等分族 2K 贴图及粗糙度区间。
4. 本星球的 Godot `gl_compatibility` 五层灯光配方（1盏主阴影光色温/角度、补光比例、高对比轮廓光色、掠射角度、绑定实体的实用光及雾效基调）。
5. 物理因果与“零悬浮文字”方案：用什么管线载体、实体表盘和接地氛围让玩家不用读文字就能看懂路径与危险。
```

### 2 号提示词：Blender 精细 3D 建模 + 烘焙 Python 脚本执行（工业 / 建筑 / 自然通用）

```text
请根据上面的设计单，用 Blender 5.2.2 LTS 编写可无头运行的建模与烘焙脚本：`[art-source/blender/<星球名>/build_<资产名>.py]`，制作 [资产名称、尺寸包络、核心用途与所属类别（工业设备/模块化建筑废墟/自然岩冰/异星晶簇菌落/角色小物）]。

【必须逐条在代码中实现的具体工艺】
1. 造型与结构（绝不造裸方块或平滑噪点球）：
   - 按 Godot 坐标设计后通过矩阵 GB 转进 Blender；主结构手写 `rrect_r(seg>=8)` / 多剖面 `bm_loft` / 车削 `bm_lathe` / 工字钢 `i_profile` 确立轮廓；若是岩冰用 `7–14` 刀 `bisect_plane` 解理切割+微倒角+层理错台；若是晶体/生态体用不等边多棱/饱满分段放样+硬朗箍环并深埋宿主地形 15–25%。
   - 拆出骨架/防护壳/嵌件，拼合缝留 `2–3 mm` 实体凹槽；薄板厚度 `>= 8 mm` 带折边；全加工棱 `BEVEL >= 2` 段；落地必有承台/加强筋，管线用平行传输 `bm_tube` 加卡箍，紧固件只在法兰/检修口做“凸台+垫圈+45°倒棱六角头+随机 phase”，焊角加 ±28% 抖动焊道。
2. UV、顶点遮罩与高烘低：
   - 用 `M_` 前缀命名材质槽；展开 Smart UV (`angle_limit=1.15, island_margin=0.006`)。
   - **必须在 `EDGE_SPLIT(30°)` 之前**完成 4 通道顶点色 `Col` 烘焙（R=凸棱曲率磨损, G=BVH AO dist 0.16m, B=斑块剥落, A=朝上堆积度）。禁止使用 Blender 3.x 已移除的 `use_auto_smooth`。
   - 若为 0–3 m 英雄件：复制低模 `Subsurf(2)` 至 >=50k 面 → 施加向内为主的三频微位移（-2.2mm..+0.8mm，**严禁整体收缩高模**）+ 2–3 处不对称使用痕迹 → `Cycles selected_to_active` (`cage_extrusion=0.035, margin=12`) 烘焙 `2048² Tangent Normal` 与 `1024²` 合成 `*_mask.png` (`R=Pointiness 0.42..0.58, G=AO`)。
3. 导出与白灰模初检：
   - 验证 `scale==(1,1,1)`、全部 `Triangulate` 三角化、`export_yup=True / export_apply=True / export_tangents=True / export_vertex_color="ACTIVE"` 导出 GLB，贴图打包保存 `.blend`。
   - 完成后运行 `blender -b --factory-startup -P <脚本>` 并调用 `render_preview.py` 输出四视角图自检结构，把输出图路径与面数报给我。
```

### 3 号提示词：Godot 4.7 Compatibility 装配、材质接管、五层布光与氛围接地

```text
请把生成的 [GLB/模型路径] 装配进 [新星球场景/脚本路径]，按《指南》方法二、三完成 Godot 4.7 `gl_compatibility` 全套美术渲染落地，不修改原有玩法碰撞与逻辑。

【接入执行清单】
1. 材质与着色器：
   - 复查法线图 `.import`（`compress/mode=2, compress/normal_map=1`）；通过 `ArtPbrLib` 按 `M_` 材质名映射分族纹理与 PBR 参数（paint/cast/mach/conc/rock 或扩展族），确保有明确粗糙度差与 4 层磨损落尘/霜。
   - 无顶点色模型显式设 `vertex_mask_valid = false`；玩家可从内部观察的大型壳体用双面 `rock_shell`；零散小装饰按材质合并网格合批。
2. Compatibility 五层灯光与 WorldEnvironment：
   - 显式关闭 `ssr_enabled` / `ssil_enabled` / `volumetric_fog_enabled`；布置 1 盏开阴影主光 + 关阴影补光 + 主体后上方强对比轮廓光 + 地形/建筑掠射光 + 绑定可见灯具的实用光。
3. 接地、生命力与物理因果：
   - 用 `ArtAtmosphereKit` 为全部落地设施/岩体底座挂 `build_ground_skirt` 与 `build_gravel_cluster` 消除硬边插地；按需拉 `build_catenary_hose` 软管，加 `build_ambient_motes` / `build_steam_vent` 与克制 `build_godray_cone`（`intensity <= 0.12`）。
   - 用 `PhysicalLinkKit` 沿墙角/地面铺设带法兰且不挡路的因果导管、`build_live_dial` 表盘、`build_status_lamp` 灯罩与贴壳纯图标铭牌，绝对禁止悬浮 `Label3D`。
   - 若需要让场景摆件支持自由探索按 E 交互，确认静态节点命名对齐 `ExplorePropKit` 关键词并正确避开主机关。
```

### 4 号提示词：双端实机截图验收与缺陷返修闭环

```text
不要只做文字汇报。请你用 `gl_compatibility` 模式运行 headless 渲染自检脚本，截取新星球场景 [场景路径] 以下机位并亲自看图逐一打分修补，直到全部过关：
1. `A_wide.png`（FOV 50，审地标轮廓独立性、空间层次与 70/15/10/8 色彩比例）
2. `B_player_eye.png`（眼高 1.60m 玩家实机视角，FOV 65，审引导清晰度）
3. `C_interaction.png`（核心机关 1.3–1.8m 近景特写，FOV 44，审倒角、装配缝、微肌理与磨损）
4. `D_threequarter.png`（建筑/设备与地貌交界、接地碎屑与悬垂线缆，FOV 52）
5. 若有激活状态变化，额外输出锁定/激活对比图。

请逐条自查，只要发现任一缺陷立刻改代码/模型并重截：
- [ ] 近景 1.5m 是否彻底消灭“数学平面”、“零厚度片”或“光滑玩具块”？
- [ ] 是否有悬空物、穿门导管、或与地面割裂的黑硬边？
- [ ] 是否绝对没有漂浮 3D `Label3D`？
- [ ] 是否无黑块/全烂漆（`vertex_mask_valid`）、无单面穿黑（`rock_shell`）、无过曝死白/死亮？
- [ ] 是否既有本星生态独特性，又一眼符合《迷失太空》精致卡通风格且不逊于共振星画质？
- [ ] Godot `--headless` 冒烟与交互测试全 pass 且无 Compatibility 着色器告警？
```

---

## 第五部分 · 仓库核心代码与权威索引

| 内容分类 | 仓库直接可复用路径 |
|---|---|
| **Blender 建模 / 烘焙 / 四向预览全套源码** | [AI精细3D建模分步制作指南.md](file:///d:/迷失太空/docs/AI精细3D建模分步制作指南.md)、[aqs_kit.py](file:///d:/迷失太空/work/art-sample-002/deliverable/ART-SAMPLE-002_TEAM_KIT/02_BLENDER_SOURCE/scripts/aqs_kit.py)、[aq2kit.py](file:///d:/迷失太空/work/art-sample-002/deliverable/ART-SAMPLE-002_TEAM_KIT/02_BLENDER_SOURCE/scripts/aq2kit.py)、[build_head.py](file:///d:/迷失太空/work/art-sample-002/deliverable/ART-SAMPLE-002_TEAM_KIT/02_BLENDER_SOURCE/scripts/build_head.py)、[render_preview.py](file:///d:/迷失太空/work/art-sample-002/deliverable/ART-SAMPLE-002_TEAM_KIT/02_BLENDER_SOURCE/scripts/render_preview.py) |
| **2K 多族程序化贴图生成 & 角色规范** | [make_textures_2k.py](file:///d:/迷失太空/work/art-sample-002/deliverable/ART-SAMPLE-002_TEAM_KIT/02_BLENDER_SOURCE/scripts/make_textures_2k.py)、[build_protagonist.py](file:///d:/迷失太空/art-source/editable/characters/build_protagonist.py)、[build_assets.py（样本02 岩与晶）](file:///d:/迷失太空/art-source/editable/resonance/codex_environment_sample_02/build_assets.py) |
| **Godot 材质库 / 着色器 / 环境灯光样板** | [art_pbr_lib.gd](file:///d:/迷失太空/work/resonance-art-integrated-001/project/scripts/world/art_pbr_lib.gd)、[aqs2_metal.gdshader](file:///d:/迷失太空/work/resonance-art-integrated-001/project/shaders/aqs2_metal.gdshader)、[aenv8_rock.gdshader](file:///d:/迷失太空/work/resonance-art-integrated-001/project/shaders/aenv8_rock.gdshader)、[aenv003_env.gd](file:///d:/迷失太空/work/resonance-art-integrated-001/project/tests/aenv003_env.gd) |
| **物理因果连线 & 接地微动态 & 全场景探索套件** | [physical_link_kit.gd](file:///d:/迷失太空/game/scripts/core/physical_link_kit.gd)、[art_atmosphere_kit.gd](file:///d:/迷失太空/game/scripts/core/art_atmosphere_kit.gd)、[explore_prop_kit.gd](file:///d:/迷失太空/game/scripts/world/explore_prop_kit.gd) |
| **全局风格权威档案与交接验收样例** | [ART-DIRECTION-001](file:///d:/迷失太空/docs/handoff/ART-DIRECTION-001-既定美术风格权威档案-20261101.md)、[ART-001A](file:///d:/迷失太空/docs/handoff/ART-001A-K17发车站台美术样板-交付报告-20261111.md)、[aenv004_env.gd](file:///d:/迷失太空/work/resonance-art-integrated-001/project/tests/aenv004_env.gd) |
