# 共振星合作纵切片 01

阶段性交付 / 审阅候选，Godot **4.7.2 Compatibility**，1280×800。独立派生于能源交互样板 01（任务中称 Prototype 01.2）；已验收工程及正式关卡未修改。

## 打开与操作

在 Godot 导入本目录 `project.godot`，首次等待 GLB 导入后按 F6 运行当前 station.tscn 或 F5 运行工程。默认单人。

| 输入 | 操作 |
| --- | --- |
| WASD / Shift | 移动 / 跑动；携带时减速 |
| 鼠标 | 第三人称视角；距离随洞穴和矿车空间约束 |
| F | 面向附近能源核心拾取 |
| X | 找到可落地空间后缓放核心 |
| G | 面向正确插槽安装核心 |
| E | 使用控制端 / 离开控制端 |
| A / D | 在 A 端调整共振频率 |
| W / S | 在 B 端调整锁爪预载 |
| H | 靠近真实护栏时抓扶 |
| C | 取消当前校准或充能，保留已锁定核心 |
| F6 | 复位设备；联机时仅房主允许 |
| F7 / F8 | 建立主机 / 加入本机 127.0.0.1 主机 |
| F9 / M | 开发信息开关 / 静音 |
| Esc / 左键 | 释放 / 捕获鼠标 |
| Tab | 第一人称近景检查开关；默认第三人称 |

沿入口维护通道走到矿车台阶上车。拾取核心后可先 X 放下并再次拾取；靠近插槽 G 安装。单人先在 B 端 W/S 对准稳定带，E 离开后预载锁存 24 秒，再前往 A 端 A/D 连续调谐。双人分别保持 A/B 两端，互相影响的参数持续达标后充能 3.6 秒。设备稳定后不会自动开车。

平台侧沿约 0.46m，不能从侧沿直接走回高台；经入口坡道返回。没有新增跳跃或攀爬系统。控制端占用期间暂停平移，E 可退出。

## 真实联机

在两个独立进程运行本工程，一方 F7，另一方 F8。也可使用引擎命令行参数 `-- --host --port 26749` 与 `-- --join 127.0.0.1 --port 26749`。`--loopback-test` 只绑定本机地址。默认最大房主加三名客户端；本轮验证了两名活动玩家和第三进程晚加入，未验证四人同时游玩。

这是沿用正式工程 peer ownership / RPC / stage action 合约的独立预览适配器，尚未接回正式 Main3D。主机管理唯一核心与设备状态；客户端提交指令、按 20Hz 同步姿态和状态。仅验证本机 ENet，未宣称广域网、丢包、高延迟、主机迁移或完整反作弊通过。

## 模块与来源

- `station_base.gd`：沿用 Prototype 01.1 / 01.2 场景、材质、碰撞和相机边界。
- `scripts/station_player.gd`：沿用现有第三人称移动和相机逻辑，增加携带运动约束与姿态调用。
- `scripts/protagonist_visual.gd`、`scenes/protagonist_visual.tscn`：沿用正式角色可视层。
- `scripts/carry_motion.gd`：受控弹簧、形状扫掠、安全缓放与自由刚体恢复。
- `scripts/interaction_pose.gd`：原角色上半身双骨程序姿态；原有下半身动画保留。
- `scripts/energy_device.gd`：沿用阶段交互接口，管理核心、校准和启动状态机。
- `scripts/resonance_calibration.gd`：单人锁存 / 双人互补参数与稳定进度。
- `scripts/device_motion.gd`：真实环体 pivot、锁爪、能量流、音效和局部光。
- `scripts/coop_session.gd`：独立 ENet 预览适配、权属与同步。
- `scripts/coop_hud.gd`、`calibration_meter.gd`：情境 UI 与可切换调试信息。

动态核心与环体从原 V2.3 网格提取，保留洞穴静态视觉方案；没有替换为灰盒。动态受光是 Compatibility 下的共享近似，未重算实时 GI。

## 测试和交付证据

独立证据目录：`work/gameplay-iterations/20261020-resonance-coop-vertical-slice-01/`（仓库根目录下）。其中 `REVIEW.md`、`TEST-RESULTS.md`、`KNOWN-ISSUES.md`、`delivery/` 包含录像、中文拼版与完整限制。

当前测试脚本：`tests/test_solo.gd`、`test_recovery.gd`、`test_network.gd`、`test_late_join.gd`、`test_performance.gd`。测试用 `--script res://tests/test_solo.gd -- <绝对输出目录>` 启动；双进程调度工具位于新建美术派生目录 `art-source/editable/resonance/codex_cooperation_vertical_slice_01/run_network.py`。联网测试需要允许本机 UDP。

输入重放实际驱动角色行走与物理；少量负向组件测试明确使用临时障碍和核心物理布置，不作为游玩路线证据。自动重放证明流程和状态，不能代替人类对操作手感与趣味性的验收。
