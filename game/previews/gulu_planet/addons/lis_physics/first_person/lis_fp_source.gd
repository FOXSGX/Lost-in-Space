class_name LISFirstPersonSource
extends Node3D
## LIS Physics SDK · 第一人称控制器接入协议（方式 B：自定义控制器）
##
## 公共物理 SDK **不依赖**任何特定 PlayerController。归航号、霜烬星、腐墟星、
## 共振星的第一人称控制器可以是不同版本、不同节点树、不同输入封装 ——
## 只要实现本协议的 6 个方法，就能用同一套抓握系统。
##
## 用法（方式 B）：
##   1. 在自定义玩家节点下加一个 LISFirstPersonSource 的子类脚本：
##        class_name MyPlayerSource extends LISFirstPersonSource
##        func fp_camera() -> Camera3D: return $Head/Cam
##        func fp_forward() -> Vector3: return -$Head/Cam.global_transform.basis.z
##        ...
##   2. 把该节点赋给 LISFirstPersonAdapter.source，其余交给 SDK。
##
## 若玩家的节点结构恰好是 CharacterBody3D + Camera3D（方式 A），
## 不需要实现本协议 —— 直接用 LISFirstPersonAdapter 的导出路径即可。
##
## 全部方法都有安全默认实现，未覆写时不会崩溃，只会让抓握失效
## （并通过 is_valid_source() 报告原因）。


## 玩家唯一身份。1 = 主机 / 单人；2..4 = 客户端。
func fp_player_id() -> int:
	return 1


## 第一人称相机。交给抓握器决定"手的目标点"。
func fp_camera() -> Camera3D:
	return null


## 玩家身体碰撞体（Node3D）。用于排除自身、计算推挤接触。
func fp_body() -> Node3D:
	return null


## 世界空间手部锚点。返回 null 表示用相机前方 hold_distance。
func fp_hand_anchor() -> Node3D:
	return null


## 摄像机前向（单位向量）。
func fp_forward() -> Vector3:
	var cam: Camera3D = fp_camera()
	if cam != null and is_instance_valid(cam):
		return -cam.global_transform.basis.z
	return Vector3.FORWARD


## 眼睛位置（世界坐标）。相机为空时退回到自身位置。
func fp_eye_position() -> Vector3:
	var cam: Camera3D = fp_camera()
	if cam != null and is_instance_valid(cam):
		return cam.global_position
	return global_position


## 本地权威（主机 / 单人）还是远端代理（客户端只读镜像）。
func fp_is_authority() -> bool:
	return true


## 玩家最大施力能力（N）。返回 <= 0 表示用 SDK 默认值。
func fp_max_lift_force() -> float:
	return 0.0


## 玩家最大拖推力（N）。返回 <= 0 表示用 SDK 默认值。
func fp_max_drag_force() -> float:
	return 0.0


## 玩家单手姿态辅助上限（N·m）。返回 <= 0 表示用 SDK 默认值。
func fp_palm_torque_max() -> float:
	return 0.0


## 自检：返回空字符串表示可用，否则给出人话原因。
func is_valid_source() -> String:
	if fp_camera() == null:
		return "fp_camera() 返回 null"
	if not is_instance_valid(fp_camera()):
		return "fp_camera() 返回已释放对象"
	if fp_forward().length() < 0.01:
		return "fp_forward() 返回零向量"
	return ""
