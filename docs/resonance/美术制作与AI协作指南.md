# 《迷失太空》美术制作与 AI 协作权威指南（v2.0 · 本仓库落地版）

> **文档定位**：本手册是项目面向所有星球的**统一美术权威执行指南**。v1.0 整理自项目既定设计文档、美术样本 `ART-SAMPLE-002`、`ART-QUALITY-001` 与共振星整合管线；**v2.0 只做三件事：把指南绑到本机真实工具链、把「做到什么程度」变成可实测的数字、把「现在该改哪几刀」变成按优先级排好的返修单**。不越权改动团队分工或未定设计决策。
>
> **v2.0 修订记录（2026-11-25）**
>
> | # | 修订内容 | 依据 |
> |---|---|---|
> | 1 | 全部 `file:///d:/迷失太空/...` 链接替换为本机真实路径（`D:\迷失太空` 在本机**不存在**） | 路径探测 |
> | 2 | Blender `5.2.2 LTS` → **`4.5 LTS`**（本机唯一安装版本） | 本机安装 + `build_nailong.py` 头注释 |
> | 3 | 新增**第 0 部分 落地基线**：已有能力 / 缺口 / 资产实测面数 | 实跑 `check_nailong_assets.gd` |
> | 4 | 方法二去掉本仓库不存在的 `ArtPbrLib`，改成等价链路 | `art_pbr_lib.gd` 搜索无结果 |
> | 5 | 修正「albedo ≤ 0.62」与同表 `#EFE6CE` 的**数值自相矛盾** | 线性反照率换算（见 1.3） |
> | 6 | 新增**第 6 部分 画面实测与返修单**（P0/P1/P2，含复现命令） | 4 张 art shot 实测 |
> | 7 | 新增**附录 A 事实更正表**（12 条） | 同上 |
>
> **阅读顺序**：第 0 部分（30 秒认清手里有什么、缺什么）→ 第 1/2 部分（标准）→ 第 3 部分（做法）→ 第 6 部分（现在该改哪几刀）。第 4 部分是把以上打包成可直接发给 AI 的提示词。

---

## 第 0 部分 · 落地基线（先读这一节，否则后面全是空话）

### 0.1 工具链（本机实测，2026-11-25）

| 用途 | 真实路径 | 版本 | 验证方式 |
|---|---|---|---|
| 建模 / 烘焙 | `C:\Users\31798\AppData\Local\Programs\Blender Foundation\Blender 4.5\blender.exe` | 4.5 LTS | 目录存在；`tools/blender/build_nailong.py` 头注明 4.5 LTS |
| 引擎 | `C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe` | 4.7.2-stable | 本次实跑资产检查脚本通过 |
| 素材包 | `C:\Users\31798\.openclaw\workspace\ref\art_sample_002\` | ART-SAMPLE-002 | 含 `02_BLENDER_SOURCE` / `04_MATERIAL_LIBRARY` / `05_ART_STYLE_GUIDE` / `08_TEAM_STARTER`，25 个 py 脚本 |
| Godot 工程 | `game/previews/gulu_planet/` | — | `project.godot` |
| 素材来源记录 | `game/previews/gulu_planet/ASSETS.md` | — | 逐条许可与来源 |

> ⚠️ **v1.0 的两个致命路径错误**：① `D:\迷失太空\...` 在本机不存在，指南里 15 个指向它的链接全部点不开；② `blender-5.2.2-windows-x64` 只存在于共振星工位，本仓库脚本跑不起来。**照 v1.0 原样执行，第一步就会卡死。**
>
> Blender 4.5 与 5.2 在本指南用到的 API 上行为一致：`use_auto_smooth` 自 4.1 起已移除，`p.use_smooth = True` + `EDGE_SPLIT(30°)` 的写法在 4.5 上直接可用，**Step 6 不需要改写**。

### 0.2 已有能力（可直接调用，别重复造）

> 路径约定：本节及后文的 `shaders/`、`scripts/`、`assets/`、`tools/`、`docs/`、`project.godot` 均相对于 **`game/previews/gulu_planet/`**；凡以 `game/` 开头的路径相对于**仓库根**；`C:\` 开头的是本机工具链绝对路径。

| 能力 | 文件 | 关键接口 / 参数 |
|---|---|---|
| 五族 2K 贴图 | `game/previews/gulu_planet/assets/textures/{paint,cast,mach,conc,rock}_{normal,rough,mask}.png` | 15 张，约 52 MB；`.import` 已设 `compress/mode=2`、法线 `normal_map=1`、开 mipmaps |
| 金属 / 涂装 / 混凝土着色器 | `shaders/aqs2_metal.gdshader` | `detail_normal` / `detail_rough` / `detail_mask` / `detail_scale` / `detail_strength` / `use_detail` / `use_detail_mask` / `vertex_mask_valid` |
| 岩体着色器 | `shaders/aqs2_rock.gdshader` | `render_mode ... cull_back`（**只有单面**） |
| 材质工厂 | `scripts/gulu_art_kit.gd` | `paint()` / `clean_paint()` / `bare_metal()` / `dark_metal()` / `concrete()` / `rubber()` / `rock()`；内部 `_apply_family(m, family, scale, strength)` 自动绑族贴图 |
| 接地与氛围 | `scripts/core/art_atmosphere_kit.gd` | `build_ground_skirt` / `build_gravel_cluster` / `build_catenary_hose` / `build_ambient_motes` / `build_steam_vent` / `build_godray_cone` |
| 物理因果连线 | `game/scripts/core/physical_link_kit.gd` | 贴地导管 / `build_live_dial` / `build_status_lamp` / `build_diagram_plaque` |
| 全场景 E 探索 | `game/scripts/world/explore_prop_kit.gd` | 按 `*Crate*` / `*Valve*` / `*Pipe*` / `*Lamp*` / `*Panel*` 等命名自动接入 |
| 其它着色器 | `shaders/walle_godray.gdshader`、`game/shaders/conduit_flow.gdshader`、`shaders/gulu_contact_decal.gdshader`、`shaders/gulu_yard.gdshader` | 假光束 / 导管脉冲 / 接地暗晕贴片 / 场地地面三级尺度 |
| 校验工具 | `tools/check_nailong_assets.gd`、`tools/inspect_shot.py` | 资产面数/材质/包围盒；截图亮度与色块体检测 |

### 0.3 缺口（指南提到但本仓库**没有**，照抄会报错）

| 指南 v1.0 假设 | 本仓库实况 | 本项目替代方案 |
|---|---|---|
| `ArtPbrLib.metal_native()` / `rock()` / `rock_shell()` / `crystal()` | **无** `art_pbr_lib.gd` | 用 `gulu_art_kit.paint / dark_metal / concrete / bare_metal / rock` + 直接设 `aqs2_*` 参数 |
| `aqs2_crystal.gdshader`、`aenv8_rock.gdshader` | **无** | 晶体暂用 `aqs2_metal` + 自发光；要正式晶体须新建 shader |
| `rock_shell`（`cull_disabled`）内视双面壳 | `aqs2_rock.gdshader` 只有 `cull_back` | 复制 shader 改 `render_mode` 为 `cull_disabled`；奶龙星当前无内视壳，暂不需要 |
| `make_textures_2k.py` 造 `ice` / `bio` 新族 | 脚本在素材包，工程内只有 5 族 | 跑素材包脚本生成后放进 `assets/textures/`，再在 `gulu_art_kit` 加一族 |

### 0.4 已建资产实测（可复现）

```powershell
& 'C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path game/previews/gulu_planet --script tools/check_nailong_assets.gd
```

| 资产 | 三角面 | 顶点色 / UV | 材质数 | 尺寸（m） | 贴地 | 预算判定（Mid 2k–15k） |
|---|---|---|---|---|---|---|
| `service_shed` | 13,216 | ✅ / ✅ | 6 | 6.25 × 3.41 × 3.10 | ✅ | 贴上限，合格 |
| `container_a` | 8,196 | ✅ / ✅ | 6 | 3.41 × 2.50 × 1.42 | ✅ | 合格 |
| `container_b` | 7,956 | ✅ / ✅ | 6 | 2.61 × 2.20 × 1.22 | ✅ | 合格 |
| `observation_deck` | 13,576 | ✅ / ✅ | 6 | 6.54 × 4.50 × 2.42 | ✅ | 贴上限，合格 |
| `loading_frame` | 10,152（代码注释值，**未进检查脚本**） | ✅ / ✅ | — | — | — | 合格；应补进 `ASSETS` 列表 |

五件合计 **53,096 tri**。所有 GLB 均带四通道顶点色与 UV，因此**这批 GLB 必须 `vertex_mask_valid = true`**（`gulu_scenery.gd` 已按材质名逐个设 true）。

### 0.5 本仓库铁律

- **运行时生成几何**（`_box` / `_cyl` / 程序化岩体）没有 UV、没有顶点色 → 材质一律 `vertex_mask_valid = false`，靠世界坐标噪声做磨损。
- **Blender 导出的 GLB** 已烘 `Col` → `vertex_mask_valid = true`；两者搞反的后果是「整件变黑烂漆」，见红线 4。
- 视觉包装**不得越界改动玩法碰撞**（球路、进球判定、奶龙 AI、边界墙均不动）。

---

## 第 1 部分 · 风格规范（STYLE：决定「像不像同一款游戏」）

### 1.1 一句话风格总纲

- **已确认核心画风**：**「精致卡通」——清晰轮廓、圆润设备、统一色彩**。
- **技术表达落地**：**硬朗清晰的几何切面与物理倒角（非圆球堆砌、非零厚度片） + 工业/生态结构分层 + 多层旧化质感 + 严格的功能语义色板比**。
- **明确排斥**：明确**排除像素风**；明确**排除纯写实高频杂乱肉瘤/噪点脏脸**；明确**禁止悬浮在空中的 3D 文字（`Label3D` / Billboard）**。

### 1.2 跨星球不变的 5 条核心风格基因 & 功能色板比例

1. **几何秩序与「圆润硬朗」美学**：大形体剪影干脆、体块明确、转折利落，主体大转角带明显圆角（`40–60 mm`），次级机械/装备带有手办般的精致厚度感与物理倒角（`0.8–3 mm`）。
2. **高度克制的功能色板分配（65–75 / 15 / 10 / 8 / 2 法则）**：

| 色彩层级 | 面积占比 | 跨星球定位与常见取值参考 | 奶龙星现值 | 视觉职责（不可越界） |
|---|---|---|---|---|
| **主骨架/地貌中性底色** | **65–75%** | 共振星参考：深石墨 `#29303B` / 蓝灰 `#5C7085` / 红褐岩棕；其他星球换成与生态一致的**低饱和暗灰/冷灰/泥炭褐/风蚀灰** | 深青 `#2f5c68` / `#1f3f49` + 岩灰 | 压住全画面调性，把高亮交互区和角色「托」出来 |
| **高明度识别外壳** | **10–15%** | `#EFE6CE` / `#CFC5AE`（**线性反照率 ≤ 0.62**，见 1.3）/ 极地浅灰 / 旧米白 | `#b4c1b7`（灰绿，**偏色且占比仅 0.3–3.7%**） | 机器主外壳、建筑门柱、货箱腰线，防高光下炸成死白 |
| **青绿（安全/引导/我方）** | **5–10%** | 深青 `#1E3B44` / 钢青 `#41627A` / 激活青光 `#28DBFF` | `#3fd8ff`（引导）+ 天空 | 角色主视觉、飞船与轨道引导线、已就绪/已接通状态 |
| **工业橙/琥珀（交互专色）** | **5–8%（严控）** | 工业橙 `Color(0.700, 0.268, 0.062)` / 安全黄 `Color(0.95, 0.70, 0.14)` | `#ffb347` 琥珀 / `#cc8f17` 黄 | **只能出现在手柄、阀门、可抓扶栏杆、卡箍、操作按钮与警示边界上**，严禁刷满整台设备或墙面 |
| **警示红（故障/未解锁）** | **< 2%** | 告警红光 `Color(1.0, 0.20, 0.12)` | 未用 | 急停按钮、未解除闭锁、告警状态灯 |

