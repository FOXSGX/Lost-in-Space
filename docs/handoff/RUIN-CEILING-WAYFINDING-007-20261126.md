# RUIN-CEILING-WAYFINDING-007 · 医院/能源站顶板、楼梯、导视与管线清理

日期：2026-11-26
范围：腐墟星医院/能源站顶板与灯具、楼梯端头、楼层/房间导视、配电间路线、长管线清理、任务文本引导。
未改：任务物 ID/位置、病房门锁、剧情门槛/结局、敌人/物品数值、联机字段。

## 一、根因

- 医院顶板使用三平面 PBR 材质，在 `gl_compatibility` 背光时接近黑色；大块顶板没有灯具底座/收边。
- 楼梯井上方本来就是开口，周围没有 soffit/收边，读成纯黑缺口。
- 医院 `StairWallHandrail` 是 10.2 m 长斜圆柱，没有墙托，端头伸进平台/门洞；`StairRail` 也过长。
- 医院/能源站楼梯灯是贴在天花板下方的发光薄板，部分在井口上方，没有灯座，看起来悬空。
- 医院走廊 `CorridorPipe` 18 m 长，穿门楣/楼梯口；能源站 `TurbinePipe` 6 m、`CoolantPipe` 3 m、`TankPipe` 从顶板穿出。
- 配电间暗门在 1F 北墙，入口看不到，只有小 label；HUD 只写“进入能源站配电间暗门”，没有说明“1F 核心井北侧”。
- 建筑内部没有室内地图/楼层目录，玩家只靠一行 HUD 记多段任务，容易断线。

## 二、修复

### 顶板与灯具

- 真正根因是楼上地板底面比顶板低约 0.22 m，从下方盖住了顶板；把可读顶面（`HospitalCeiling`）下移到地板底面以下，灯具随之下移；删掉会盖住下一层地板的厚顶板实体，只保留顶面与 soffit。医院顶面改为与墙面同色系的灰泥纹理（`ceiling_plaster.png`），不再用纯色平面。
- 能源站顶面改为钢蓝色金属纹理（`ceiling_metal.png`）+ 收边。
- `_light_panel` 增加吸顶底座，灯板与顶板相连；医院/能源站楼梯灯改为东墙壁挂灯。
- 楼梯井四周加 `StairSoffit` 浅色收边，避免从下方看到黑色尖片。
- 远墙加洗墙灯/墙顶 cove，压低“整面黑墙”突兀感。

### 楼梯

- 删除医院 `StairWallHandrail` 10.2 m 斜圆柱和墙托；不再有横在门口的长管。
- 医院/能源站 `StairRail` 从 10.2 m 缩到 9.6 m，端头不进入平台/门框。
- 楼梯门保持 1.8 m 开放门洞，门框仍按 X 方向墙正确展开。

### 楼层/房间导视

- 医院/能源站每层楼梯平台放置贴墙 **楼层牌**（B1/1F/2F/3F、B2/B1/1F/2F）和 **本层房间目录**。
- 标牌改为 **QuadMesh + 生成的 PNG 纹理**，不是 Label3D，不随镜头旋转；满足“无悬浮 3D 文字”红线。
- 医院 1F 入口增加科室导视牌；能源站入口增加 1F 平面/方向导视牌。
- 图片资产在 `game/assets/ruin/signs/`。

### 配电间与任务引导

- 配电间北墙增加浅凹龛、门头、门上方灯、青色门缝灯和“配电间 · 维护通道”实体牌；暗门位置与 `secret_door_position()` 不变。
- 入口沿核心井西侧到配电间增加贴地青色导向线（三个短段，避开核心井）。
- `story_objective_text()` 改为带楼层/房间的下一步：
  - `能源站 1F · 核心井北侧：进入配电间暗门…`
  - `医院 B1 西侧药库… / 医院 1F 保安室…`
  - `能源站 B2 应急舱… 路线：1F 西侧楼梯 → B1 → B2`
  - `能源站 B1 泵房…` / `能源站 B2 反应堆控制台…`
