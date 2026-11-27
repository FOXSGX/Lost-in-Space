extends RefCounted

## 腐墟星楼梯统一模板：医院双层梯段槽、实体踏步、中央分隔墙、每层单侧入口。
## 建筑只提供楼梯井范围和外观参数，具体坡道/踏步/门框全部在这里生成。

const ART := preload("res://scripts/ruin_cartoon_art.gd")

const LANE_WIDTH := 2.3
const DIVIDER_WIDTH := 0.12
const STEP_COUNT := 14
const RUN := 10.0
const RAMP_RUN := 10.44
const ENTRY_WIDTH := 2.4

static func stair_mid_x(x0: float, x1: float) -> float:
	return (x0 + x1) * 0.5

static func lane_center(x0: float, x1: float, interval: int) -> float:
	return stair_mid_x(x0, x1) + (-1.21 if interval % 2 == 0 else 1.21)

static func entry_z(level: int, stair_z: float) -> float:
	return (stair_z + 1.0) if level % 2 == 0 else -(stair_z + 1.0)

static func build(host: Node3D, cfg: Dictionary) -> void:
	var levels := int(cfg.get("levels", 3))
	var floor_height := float(cfg.get("floor_height", 3.0))
	var x0 := float(cfg.get("x0", -12.0))
	var x1 := float(cfg.get("x1", -7.0))
	var stair_z := float(cfg.get("stair_z", 5.0))
	var tread_color: Color = cfg.get("tread_color", Color("#aeb6b3"))
	var fill_color: Color = cfg.get("fill_color", Color("#778487"))
	var rail_color: Color = cfg.get("rail_color", Color("#7f8a8c"))
	var floor_color: Color = cfg.get("floor_color", Color("#778487"))
	var mid := stair_mid_x(x0, x1)
	# 每层入口平台：填满门洞到第一级踏步之间的 1 m，避免进门直接踩空。
	for level: int in levels:
		var landing_sign := 1.0 if level % 2 == 0 else -1.0
		var landing_center := Vector3(mid, float(level) * floor_height - 0.09, landing_sign * (stair_z + 0.25))
		ART.block(host, "StairLanding_%d" % level, Vector3(x1 - x0, 0.18, 1.5), landing_center, floor_color, 0.02).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.call("_collider", Vector3(x1 - x0, 0.18, 1.5), landing_center)
	# 没有梯段的槽位整段补地板，直接把井道封死；不再用护栏挡人。
	for level: int in levels:
		var active_lanes: Array[float] = []
		if level > 0:
			active_lanes.append(lane_center(x0, x1, level - 1))
		if level < levels - 1:
			active_lanes.append(lane_center(x0, x1, level))
		for lane_x: float in [lane_center(x0, x1, 0), lane_center(x0, x1, 1)]:
			var used := false
			for active_x: float in active_lanes:
				if absf(lane_x - active_x) < 0.01:
					used = true
					break
			if used:
				continue
			var fill_center := Vector3(lane_x, float(level) * floor_height - 0.09, 0.0)
			ART.block(host, "StairFloorFill_%d_%d" % [level, int(lane_x * 10.0)], Vector3(LANE_WIDTH, 0.18, stair_z * 2.0), fill_center, floor_color, 0.02).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			host.call("_collider", Vector3(LANE_WIDTH, 0.18, stair_z * 2.0), fill_center)
	for interval: int in levels - 1:
		var lower_y := float(interval) * floor_height
		var rises_north := interval % 2 == 0
		var run_length := stair_z * 2.0
		var angle := atan(floor_height / run_length)
		var rotation := angle if rises_north else -angle
		var lane_x := lane_center(x0, x1, interval)
		var center := Vector3(lane_x, lower_y + floor_height * 0.5, 0.0)
		var ramp := ART.block(host, "StairRamp_%d" % interval, Vector3(LANE_WIDTH, 0.18, run_length + 0.44), center, rail_color, 0.04)
		ramp.rotation_degrees.x = rad_to_deg(rotation)
		ramp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.call("_collider", Vector3(LANE_WIDTH, 0.18, run_length + 0.44), center, Vector3(rad_to_deg(rotation), 0.0, 0.0))
		for step: int in STEP_COUNT:
			var fraction := (float(step) + 0.5) / float(STEP_COUNT)
			var z := (stair_z - fraction * stair_z * 2.0) if rises_north else (-stair_z + fraction * stair_z * 2.0)
			var tread_y := lower_y + fraction * floor_height + 0.105
			var fill_height := maxf(tread_y - lower_y, 0.06)
			ART.block(host, "StairStepFill_%d_%d" % [interval, step], Vector3(LANE_WIDTH, fill_height, 0.76), Vector3(lane_x, lower_y + fill_height * 0.5, z), fill_color, 0.02).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ART.block(host, "StairTread_%d_%d" % [interval, step], Vector3(LANE_WIDTH - 0.08, 0.025, 0.72), Vector3(lane_x, tread_y, z), tread_color, 0.02).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 两条梯段槽之间的中央分隔墙，整层高，避免从中间缝掉进井道。
		var divider := ART.block(host, "StairSideWall_%d" % interval, Vector3(DIVIDER_WIDTH, floor_height, stair_z * 2.0), Vector3(mid, lower_y + floor_height * 0.5, 0.0), rail_color, 0.02)
		divider.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.call("_collider", Vector3(DIVIDER_WIDTH, floor_height, stair_z * 2.0), Vector3(mid, lower_y + floor_height * 0.5, 0.0))


## 东墙楼梯门洞：立柱/门楣沿 Z 轴，而不是把学校/超市之前的门框横放在 X 轴上。
static func build_door_frame(host: Node3D, at: Vector3, width: float, height: float, color: Color) -> void:
	var post_w := 0.18
	for side: float in [-1.0, 1.0]:
		var post_center := at + Vector3(0.0, height * 0.5, side * (width * 0.5 + post_w * 0.5))
		var post := ART.block(host, "StairDoorPost_%d_%d_%d" % [int(at.y * 10.0), int(at.z * 10.0), int(side)], Vector3(0.20, height, post_w), post_center, color, 0.03)
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ART.block(host, "StairDoorHeader_%d_%d" % [int(at.y * 10.0), int(at.z * 10.0)], Vector3(0.20, 0.22, width + post_w * 2.0), at + Vector3(0.0, height - 0.11, 0.0), color, 0.03)
	# 门楣灯与地面色条：让楼梯间在长走廊里可辨认，不做悬浮文字。
	ART.block(host, "StairDoorLamp_%d_%d" % [int(at.y * 10.0), int(at.z * 10.0)], Vector3(0.26, 0.12, 0.62), at + Vector3(-0.18, height - 0.02, 0.0), color, 0.02, true, 0.55)
	ART.block(host, "StairDoorMark_%d_%d" % [int(at.y * 10.0), int(at.z * 10.0)], Vector3(0.60, 0.012, width), at + Vector3(-0.32, 0.015, 0.0), color, 0.0)
	ART.block(host, "StairDoorSign_%d_%d" % [int(at.y * 10.0), int(at.z * 10.0)], Vector3(0.10, 0.34, 1.05), at + Vector3(-0.17, height - 0.52, 0.0), color, 0.02, true, 0.35)
	var entry_light := OmniLight3D.new()
	entry_light.light_color = color
	entry_light.light_energy = 0.62
	entry_light.omni_range = 4.2
	entry_light.position = at + Vector3(-0.9, height - 0.55, 0.0)
	entry_light.shadow_enabled = false
	host.add_child(entry_light)
