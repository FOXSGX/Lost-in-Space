# TESTING — 咕噜星第一人称试玩预览

最后更新：2026-10-28 20:05（GMT+8）

## 0. 环境与启动

- Windows 10.0.26200 x64
- Godot 4.7.2 stable（`ed1daf0bf`），GL Compatibility
- 工程：`C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet\project.godot`
- 窗口：1280×800

```powershell
$godot = "C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
$preview = "C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet"

# 正常试玩
& $godot --path $preview

# 自动运行验证（有窗口，鼠标观察也测试）
& $godot --path $preview -- --selftest

# 无窗口验证（跳过鼠标观察）
& $godot --headless --path $preview -- --selftest

# 截图（有窗口）
& $godot --path $preview -- --shots
```

## 1. 实际通过的项目

窗口模式 `--selftest`（2026-10-28）：

```
GULU SELFTEST SUMMARY passes=16 failures=0
```

覆盖：

| 项目 | 实测 |
| --- | --- |
| 默认第一人称 | 通过 |
| 相机眼睛高度 | 1.65 m（误差 < 0.06） |
| FOV | 62° |
| 占位咕噜首屏可见 | 屏幕 `(406.6, 333.2)` |
| 占位燃料首屏可见 | 屏幕 `(793.7, 338.8)` |
| WASD 前进 0.9 s | 位移 5.22 m |
| 鼠标观察 | 通过（yaw 改变 > 0.15） |
| 俯仰限制 | clamp 到 `0.300`（上限） |
| 场景碰撞 | 内墙前停在 `x=11.32` |
| Tab 切第三人称 | 通过；角色身体可见 |
| Tab 回第一人称 | 通过；本机身体隐藏 |
| R 重置 | 回到 `(-8, 0.02, 0)`；恢复第一人称 |
| F3 调试面板 | 通过（渲染出真实数值） |

headless `--selftest`：`passes=14 failures=0`，鼠标观察与俯仰测试按预期跳过
（headless 无真实鼠标捕获）。

启动 360 帧：`--quit-after 360` 无脚本错误/警告输出。

## 2. 截图

`docs/screenshots/`：

| 文件 | 内容 |
| --- | --- |
| `01_first_person.png` | 默认第一人称；左侧占位咕噜、右侧占位燃料、HUD 与准星 |
| `02_third_person.png` | Tab 切到第三人称；同一灰盒场地与角色外观 |

截图由实际运行窗口通过 `get_viewport().get_texture().save_png()` 生成，1280×800。

## 3. 尚未验证

- **真人手动试玩**：鼠标/键盘手感、镜头高度、转向舒适度未由真人验收。
- **跳跃**：复用的 `station_player.gd` 本身没有跳跃逻辑，本轮不新增；因此“跳跃”未验证。
- 咕噜发现/转向/靠近/停靠：本轮未实现。
- 麦克风、声音吸引、叼走/取回燃料：本轮未实现。
- 联网同步：本轮无联网网络代码；没有同步可测。
- 正式模型/动画/音效：占位灰盒，不代表最终表现。

## 4. 已知风险

- 本地 `origin/main` 是旧 2D `3969511`；当前 GitHub main 是 3D `42519ff`。
  `git fetch` 连接重置，无法把分支基到最新 main；预览文件从 42519ff raw 复制，工程自包含。
  网络恢复后需 rebase 到最新 main 再提交。
- 第三人称只用于检查：镜头被 `clamp_cave_camera_position()` 限制在灰盒内；
  角色很近时 `camera_guard` 可能隐藏身体（与原预览行为一致）。