3. **人机尺度统一（世界空间真实比例）**：以玩家第一/第三人称眼高 **`1.55 – 1.65 m`**、三头身主角身高 **`~1.85 m`（头盔占 ~1/3）** 为全宇宙唯一尺子——操作台/手柄高 `1.00–1.08 m`、护栏上杆高 `1.00–1.05 m`、踢脚板高 `0.10–0.12 m`、直梯踏步 `0.26–0.28 m`、通行净宽 `>= 2.0 m`、大厅门高 `>= 4.2–4.7 m`。
4. **物理叙事取代空中飘字**：所有交互与引导必须长在实体世界上——靠贴地/贴墙物理导管、实时摆动表盘指针、遮光状态灯和贴壳 `<= 2–3 cm` 的纯图标铭牌（`① → ② → ③`）交代规则；操作按键提示走简洁 HUD。
5. **非写实碎噪点概括**：哪怕刻画冰层、珊瑚、真菌或生物外壳，也用干净的**几何/分段体块 + 局部高对比微细纹理**，避免满屏写实肉质皱褶。

### 1.3 「albedo ≤ 0.62」的口径问题（v2.0 修正）

v1.0 在同一张表里既写「**PBR 反照率严控 `<= 0.62`**」，又给示例值 `#EFE6CE`。两者**互相矛盾**：

| 颜色 | 线性反照率（逐通道） | 最大值 | 是否 ≤ 0.62 |
|---|---|---|---|
| `#EFE6CE`（v1.0 示例） | 0.863 / 0.791 / 0.617 | **0.863** | ❌ 超限 39% |
| `#D6CDB5` | 0.672 / 0.610 / 0.462 | 0.672 | ❌ 略超 |
| `#CFC5AE`（推荐） | 0.624 / 0.558 / 0.423 | 0.624 | ≈ 临界，可用 |
| `#C9BFA6`（安全） | 0.584 / 0.521 / 0.381 | 0.584 | ✅ |
| `#b4c1b7`（奶龙星现值） | 0.456 / 0.533 / 0.474 | 0.533 | ✅ 但**偏灰绿，不是奶油白** |

**v2.0 执行口径（二选一，写清楚再执行）**：

- **口径 A（推荐，与「防死白」目的对齐）**：0.62 指**线性反照率上限**，等价 sRGB ≈ `0.812`。奶油白取 `#CFC5AE` ~ `#C9BFA6`；`#EFE6CE` 只能用于**面积 < 1% 的贴花 / 小面积识别件**。
- **口径 B**：0.62 指 sRGB 显示值（等价线性仅 0.34）。这会让所有外壳整片发灰，而且**依然救不了** `#EFE6CE`（sRGB 0.94）——所以 v1.0 的矛盾无论按哪种口径都成立，必须选 A 或删掉示例值。

> 这条不是抠字眼：奶龙星当前外壳 `#b4c1b7` 的关键问题不是白，而是**色相偏绿**，和深青骨架同族，导致「高明度识别壳」这层视觉职责根本没起作用（实测占比 0.3–3.7%，见 6.4）。

### 1.4 跨星球风格迁移矩阵（含奶龙星已实装列）

| 迁移项 | 共振星（标杆） | **奶龙星（已实装）** | 极寒冰原型（示例） | 腐蚀菌沼/废墟（示例） | 荒漠裂谷（示例） |
|---|---|---|---|---|---|
| **70% 基底色（改）** | 深石墨 + 红褐矿岩 | 深青 `#2f5c68`/`#1f3f49` + 冷岩灰 | 冷板岩灰蓝 + 暗冻土 | 暗泥炭绿褐 + 氧化铅灰 | 风蚀暖灰褐 + 玄武深灰 |
| **15% 明度壳（微调）** | 暖奶油白工业涂装 | `#b4c1b7` → **建议改 `#CFC5AE`** | 极地浅灰白（寒霜蓝调） | 旧殖民站浅米灰 | 褪色象牙白工程壳 |
| **8% 交互亮色（不变）** | 工业橙 / 安全黄 | 琥珀 `#ffb347` / 黄 `#cc8f17` | **仍用工业橙 / 琥珀** | **仍用工业橙 / 琥珀** | **仍用工业橙 / 安全黄** |
| **地貌与能源载体（改）** | 解理页岩 + 棱面青紫晶簇 | 程序化低多边岩体 + 能源球/装货口 | 陡切蓝冰崖 + 地热喷汽口 | 饱满分段菌伞 + 几丁质荧光囊 | 风蚀砂岩台 + 聚光琥珀阵 |
| **表面风化层语义（改）** | 橘皮漆→底漆→亮铁→矿尘 | 5 族 2K 贴图 + 4 通道 `Col`（仅 GLB） | 防冻漆→铝底→**霜雪(`A`)** | 涂层→铜底→**湿苔孔蚀(`G/B`)** | 砂砾漆→钢底→**黄沙积层(`A`)** |
| **物理连线载体（改形不改规）** | 三轨装甲能量导管 | 贴地导管 + 状态灯 + 贴壳铭牌 | 保温棉伴热蒸汽管 | 透明脉冲输液软管 + 压环 | 铠装耐热埋沙电缆桥架 |

### 1.5 色板比例怎么量（别靠眼睛）

