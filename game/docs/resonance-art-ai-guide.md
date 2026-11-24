# 《迷失太空》美术制作与 AI 协作指南

> **文档性质**：基于项目既定设计文档、美术样本规范与当前运行代码整理的可执行制作手册（不改变既有团队分工或游戏设计决定；文中工作流模板与 AI 提示词属**工程协作执行方案**，具体新星球定稿仍需创建者审核）。  
> **核心用途**：队友只需把本文档对应章节（或第 6 节的提示词模板）**直接复制发给 AI**，即可让 AI 按与主程/创建者一致的审美、工艺、着色器与引擎兼容规范产出资产与场景。

---

## 0. 一句话总纲（发给 AI 时的最高约束）

**风格定位（已确认）**：**「精致卡通」——清晰轮廓、圆润设备、统一色彩**（技术落地：**带倒角硬边切面结构 + 分层磨损工业材质 + 有限色板**，明确**排除像素风**，明确**禁止悬浮 3D 文字**）。  
**质量标准**：**远看构图（剪影与主次）、中看结构（承力与装配关系）、近看工艺（1–2 米内看得到倒角、接缝、漆面分层与烘焙法线细节，绝不出现裸 `BoxMesh`/`CylinderMesh` 方块）**。  
**引擎硬基线**：**Godot 4.7 · `gl_compatibility` 渲染后端**（非 Forward+），所有材质、灯光与雾效必须在 Compatibility 模式下实机成立。

---

## 1. 视觉规范核对表（哪些已定、哪些禁做）

### 1.1 五条核心色彩与视觉语义（不可破坏）

