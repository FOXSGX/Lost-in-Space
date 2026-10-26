# HANDOFF · Resonance 03.1 绞盘轨道修复

**日期：** 2026-10-20
**范围：** 只改 `game/previews/resonance_03_winch_prototype/`、`work/gameplay-iterations/20261020-resonance-03-1-playability/`、
`builds/Resonance_03_Winch_v0.1_20261020/` 和一份基线快照。没有改 Resonance 02，没有接正式关卡，没有提交/推送。

## 现在是什么状态

- 单人第三人称可以从场景入口走到断裂轨道、挂前端/中段吊耳、回绞盘收放、看轨道实际移动、
  过冲到负角、按 S 放线、W 追回、走到锁定座插销、完成修复、R 重置再来一次。
- 自动回归 `tests/probe_rig.gd`：**32/32**。
- 三段玩家视角演示（Movie Maker 实机渲染 + ffmpeg 转 MP4）：完整通关、错误吊耳恢复、过冲恢复，均完成并锁定。
- Windows 包：官方 Godot 4.7.2 运行器 + PCK + `启动_Resonance_03_Winch.cmd`；
  直接运行 exe 和通过 `.cmd` 运行均验证 `--demo=full` 返回 `completed=true`。
- 帧时间：窗口化 P50 6.94 ms / P95 8.40 ms / P99 9.09 ms，27.4 秒 3797 帧里 2 帧 >16.7 ms、
  1 帧 35.4 ms，无 >50 ms。截图里的 10 FPS 是 PNG 保存 + 首次管线编译造成的瞬时读数，详见 `PERFORMANCE.md`。
- **真人试玩尚未进行。** 不要对外说“已被证明有趣”。

## 关键路径

| 内容 | 路径 |
| --- | --- |
| 工程 | `game/previews/resonance_03_winch_prototype/` |
| 操作说明（玩家） | `game/previews/resonance_03_winch_prototype/README_试玩说明.txt` |
| 已知问题 | `game/previews/resonance_03_winch_prototype/KNOWN-ISSUES.md` |
| 性能报告 | `game/previews/resonance_03_winch_prototype/PERFORMANCE.md` |
| 整合接口 | `game/previews/resonance_03_winch_prototype/docs/integration.md` |
| 双人预留 | `game/previews/resonance_03_winch_prototype/docs/coop-future.md` |
| 本轮记录 | `work/gameplay-iterations/20261020-resonance-03-1-playability/REVIEW.md` |
| 测试报告 | `work/gameplay-iterations/20261020-resonance-03-1-playability/05-test-report.md` |
| 录像 | `work/gameplay-iterations/20261020-resonance-03-1-playability/demo/{full,wrong_eye,overshoot}.mp4` |
| 玩家视角截图 | `work/gameplay-iterations/20261020-resonance-03-1-playability/audit/player-views-final/` |
| 帧数据 | `work/gameplay-iterations/20261020-resonance-03-1-playability/perf/` |
| 试玩包 | `builds/Resonance_03_Winch_v0.1_20261020/` |
| 改动前快照 | `backups/resonance-03-winch-20261020-baseline/` |

## 怎么跑

```powershell
# 编辑器运行
.\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path .\game\previews\resonance_03_winch_prototype

# 回归
.\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 `
  --path .\game\previews\resonance_03_winch_prototype `
  --script res://tests/probe_rig.gd -- <outdir>

# 性能
... --script res://tests/perf_probe.gd -- <outdir> final_windowed
... --headless --script res://tests/perf_probe.gd -- <outdir> final_headless

# 演示 / 录像
... --write-movie <out.avi> --fixed-fps 30 -- --demo=full
```

试玩包：双击 `启动_Resonance_03_Winch.cmd`；SmartScreen 提示时选“更多信息 → 仍要运行”。

## 本轮最主要的改动

1. **HUD 拆成正常/调试两档（F3）。** 正常模式只给目标、状态、张力条、操作提示；
   角度/缆绳米数/端部误差/fps 收进调试。
2. **第三人称可玩性**：出生点移到能同时看到绞盘和轨道的位置；控制台接管时镜头右肩偏移；
   走近吊耳有高亮环和 3D 标签；吊耳/锁定销/复位线/绞盘都有世界内标识。
3. **吊耳不再是“正确/错误”提示**：改成“前端吊耳（轨道前端）”“中段吊耳（靠近铰链）”，
   错误反馈由机械现象承担（张力过载、离合器打滑、轨道不动、声音变化、建议换另一端）。
4. **试错/补救**：Q 拆缆、E 离开控制台、S 放线、W 追回、锁定座拒绝时给原因、R 任意时刻重置。
5. **视觉**：测试舱重做为面板墙、顶棚桁架、吊灯、地面拼板、走道、货架/缆盘/工具车/管线；
   绞盘增加电机、齿轮箱、机柜、张力表、三色灯、警示灯、护罩；轨道增加侧梁、配重、铰链盖、
   对齐销、接收架靶线；去掉发白的洞穴 kit 和悬空晶体。
6. **音频**：张力越大绞盘音高越高，叠加低频吃力层；打滑时节流播放金属提示音；拆缆/重置清张力。
7. **验证**：新增 `perf_probe.gd`、`demo_driver.gd`、`capture_player.gd`；重写 `probe_rig.gd` 的
   演示/恢复路径；导出 PCK 并验证包内启动。

## 已知的坑（接手先看）

- 轨道的 `_point_at()` 必须是 `to_global(Basis(axis, angle - hinge_angle) * local)`；
  写成 `Basis(axis, angle)` 会把铰链角转两次，力臂算错一半，卡滞永远拉不开。
- 远端吊耳在 15° 时力臂约 1.42 m；卡滞 4000 N·m 是跟着这个几何调的。改轨道尺寸/滑轮位置必须重调。
- 挂缆必须 `feed_to(distance + 0.45)`，否则挂上就 105% 张力。
- W/S 必须轮询 `Input.is_action_pressed`；只监听按下事件会导致“按住没反应”。
- 交互选择：未挂缆时吊耳优先；挂缆后按最近目标（锁定座/控制台）。固定优先级会让锁定座被吊耳抢。
- 接管绞盘后移动被锁定，按 E 离开；演示脚本也必须先离开再走。
- 正常 HUD 不显示角度；不要为了“看得清”把角度数字加回正常模式。
- 测试沙箱 `user://` 不可写，着色器缓存被禁用；冷启动数据是最坏情况。
- 窗口标题 `(DEBUG)`、181 MB 体积是“官方运行器代替导出模板”的代价，不是游戏内容。

## 下一步

1. **用户单人试玩**（最高优先）：记录是否先试中段吊耳、是否理解打滑、松手时机、过冲后是否知道按 S、
   是否发现 E 离开控制台、是否觉得往返太多。填写 `06-feedback.md`。
2. 若试玩通过，再讨论接入正式共振星；接口和检查清单见 `docs/integration.md`。
3. 视觉 pass 留在正式矿洞美术之后；本轮的程序化舱室只用于独立试玩。
4. 双人只是 `docs/coop-future.md` 的未验证方向，不要先写网络代码。
5. 等 Resonance 02 质量返工通过验收后再讨论整合顺序。

## 不要做

- 不要修改 `game/previews/resonance_02_quality_rework/` 或另一个代理的 `work/` 输出。
- 不要修改 `game/scripts/resonance_stage.gd`、`game/scenes/resonance_stage.tscn` 来“顺便接入”。
- 不要提交/推送；本轮按要求保持工作区改动未入库。
- 不要把脚本演示当成真人试玩证据。