```powershell
& 'C:\Users\31798\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe' `
  game/previews/gulu_planet/tools/inspect_shot.py game/previews/gulu_planet/docs/shots_art_2026_11_25/A_wide.png
```

输出三类读数，各自的判据：

- `luminance mean / p50 / p90` —— 画面明暗分布。`p50 < 0.25` 偏暗；`p90 < 0.6` 说明没有亮部支撑（奶龙星 A_wide 就是这个病）。
- `blown>0.94` —— 过曝比例，必须 **0%**（防死白）。
- `dark<0.06` —— 死黑比例，**> 3% 判不合格**（D_threequarter 实测 7.0%，见 6.2）。
- 各色块 `xx.xx%` —— 与 1.2 表的 65/15/10/8/2 对表；注意 `hull_light` 是**灰绿系**，`dragon_cream` 才是奶油的暖白，两者别混。

---

## 第 2 部分 · 质量标尺（QUALITY：做到什么程度才算合格）

### 2.1 三距验收标准（每件资产与场景必须同时通过 3 个距离）

- **远距（> 10 m）看构图与剪影**：30 米外纯黑剪影也能一眼分辨「这是反应堆、大门还是采集信标」，不能全是「方块台子 + 一根发光柱」；主灯光把主体从背景岩壁剥离。
- **中距（3–10 m）看结构与承力**：每一个悬挂物、管线、箱体都能说出「谁承重、拧在哪里、往哪走」；没有悬空方块或违背重力的斜插穿模。
- **近距（1–2 m）看工艺与微表面**：绝对看不到光滑「数学平面」或锐死直棱——必须看得见物理倒角、零件拼缝阴影、螺母/焊道工艺细节、4 层磨损落尘以及明显的粗糙度高光反差。

### 2.2 资产分级与引擎硬指标

| 资产级别 | 典型视距 | 三角面预算 | 贴图与合批标准 | 必须具备的工艺度 |
|---|---|---|---|---|
| **英雄件（Hero）** | `0 – 3 m`（主交互设备/主角/地标中心） | 高模 `>= 50k`；运行时低模 `3k–15k`（大型组合结构 `<= 60k`） | `2048²` Tangent 法线 + `2048²` 粗糙 + `1024²` Mask（VRAM 压缩） | 自定义截面放样 + 多段倒角 + `2–3mm` 装配缝 + 四件套螺栓/焊道 + **高烘低法线与曲率/AO** |
| **中景件（Mid）** | `3 – 10 m`（廊道/岩壁/管网/护栏） | `2k – 15k / 件` | 共享 `1K–2K` 家族图集 + 4 通道顶点色 `Col` | 真厚度与折边 + 承力梁/管卡 + 解理切面岩体，允许免单件 Cycles 烘焙 |
| **远景件（Far）** | `> 10 m`（远山/外围碎石/穹顶壳） | `<= 2k / 件`（按材质合批或 `MultiMesh`） | `512–1K` 或三平面程序化材质 | 强轮廓剪影与冷暖色调分离，**不建螺母、小焊道或小倒角** |

**奶龙星实测对照**：5 件 Mid 资产 7,956–13,576 tri，全部落在 `2k–15k` 内但**贴上限**——下一轮任何加细节（焊道、螺栓、缝）都必须先减面，否则直接爆预算。

### 2.3 十条绝对红线（触犯任一条即判定返工）

1. **禁悬浮 3D 文字**：禁止漂浮或朝向相机的 `Label3D`；教学与顺序做在贴合实体的图解铭牌（`<= 2–3 cm`），按键提示走 HUD。
2. **禁裸几何成品**：`BoxMesh`/`CylinderMesh`/`SphereMesh` 只能当白盒草稿，成品必须用自定义轮廓、倒角、底座与筋板替换。
3. **禁无承力悬浮件**：架子必落地/入墙，管道必带法兰和固定管卡，灯具必带挂架与遮光罩。
4. **禁顶点遮罩标志设反**（v2.0 精确化）：
   - GLB 已烘四通道 `Col` → **必须 `vertex_mask_valid = true`**（否则磨损/AO 全失效，画面变成干净塑料）；
   - 运行时生成、无 `Col` 的网格 → **必须 `vertex_mask_valid = false`**（否则默认 `COLOR=1`，整件变黑烂漆）；
   - 两种情况都会「翻车」，但翻的方向相反，**上线前逐材质核对一遍**。
5. **禁全场景共用同一张噪声**：喷漆（`paint`）、铸件（`cast`）、机加工（`mach`）、混凝土（`conc`）、地貌（`rock`/`ice`/`bio`）必须分家族独立高度场与粗糙通道。
6. **禁拉满环境光充数**：必须在关闭环境光下先用主光把体块打立起来，禁止靠平铺环境光掩盖没有层次的结构。
7. **禁改动玩法碰撞与触发器**：美术包裹外壳严格贴合既有碰撞盒（外扩 `<= 2.5 mm`），视觉与物理碰撞分离。
8. **禁无意义堆砌螺母**：螺栓/焊缝只放在真实受力与检修节点，不乱撒。
9. **禁发光过曝炸死白**：任何晶体/孢子/灯条必须保留色相变化并用软膝限幅（`emit / (1 + emit * 0.62)`）。
10. **禁跳过 `gl_compatibility` 实机验收**：Godot 4.7.2 运行基线为 **`gl_compatibility`（无 SSR / SSIL / VolumetricFog）**，Blender Viewport 好看完全不算通过。

### 2.4 三距验收记录表（每件资产必须填，没有记录 = 没验收）

| 资产 | 远距剪影可辨 | 中距承力可读 | 近距工艺（倒角/缝/螺栓） | 三角面 | 结论 |
|---|---|---|---|---|---|
| `loading_frame` | ☐ | ☐ | ☐ | 10,152 | 未记录 |
| `service_shed` | ☐ | ☐ | ☐ | 13,216 | 未记录 |
| `container_a` | ☐ | ☐ | ☐ | 8,196 | 未记录 |
| `container_b` | ☐ | ☐ | ☐ | 7,956 | 未记录 |
| `observation_deck` | ☐ | ☐ | ☐ | 13,576 | 未记录 |

> 目前**一件都没填**。这不是流程洁癖：不填表就会出现「看起来换成了 Blender 资产，实际近景还是一块平板」的返工（见 6.6）。

---

## 第 3 部分 · 实现该风格与质量的具体工程方法（HOW-TO）

> 本部分精确规定 AI 必须如何通过 **① Blender 建模烘焙 ② 分层材质贴图 ③ Godot Compatibility 布光与接地因果 ④ 双端渲染自检** 四步落地。

---

### 方法一：Blender 4.5 LTS 精细 3D 建模与烘焙 9 步流水线

> 开源脚本模板（本机真实路径，素材包已解包）：
> `C:\Users\31798\.openclaw\workspace\ref\art_sample_002\02_BLENDER_SOURCE\scripts\` 下的 `aqs_kit.py`、`aq2kit.py`、`build_head.py`、`render_preview.py`、`make_textures_2k.py`
> 可执行文件：`C:\Users\31798\AppData\Local\Programs\Blender Foundation\Blender 4.5\blender.exe`

| 步骤 | AI 必须执行的具体做法 | 关键参数与防坑要点 |
|---|---|---|
| **Step 0 · 初始化与坐标** | 清空场景设为米制；脚本内全部按 **Godot 坐标（`X` 右、`Y` 上、`-Z` 前）** 算位置尺寸，合入 Mesh 时乘矩阵 `GB` 转 Blender（`Z` 上） | `GB = ((1,0,0,0), (0,0,-1,0), (0,1,0,0), (0,0,0,1))`；先锁定交互件在 `y=1.00–1.08m` 及原碰撞盒最大包络 |
| **Step 1 · 轮廓先于细节** | 用 **`rrect_r(w, d, r, seg)` 真圆角截面 + `bm_loft` 多剖面插值放样**造机壳，用 **`bm_lathe` 剖面车削**造圆筒/法兰/手轮，确立 30m 剪影 | 拐角 `seg = 4`（中景）或 `seg = 10`（英雄件）；控制点列按高度 `y` 写出「扩底→收腰→宽肩→斜顶」工业节奏，**绝不用 Cube 缩放硬凑** |
| **Step 2 · 承力结构网** | 造地脚承台/铸铁靴（斜坡扩底嵌入 `y=0`）、直角**三角形加强肋（厚 `14–24 mm`）**、**工字钢 `i_profile` 梁柱**与挂壁托架 | 所有立柱、管架、控制台都看得出受重力支撑；悬垂灯头加防眩金属罩 `_LampHood` |
| **Step 3 · 分层与 `2–3mm` 缝** | 拆成**内骨架 + 外护壳 + 功能嵌件（百叶/表框/胶条）**；壳板之间留 **`2–3 mm` 实体凹槽缝**；薄板带真实厚度（`8–20 mm`）和折边；全外棱加真实倒角 | 机加工棱 `bevel = 0.8–3 mm`（`>=2` 段），主骨架大圆角 `8–35 mm`（`clamp_overlap=True`）；若保留修改器则配 `WEIGHTED_NORMAL(keep_sharp=True)` |
| **Step 4 · 次级工艺件** | **仅在法兰、检修门角、支座根部**加紧固件；焊角加带起伏焊道；线缆用**平行传输防翻转**扫掠（`bm_tube`）并在两端挂金属卡箍 | **紧固件四件套**：沉座凸台 + 垫圈(`1.42r`) + 45° 倒棱六角头 + **每颗独立随机旋转 `phase`**；**焊道**：`r=5–7 mm` 加 **`±28%`** 半径噪点；指示物做实体指针/灯罩/贴壳纯图铭牌 |
| **Step 5 · UV 与材质命名** | 用 `M_` 前缀命名占位材质作 Godot 绑定键（如 `M_CastMetal`/`M_PaintMain`/`M_PaintCream`/`M_Terrain`）；低模执行 Smart UV 展开 | `bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.006)`；**致命顺序：必须先把拓扑焊接合并、展 UV，下一步烘完顶点色后，最后才能做 `EdgeSplit`** |
| **Step 6 · 4 通道顶点色 `Col`** | 调用 `bake_masks()` 在拆边前把物理风化信息写入顶点色（`use_auto_smooth` 自 4.1 已移除，改用 `p.use_smooth=True` + **`EDGE_SPLIT(30°–32°)`**） | **`R`**：1-ring 离散曲率×`fbm` 边缘磨损；**`G`**：BVH 余弦半球 AO（**`ao_dist=0.15–0.18 m`**，`ao_rays=9–12`）+贴地暗带；**`B`**：碎漆/孔蚀斑；**`A`**：法线朝上度（积尘/霜/沙） |
| **Step 7 · 高模与 Cycles 烘焙** | （0–3m 英雄件）复制低模 `Subsurf(2)` 至 `>=50k` 面；施加**以向内为主的三频铸造/风化位移** + **2–3 处非对称历史痕迹**（单侧凸台/补焊/擦凹）→ `Cycles` 高烘低 | 位移 `d = min(低2.2mm+中1.1mm+高0.4mm, +0.8~2.5mm)`；**严禁全局负向 Shrink 整体缩小高模**；`selected_to_active` (`cage_extrusion=0.035, margin=12px`) 烘 `2048² Tangent Normal`、`1024² AO`、`1024² Pointiness(0.42..0.58)→Emit`，NumPy 将 Curv(`R`)+AO(`G`) 合进 `*_mask.png` |
| **Step 8 · 清洗与 GLB 导出** | 检查 `scale==(1,1,1)` 无负缩放；**导出前强制 `Triangulate` 全三角化**（否则缺 `TANGENT` 法线贴图全废）；打包贴图保存 `.blend` 源工程 | `export_format="GLB", export_apply=True, export_yup=True, export_normals=True, export_tangents=True, export_vertex_color="ACTIVE"`（`Col`） |

#### 附：4 类非机械通用资产的建模实现公式（直接复用 Step 0–8 后半程）

- **① 自然地质体（岩崖 / 冰崖 / 砂岩 / 玄武岩）**——严禁「平滑球 + 噪点」或「立方体堆砌」：
  - **单体岩块（`rock_from_planes`）**：立方体细分 3 级并轻柔化 → 执行 **`7–14` 刀倾斜平面切割 `bisect_plane(clear_outer=True)`** 切出清晰解理锐面（第 1 刀削底放稳）→ 面内双频凹凸 → 水平/斜向层理错台 `strata=(层厚 period, 错台 amp)` → 加 `3–18 mm` 单段微倒角（页岩 `6mm`、锋利蓝冰 `3–4mm`、风蚀砂岩 `12–18mm`）。
  - **大跨度峡谷壁 / 洞壳**：外轮廓放样 → `REMESH(VOXEL)` → 手写地质断裂折线 `joints` 与斜削凹面 `scoops` 刻痕 → `DECIMATE` 减面；若从内部观看，执行 `orient_toward(me, center)` 把法线翻向室内。
- **② 异星能源物 / 晶体 / 卡通概括菌囊**：
  - **硬质晶体/冰柱**：手写**不等边 `5–7` 边形**截面并在侧边捏出约 `9%` 凹槽（放高光内芯材质），沿 9 环粗细曲线微弯斜切放样 + `3–6 mm` 倒角；
  - **有机菌伞/生物囊**：保持「精致卡通」的饱满圆润分节放样，**在根颈、菌褶、甲片处做硬朗箍环和 `2 mm` 镶嵌槽**；
  - **统一破土绑定**：用 `BVHTree.ray_cast()` 把根部**深埋进基岩以下 `15–25%` 高度**，压出一圈碎岩/蚀变槽，写入顶点属性 `growth(0..1)` 驱动根浊到顶亮。
- **③ 模块化建筑与废墟**：按 `2.5–4.0 m` 间距插工字钢肋柱 + `0.10–0.12 m` 防撞踢脚线打破白墙；做废墟时**先建完整标准建筑框，再用 3–5 刀斜向 `bisect_plane` 削出断茬**并外露折弯钢筋与碎块。
- **④ 环境交互小道具与角色皮肤**：中小型物件按 `ExplorePropKit` 关键词命名（`*Crystal*`/`*Valve*`/`*Pipe*`/`*Lamp*`/`*Panel*`/`*Crate*`/`*Barrel*`），接入关卡即可自动全场景按 `E` 探索反应；角色严格保持 `~1.85m` 三头身（头盔 `~1/3`）及 `HeadPivot`/`*ArmPivot`/`*LegPivot` 挂点契约。

---

### 方法二：四层表面分化、2K 多频纹理与本仓库的着色器绑定（v2.0 重写）

**为什么同类几何别人像塑料、共振星像重工成品？** 因为材质必须做足 **4 层物理叠合 + 家族级粗糙度差异（`>= ±0.15`）**。

> ⚠️ **v1.0 此处要求「调用 `ArtPbrLib`」——本仓库没有这个文件**。下面的链路是**本仓库真实可用**的等价实现，照着写不会卡。

**2.1 三频程序化可平铺 2K 贴图（`make_textures_2k.py` 算法，素材包内）**

- 使用 **FFT 频域粉红噪声** + 环形绕边绘制（`ox, oy in (-S, 0, S)`）生成绝对无接缝四方连续贴图；
- 每类材质单独合成 **低频大斑块（20–60 周）+ 中频工艺肌理（200–600 周）+ 高频颗粒/拉丝（2000+ 周）**，经中心差分转为 `2048² Normal` 与 `2048² Roughness` + `1024² Mask`：

| 家族 | 语义 | 粗糙度 `R` | 本仓库现状 |
|---|---|---|---|
| `paint` | 橘皮 + 起皮边 + 细擦痕 | 0.38–0.58 | ✅ 已导入 |
| `cast` | 砂型麻点 + 气孔 + 浇铸波纹 | 0.46–0.72 | ✅ 已导入 |
| `mach` | 各向异性金属拉丝 | 0.18–0.34 | ✅ 已导入 |
| `conc` | 解理裂沟 + 骨料坑蚀 | 0.72–0.92 | ✅ 已导入 |
| `rock` | 层理沟 + 解理面 | 0.72–0.92 | ✅ 已导入 |
| `ice` / `bio` | 直线刮痕+浊斑 / 同心生长波纹 | 0.08–0.28 / 0.55–0.75 | ⬜ 未生成（脚本在素材包） |

**2.2 本仓库的四层融合怎么落（替代 `ArtPbrLib`）**

| 层 | 语义 | 本仓库落点 | 关键参数 |
|---|---|---|---|
| L1 面漆 / 表壳 | 主色与光泽 | `gulu_art_kit.paint(color, rough, metallic, wear, seed)` → `aqs2_metal` | `paint_color` / `roughness` / `metallic` |
| L2 露底漆 / 原胚 | 掉漆、擦痕 | `aqs2_metal` 内置 | `primer_color`、`bare_color`、`chip_threshold`（`paint` 0.66 / `bare` 1.55 / `dark` 0.92）、`rust_amount` |
| L3 凹缝 / 接地污垢 | 缝内压暗、AO | `aqs2_metal` 的 `grime_amount` + 贴地贴片 `gulu_contact_decal.gdshader`（`ArtAtmosphereKit.build_ground_skirt`） | `Col.G`（GLB）/ 世界噪声（程序化） |
| L4 朝上尘 / 霜 / 沙 | 顶面积层 | `Col.A`（GLB）或 `aqs2_metal` 朝上度噪声 | `detail_mask` 4 通道 |
| 细节族 | 微表面 | `_apply_family(m, "paint"\|"cast"\|"mach"\|"conc"\|"rock", scale, strength)` | `detail_scale`：paint 3.4 / mach 2.6 / cast 2.8 / conc 2.2；`detail_strength` 0.5–0.6 |

**2.3 导入清单强制项**

- 法线贴图：`compress/mode = 2`（VRAM Compressed）、`compress/normal_map = 1`、`mipmaps/generate = true`；
- `vertex_mask_valid`：**GLB 已烘 `Col` → `true`；运行时生成无 `Col` → `false`**（见红线 4）；
- 多件静态小装饰按材质合并网格合批；大型内视壳体本仓库暂无 `cull_disabled` 岩石 shader，**需要时先补 shader 再谈用法**。

---

### 方法三：Godot 4.7.2 `gl_compatibility` 五层布光、接地氛围与物理因果实现

**`gl_compatibility` 下没有 SSIL / SSR / 实时体积雾，质感全靠以下四项硬配比拉起**：

1. **`WorldEnvironment` Compatibility 安全配置**（本仓库实测值，`scripts/gulu_app.gd` L397–442）：
   - 必须显式关闭 `ssr_enabled = false`、`ssil_enabled = false`、`volumetric_fog_enabled = false`；
   - 环境光：`ambient_light_source = COLOR`、`#e6f0f2`、`energy 0.24`（**偏低**，见 3.5 诊断）；
   - 雾：指数雾 `density 0.0045`、`fog_sky_affect 0.12`、色 `#c2d2d0`；
   - 色调：ACES、`exposure 1.0`；辉光 `intensity 0.55`、`hdr_threshold 1.05`；调色 `contrast 1.06 / saturation 1.10 / brightness 1.01`。

