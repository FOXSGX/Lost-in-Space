> 后续变更：2026-11-27 已恢复激光剑与前方近战，见 `RUIN-UX-012-20261127.md`；本报告中的“无武器近战”保留为历史记录。

# RUIN-SHELTER-INTERCOM-008 · 配电间门禁通讯、E 键对话与无武器近战

日期：2026-11-26
范围：腐墟星能源站 1F 配电间、庇护所入口、工程师/医生对话、配电间门牌、第一人称近战。
未改：任务物 ID/位置、`secret_door_position()`、剧情门槛、三种方案、敌人/物品数值、联机字段。

## 一、配电间门牌反字

- 门头 `energy_distribution_fixed.png` 只在配电间门牌材质上做 UV 修正，不再全局翻转所有标牌。
- 门牌文案改为：
  - `配电间 · 维护通道`
  - `门禁通讯 · 呼叫庇护所`
- 不再写“从这里进入地下庇护所”。

## 二、不进入庇护所

- 删除 `energy_secret_door` 交互里的 `enter_shelter()` 调用。
- 暗门后加实体 `ShelterDoorCollision`，门保持关闭，玩家不能穿门。
- 门旁增加壁挂式门禁通讯：
  - `IntercomHousing` 外壳
  - `IntercomGrille` 扬声器格栅
  - `IntercomButton` 发光呼叫按钮
  - `IntercomLabel` 面板
  - 低亮青色呼叫灯
- 交互提示改为 `[E] 使用门禁通讯 · 庇护所`。
- 庇护所内部 NPC 模型不再生成；`shelter_npc_positions()` 仅保留对话位置数据。

## 三、工程师/医生顺序与自动关闭

- 第一次门禁通讯：老工程师。
- 第二次：年轻医生。
- 之后按 `shelter_talk_count` 奇偶交替。
- 每次完成选择后 `_hide_ruin_dialogue_panel()` 关闭面板，并写入 350 ms 输入锁，避免同一次 E 按键在 physics 帧再次触发门禁、自动重开上一人对话。
- HUD 目标改为：
  - `能源站 1F · 核心井北侧：到配电间门外使用门禁通讯`
  - `分别和老工程师、年轻医生通话`
  - `点火三件套已齐 · 回配电间门外用门禁通讯决定撤离方案`

## 四、E 键推进对话与鼠标点击

- 对话标题显示 `老工程师 · E 继续`。
- 第一个选项显示 `[E] 我会回来`；后续选项仍显示数字。
- `E` / `Enter` / `Space` 触发第一项；`1`–`9` 选择对应项；`Esc` 关闭。
- 对话显示期间 `_ruin_ui_blocked()` 返回 true，玩家不再抢鼠标事件；鼠标点击按钮仍可用。

## 五、无武器近战

- 腐墟星第一人称不再调用 `_build_ruin_viewmodel()`；激光剑、叉子、手臂和撬棍视图模型都不再生成。
- F 近战参考新版共振星：自动选择 3.2 m 内最近感染者，不再要求准星对准；仍保留墙体遮挡检测。
- HUD / 状态文字从 `F 激光剑` 改为 `F 近战`。
- 攻击反馈只保留相机震动、目标冲击环和 HUD 命中闪烁。

## 六、验证

| 测试 | 结果 |
|---|---|
| `ruin_story.gd` | **37/0**（门外通讯、不进入、工程师→医生、E 推进、关闭后不重开） |
| `ruin_weaponless_melee.gd` | **6/0**（无 Saber/viewmodel、无目标攻击安全） |
| `ruin_story_endings.gd` | 11/0 |
| `ruin_door_lock.gd` | 42/0 |
| `ruin_energy_station_interior.gd` | 35/0 |
| `ruin_interior_clipping.gd` | 1492/0 |
| `ruin_wayfinding.gd` | 16/0 |
| `ruin_art_audit.gd` | 47/0 |
| 其余腐墟星全量回归 | 全部 exit 0 |

## 七、证据

`work/ruin-intercom-melee-20261126/`

- `story/01_shelter_intercom.png`：门外门禁通讯、关闭的配电间门、新门牌。
- `story/04_engineer_dialogue.png`：老工程师对话、`[E] 我会回来`。
- `first_person/02_avenue_plaza.png`：第一人称无武器/无手臂。
- `energy/07_distribution_1f.png`：修正后的配电间门牌与通讯设备。

## 八、边界

- 不再允许进入庇护所；`enter_shelter/exit_shelter` 代码保留但不由配电间交互调用，便于回滚。
- 工程师/医生对话内容本身未改写。
- 未提交 git。