> 参考源文件：[act1_art_mats.gd](file:///d:/迷失太空/work/resonance-art-integrated-001/project/act1/scripts/world/act1_art_mats.gd)、[art_pbr_lib.gd](file:///d:/迷失太空/work/resonance-art-integrated-001/project/scripts/world/art_pbr_lib.gd)、[act05_art_layer.gd](file:///d:/迷失太空/work/resonance-art-integrated-001/project/scripts/act5/act05_art_layer.gd)、[ART-DIRECTION-001](file:///d:/迷失太空/docs/handoff/ART-DIRECTION-001-既定美术风格权威档案-20261101.md)

| 色彩层级 | 常见基色参考（线性/RGB 范围） | 面积占比 | 承担功能 |
|---|---|---|---|
| **主骨架中性色** | 浅灰 `#D6DEE6` / 蓝灰 `#5C7085` / 深石墨 `#29303B` / 深结构黑 `#14181F` | **65–75%** | 墙体、平台底座、桁架、门框、甲板 |
| **高明度结构分块** | 奶油白 `Color(0.615, 0.578, 0.488)` ~ `#EFE6CE` | **10–15%** | 设备外壳主视觉面、货箱/门柱腰线，用来拉开与深灰骨架的层次 |
| **青绿（我方/供能/安全）** | 深青 `#1E3B44` / 钢青 `#41627A` / 青光 `#28DBFF` | **5–10%** | 角色、飞船引导线、供能端、已完成/安全状态 |
| **工业橙/琥珀（交互/可操作）** | 工业橙 `Color(0.700, 0.268, 0.062)` / 安全黄 `Color(0.95, 0.70, 0.14)` | **5–8%（严格控量）** | 只出现在手柄、卡箍、警示边界、矿车腰线、交互按钮与可操作件上 |
| **警示红（禁止/故障/未解锁）** | 红光 `Color(1.0, 0.20, 0.12)` | **< 2%** | 告警灯、未解锁状态、急停部件 |

- **色板原则**：**大面积中性色打底 + 小面积高纯度色只承担“读图”**；绝不能把整栋建筑或整台车刷成高饱和纯橙/纯青。
- **白色/奶油色不过曝原则**：PBR 着色器下的奶油白反照率通常控制在 `0.54–0.62`（如 `Color(0.615, 0.578, 0.488)`），避免在聚光灯下变成死白方块。

### 1.2 十条绝对红线（违反即返工）

1. **禁止悬浮 3D 文字（`AGENTS.md` 硬约定）**：禁止在空中或部件上方放置随镜头旋转（`BILLBOARD_ENABLED`）或漂浮的 `Label3D`。说明文字必须做在**贴合墙面/机壳的实体铭牌与图示板**上，交互键位提示统一走 HUD。
2. **禁止裸露基础几何当成品**：`BoxMesh` / `CylinderMesh` / `SphereMesh` 只能作白盒阶段草案；成品主构件必须有**倒角（bevel）、筋板/折边、基座与承力结构**。
3. **禁止“无物理支撑的悬浮构件”**：支架必须落地或锚入墙体/台肩；风道、底座、导管必须有法兰座、管卡、立柱交代受力路径。
4. **禁止单件无紫外线/切线贴图强开烘焙参数**：没有 `TANGENT` 或未三角化的 GLB 法线贴图会整片失效；**没有顶点色的网格必须设 `vertex_mask_valid = false`**（否则 `COLOR = 1` 会让整个模型发黑或全漆剥落）。
5. **禁止全表面同一张噪声**：喷漆（`paint`）、铸铁（`cast`）、机加工（`mach`）、混凝土（`conc`）、岩石（`rock`）必须使用各自的法线/粗糙/掩膜通道。
6. **禁止靠把环境光拉满来照明**：必须关闭环境光自检主光造型；`gl_compatibility` 下没有 SSIL/SSAO/体积雾，严禁依赖 Forward+ 特有后处理（SSR/SSIL/VolumetricFog）撑画面。
7. **禁止改动既有碰撞体积与玩法节点**：美术重制只替换视觉层或贴着既有碰撞尺寸包裹外壳；**视觉壳与物理碰撞分离**（参考 [ART-001A](file:///d:/迷失太空/docs/handoff/ART-001A-K17发车站台美术样板-交付报告-20261111.md)）。
8. **禁止为“细节而细节”乱堆螺栓**：紧固件只出现在真实需要装配/检修的法兰、盖板、铰链与角钢节点处。
9. **禁止过曝发光（纯白高亮）**：晶体、灯条、能源导管必须保留色相梯度与软膝衰减（`emit / (1 + emit * 0.62)`），不能整块炸成死白。
10. **禁止跳过 Godot Compatibility 实机截图验收**：Blender Viewport / Cycles 渲染图不算验收完成，必须能在 Godot `gl_compatibility` 下跑通玩家第一人称/实机视角截图。

---

## 2. 比例、尺度与结构工艺硬参数

> 验证基准来自 [aenv004_env.gd](file:///d:/迷失太空/work/resonance-art-integrated-001/project/tests/aenv004_env.gd)（眼高基准 `1.55–1.65 m`）与 [英雄资产制作规范.md](file:///d:/迷失太空/work/art-sample-002/deliverable/ART-SAMPLE-002_TEAM_KIT/05_ART_STYLE_GUIDE/英雄资产制作规范.md)：

### 2.1 人机工程尺度标准

| 设施部件 | 标准尺寸（米） | 与眼高（1.55 m）比值 |
|---|---|---|
| 角色总高（三头身切面卡通） | `~1.85 m`（头盔约占 1/3） | — |
| 操作台面 / 控制台高度 | `1.00 – 1.08 m` | `~0.68 × 眼高` |
| 走道栏杆上横杆高度 | `1.00 – 1.05 m` | `~0.66 × 眼高` |
| 踢脚板（挡脚缘）高度 | `0.10 – 0.12 m` | `~0.07 × 眼高` |
| 直梯踏步间距 | `0.26 – 0.28 m` | `~0.18 × 眼高` |
| 机械主立柱截面 | `0.42 – 0.50 m` | `~0.30 × 眼高` |
| 工业出口/大厅门净高 | `≥ 4.2 – 4.7 m` | `~2.7–3.0 × 眼高` |
| 交互区最小通行净宽 | `≥ 2.0 m` | — |

### 2.2 资产分级与预算

| 资产级别 | 典型视距 | 三角面预算 | 贴图分辨率与格式 | 工艺要求 |
|---|---|---|---|---|
| **英雄件（Hero）** | `0 – 3 m` | 单件 `≤ 60k`；核心近景件烘焙低模 `3k–15k` | 2K 法线 + 2K 粗糙 + 1K 掩膜（VRAM 压缩） | 必须有倒角、折边、紧固件、焊缝、高模烘焙法线/AO |
| **中景件（Mid）** | `3 – 10 m` | `2k – 15k / 件` | 1K 图集或三平面程序化材质 | 承力结构完整（柱/梁/斜撑/管卡），允许免单件烘焙 |
| **远景件（Far）** | `> 10 m` | `≤ 2k / 件`（建议合批或 `MultiMesh`） | 512–1K 或程序化着色器 | 重轮廓剪影与冷暖对比，不建螺栓/小倒角 |

### 2.3 结构造型关键工艺数值

- **机加工金属倒角**：`0.8 – 3.0 mm`（`≥ 2` 段 bevel）；**主结构大圆角**：`40 – 60 mm`（`≥ 8` 段）。
- **装配结构缝**：零件拼合处保留 `2 – 3 mm` 阴影凹槽缝，不能严丝合缝贴成一块。
- **薄板构件**：必须有真实厚度（`8 – 20 mm`）和折边，严禁零厚度单面纸片。
- **高模铸造表面多尺度位移**：以**向内凹蚀为主**（外扩 `≤ 2.5 mm` 防止穿插碰撞体），总位移幅度 `0.7 – 2.2 mm`（低频塌落 + 中频砂型颗粒 + 高频表面噪点 + 局部补焊/凸台）。
- **地质岩体**：用 **8–10 刀随机平面 `bisect` 切面** + `6 mm` 微倒角 + `22–44 cm` 明显层理与 `3–8 cm` 层间错台，不做“平滑球加噪声”。
- **晶体与地貌接触**：晶体根部必须穿过地基或伴生碎岩片（`ContactDebris`），着色器开启根部浑浊灰垢渐变（`murk_height` / `root_grime`），让晶体看起来“从岩石裂缝长出来”。

---

## 3. Blender → Godot 标准资产管线（避坑要点）

> 对应工具参考：[Blender制作流程.md](file:///d:/迷失太空/work/art-sample-002/deliverable/ART-SAMPLE-002_TEAM_KIT/05_ART_STYLE_GUIDE/Blender制作流程.md)、[bake_kit_batch.py](file:///d:/迷失太空/work/resonance-art-integrated-001/tools/bake_kit_batch.py)

1. **坐标系**：在脚本内推荐先按 Godot 坐标（`X 右 / Y 上 / Z 深`）推算位置，导出 glTF 2.0（`.glb`）时统一设置：
   - `export_yup = True`
   - `export_apply = True`
   - `export_tangents = True`
   - **导出前必须先对网格 Triangulate（三角化）**，否则 glTF 丢失 `TANGENT`，法线贴图会在 Godot 中完全无效。
2. **材质命名即 Godot 绑定键**：
   - Blender 内只建轻量占位材质用于分区，命名严格采用 `M_<家族><用途>`（如 `M_PaintCream`、`M_CastSteel`、`M_MachinedSteel`、`M_Concrete`、`M_Hazard`、`M_CrystalCyan`）。
   - 真正材质观感统一在 Godot 运行期通过 [ArtPbrLib](file:///d:/迷失太空/work/resonance-art-integrated-001/project/scripts/world/art_pbr_lib.gd) 挂载 `aqs2_*.gdshader` 覆盖，**不在 Blender 里手调复杂节点去兼容 Godot**。
3. **高模烘焙规范（英雄件必做）**：
   - 先做干净拓扑低模并展开 UV（`Smart UV Project, island_margin = 0.006`）。
   - **严禁对高模做全局负向 Shrink/Smooth 整体收缩**——否则烘焙出的法线整面倾斜，低模会出现“球面假高光”。
   - Cycles `selected_to_active` 烘焙：`cage_extrusion = 0.035`（35 mm），`margin = 12 px`；输出 `Normal (2048², Tangent)`、`AO (1024², dist 0.15–0.18 m, 24 samples)`、`Curvature (1024², Pointiness → Emit ColorRamp 0.42–0.58)`，打包成 `*_mask.png`（`R = 曲率, G = AO`）。
4. **顶点色遮罩顺序**：
   - 若使用顶点色遮罩（`R=凸棱磨损, G=自遮挡, B=起皮, A=朝上`），**必须在 `EdgeSplit`（拆边）之前烘焙顶点色**，拆边之后 1-ring 拓扑断开会导致曲率恒为 0。
5. **Godot 导入与合批要求**：
   - 法线贴图设置：`compress/mode = 2`（VRAM Compressed）、`compress/normal_map = 1`、`mipmaps/generate = true`。
   - 静态装饰多构件场景优先**按材质合并网格**（参考 [Act1ArtKit](file:///d:/迷失太空/work/resonance-art-integrated-001/project/act1/scripts/world/act1_art_kit.gd) 与 `act05_art_layer.gd` 合批逻辑），控制 Draw Calls。
   - **大型包裹洞壳/穹顶**：如果相机在壳体内部看背面，必须用双面岩石着色器 `ArtPbrLib.rock_shell(...)`（`cull_disabled`），否则特定视角会出现整面剔除“黑洞”。

---

## 4. Godot 着色器、物理因果连线与灯光配方

### 4.1 统一材质库调用（不要自写零散 `StandardMaterial3D`）

所有共振星及新增工矿类场景优先复用 [ArtPbrLib](file:///d:/迷失太空/work/resonance-art-integrated-001/project/scripts/world/art_pbr_lib.gd) 的 4 类着色器入口：
- **金属与涂装/混凝土**：`ArtPbrLib.metal_native(key, params, family)`（`family` 取 `"paint" | "cast" | "mach" | "conc"`），或直接调用内置预设 `paint_cream()` / `paint_orange()` / `paint_teal()` / `dark_steel()` 等；对应着色器 [aqs2_metal.gdshader](file:///d:/迷失太空/work/resonance-art-integrated-001/project/shaders/aqs2_metal.gdshader)。
- **岩石**：`ArtPbrLib.rock(...)`（实体岩体）或 `ArtPbrLib.rock_shell(...)`（双面洞壳），对应 [aenv8_rock.gdshader](file:///d:/迷失太空/work/resonance-art-integrated-001/project/shaders/aenv8_rock.gdshader)。
- **晶体**：`ArtPbrLib.crystal(...)`（带深芯 `deep_color` + 尖端亮色 `tip_color` + 软膝限幅），对应 [aqs2_crystal.gdshader](file:///d:/迷失太空/work/resonance-art-integrated-001/project/shaders/aqs2_crystal.gdshader)。

### 4.2 机关物理联系与“零悬浮文字”机械表现库（[PhysicalLinkKit](file:///d:/迷失太空/game/scripts/core/physical_link_kit.gd)）

让玩家**不用读字**就能看懂“谁控制谁、按什么顺序做”：
- **连续三轨装甲能源导管**（`PhysicalLinkKit.build_conduit_run`）：起止带端面法兰与嵌入式发光卡箍环，转角圆弧倒角不折断，使用 [conduit_flow.gdshader](file:///d:/迷失太空/game/shaders/conduit_flow.gdshader)（未通电暗红慢流 / 就绪暖琥珀 / 激活亮青快流）。
- **机械实操刻度表盘**（`PhysicalLinkKit.build_live_dial` + `set_dial_value`）：带红/黄/绿目标区间弧与实时摆动指针，取代数字 HUD 或悬浮读数。
- **实体配重/工作状态灯**（`PhysicalLinkKit.build_status_lamp`）：带半包覆金属遮光罩 `_LampHood` 与高对比灯芯。
- **贴壁/贴机壳图解铭牌**（`PhysicalLinkKit.build_diagram_plaque`）：严格贴附机壳正面 `2–3 cm` 内，只用 `① → ② → ③` 几何图标表达操作顺序，零空中飘字。

### 4.3 五层布光铁律（`gl_compatibility` 通用模板）

| 层级 | 灯具类型 | 参数/角度参考 | 职责 |
|---|---|---|---|
| **1. 主光（Key）** | `SpotLight3D`（**仅此处开阴影**，全厅投影灯 `≤ 1–2` 盏） | 暖白/暖琥珀，42–48°，斜向 `15–25°` 掠射主体 | 建立明暗交界与地面投影 |
| **2. 补光（Fill）** | `SpotLight3D` / `OmniLight3D`（关阴影） | 主光能量 `40–55%`，偏冷或中性 | 保证暗面结构可辨而不死黑 |
| **3. 轮廓光（Rim）** | `SpotLight3D`（关阴影） | 置于主体斜后上方，冷青/冰蓝，32–38° | 把机械剪影从背景岩壁“剥离” |
| **4. 地质/墙面掠射（Graze）** | 窄角 `SpotLight3D`（关阴影） | 沿岩面/建筑表面 `10–20°` 擦过 | 打出层理台阶、凸筋和微表面高光 |
| **5. 实用状态光（Practical）** | 小范围 `OmniLight3D`（关阴影，`omni_range 3–6 m`） | 绑在可见灯罩/晶体/控制台实物体上 | 让光照色彩同步反映机关状态 |

> **Compatibility 补偿提醒**：GL Compatibility 无 SSIL/SSAO/体积雾，`WorldEnvironment` 需在 GL 模式下关闭 `ssr_enabled` / `ssil_enabled` / `volumetric_fog_enabled` 避免启动报错（见 [aenv003_env.gd](file:///d:/迷失太空/work/resonance-art-integrated-001/project/tests/aenv003_env.gd#L386-L426)），并依靠**烘焙 AO 掩膜 + 略高一档的定向补光 + 接触阴影贴片**维持体积感。

### 4.4 接地过渡、悬垂软管、光柱与微动态生命力（[ArtAtmosphereKit](file:///d:/迷失太空/game/scripts/core/art_atmosphere_kit.gd)）

避免画面出现“方块硬插进地里”与“静止模型展览馆”感，全部组件均为纯视觉节点（零碰撞、零阴影开销、`gl_compatibility` 全兼容）：
- **贴地渐变尘圈/暗带**（`ArtAtmosphereKit.build_ground_skirt`）：在重型机柜、立柱底座、矿轨支座与岩台交界底面 `y + 0.012` 铺设程序化径向衰减接触阴影贴片，立刻消掉“生硬直角插地感”。
- **倒角碎石片围边**（`ArtAtmosphereKit.build_gravel_cluster`）：在底座周围按固定随机种子合批撒布一圈微倒角碎屑，衔接机械台基与矿区岩土。
- **悬垂软管打破方块轮廓**（`ArtAtmosphereKit.build_catenary_hose`）：在机柜之间、控制箱与门框/阻尼器之间拉出带金属接头卡箍的悬链线橡胶软管，软化刚硬机箱剪影。
- **环境微动态粒子**（`ArtAtmosphereKit.build_ambient_motes`、`build_steam_vent`）：用轻量化 `CPUParticles3D` 补充晶体/大厅慢速漂浮孢子粉尘与脉冲蒸汽泄压阀，让静止场景保持持续“呼吸感”。
- **兼容性假体积光柱**（`ArtAtmosphereKit.build_godray_cone`）：基于 [walle_godray.gdshader](file:///d:/迷失太空/game/shaders/walle_godray.gdshader) 在井口/核心穹顶/通道口挂轻淡渐隐光锥片（`intensity 0.09–0.12`），在不依赖 `VolumetricFog` 的前提下做出空间空气层次。

---

## 5. 发给 AI 的完整操作流程（队友照着做）

遇到“做不下去 / 样式跑偏 / 细节单薄”时，按这 4 步喂给 AI：

1. **先做白盒与机位（Body Block + Camera）**：不要一上来让 AI 写高模和着色器；先让 AI 用 `1.6 m` 眼高站位对齐交互范围与通行净宽，跑出 4 张白盒机位。
2. **跑 Blender 脚本出倒角与烘焙资产（Structure + Bake）**：把**提示词 A**发给 AI，生成带 `bevel + 紧固件 + 高模置换 + 烘焙 Normal/Mask + 三角化导出 GLB` 的独立 Blender Python 脚本，命令行无头运行生成 `.glb`。
3. **接入 `ArtPbrLib` + `PhysicalLinkKit` + 五层灯光（Shader + Link + Lighting）**：把**提示词 B / C**发给 AI，只在视觉层/连接层挂载外观与指示设备，绝不修改原物理与碰撞脚本。
4. **运行 Godot Compatibility 自动截 4+ 机位并自检（Inspect & Fix）**：把**提示词 D**发给 AI，让 AI 自己跑 Godot 截图并用眼睛读图检查“穿模、黑块、悬浮物、过曝、悬浮文字、1–2 m 数学平面”。

---

## 6. 可直接复制发给 AI 的提示词包（其他星球专用）

> 下方提示词专为**制作新星球（非共振星）的队友**设计：每块代码框均可**直接复制整段发送给 AI**，只需修改 `[ ]` 内的星球主题与目标路径。建议新开对话时先发 **【0 号总控提示词】**，再按任务阶段发 **【1～4 号执行提示词】**。

### 0 号提示词：新星球总控约束（开新对话第一条直接发给 AI）

```text
你正在协助制作多人合作游戏《迷失太空》的新星球：[星球名，例如：霜烬星 / 腐墟星 / XXX]。
你的核心目标是：做出与项目现有主舱与共振星样板（如 K-17 站台、ART-SAMPLE-002）**完全同一套美术风格与工艺水准**的 3D 资产与场景，但题材与地貌必须属于本星球，**绝对不要照搬共振星的红褐洞穴与蓝色矿柱**。

【你必须严格遵守的《迷失太空》统一视觉法则】
1. 核心画风：「精致卡通（清晰轮廓、圆润设备、统一色彩）」
   - 造型语言：硬边切面 + 明显倒角（小加工件 1–3mm 两段倒角，主结构大圆角 40–60mm >=8段）+ 真实装配缝（2–3mm 凹槽）+ 真实厚度与折边（禁止零厚度纸片）。
   - 禁止使用裸露的 BoxMesh / CylinderMesh / SphereMesh 当成品，禁止用"平滑球体 + 随机噪点"当岩石。
   - 绝对禁止像素风；绝对禁止悬浮在空中的 3D 文字（Label3D / Billboard），所有指引牌必须做成贴合实体表面的铭牌或图标板，交互提示走 HUD。

2. "跨星球不变"的色彩与功能语义比例：
   - 70% 左右：中性骨架底色（与本星球环境自洽，如冷灰/蓝灰/风化灰/深石墨，保证低饱和衬托主体）。
   - 10–15%：高明度结构分块（如暖奶油白或浅灰白涂装外壳，注意反照率 <= 0.62 避免过曝死白）。
   - 5–10%：功能引导与安全/我方识别色（青绿系为主）。
   - <= 8%：交互强调色（工业橙/琥珀/安全黄，只准用在手柄、阀门、可抓握栏杆、警示边、卡箍等"可操作件"上，禁止大面积刷满高饱和色）。
   - 发光克制：任何自发光必须保留色相梯度与软膝限幅，禁止过曝炸成纯白块。

3. 人机尺度与结构可信度：
   - 玩家眼高按 1.55–1.65 m 设计：操作台/栏杆高 1.0–1.08 m，门洞/通道净宽 >= 2.0 m，直梯踏步间距 ~0.28 m。
   - 每一件机械都必须能看清"谁承重、怎么固定、怎么拆装"，落地支架必须真落地或锚入底座，管道/风道必须有法兰与支架。
   - 自然地质要有成因（层理、断层、冰裂、侵蚀方向），晶体或星球特殊能源物必须从裂缝/根部碎屑中"长出来"，禁止孤立插在光滑平台上。

4. Godot 4.7 引擎硬约束（gl_compatibility）：
   - 全项目渲染基线是 `gl_compatibility`（无 SSIL / SSR / VolumetricFog），所有材质、灯光、雾效必须按 Compatibility 实机验收，不许依赖 Forward+ 特效欺骗自己。
   - 统一复用仓库既有材质脚本与着色器框架（`ArtPbrLib` / `aqs2_metal.gdshader` / `aenv8_rock.gdshader` / `aqs2_crystal.gdshader` / `PhysicalLinkKit`），不同表面家族（paint/cast/mach/conc/rock）必须用各自纹理通道，禁止全场景共模一种噪声；无顶点色的网格必须显式关闭 `vertex_mask_valid = false`。
   - 任何时候不得擅自改动原有碰撞体位置或玩法触发器参数；视觉网格与物理碰撞必须分离。

收到请先复述本星球你将改变什么、保持什么不变，再等我下达具体制作任务。
```

### 1 号提示词：为这颗新星球定调（配色表 + 地质/建筑/能源语言）

```text
请先不要急着写大量建模代码，基于《迷失太空》的统一画风与水准，为我的新星球做一份可直接落地的【美术设计单】。

【我的星球信息】
- 星球名称：[填写]
- 地貌与气候：[例如：极寒冰原与冻裂峡谷 / 被遗弃的风沙殖民废墟 / 酸性孢子沼泽]
- 核心环境危险：[例如：暴风雪能见度骤降 / 声音引怪 / 间歇地热喷发]
- 核心交互机关：[例如：3座破冰热能塔 + 地下输暖管网 / 废墟供电闸门与声呐信标]

【请输出以下 5 项精确规范供后续建模脚本直接引用】
1. 配色表（全部给出 0..1 线性/RGBA 与 Hex，严格遵守 70% 中性骨架 + 15% 明度分块 + <=10% 青绿引导 + <=8% 橙琥珀可操作件）：
   - 地形岩石/地表（主色/暗部层理/高光尘土 3色）
   - 设施结构（深骨架、主体涂装、高明度门框/外壳分块）
   - 本星球特色能源/异星物主色与危险色（不能与共振星红棕洞穴+青紫水晶撞车）
2. 4 个以上远/近景主地标的独立轮廓定义（保证 30m 外仅靠剪影就能区分功能，不能都是"平台+发光柱"）。
3. 材质家族分配表：哪些用 `paint`（喷漆）、`cast`（铸铁）、`mach`（机加工）、`conc`（混凝土）、`rock`（地貌）或自定义着色器。
4. 本星球的五层 Compatibility 灯光基调（主故事光颜色/方向/角度、补光、轮廓光、掠射光、雾色与环境光能量）。
5. 物理因果可读性方案：玩家不读悬浮文字，怎么通过地形颜色变化、管线、仪表盘或结构形态看懂危险与机关顺序。
```

### 2 号提示词：Blender 批量制作这颗星球的英雄机械 / 建筑 / 自然件

```text
请根据上面定好的【[星球名] 美术设计单】，用 Blender Python 编写可无头运行的建模与烘焙脚本：`[例如：art-source/blender/<星球名>/build_<资产名>.py]`，做出 [资产名称与用途]，要求近景 1–2m 工艺水准对齐项目样板。

【建模与烘焙强制规范】
1. 阶段要求：
   - 英雄件（0–3m 近景交互/主视觉）：单件 <= 60k 面（低模 3–15k），必须有 1–2.5mm 两段机加工倒角、40–60mm 大圆角结构柱、实体厚度折边（>=10mm）、2–3mm 装配缝、以及法兰/铰链/检修盖处带垫圈的六角螺栓。
   - 若包含地貌岩体/冰块/废墟残垣：用随机平面切面（bisect 8–10刀）+ 6mm 微倒角 + 明显层理错台（20–45cm 层厚，3–8cm 错台），禁止光滑曲面或球体噪点。
   - 若有异星能源体/晶体/菌株嵌入环境：根部必须真实穿插并压裂周围岩层，伴生碎屑或融蚀坑。
2. 材质槽命名（供 Godot 覆盖，Blender 仅上占位色）：
   - 必须使用语义清晰且统一的 `M_` 前缀材质名，如 `M_<星球>_PaintMain`、`M_<星球>_FrameDark`、`M_<星球>_InteractiveOrange`、`M_<星球>_Terrain`、`M_<星球>_Energy`。
3. 防踩坑烘焙与导出（必须写进脚本自动执行）：
   - 低模用 Godot 坐标系估算尺寸（Y-up，地面 y=0，操作件在 y=1.0~1.1m），展开 Smart UV（island_margin=0.006）。
   - 高模添加多尺度位移（以向内凹蚀 <=2.2mm 为主，绝不做全局 Shrink 整体缩小避免法线斜倾出现球面假高光）。
   - 用 Cycles selected_to_active（cage_extrusion=0.035, margin=12px）烘焙 2048x2048 Tangent Normal 与 1024x1024 Mask（R=Pointiness曲率 0.42..0.58，G=AO dist 0.16m）。
   - 若使用顶点色磨损遮罩（R=磨损, G=AO, B=起皮, A=朝上），必须在 EdgeSplit(30度) 之前烘焙。
   - 导出 GLB 前必须对全部网格 Triangulate（三角化），glTF 导出必须开启 `export_yup=True, export_apply=True, export_tangents=True`，同时保存打包贴图后的 `.blend` 工程。

请写出完整脚本，并在完成后直接执行导出验证无报错、网格无缺面/法线正常。
```

### 3 号提示词：Godot 4.7 场景装配 + 材质/灯光 + 物理因果交互

```text
请将我刚才生成的 [GLB/模型路径] 装配进《迷失太空》新星球关卡 [场景脚本/路径]，完整接入项目统一 PBR 渲染、Compatibility 五层灯光和机关物理联系，绝不破坏任何玩法逻辑与碰撞。

【必须执行的接入清单】
1. 材质与着色器接入：
   - 复用仓库里的 `ArtPbrLib`（`aqs2_metal.gdshader` / `aenv8_rock.gdshader` / `aqs2_crystal.gdshader`）按材质名映射覆盖 GLB 表面材质，使喷漆、铸件、混凝土、地貌的微观粗糙度与磨损语义与主仓库完全统一。
   - 检查所有无顶点色的网格是否已显式设置 `"vertex_mask_valid": false`；带烘焙贴图的模型已打开 `"use_uv_baked": true` 且法线图按 `compress/mode=2` + `compress/normal_map=1` 导入。
   - 若存在玩家可从内部观察的大型壳体/穹顶，必须使用双面版 `ArtPbrLib.rock_shell(...)`，防止特定角度剔除透黑。
2. 物理因果联系（复用 `PhysicalLinkKit` + `shaders/conduit_flow.gdshader`）：
   - 用贴地/贴墙连续倒角三轨导管（`PhysicalLinkKit.build_conduit_run`）连出机关之间的触发与供能流向，绕开主通道门洞与立柱（不能穿墙/挡门/斜飞穿模），状态随机关实时切换（暗红锁定 / 琥珀待机 / 青色激活）。
   - 对压力/温度/充能/校准类机关，用 `PhysicalLinkKit.build_live_dial` 加装实体指针表盘，用 `build_status_lamp` 加装带防眩灯罩的状态灯，并在机壳正面贴装无文字纯图标 `build_diagram_plaque`（1→2→3 顺序）。
   - 严禁创建任何悬浮 `Label3D` 或 billboard 提示。
3. `gl_compatibility` 五层灯光、接地与氛围细节：
   - 设置 1 盏开阴影的主故事光 + 关阴影补光 + 主体后上方冷/反差轮廓光 + 地貌掠射光 + 绑定可见灯具/能源体的局部实用光。
   - 环境资源在 `gl_compatibility` 下必须显式关闭 SSR / SSIL / VolumetricFog，不出现引擎告警。
   - 统一调用 `ArtAtmosphereKit` 为所有底座补充 `build_ground_skirt` + `build_gravel_cluster`（消除直角插地），用 `build_catenary_hose` 为主设备补悬垂软管打破方块轮廓，并按需加入 `build_steam_vent` / `build_ambient_motes` 与克制的 `build_godray_cone`（`walle_godray.gdshader`）。
   - 多件静态装饰网格按材质合并合批；仅加视觉，原有碰撞坐标与 Trigger 范围保持原封不动。
```

### 4 号提示词：让 AI 自动渲染 4 机位实机截图并自我验收返修

```text
现在不要只口头报告完成。请你以 `gl_compatibility` 模式运行临时渲染脚本，把新星球场景 [场景路径] 按《迷失太空》验收机位输出截图并亲自读图检查：
1. `A_wide.png`（整体地标、色板比例与动线可读性，FOV 50）
2. `B_player_eye.png`（眼高 1.60m 玩家实机视角，FOV 65）
3. `C_interaction.png`（核心机关 1.3–1.8m 近景特写，FOV 44）
4. `D_threequarter.png`（设备/建筑与星球自然地貌、能源体的接触交界，FOV 52）
5. 若有机关状态变化，额外输出 `locked` 与 `active` 两张对照图。

打开每张渲染图，按下面 6 条逐一审查；只要发现任何一条不合格，立刻直接改代码/模型并重截验证，直到全部过关：
- [ ] 近景 1.5m 看起来是不是仍有未经倒角/无接缝/无粗糙变化的"数学方块或塑料桶"？
- [ ] 是否存在构件悬空、没有地基支撑、导管斜穿门洞或插进立柱？
- [ ] 是否出现了任何漂浮在空气中的 3D 文字提示？
- [ ] 是否有特定视角模型消失/变黑（法线翻转、单面剔除或 `vertex_mask_valid` 漏设）或发光过曝成一片白块？
- [ ] 中性骨架色（约70%）是否稳住画面，交互亮橙/功能青绿是否克制且一眼能指明"点哪里、先做哪步"？
- [ ] `--headless` 冒烟测试及交互流程测试退出码全部为 0，无 GDScript 报错或 Compatibility 渲染警告。
```

---

## 7. 一页快速对照索引（项目关键样板路径）

| 你想看/复用的内容 | 仓库权威路径 |
|---|---|
| 全局风格考据与禁用项总表 | [ART-DIRECTION-001-既定美术风格权威档案-20261101.md](file:///d:/迷失太空/docs/handoff/ART-DIRECTION-001-既定美术风格权威档案-20261101.md) |
| 第一幕纯程序化站台/矿车样板 | [ART-001A交付报告](file:///d:/迷失太空/docs/handoff/ART-001A-K17发车站台美术样板-交付报告-20261111.md)、[act1_art_mats.gd](file:///d:/迷失太空/work/resonance-art-integrated-001/project/act1/scripts/world/act1_art_mats.gd)、[act1_art_kit.gd](file:///d:/迷失太空/work/resonance-art-integrated-001/project/act1/scripts/world/act1_art_kit.gd) |
| 全一到五幕统一 PBR 材质与 2K 贴图库 | [art_pbr_lib.gd](file:///d:/迷失太空/work/resonance-art-integrated-001/project/scripts/world/art_pbr_lib.gd)、[材质与灯光规范.md](file:///d:/迷失太空/work/art-sample-002/deliverable/ART-SAMPLE-002_TEAM_KIT/05_ART_STYLE_GUIDE/材质与灯光规范.md) |
| Blender 高模烘焙与图集批处理 | [Blender制作流程.md](file:///d:/迷失太空/work/art-sample-002/deliverable/ART-SAMPLE-002_TEAM_KIT/05_ART_STYLE_GUIDE/Blender制作流程.md)、[bake_kit_batch.py](file:///d:/迷失太空/work/resonance-art-integrated-001/tools/bake_kit_batch.py) |
| 物理因果连线 / 指针表盘 / 图解铭牌 | [physical_link_kit.gd](file:///d:/迷失太空/game/scripts/core/physical_link_kit.gd)、[conduit_flow.gdshader](file:///d:/迷失太空/game/shaders/conduit_flow.gdshader) |
| 接地过渡 / 悬垂软管 / 光柱 / 微动态套件 | [art_atmosphere_kit.gd](file:///d:/迷失太空/game/scripts/core/art_atmosphere_kit.gd)、[walle_godray.gdshader](file:///d:/迷失太空/game/shaders/walle_godray.gdshader) |
| 新星球目录模板与验收清单 | [08_TEAM_STARTER/星球制作模板](file:///d:/迷失太空/work/art-sample-002/deliverable/ART-SAMPLE-002_TEAM_KIT/08_TEAM_STARTER/星球制作模板/README.md)、[aenv004_env.gd（尺度与接触样例）](file:///d:/迷失太空/work/resonance-art-integrated-001/project/tests/aenv004_env.gd) |