2. **五层通用布光蓝图**（每层各司其职）：

| 光层 | 节点与阴影设置 | 角度与能量要点 | 解决的画面问题 |
|---|---|---|---|
| **1. 主故事光 Key** | `SpotLight3D` / `DirectionalLight3D`（**全厅唯一 1–2 盏开阴影**） | 暖白/本星主题主光，张角 `42–48°`，`15–25°` 斜向掠射主体 | 建立体积明暗交界与清晰地面投影 |
| **2. 补光 Fill** | `SpotLight3D` / `OmniLight3D`（关阴影） | 主光能量 `40–55%`，偏冷灰或环境色 | 让背光面依然能看清结构线条不死黑 |
| **3. 轮廓光 Rim** | `SpotLight3D`（**必关阴影，高对比**） | 主体斜后上方 `32–38°` 照边缘 | 把机械和角色剪影从深色背景岩壁/废墟强力「剥离」出来 |
| **4. 表面掠射 Graze** | 窄角 `SpotLight3D`（关阴影） | 贴近岩崖/冰壁/建筑墙 `10–20°` 擦面 | 在无 SSAO 时靠掠射高光把岩石层理与墙肋打出立体起伏 |
| **5. 实用状态光 Practical** | 小半径 `OmniLight3D`（关阴影，`omni_range 3–6 m`） | 直接挂在可见灯罩、晶体、控制台屏前 | 让环境光随机关激活/锁定切换色温，兼顾美学与玩法读图 |

