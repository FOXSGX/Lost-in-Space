extends "res://tests/input_driver.gd"

func run() -> void:
    await boot()
    var hud: CanvasLayer=scene.get("hud") as CanvasLayer
    hud.hide()
    var before: float=float(hud.get("_age"))
    await frames(900)
    check(is_equal_approx(float(hud.get("_age")),before),"大厅隐藏 HUD 时首次指导不消耗显示时间")
    hud.show();await frames(10)
    check(float(hud.get("_age"))>before,"进入任务后指导计时开始")
    check((hud.get("help") as Label).visible,"长时间等待后首次操作提示仍显示")
    await finish()
