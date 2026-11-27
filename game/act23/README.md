# Act23 独立第一人称入口

这是共振星第二/三幕的独立模块，**不从主游戏 `main_3d.tscn` 进入**。主游戏里的“登陆共振星”仍然走旧的第三人称 `resonance_stage`，本轮不改主流程。

## 在 Godot 里运行

1. 打开 `repo/game/project.godot`。
2. 在文件系统里双击 `act23/act23_entry.tscn`。
3. 按 **F6**（运行当前场景）。

不要按 **F5**：F5 会运行主场景 `main_3d.tscn`，那是主游戏，不是这个第一人称模块。

第一幕对应 `act1/act01.tscn`，同样双击后按 F6。

## 命令行运行

```powershell
# 在 repo 根目录
& "..\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --path game res://act23/act23_entry.tscn
```

## 已做的导入与验证

- `godot --headless --path game --import`：导入通过，Act23 资源已注册。
- `act23/act23_entry.tscn` headless 启动：通过，无脚本/资源错误。
- `act23/tests/act23_first_person_smoke.gd`：10/0，确认：
  - `use_first_person = true`
  - 相机是当前相机，刚性挂在玩家身上
  - 眼高 1.30 m（第一人称高度）
  - 第一人称手部模型 `fp_rig` 存在
- `act1/tests/act1_module_smoke.gd`：24/0（Act1 第一幕独立模块同时可运行）。

## 操作说明

Act23 使用第一人称手部/抓握/搬运逻辑；具体按键以场景 HUD 为准。如果 F6 后看到第三人称，先确认当前场景是 `act23/act23_entry.tscn`，而不是主游戏的 `resonance_stage.tscn`。