3. **接地、悬垂软管与环境微动态**（本仓库已接，`scripts/gulu_scenery.gd` 共 12 处调用）：

   | 方法 | 用途 | 本仓库调用点 |
   |---|---|---|
   | `build_ground_skirt()` | 底座 `y + 0.012` 径向暗晕，消除「硬边插地」 | 门架 / 维修棚 / 观测台 / 料箱 / 东站 |
   | `build_gravel_cluster()` | 微倒角碎石圈 | 同上 6 处 |
   | `build_catenary_hose()` | 重力悬链软管 + 金属箍 | 按需 |
   | `build_ambient_motes()` / `build_steam_vent()` | 缓飘尘雾 / 脉冲泄压汽 | 按需 |
   | `build_godray_cone()` | 极淡假体积光（`intensity 0.09–0.12`） | 天井 / 闸门上方 |

   > **更正一条过期审计**：v1.0 配套审计曾记「接地未用 `ArtAtmosphereKit`」——那是 00:57 之前的旧状态；当前 `gulu_scenery.gd` L189–443 已全面接入，该项**已合规**。

4. **物理因果机械表达**（`physical_link_kit.gd` + `conduit_flow.gdshader`）：机关连线用贴地/贴墙倒角三轨导管（绕门洞、端面法兰、颜色脉冲区分未通电/琥珀就绪/青光激活）；进度用可动实体表盘 `build_live_dial()` + 遮光状态灯 `build_status_lamp()` + 贴壳纯图标铭牌 `build_diagram_plaque()`。

5. **本仓库布光实测表（v2.0 新增，`gulu_app.gd` L444–492）**

| 层 | 节点 | 实测参数 | 指南建议 | 诊断 |
|---|---|---|---|---|
| Key 太阳 | `DirectionalLight3D` | `#fff0d2`、energy `0.42`、rot `(-52, -34)`、spec `0.15`、**唯一投影** | 15–25° 掠射、1–2 盏投影 | 角度偏陡（接近正午顶光），掠射感不足 |
| Fill | `OmniLight3D` | `#cfe9e4`、`0.15`、`(4,7,0)`、range `22` | 主光 40–55%（≈0.17–0.23） | 偏弱，暗部靠顶光兜 |
| Rim | `DirectionalLight3D` | `#8fdbe8`、`0.18`、rot `(28,148)`、spec `0` | 32–38° 斜后上、高对比 | 方向对，能量偏低，剥离力不够 |
| 场地顶光 | `SpotLight3D` | `#dfeef0`、**`1.2`**、`y=12`、`80°`、range `45`、无影 | 指南无此层 | **1.2 ≈ 主光的 2.9 倍**：平面感、剪影弱的主因，见 6.3 |
| Graze | `SpotLight3D` | `#ffd9a8`、`0.55`、rot `(-8,118)`、`52°`、range `30` | 10–20° 擦面 | 张角偏宽，掠射高光散掉 |
| 环境光 | `Environment` | `#e6f0f2`、`0.24` | GL 下需补偿暗部 | 偏低；但被顶光部分掩盖，形成「中间调靠顶光、暗部没底」 |
| 雾 / 辉光 / 调色 | — | `0.0045` / `0.55,1.05` / `1.06,1.10,1.01` | 匹配背景、阈值 >1 | 基本合理，保持 |

---

### 方法四：双端无头渲染 + AI 读图排雷闭环（验证方法）

1. **Blender 灰模构型快检**：跑素材包 `render_preview.py` 出 `front` / `three_quarter` / `side` / `detail` 四向图，脱离贴图单独审视剪影、倒角、缝隙和承力关系。
2. **Godot `gl_compatibility` 实机 4 机位截图**（本仓库已内置 `--art-shots`，`gulu_app.gd` L2361–2370）：

   | 机位 | 坐标 | 朝向 | FOV | 用途 |
   |---|---|---|---|---|
   | `A_wide` | `(-8.0, 1.06, 19.0)` | `(9.0, 0.2, -4.0)` | 50 | 整体地标轮廓与 70/15/10/8 色彩比例 |
   | `B_player_eye` | `(2.4, 0.02, 5.2)` | `(9.5, 1.0, 0.0)` | 65 | 玩家眼高实机视角、引导清晰度 |
   | `C_interaction` | `(10.4, 0.02, 2.2)` | `(12.8, 1.5, 0.0)` | 44 | 核心机关 1.3–1.8 m 近景：倒角/接缝/法线 |
   | `D_threequarter` | `(-7.2, 0.02, 13.6)` | `(-6.2, 0.9, 9.2)` | 52 | 设备与地貌接地交界、碎屑与线缆 |

   ```powershell
   & 'C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' `
     --path game/previews/gulu_planet --rendering-method gl_compatibility -- --art-shots
   ```

   截图输出到 `user://gulu_art_shots`（Windows 为 `%APPDATA%\Godot\app_userdata\<项目名>\gulu_art_shots`），拷回 `docs/shots_art_<日期>/` 再体检。

