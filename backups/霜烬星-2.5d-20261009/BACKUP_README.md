# 霜烬星 2.5D 备份

这是 2026-10-09 进行真实 3D 架构迁移前的完整 `game/` 目录备份。

- 原运行入口：`scenes/main.tscn`
- 原技术路线：`Node2D`、`CharacterBody2D`、`Camera2D` 和程序化伪 2.5D 障碍
- 当前新入口：主工程中的 `scenes/main_3d.tscn`

需要恢复旧版本时，可将本目录内容复制回 `game/`，并把 `project.godot` 的 `run/main_scene` 改回 `res://scenes/main.tscn`。
