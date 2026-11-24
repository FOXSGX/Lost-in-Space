# 标准机位模板（怎么出四机位图）

`standard_shots.gd` + `standard_shots.tscn` 会自动按目标包围盒取景，输出：

```
A_wide.png            整体空间与主焦点（FOV 50）
B_player_eye.png      第一人称玩家视角（眼高 1.60，FOV 66）
C_interaction.png     核心交互物近景（1.2–1.8 m，FOV 44）
D_threequarter.png    主体与自然的关系（左前 45°，FOV 52）
E_closeup_1..4.png   1–2 m 对角特写（FOV 42）
```

## 用法

1. 把 `standard_shots.gd` / `.tscn` 放进你的工程；
2. 把英雄区根节点命名为 **`Hero`**（或在脚本里改 `TARGET_NAME`）；
3. 运行：

```powershell
Godot_v4.7.2-stable_win64_console.exe --path <你的工程> --resolution 1920x1080 `
  res://tests/standard_shots.tscn -- --out="C:/shots/<星球>"
```

## 为什么要用模板而不是手动摆机位

- 星球之间可以**横向比较**（同一套取景规则）；
- 改版前后可以**严格对照**（不能靠改相机"制造提升"）；
- 新人不会漏拍 C（交互近景）和 E（材质特写）——这两张是最容易偷懒的。