3. **常见翻车秒查修复**：

   | 现象 | 根因 | 修复 |
   |---|---|---|
   | Blender 报 `use_auto_smooth` 不存在 | 4.1+ 已移除该属性 | 改 `p.use_smooth=True` + `EDGE_SPLIT(30°)` |
   | Godot 法线完全没凹凸 | 导出前忘 `Triangulate`，或 `.import` 漏开 `normal_map=1` | 重导 + 补导入参数 |
   | 低模像膨胀反光球 | 高模误加整体 `Shrink/Smooth` | 位移只做向内为主的局部三频 |
   | 全黑 / 全掉漆 | `vertex_mask_valid` 设反（红线 4） | GLB→`true`；程序化→`false` |
   | 内视黑洞破面 | `aqs2_rock` 只有 `cull_back` | 复制 shader 改 `cull_disabled`，或补双面材质 |
   | 画面「平、灰、没剪影」 | 顶光 ≥ 主光（奶龙星当前就是） | 顶光降到主光 1.3 倍以下，见 6.3 |

---

## 第 4 部分 · 可直接复制发给 AI 的跨星球提示词包

> 新开对话让 AI 制作**任意新星球**时，先发 **【0 号总控】** 锁定「风格+质量+实现方法」，再按阶段依次发送 **【1～4 号执行提示词】**；若只需单件资产，直接用 **【5 号单资产全流程工单】**。

### 0 号提示词：跨星球风格、质量与实现法则总控（新对话第一条必发）

```text
你正在协助制作多人合作游戏《迷失太空》的新星球：[星球名称与生态主题]。
核心要求：**同时做到“与共振星（K-17 / ART-SAMPLE-002）完全同一套画风与质量标准”以及“属于本星球的独特地貌和题材”——既不能抄共振星的红褐洞穴与蓝晶，也不能退化成粗糙方块、纯写实碎噪点或低劣玩具。**

先做一件事：读 docs/resonance/美术制作与AI协作指南.md 的【第 0 部分 落地基线】，
列出本仓库“已有能力 / 缺口 / 已建资产实测”三张表，并指出你打算复用哪些、新建哪些。
本仓库没有 ArtPbrLib、没有 aqs2_crystal，照抄指南 v1.0 的旧路径会直接报错。

然后必须同时遵守【风格 × 质量 × 实现方法】：
1. 风格不变量（精致卡通：清晰轮廓、圆润设备、统一色彩）：
   - 造型：干净硬朗的几何块面 + 真实厚度折边（>=8mm）+ 主角大圆角（40–60mm）+ 加工件多段物理倒角（0.8–3mm）+ 2–3mm 实体阴影装配缝；严禁裸 BoxMesh/CylinderMesh 当成品，严禁“平滑球+噪点”当自然岩体，严禁像素风。
   - 色板比例（跨星球死守不变）：65–75% 低饱和与本星相符的基底色 + 10–15% 高明度识别外壳 + 5–10% 安全青绿引导 + <=8% 工业橙/琥珀（严格限定只给手柄/阀门/卡箍/按钮等可操作件）+ <2% 警报红；发光必用软膝限幅保留色相梯度。
   - 高明度外壳的反照率口径按指南 1.3 的【口径 A】：线性反射率 <= 0.62，等价 sRGB <= ~0.81，取 #CFC5AE~#C9BFA6；#EFE6CE 仅限 <1% 面积的小识别件。
   - 绝对禁止悬浮 3D 文字（Label3D / Billboard）；读数与顺序必须做成实体表盘、状态灯或贴壳<=2cm的纯图铭牌，提示走 HUD。

2. 质量与人机工程基线：
   - 眼高 1.55–1.65 m 为尺度锚点（操作台/栏杆高 1.0–1.08 m，通道净宽 >= 2.0 m）。
   - 1–2 m 内拒绝“数学平面”与“单色塑料漆”：必须有 4 层表面演化（基质→外涂/覆层→凸棱/破损露底→凹缝AO与朝上积尘/霜/沙）+ 分族粗糙度变化（>= ±0.15）。
   - 机械必有落地承台/加强筋/法兰管卡；自然物/菌簇必须深埋地形 15–25% 并伴生碎屑压边。

3. 实现方法与 Godot 4.7.2 `gl_compatibility` 硬约束：
   - Blender 4.5 LTS（C:\Users\31798\AppData\Local\Programs\Blender Foundation\Blender 4.5\blender.exe）用 Godot 坐标计算后矩阵转换，先截面放样/切面雕刻，Smart UV (margin=0.006)，**必须在 EdgeSplit(30°) 之前**烘焙 4 通道顶点色 Col，英雄件高烘低严禁高模全局负向收缩，导出前必须 Triangulate 并开 export_tangents=True。
   - Godot 侧必须适配 `gl_compatibility`（禁用 SSR/SSIL/VolumetricFog），复用 gulu_art_kit / ArtAtmosphereKit / PhysicalLinkKit，顶点遮罩标志按红线 4 区分（GLB=true，程序化=false），静态装饰按材质合批，视觉外观不得越界改动既有玩法碰撞盒。
   - 布光按指南 3.5 的五层实测表：**顶光能量不得超过主光 1.3 倍**，投影灯 ≤2 盏。

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
1. 配色表（给出线性 RGB 与 Hex，严格遵循 70%基底 / 15%明度外壳(线性反照率<=0.62) / <=10%青绿引导 / <=8%工业橙可操作件 / <2%红警报）：
   - 地表/岩冰三层色（主面/断裂暗面/朝上堆积物）
   - 设施结构三层色（深骨架/高明度罩壳/橡胶密封）
   - 本星球特色能源物或生物生态色彩（必须区别于共振星红褐洞穴+青紫水晶）
   - 每色的线性反照率数值，以及预计屏幕面积占比
2. 4 个以上远/近景主地标独立剪影规范（确保 30m 外不靠发光也能区分功能）。
3. 材质家族分配方案：哪些走 paint / cast / mach / conc / rock，本星是否需要扩展冰面(ice)或生物(bio)等分族 2K 贴图及粗糙度区间。
4. 本星球的 Godot `gl_compatibility` 五层灯光配方（1盏主阴影光色温/角度、补光比例、高对比轮廓光色、掠射角度、绑定实体的实用光及雾效基调），并给每个灯写具体 energy 数值与相对主光的比值。
5. 物理因果与“零悬浮文字”方案：用什么管线载体、实体表盘和接地氛围让玩家不用读文字就能看懂路径与危险。
```

### 2 号提示词：Blender 精细 3D 建模 + 烘焙 Python 脚本执行（工业 / 建筑 / 自然通用）

```text
请根据上面的设计单，用 Blender 4.5 LTS 编写可无头运行的建模与烘焙脚本：`art-source/blender/<星球名>/build_<资产名>.py`，制作 [资产名称、尺寸包络、核心用途与所属类别（工业设备/模块化建筑废墟/自然岩冰/异星晶簇菌落/角色小物）]。

【必须逐条在代码中实现的具体工艺】
1. 造型与结构（绝不造裸方块或平滑噪点球）：
   - 按 Godot 坐标设计后通过矩阵 GB 转进 Blender；主结构手写 `rrect_r(seg>=8)` / 多剖面 `bm_loft` / 车削 `bm_lathe` / 工字钢 `i_profile` 确立轮廓；若是岩冰用 `7–14` 刀 `bisect_plane` 解理切割+微倒角+层理错台；若是晶体/生态体用不等边多棱/饱满分段放样+硬朗箍环并深埋宿主地形 15–25%。
   - 拆出骨架/防护壳/嵌件，拼合缝留 `2–3 mm` 实体凹槽；薄板厚度 `>= 8 mm` 带折边；全加工棱 `BEVEL >= 2` 段；落地必有承台/加强筋，管线用平行传输 `bm_tube` 加卡箍，紧固件只在法兰/检修口做“凸台+垫圈+45°倒棱六角头+随机 phase”，焊角加 ±28% 抖动焊道。
2. UV、顶点遮罩与高烘低：
   - 用 `M_` 前缀命名材质槽（必须包含 `M_PaintCream` 作为明度壳）；展开 Smart UV (`angle_limit=1.15, island_margin=0.006`)。
   - **必须在 `EDGE_SPLIT(30°)` 之前**完成 4 通道顶点色 `Col` 烘焙（R=凸棱曲率磨损, G=BVH AO dist 0.16m, B=斑块剥落, A=朝上堆积度）。禁止使用 4.1 起已移除的 `use_auto_smooth`。
   - 若为 0–3 m 英雄件：复制低模 `Subsurf(2)` 至 >=50k 面 → 施加向内为主的三频微位移（-2.2mm..+0.8mm，**严禁整体收缩高模**）+ 2–3 处不对称使用痕迹 → `Cycles selected_to_active` (`cage_extrusion=0.035, margin=12`) 烘焙 `2048² Tangent Normal` 与 `1024²` 合成 `*_mask.png` (`R=Pointiness 0.42..0.58, G=AO`)。
   - 面数硬约束：Mid 件 2k–15k、Far 件 <=2k；超了先 `DECIMATE` 再交。
3. 导出与白灰模初检：
   - 验证 `scale==(1,1,1)`、全部 `Triangulate` 三角化、`export_yup=True / export_apply=True / export_tangents=True / export_vertex_color="ACTIVE"` 导出 GLB，贴图打包保存 `.blend`。
   - 完成后运行
     `C:\Users\31798\AppData\Local\Programs\Blender Foundation\Blender 4.5\blender.exe -b --factory-startup -P <脚本>`
     并调用素材包的 `render_preview.py` 输出四视角图自检结构，把输出图路径与面数报给我。
```