- 庇护所 NPC 对话顶部显示当前目标；保留原长对话和三种方案，不删剧情门槛。
- 日志/目标文本仍由既有 HUD 显示，不新增 RPC/存档字段。

### 地面

- 医院 1F/B1/2F/3F 地面铺 `floor_concrete.png` 灰泥砖纹理，并按 1.2 m 加实体深色砖缝；能源站铺 `floor_metal.png` 钢板纹理，按 2.0 m 加板缝。
- 根因同样是厚顶板/地板重叠：B1 顶板盖在 1F 地面上，导致地面纹理和砖缝全被挡住；删除厚顶板后地面可见。
- 地面纹理/砖缝只做视觉，碰撞仍由原 `_collider` 承担；新增审计检查纹理层和分缝数量。

### 管线

- 移除医院 18 m `CorridorPipe`；保留贴顶 `CeilingBeam` 并贴顶收边。
- 能源站 `TurbinePipe` 6 m→1.6 m 水平短管；`CoolantPipe` 3 m→1.5 m 水平短管；`TankPipe` 1.2 m→0.45 m。
- 审计排除贯穿核心的反应堆 `CorePipe`（设计上跨层）；其余 Pipe AABB 必须在当前楼层 floor+0.1..ceiling−0.1。

## 三、审计与验证

| 测试 | 结果 |
|---|---|
| `ruin_interior_clipping.gd` | 1492/0（含顶板/灯座/管线 AABB/外墙缝/地面纹理与分缝） |
| `ruin_wayfinding.gd` | 16/0（楼层牌/目录/配电间路线/目标文本） |
| `ruin_hospital_stair_traversal.gd` | 131/0 |
| `ruin_hospital_interior.gd` | 54/0 |
| `ruin_energy_station_interior.gd` | 35/0 |
| `ruin_story.gd` | 38/0 |
| `ruin_art_audit.gd` | 47/0（无 Label3D，室内灯 159） |
| `ruin_void_recovery.gd` | 7/0 |

## 四、腐墟星全量自检

- 19 个相关测试全部 exit 0：合并、第一人称、门锁、任务物、医院/能源站/学校/市场、撤离、联机入口、剧情/结局、美术审计、感染者动画、僵尸平衡、室内穿模、掉落恢复、楼梯通行、导视。
- 穿模重点：`ruin_interior_clipping.gd` 1492/0，覆盖外墙缝、门框、楼梯井、核心井护栏、管线和新增地面纹理/分缝；`ruin_hospital_stair_traversal.gd` 131/0。
- 视觉抽查：医院/能源站各层入口、楼梯、配电间、控制室、钢板/砖纹地面截图；未发现新的可穿墙点或地板覆盖层。

## 五、证据

`work/ruin-ceiling-wayfinding-20261126/`

- `hospital/01_lobby.png`：新顶板/地面砖纹/远墙洗墙灯/入口导视。
- `hospital/01b_lobby_up.png`：抬头看顶板。
- `hospital/08a_stair_door_open.png`：楼梯门与 1F 楼层牌。
- `hospital/08b_stair_up.png`、`08c_stair_landing_2f.png`：楼梯与平台。
- `energy/01_entry_1f.png`、`01d_entry_directory.png`：入口、钢板地面与导视。
- `energy/02_control_1f.png`：控制室。
- `energy/07_distribution_1f.png`：配电间凹龛/门缝灯/门牌。
- `energy/14_stair_1f.png`：能源站楼梯。

## 六、边界

- 不删剧情步骤，只强化“下一步/楼层/房间”指引；如果仍要压缩任务链，另做剧情改动。
- 医院/能源站仍为四层、3 m 层高；不改建筑外壳。
- 楼层牌用贴墙纹理 QuadMesh，不使用 Label3D；不新增随镜头旋转的文字。
- 反应堆 `CorePipe` 作为跨层结构保留，不纳入单层 AABB 限制。
- 未提交 git。
