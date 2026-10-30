extends "res://tests/input_driver.gd"

# Focused test of the shared replay driver's shutdown, not a gameplay pass.
func run() -> void:
    await boot()
    check(is_instance_valid(scene) and is_instance_valid(device),"共享重放驱动器创建真实场景后正常释放")
    await finish()
