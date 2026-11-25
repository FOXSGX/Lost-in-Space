# 霜烬星0.4实现与验证索引

新版代码：`previews/frost_station/`。独立场景：`res://previews/frost_station/adventure.tscn`。用户可双击本目录 `play.cmd`，也可通过主舱“新航程→出舱”进入。

## 接入边界

- `frost_first_playable/adventure.gd`仅增加世界、物品栏与玩家三个构造工厂，默认仍加载旧0.3，保留其独立测试。
- 新版继承旧冒险会话、融冰和骨脊遗迹，重建紧凑六栋站区，新增吸推、食品收藏与运输车模块。
- `campaign_travel_3d.gd`只把地表构造路径切到新版；现有主舱保存、航线与任务能源交接沿用。
- `crew_items_3d.gd`补四类物件名称/图标与回舱后物品处理，保留其他未提交工作；吸推器的作用逻辑留在霜烬星模块。
- 物资、车货、队友状态、融冰、动力由主机结算；快照schema=4。旧几何快照先备份再保留任务进度导入，不套用旧冰块索引。

## 实现入口

| 文件 | 责任 |
| --- | --- |
| world.gd | 六栋建筑、普通楼梯与二层、静态骨架、标牌、动力灯、可见保险柜/收藏展示、三厅连接 |
| adventure.gd | 主机动作、吸推目标/推出、吃食与收藏结果、供暖、快照、主舱接入 |
| items.gd | 既有两格手持与双装备栏适配，新物件模型/碰撞、食用与图标 |
| player.gd | 沿用第一人称与步行推进，在车上由座位跟随而非独立移动 |
| cart.gd | 主机驾驶、碰撞与低台沿通过、乘员安全上下车、8件货斗与状态复制 |

## 证据索引

`work/gameplay-iterations/20261028-frost-station-implementation/` 保存原始运行日志、图形截图和验证回执。最终结果与限制见该目录 `05-test-report.md`。

源场景有图形运行和命名输入验证；试玩包采用本机已有Godot4.7.2运行器与导出PCK，已脱离工程目录启动验证。本机无专用Windows导出模板，因此不称为专用模板发布构建。整体仍为可玩低模原型，未进行真人四人节奏、公网延迟和最终美术验收。

## 美术层（2026-11-24）

`previews/frost_station/frost_art.gd` 按共振星模板接管视觉：五族 shader（`game/shaders/frost_panel|rock|snow|ice|bone.gdshader`）、环境与三光位、每栋门斗/灯具/基座/檐雪/冰锥、雪堆与裂隙、冰晶簇与飘雪，并把家具原色收进站区色板。只改材质与无碰撞装饰，碰撞、交互锚点、物品/车辆/融冰判定不动；`FROST_ART=0` 可关闭用于同机位对照。

机位与性能证据：`previews/frost_station/art_capture.gd`、`art_bench.gd`、`shader_check.gd`；规则见[霜烬星美术说明](../../docs/design/planets/planet-00-霜烬星美术说明.md)，本轮结论见[美术迭代记录](../../work/art-iterations/20261124-frost-station-art/README.md)。现状为视觉 CONDITIONAL GO，性能 P50 +25%，仍需 Draw Call 合并与真人试玩。