### 3 号提示词：Godot 4.7.2 Compatibility 装配、材质接管、五层布光与氛围接地

```text
请把生成的 [GLB/模型路径] 装配进 [新星球场景/脚本路径]，按《指南》方法二、三完成 Godot 4.7.2 `gl_compatibility` 全套美术渲染落地，不修改原有玩法碰撞与逻辑。

【接入执行清单】
1. 材质与着色器：
   - 复查法线图 `.import`（`compress/mode=2, compress/normal_map=1`）；通过 `gulu_art_kit` 的 `_apply_family()` 按 `M_` 材质名绑定分族纹理（paint/cast/mach/conc/rock，或新生成的 ice/bio），确保族间粗糙度差 >=0.15、四层磨损语义完整。
   - 顶点遮罩标志：GLB（已烘 Col）设 `vertex_mask_valid = true`；运行时生成网格设 `false`。
   - 零散小装饰按材质合并网格合批；本仓库无 `cull_disabled` 岩石 shader，需要内视壳时先补 shader。
2. Compatibility 五层灯光与 WorldEnvironment：
   - 显式关闭 `ssr_enabled` / `ssil_enabled` / `volumetric_fog_enabled`；布置 1 盏开阴影主光 + 关阴影补光 + 主体后上方强对比轮廓光 + 地形/建筑掠射光 + 绑定可见灯具的实用光。
   - **顶光/补光总能量不得超过主光 1.3 倍**；投影灯 <=2 盏；环境光与主光保持“暗部有底、交界清晰”的比例，落地后用 `tools/inspect_shot.py` 量 p50 与 dark<0.06 两个指标。
3. 接地、生命力与物理因果：
   - 用 `ArtAtmosphereKit` 为全部落地设施/岩体底座挂 `build_ground_skirt` 与 `build_gravel_cluster` 消除硬边插地；按需拉 `build_catenary_hose` 软管，加 `build_ambient_motes` / `build_steam_vent` 与克制 `build_godray_cone`（`intensity <= 0.12`）。
   - 用 `PhysicalLinkKit` 沿墙角/地面铺设带法兰且不挡路的因果导管、`build_live_dial` 表盘、`build_status_lamp` 灯罩与贴壳纯图标铭牌，绝对禁止悬浮 `Label3D`。
   - 若需要让场景摆件支持自由探索按 E 交互，确认静态节点命名对齐 `ExplorePropKit` 关键词并正确避开主机关。
```

### 4 号提示词：双端实机截图验收与缺陷返修闭环

```text
不要只做文字汇报。请你用 `gl_compatibility` 模式运行 headless 渲染自检脚本，截取新星球场景 [场景路径] 以下机位并亲自看图逐一打分修补，直到全部过关：
1. `A_wide.png`（FOV 50，审地标轮廓独立性、空间层次与 65–75/10–15/5–10/<=8/<2 色彩比例）
2. `B_player_eye.png`（眼高 1.60m 玩家实机视角，FOV 65，审引导清晰度）
3. `C_interaction.png`（核心机关 1.3–1.8m 近景特写，FOV 44，审倒角、装配缝、微肌理与磨损）
4. `D_threequarter.png`（建筑/设备与地貌交界、接地碎屑与悬垂线缆，FOV 52）
5. 若有激活状态变化，额外输出锁定/激活对比图。

每张图都必须跑一次 tools/inspect_shot.py 并把读数贴出来，逐条自查：
- [ ] `blown>0.94` 是否 0%？`dark<0.06` 是否 <3%？`p50` 是否 >=0.25？
- [ ] 高明度外壳（hull_light/dragon_cream）占比是否落在 10–15%？骨架底色是否 65–75%？琥珀是否 <=8%？
- [ ] 近景 1.5m 是否彻底消灭“数学平面”、“零厚度片”或“光滑玩具块”？
- [ ] 是否有悬空物、穿门导管、或与地面割裂的黑硬边？
- [ ] 是否绝对没有漂浮 3D `Label3D`？
- [ ] `vertex_mask_valid` 是否按 GLB / 程序化两类分别设对（无黑块/全烂漆）？
- [ ] 是否有本星生态独特性，又一眼符合《迷失太空》精致卡通风格且不逊于共振星画质？
- [ ] Godot `--headless` 冒烟与交互测试全 pass 且无 Compatibility 着色器告警？

只要发现任一缺陷立刻改代码/模型并重截，不要等我追问。
```

---

## 第 5 部分 · 仓库核心代码与权威索引（v2.0 全部换成本机真实路径）

| 内容分类 | 本仓库可直接复用的路径 |
|---|---|
| **Blender 建模 / 烘焙 / 四向预览脚本** | `C:\Users\31798\.openclaw\workspace\ref\art_sample_002\02_BLENDER_SOURCE\scripts\`（`aqs_kit.py`、`aq2kit.py`、`build_head.py`、`render_preview.py`、`make_textures_2k.py`） |
| **2K 多族贴图与着色器** | `game/previews/gulu_planet/assets/textures/`（5 族 × normal/rough/mask）、`shaders/aqs2_metal.gdshader`、`shaders/aqs2_rock.gdshader` |
| **材质工厂与美术工具** | `scripts/gulu_art_kit.gd`、`scripts/core/art_atmosphere_kit.gd`、`game/scripts/core/physical_link_kit.gd`、`game/scripts/world/explore_prop_kit.gd` |
| **其它着色器** | `shaders/walle_godray.gdshader`、`game/shaders/conduit_flow.gdshader`、`shaders/gulu_contact_decal.gdshader`、`shaders/gulu_yard.gdshader` |
| **环境与布光实现** | `scripts/gulu_app.gd`（`_build_environment` L397–492、`_run_art_shots` L2361–2370）、`scripts/nailong_environment.gd`、`scripts/gulu_scenery.gd` |
| **验收工具** | `tools/check_nailong_assets.gd`、`tools/inspect_shot.py`、`tools/probe_props.gd`、`tools/probe_dressing.gd` |
| **风格与素材档案** | `docs/resonance/美术制作与AI协作指南.md`（本文件）、`game/previews/gulu_planet/ASSETS.md`、`game/previews/gulu_planet/DECISIONS.md`、`game/previews/gulu_planet/docs/ART_GUIDE_AUDIT_2026_11_25.md` |
| **缺失（需自建，勿引用）** | `art_pbr_lib.gd`、`aqs2_crystal.gdshader`、`aenv8_rock.gdshader`、`cull_disabled` 岩石变体 |

---

## 第 6 部分 · 奶龙星画面实测与返修单（v2.0 新增）

> **本节是助手基于 2026-11-25 01:27 那批截图给出的建议，未经团队确认**；优先级按「对画面的视觉收益 ÷ 改动风险」排，P0 三条都只动视觉层，不碰玩法碰撞。

### 6.1 基线读数（`tools/inspect_shot.py` 实测，4 张 1280×800）

| 指标 | A_wide | B_player_eye | C_interaction | D_threequarter | 合格线 |
|---|---|---|---|---|---|
| `luminance mean` | 0.31 | 0.41 | 0.40 | **0.17** | ≥ 0.33 |
| `p50` | 0.24 | 0.37 | 0.36 | **0.11** | ≥ 0.25 |
| `p90` | 0.68 | 0.68 | 0.80 | **0.37** | ≥ 0.60 |
| `blown > 0.94` | 0% | 0% | 0% | 0% | 0% ✅ |
| `dark < 0.06` | 0.1% | 0.1% | 0.1% | **7.0%** | < 3% |
| `hull_light` | **0.30%** | 3.68% | 2.72% | **0.00%** | 10–15% |
| `dragon_cream` | 0% | 0.04% | 0.02% | 0.17% | — |
| `trim_teal` | 0.49% | 8.21% | **22.23%** | 0.16% | 5–10% |

**三条结论**：① A 与 D 都「暗且没有亮部」；② 高明度外壳在所有机位都几乎不存在（目标 10–15%，实测 0–3.7%）；③ C 机位近景被单一深青（22%）吃满，颜色失层次。

### 6.2 P0-1 · D 机位近全黑（死黑 7%，p50 0.11）

- **现象**：`D_threequarter` 平均亮度 0.17，7% 像素低于 0.06，几乎看不出接地交界的碎屑与线缆——而这正是这张图存在的唯一意义。
- **根因（待验证）**：D 机位 `(-7.2, 0.02, 13.6)` 朝 `(-6.2, 0.9, 9.2)`，视线对着设施的**背光面**；主光从 `rot(-52,-34)` 打来，这一侧没有 key 也没有 fill 覆盖。
- **处方**：
  1. 在 D 机位前方 `+3 m` 处加一盏关阴影 `OmniLight3D`（`range 8`、`energy 0.35`、暖白 `#ffe9c8`），只照接地带；
  2. 或把 D 机位挪到设施**迎光侧**（把 x 从 `-7.2` 改到 `-3.0` 一侧），同样 FOV 52；
  3. 验收：`p50 ≥ 0.25`、`dark<0.06 ≤ 3%`，且接地碎石能看出「压边」关系。
