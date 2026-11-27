# RUIN-HOSPITAL-UX-010-20261126 · 医院穿模/挡板/导向与任务栏修复

## 1. 能源站出门朝向

- `main_3d.gd` 的 `exit_energy_station_rpc()` 从「面向大门（-Z）」改为「面向门外（+Z）」。
- 玩家位置仍在 `buildings["energy_station"].entry`，只是旋转和第一人称相机 yaw 设为 `PI`。
- 验证：`ruin_energy_station_interior.gd` **36/0**，新增镜头朝向检查。

## 2. 对话按钮压文案

- 对话面板从 `760×520` 放大到 `760×600`，正文区从 `200` 高扩到 `294`。
- 选项按钮最小高度改为 `44`，选项区下移到 `y=382`，与正文分离。
- 打开对话时立即隐藏场景底部 `[E]` 交互条，关闭对话后恢复；避免两个交互按钮叠在一起。
- 截图：`work/round2-20261126/story4/04_engineer_dialogue.png`。

## 3. 医院穿模与半身高黑色挡板

- 删除 1F/走廊全线 `Wainscot`（0.92 m 高、19 m 长的深色墙裙）。它横穿门洞和柜台，是 1F/B1 最明显的黑色挡板与穿模来源。
- 接待台/柜台前沿从 `WALL_LOW` 深色改为浅灰绿，保留家具但不形成半身高黑墙。
- 删除 B1 档案室悬在通道中央的 `ArchiveMonitor`（近距离会占满视野并遮挡档案墙）。
- 为 B1 档案柜、1F 药架、药房冷柜、大厅长椅补碰撞，减少玩家直接穿进家具。
- 保留仅 0.10 m 高的踢脚线。
- 验证：`ruin_hospital_interior.gd` **60/0**（新增 Wainscot 不存在检查）；`ruin_interior_clipping.gd` **1492/0**。

## 4. 进门左手楼梯间导向牌

- 新增 `game/assets/ruin/signs/hospital_stairs.png`。
- 贴在 1F 西墙 `x=-11.60, z=6.9, y+1.55`，尺寸 `2.8×0.79`；内容是「楼梯间 / STAIRWELL / 西侧北行」+ 黄色左箭头。
- 位置就在进门后左手墙，转身即可看到。
- 验证：`ruin_hospital_interior.gd` 检查 `WallSign_hospital_stairs*` 存在。
- 截图：`work/round2-20261126/hospital8/01e_stair_sign_close.png`。

## 5. 任务栏重做

- 目标面板扩大到 `420×192`，位置仍在 VITALS 下方 `(24,112)`。
- 拆成三层：
  - 标题：`当前目标`
  - 目标正文：`探索腐墟星 · 区域` + 当前剧情/撤离目标 + 噪音/价值
  - 独立底行：`任务物品 · 进度`
- 医院内显示：`任务物品 · 0/3 · 病历○ 稳定剂○ 门禁卡○`
- 学校/超市显示导航线索；其他区域显示 `任务物品 · 0/6`。
- 支线面板下移到 `y=342`，腐墟星隐藏，避免与任务栏重叠。
- 验证：`ruin_task_hud.gd` **6/0**，检查目标/任务物品分行且不重叠。

## 截图

- 大厅与浅色柜台：`work/round2-20261126/hospital8/01_lobby.png`
- B1 太平间：`work/round2-20261126/hospital8/05_morgue_b1.png`
- 药房：`work/round2-20261126/hospital8/02_pharmacy.png`
- 楼梯牌近景：`work/round2-20261126/hospital8/01e_stair_sign_close.png`
