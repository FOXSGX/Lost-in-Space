# 《美术制作与 AI 协作指南》对照审计（奶龙星，2026-11-25）

指南版本：`Downloads/美术制作与AI协作指南.md`（2026-11-25 00:57，35,987 B）
已同步到仓库：`docs/resonance/美术制作与AI协作指南.md`
配套素材：`ART-SAMPLE-002_TEAM_KIT.zip` → 已解包到 `workspace/ref/art_sample_002/`

## 0. 复述（按 0 号提示词要求）

- **风格怎么体现**：精致卡通——干净硬朗的几何块面 + 真实厚度折边（≥8 mm）+ 大圆角 40–60 mm +
  加工件 0.8–3 mm 多段物理倒角 + 2–3 mm 装配缝；色板 65–75% 基底 / 10–15% 高明度壳（albedo ≤0.62）/
  5–10% 青绿 / ≤8% 工业橙（只给可操作件）/ <2% 红；禁悬浮 3D 文字。
- **质量如何达标**：三距验收（>10 m 剪影 / 3–10 m 承力 / 1–2 m 工艺），资产分级三角面预算，
  十条红线（禁裸几何成品、禁无承力悬浮、禁同场景共用噪声、禁拉满环境光、禁发光过曝等）。
- **技术路线**：Blender 5.2.2 LTS 九步流水线（轮廓放样→承力→分层缝→工艺件→UV→4 通道顶点色→高烘低→
  三角化导出）→ Godot 4.7 `gl_compatibility`（禁 SSR/SSIL/VolumetricFog）用 ArtPbrLib/2K 家族 +
  五层布光 + ArtAtmosphereKit 接地 + PhysicalLinkKit 物理因果 → A/B/C/D 四机位无头截图自检。

## 1. 逐条对照现状

| 指南要求 | 现状 | 判定 | 处理 |
| --- | --- | --- | --- |
| 方法二：5 族 2K（paint/cast/mach/conc/rock） | **已导入** 15 张（normal/rough/mask），`.import` 已按规范设 `compress/mode=2`、法线 `normal_map=1`、开 mipmaps | ✅ 本轮完成 | — |
| 红线 5：不同材质家族独立高度场/粗糙 | `gulu_art_kit` 已按 `paint/cast/mach/conc/rock` 分族绑定 detail_normal/rough/mask + `use_detail(_mask)=true` | ✅ 本轮完成 | — |
| 红线 4：无顶点色必须 `vertex_mask_valid=false` | kit 所有 ShaderMaterial 显式设 false；GLB 岩石补顶点色 | ✅ | — |
| 方法三：五层布光 | 有 key（太阳，唯一开阴影）+ rim（冷）+ fill（球面）+ graze（掠射暖）+ practical（装货口/棚下/堆场灯） | 🟡 需固化参数表 | 下一轮写进 `ART_LIGHT_RIG.md` 并核对阴影灯数量 ≤2 |
| 方法三：接地（ground skirt / gravel / catenary / motes / godray） | 目前是自制径向贴片 + MultiMesh 碎石，**未用** `ArtAtmosphereKit.build_ground_skirt/build_gravel_cluster` | ❌ 不合规 | 下一轮改为 ArtAtmosphereKit（或对齐其参数） |
| 方法四：A/B/C/D 四机位（FOV 50/65/44/52） | **新增 `--art-shots`**，输出 `A_wide/B_player_eye/C_interaction/D_threequarter` | ✅ 本轮完成 | — |
| 色板比例 65–75/10–15/5–10/≤8/<2 | A_wide 粗测：基底中性 70.8%（44.0+26.8）、青绿 24.6%（天空计入）、琥珀 3.8%、红 0%、高明度壳 0.9% | 🟡 基底/琥珀/红达标；**高明度壳偏少、青绿被天空拉高** | 增加奶油白外壳件（门框/吊臂/货箱腰线），重新量 |
| 红线 2：禁裸几何成品 | 场边设施（装卸场/维修棚/集装箱/观察台/管线塔）**全部是 BoxMesh/CylinderMesh** | ❌ 不合规（白盒阶段） | 用 Blender 九步重做 4 组资产，替换 |
| 红线 3：禁无承力悬浮件 | 门架/管线有柱，但拱门、天线塔为方块堆叠 | ❌ 部分不合规 | 随 Blender 重做 |
| 2.1 三距验收 | 未逐件记录 | ❌ | 资产替换时按 Hero/Mid/Far 预算逐件过 |
| 红线 10：Compatibility 实机验收 | 一直在 `gl_compatibility` 跑自测 + 截图 | ✅ | — |

## 2. 本轮已落地（提交内容）

1. 导入 ART-SAMPLE-002 的 5 族 2K 贴图到 `assets/textures/`（52.6 MB），按指南设置导入参数；
2. `gulu_art_kit.gd` 新增 `_apply_family()`：paint→paint、bare/dark→mach、concrete→conc、rock→rock，
   全部打开 `use_detail/use_detail_mask`，细节尺度按族区分；
3. 新增 `--art-shots` 验收模式（指南方法四的四机位）；
4. 自测仍 46/0、街机 21/0；FPS 316.1（改前 305.5）、DC 1318、prims 186.3k。

## 3. 下一轮（严格按指南）

1. **Blender 九步重做 4 组中景设施**：装卸门架、维修棚、集装箱堆、观察台 —— `rrect_r` 圆角截面 +
   `bm_loft` 放样 + 工字钢 + 2–3 mm 装配缝 + 四件套螺栓 + 焊道；导出前三角化、`export_tangents=True`。
2. **接地改用 ArtAtmosphereKit**：`build_ground_skirt` + `build_gravel_cluster`，补 `build_catenary_hose`。
3. **PhysicalLinkKit**：给货台/坑底目标铺贴地导管 + `build_live_dial` + 贴壳铭牌（零悬浮文字）。
4. **ExplorePropKit**：按 `*Crate*/*Barrel*/*Valve*/*Panel*/*Lamp*` 命名，让场边件可用 E 探索。
5. **色板补齐**：加高明度壳（奶油白）比例到 10–15%，重跑 A_wide 量化。
6. **逐件三距验收表**：Hero/Mid/Far 三角面 + 倒角 + 缝宽进文档。