- **风险**：只增加一盏不投影的灯，对 FPS 与玩法零影响。

### 6.3 P0-2 · 顶光压主光（1.2 vs 0.42，2.9 倍）

- **现象**：A/B/C/D 四张都「平、灰、没剪影」；按 3.5 表，`yard_fill` 从正上方 `y=12`、`80°` 打 `1.2`，而 key 太阳只有 `0.42`。
- **为什么是硬伤**：五层布光的第一条是「主光建立体积明暗交界」。顶光比主光强 2.9 倍时，地面与箱体顶面被均匀点亮，**地面投影被冲淡**，剪影与主体分离全失效——这直接吃掉 2.1 的「远距看构图」。
- **处方（按顺序试，一次只改一个）**：
  1. `yard_fill.light_energy: 1.2 → 0.55`（≈主光 1.3 倍）；
  2. `yard_fill.spot_angle: 80 → 58`，让顶光成为「池状」而不是全覆盖；
  3. key `sun.light_energy: 0.42 → 0.55`，`rot` 的俯角 `-52 → -38`，让掠射感出来；
  4. `ambient_light_energy: 0.24 → 0.32` 补暗部（避免降顶光后 D 更黑）。
- **验收**：A_wide 中 `container`/门架的**地面投影长度**明显变长且边缘可辨；`p90` 上升、`dark<0.06` 不增加超过 1%。

### 6.4 P0-3 · 高明度识别壳几乎为零（且色相跑偏）

- **现象**：`hull_light` 在 A 只有 0.30%、D 为 0；而 1.2 表要求 10–15%。同时 `M_PaintCream` 实际绑的颜色是 `HULL_LIGHT = #b4c1b7`（**灰绿**，线性 0.53），和深青骨架同族——等于「识别层」不存在。
- **处方**：
  1. `gulu_scenery.gd` 的 `HULL_LIGHT` 改 `#CFC5AE`（线性 0.62，符合口径 A）；`_mat_paint_light` 同步；
  2. 指定三处**必刷明度壳**的件：① 装卸门架横梁与吊臂端板；② 集装箱腰线（`M_PaintCream` 面）；③ 维修棚檐口 + 观测台栏板；
  3. 目标：`hull_light` 在 A_wide ≥ 8%、B/C ≥ 10%；颜色偏暖，和深青骨架形成冷/暖分层。
- **风险**：只改材质颜色与指定件，不动几何与碰撞。GLB 里的 `M_PaintCream` 面若面积不够，需要在 Blender 侧把腰线加宽 `80–120 mm` 后重导。

### 6.5 P0-4 · A_wide 前景岩体压死构图

- **现象**：`A_wide` 左下与中景被深色巨岩占满，球与装货口被挡在后面；机位 `(-8.0, 1.06, 19.0)` 高度只有 1.06 m，几乎贴着岩脚。
- **处方（二选一，先试 1）**：
  1. 抬高并后撤机位：`(-8.0, 1.06, 19.0) → (-10.5, 2.30, 21.0)`，target 保持 `(9.0, 0.2, -4.0)`，FOV 50。抬高 1.2 m 后前景岩体从「墙」变成「前景框」。
  2. 把西侧那组巨岩整体外推 `3–5 m`（改生成坐标，不动碰撞体），让出通往装货口的视线。
- **验收**：A_wide 里「球 → 门 → 装货口」三者在同一画面内无遮挡；`p50` 与 `p90` 同时上升。

### 6.6 P1 · 次级问题

| # | 问题 | 处方 | 验收 |
|---|---|---|---|
| P1-1 | C_interaction 近景 `trim_teal` 22%，单色吃满 | 给近景件加 2–3 处异色小件（`M_BareSteel` 螺栓面、暖白腰线、琥珀阀门），把深青压回 10% 内 | `trim_teal ≤ 12%`，且近景能数出 3 种材质 |
| P1-2 | 五件资产一件都没过三距验收（2.4 表全空） | 用 C 机位补每件 1.3–1.8 m 特写，逐件填表 | 表填满且每格有截图编号 |
| P1-3 | `loading_frame` 未进资产检查脚本 | 把 `["loading_frame", ...]` 加进 `tools/check_nailong_assets.gd` 的 `ASSETS` | 检查脚本输出 5 件全 PASS |
| P1-4 | 未生成 `ice`/`bio` 分族（指南允许扩展） | 跑素材包 `make_textures_2k.py` 生成后放进 `assets/textures/` | 新族在 `gulu_art_kit` 有分支且被至少一件资产使用 |

### 6.7 每轮固定 5 条（缺一条就算没做完）

1. 截 4 机位 → 2. 跑 `inspect_shot.py` 贴读数 → 3. 跑 `check_nailong_assets.gd` 贴面数 → 4. 自测（`GULU SELFTEST` 全绿）→ 5. 把改前/改后读数写进本轮记录。

### 6.8 复现命令（可直接复制）

```powershell
# 1. 资产面数/材质/贴地检查
& 'C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path game/previews/gulu_planet --script tools/check_nailong_assets.gd

# 2. 四机位美术截图（gl_compatibility）
& 'C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' `
  --path game/previews/gulu_planet --rendering-method gl_compatibility -- --art-shots

# 3. 截图体检
& 'C:\Users\31798\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe' `
  game/previews/gulu_planet/tools/inspect_shot.py game/previews/gulu_planet/docs/shots_art_2026_11_25/A_wide.png
```

---

## 附录 A · 本轮事实更正表（v1.0 → v2.0）

| # | 位置 | v1.0 写法 | 本机/本仓库实际 | 处理 |
|---|---|---|---|---|
| 1 | 全文 15 处链接 | `file:///d:/迷失太空/...` | `D:\迷失太空` **不存在** | 全部改为本机真实路径 |
| 2 | 方法一标题 | Blender `5.2.2 LTS` | 本机仅 4.5 LTS；`build_nailong.py` 头注明 4.5 | 改 4.5，并说明 API 兼容 |
| 3 | 方法一链接 | `blender-5.2.2-windows-x64\blender.exe` | 该目录不存在 | 改 `...\Blender Foundation\Blender 4.5\blender.exe` |
| 4 | 方法二 | 调用 `ArtPbrLib` | 无 `art_pbr_lib.gd` | 改 `gulu_art_kit` + `aqs2_*` 等价链路 |
| 5 | 方法二 | `aqs2_crystal` / `aenv8_rock` | 两者都不存在 | 列为缺口，给替代 |
| 6 | 方法二/三 | `rock_shell(cull_disabled)` | `aqs2_rock` 只有 `cull_back` | 注明需先补 shader |
| 7 | 方法二 | 「导入 5 族 2K 贴图」当待办 | 已导入 15 张，`.import` 已合规 | 改为「已有能力」并给路径 |
| 8 | 1.2 色板表 | albedo ≤0.62 **且** 示例 `#EFE6CE` | 两者矛盾（0.86 vs 0.62） | 新增 1.3 口径裁定 |
| 9 | 分红线 4 | 只写「无顶点色必须 false」 | GLB 已烘 `Col`，必须 `true` | 拆成两分支并举例 |
| 10 | 方法三 | 环境光「~1.8–2.4」 | 本仓库实测 `0.24` | 补 3.5 实测表与诊断 |
| 11 | 配套审计 | 「接地未用 `ArtAtmosphereKit`」 | 已接入 12 处（`gulu_scenery.gd`） | 标注该条过期 |
| 12 | 素材包路径 | `work/art-sample-002/...` | 解包在 `C:\Users\31798\.openclaw\workspace\ref\art_sample_002\` | 全部替换 |
