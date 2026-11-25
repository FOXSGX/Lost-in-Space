# 第2层：热源改变路线 · 验收

2026-10-24。只交付“固定热源融薄冰入口”这一种环境机制。新入口：[play.cmd](play.cmd)，键位见 [README](README.md)。原开放第1层与成员未提交工作保留。

| 第2层验收项 | 状态 | 证据与边界 |
| --- | --- | --- |
| 1. 可观察变化，变化实际影响通行 | **通过**（输入与碰撞回放） | 冷态冰层阻挡移动和现有跳/喷气；按住E后冰体和碰撞一起缩小，出现融水与开口；完整融开后实际步行穿入遗迹，释放控制后仍可通行。不是只改颜色、日志或进度条。 |
| 2. 至少两种有取舍的走法 | **通过**（技术结构） | 较直接的安全侧门路线约98米，无需操作；完整供热路线约82米，需要约8秒供热。首次供热总用时约25秒，直接安全绕行约18秒；近路省距离，首次不保证省时间，后续保持开放。西侧观景路线仍约141米可用。玩家是否愿意权衡仍需真人。 |
| 3. 能从现场反馈理解阻挡与解法 | **未测**（真人理解） | 已提供实体柱上的热风→薄冰图片、管线、手柄、可见热风/暖光、冰形状与融水反馈及简洁HUD。图形已观察，回放知道解法，不能证明新玩家能自行理解。 |
| 4. 失败可恢复，不永久封死必经路 | **通过** | 实际释放E、走出供热范围后停机；已融进度不倒退，返回即可继续，不用物资或F5。外围侧门在完全未供热时仍能完成往返。融开后不重新结冰。F5另作完整重开测试。 |
| 5. 单人可完成，多人自然分工 | **未测**（多人部分） | 单人实际完成冷态阻挡→供热→中断恢复→穿入→返程。设计上可一人供热、一人观察或先过开口，松手后通路保留；本轮未做真人合作或真实双进程同步，留第4层。 |

## 实机证据

- [未完全融化的实际开口](../../../work/gameplay-iterations/20261024-frost-heat-layer2/runtime/partial/partial-opening.png)、[半融状态仍可穿过并返回的轨迹](../../../work/gameplay-iterations/20261024-frost-heat-layer2/runtime/partial/result.json)：约一半进度时释放控制，残冰仍有碰撞，玩家已能从侧边开口正常走入；通行不依赖100%状态标记。
- [冷态实际挡住角色](../../../work/gameplay-iterations/20261024-frost-heat-layer2/runtime/heat/02-cold-blocked.png)
- [实体操作柱和图片](../../../work/gameplay-iterations/20261024-frost-heat-layer2/runtime/heat/03-control-pictogram.png)
- [供热中冰体开始融开](../../../work/gameplay-iterations/20261024-frost-heat-layer2/runtime/heat/04-heat-partial.png)
- [完整融开后的入口](../../../work/gameplay-iterations/20261024-frost-heat-layer2/runtime/heat/05-ice-open.png)
- [实际进入同一遗迹](../../../work/gameplay-iterations/20261024-frost-heat-layer2/runtime/heat/06-inside.png)
- [融冰后返回停机坪](../../../work/gameplay-iterations/20261024-frost-heat-layer2/runtime/heat/07-returned.png)
- [中断恢复输入轨迹](../../../work/gameplay-iterations/20261024-frost-heat-layer2/runtime/heat/result.json)、[正常供热路线](../../../work/gameplay-iterations/20261024-frost-heat-layer2/runtime/clean/result.json)、[直接安全绕行](../../../work/gameplay-iterations/20261024-frost-heat-layer2/runtime/direct/result.json)、[西侧安全路线](../../../work/gameplay-iterations/20261024-frost-heat-layer2/runtime/west/result.json)

运行环境：Godot4.7.2，1280×720，OpenGL Compatibility，RTX5070Ti Laptop。回放向Godot注入真实输入事件/动作，经实际胶囊、move_and_slide和共享跳跃/推进完成；出生后没有传送、改角色位置或关闭墙体碰撞。这不是原生OS键鼠或真人试玩。

场景导入与启动通过，F5恢复冷态、初始5HP和装备通过。完整运行日志、错误日志、结果和位置轨迹位于 `work/gameplay-iterations/20261024-frost-heat-layer2/`。本轮全项目lint保持原有77错误/9警告、0解析错误、0新增诊断；不声称修复旧静态问题。

首次回放在离开操作柱时直接撞上实体柱，随后改走柱侧留出的通路，保留设备碰撞；失败日志和截图保留在 `attempt-heat-01/`。运行时生成的前墙用运行时查找接口定位，避免静态场景路径误报。未覆盖所有边角或所有跳法。

## 当前边界

环境融化由当前本机主机更新，尚未接入正式环境状态RPC、加入补发或掉线流程。两个真实进程、四人、真人理解/合作、正式远征、其他入口回归、导出包均未测。未开展本层真人试玩，不将用户对上一层“还行”的反馈当成本层验收。

第3层目标、可选发现和物件故事，第4层主舱往返与正式联机仍只有计划。本轮候选观测站设定未升格为确定剧情；没有新增消耗品、压力、过热、热伤害或悬浮文字。
