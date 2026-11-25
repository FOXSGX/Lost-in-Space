# 开放探索第1层 · 交付与验收

2026-10-24。用户明确希望开放世界，并批准按“小型开放区域、两种接近方向、一个可进入遗迹”重做第1层。**请双击本目录 [play.cmd](play.cmd)**，旧 `frost_layer1` 是保留的历史迷宫预览。

## 这次的空间变化

- 连续起伏地形取代格子通道，内部没有成片的高墙迷宫；外围为可见、有实体碰撞的山脊。
- 高塔是主地标，西侧天线和东侧装卸设备有不同轮廓，均可实际走近。
- 西侧高地与东侧浅冰盆通向同一遗迹的两个侧入口。地面允许路外行走、横切和改方向；回放路径只用于验证，不限制玩家移动。
- 西侧约5.4米高处可回望停机坪；建筑提供有顶的室内空间。内侧门闩打开检修通路后，返回距离缩短；不开门也可走外围返回。

候选布景仍为“冰川逐渐吞没的地热观测站”，未确认正式剧情。暖色供热设备仅是现场线索，没有提前实现第2层融冰。地图尺度不作为探索提升的验收依据。

## 验收表

| 原第1层验收项 | 状态 | 本轮证据与限制 |
| --- | --- | --- |
| 1. 第一人称走动、环视、跳跃和现有推进 | **通过**（输入回放） | 使用共享胶囊、跳跃/双资源推进、5HP五格、两手持/两装备UI。实际短跳、单瓶约0.5秒喷气、落地耗氧恢复和完整步行路线通过。不是原生OS键鼠或真人试玩。 |
| 2. 首次约3～5分钟完成出发→入口→遗迹→返回 | **未测** | 已知路线去程约27～29秒，检修通路返回约10秒；完整自动回放还包含观察截图和控制探针。自动测试知道路线，不能推断真人首次耗时；没有强制停留或降移速凑时长。 |
| 3. 起点地标吸引探索，环境线索能找到入口 | **未测**（完整体验验收） | 起点能实际看见高塔、西天线与东侧装卸臂，视线检查和截图通过；途中可回望。玩家是否愿意去、是否能靠现场线索自行找到入口，仍需真人。 |
| 4. 从另一侧开启捷径并实际缩短返回 | **通过** | 外侧E无效，现有单瓶跳/喷气不能越过闭门；内侧E使门板和碰撞一起移开。相同两端去程约137～146米、回程约48米，距离缩短约65～67%。 |
| 5. 碰撞与输入完成，无穿墙或传送必经点 | **通过**（覆盖路径） | 分别走过东侧低地、西侧高地、路外横切；地形由实际渲染网格生成碰撞，每个到达点检查落地与高度匹配。角色仅初始化设置出生位置，之后没有传送或禁用地形碰撞；没有穷举全部边角/跳法。 |
| 6. 启动入口、操作说明和实机证据 | **通过** | play.cmd、编辑器F6、README操作；Godot图形截图、输入轨迹、日志与F5重开验证。没有真人试玩或导出包验证。 |

## 可复查证据

- [开放盆地整体空间](../../../work/gameplay-iterations/20261024-frost-open-layer1/overview/01-open-basin.png)
- [高地俯看遗迹](../../../work/gameplay-iterations/20261024-frost-open-layer1/overview/02-overlook-ruin.png)
- [不开门从外围返回的结果](../../../work/gameplay-iterations/20261024-frost-open-layer1/runtime/loop/result.json)
- [起点的开放视野](../../../work/gameplay-iterations/20261024-frost-open-layer1/runtime/west/01-open-start.png)
- [西侧高地回望停机坪](../../../work/gameplay-iterations/20261024-frost-open-layer1/runtime/west/look-back-to-pad.png)
- [西侧接近遗迹](../../../work/gameplay-iterations/20261024-frost-open-layer1/runtime/west/route-view-3.png)
- [东侧低地接近遗迹](../../../work/gameplay-iterations/20261024-frost-open-layer1/runtime/east/route-view-2.png)
- [路外横切接近](../../../work/gameplay-iterations/20261024-frost-open-layer1/runtime/cross/route-view-2.png)
- [实际进入室内](../../../work/gameplay-iterations/20261024-frost-open-layer1/runtime/east/02-inside-ruin.png)
- [内侧开门](../../../work/gameplay-iterations/20261024-frost-open-layer1/runtime/east/03-inner-latch.png)
- [东侧结果与轨迹](../../../work/gameplay-iterations/20261024-frost-open-layer1/runtime/east/result.json)、[西侧结果与轨迹](../../../work/gameplay-iterations/20261024-frost-open-layer1/runtime/west/result.json)、[横切结果与轨迹](../../../work/gameplay-iterations/20261024-frost-open-layer1/runtime/cross/result.json)

原始日志在 `work/gameplay-iterations/20261024-frost-open-layer1/`：`east-final.log`、`west-final.log`、`cross-final.log`、`loop-final.log`，以及相应错误日志。图形回放向Godot注入键鼠事件/输入动作，由真实move_and_slide、地形碰撞和共享推进资源完成，不是传送模拟通关。截图已实际查看，不把回放通过写成“探索已经有趣”。

失败历史保留：初次新方法名与Main3D签名冲突，已改成独立命名；初次地形三角面朝下导致地面不承接角色，已修正绕序并用向下射线/法线验证；西门旁供热设备挡住直行，已移到门边，保留实体碰撞。旧失败日志与截图归档，未改成通过。

本轮新增独立目录和设计说明，启动前已有文件的SHA256保持一致。旧正式星球、旧预览、主舱、物品栏/HP等成员未提交工作均保留。没有提交或发布Git改动。全项目静态lint仍有原有77错误/9警告、0解析错误、0新增诊断；本场景导入与运行通过，未声称修复旧静态诊断。

## 未覆盖与后续

真人首次寻路、3～5分钟节奏、动机与可读性、全部边界跳法、其他分辨率未测。本轮为本机离线主机，不提供正式多人加入；双真实进程、四人、正式远征/返航/救援、中途加入掉线、其他关卡回归和导出包均未覆盖。

第2层融冰、第3层目标/发现/物件故事、第4层正式远征与主机同步均只留计划。设计方向和实现边界见 `docs/design/planets/planet-00-开放探索第1层.md`。
