# 训练室墙面图示

`generate_posters.py` 为可编辑原稿，使用 Pillow 绘制原创几何图形与中文说明，没有使用外部插画。运行：

```powershell
python art-source/editable/training-wall-posters/generate_posters.py
```

预览输出至本目录 `previews/`，游戏资源输出至 `game/assets/training-wall-posters/`。共六张：装配、短跳、喷气、充气、跨越、返回主舱。图像尺寸 1200×720，训练室内显示为固定墙面印刷板，不随镜头转动。

生成时使用 Windows 本机微软雅黑字体栅格化中文，不随项目分发字体文件。修改喷气数值时，应同步图中 0.5 秒、0.3 秒、1 秒和 2% 的说明。
