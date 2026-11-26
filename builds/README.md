# builds/ 说明

本目录放可分发/可试玩的构建产物。

## 发布版（给玩家）

`奶龙星三图试玩_单文件/`

- `奶龙星.exe` —— 单文件试玩版（约 166 MB，资源内嵌，不需要安装 Godot）
- `试玩说明.txt` —— 操作、六关表、已知限制

启动方式：双击 `奶龙星.exe`。
直达关卡：`奶龙星.exe --stage=2`（北场）/ `--stage=3`（南场）。

## 开发版（给团队）

`奶龙星三图试玩/`

- `奶龙星.exe` —— Godot 4.7.2 运行时（未嵌入资源）
- `game/` —— 工程、脚本、资源（可直接用编辑器打开调试）
- `启动游戏.bat` —— 以 1600×900 + gl_compatibility 启动
- `试玩说明.txt`

开发版体积更大（约 465 MB），改脚本后不需要重新导出；发布时用
`godot --headless --path game/previews/gulu_planet --export-release "Windows Desktop" <输出路径>` 重新导出单文件版。

## 重新导出的前置条件

- 本机已安装 Godot 导出模板 4.7.2：`%APPDATA%\Godot\export_templates\4.7.2.stable\`
- 导出预设：`game/previews/gulu_planet/export_presets.cfg`（Windows Desktop，embed_pck）
