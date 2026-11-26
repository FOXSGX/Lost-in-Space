extends SceneTree

## MECHANICS-005A-R4 · 第一阶段：只读三维几何复核
##
##   godot --headless --path game --script res://tests/mech005a_r4_geom.gd
##
## 不改任何生产代码。把压板接触面与运动轴转换到**环体局部坐标系**，再算
## 射线与环体（外圆柱 / 内圆柱）的交点，得到：
##   - 到外壁的距离（首次接触位置）
##   - 到内孔的距离（穿模判据）
##   - 当前间隙
## 关键：内外壁都随环心一起移动，判据必须用「近侧内缘」而不是裸内半径。

const SAMPLES: Array[float] = [0.0, 0.087, 0.20, 0.30, 0.396, 0.45, 0.577, 0.58,
	-0.087, -0.396, -0.577]

var app: Node3D
var level: LevelBuilder
var core: CoreRig
var legs: Array[StabilizerRig] = []
var rows: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


## 环体局部坐标系下的射线-圆柱求交。
## 返回沿射线到该圆柱面最近交点的距离（+ 表示在圆柱外，负表示已在圆柱内）。
func ray_cyl(ring: Node3D, origin_w: Vector3, dir_w: Vector3, radius: float) -> float:
	var inv: Transform3D = ring.global_transform.affine_inverse()
	var p: Vector3 = inv * origin_w
	var d: Vector3 = inv.basis * dir_w
	var flat_o: Vector2 = Vector2(p.x, p.z)
	var flat_d: Vector2 = Vector2(d.x, d.z)
	if flat_d.length() < 1.0e-7:
		return 999.0
	flat_d = flat_d.normalized()
	var b: float = flat_o.dot(flat_d)
	var c: float = flat_o.length_squared() - radius * radius
	var disc: float = b * b - c
	if disc < 0.0:
		return 999.0
	var t: float = -b - sqrt(disc)
	return t


## 环心相对核心轴的横移（世界）
func ring_lateral() -> float:
	var rc: Vector3 = core.outer_ring.global_transform.origin
	var cc: Vector3 = core.global_transform.origin
	return Vector2(rc.x - cc.x, rc.z - cc.z).length()


func pad_face(i: int, e: float) -> Vector3:
	return legs[i].to_global(Vector3(
		StabilizerRig.PAD_FACE_LOCAL_X + e * StabilizerRig.STROKE, 7.30, 0.0))


func _run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for _i in range(90):
		await physics_frame
	level = app.get("level") as LevelBuilder
	core = level.core
	legs = level.stabilizers

	print("======== R4 STAGE-1 3D GEOMETRY AUDIT ========")
	print("RIG_RADIUS=%.4f PAD_FACE_X=%.4f STROKE=%.4f" % [
		StabilizerRig.RIG_RADIUS, StabilizerRig.PAD_FACE_LOCAL_X, StabilizerRig.STROKE])
	print("RING_OUTER=%.4f RING_INNER=%.4f  wall=%.4f" % [
		CoreRig.RING_OUTER_RADIUS, CoreRig.RING_INNER_RADIUS,
		CoreRig.RING_OUTER_RADIUS - CoreRig.RING_INNER_RADIUS])
	print("SWING_PER_NET=%.3f SWING_LIMIT=%.3f" % [CoreRig.SWING_PER_NET, CoreRig.SWING_LIMIT])

	# --- 环体轴向厚度（从可见网格读）---
	print("\n[环体可见几何]")
	for node in core.outer_ring.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null:
			continue
		if str(mi.name) in ["RingBody", "TopTrim", "BottomTrim"]:
			var ab: AABB = mi.global_transform * mi.mesh.get_aabb()
			print("  %-12s size=(%.3f %.3f %.3f)" % [mi.name, ab.size.x, ab.size.y, ab.size.z])

	# --- 逐角度：双侧外壁/内孔距离 ---
	print("\n[逐角度 3D 检查]")
	print(" angle    lat    side  ext0_gapOut ext1_gapOut  gapIn@ext1  verdict")
	for a in SAMPLES:
		core.angle = float(a)
		core.omega = 0.0
		core._update_visuals(0.0)
		await physics_frame
		var lat: float = ring_lateral()
		for i in range(2):
			var ax: Vector3 = legs[i].global_transform.basis.x.normalized()
			var p0: Vector3 = pad_face(i, 0.0)
			var p1: Vector3 = pad_face(i, 1.0)
			var g_out0: float = ray_cyl(core.outer_ring, p0, ax, CoreRig.RING_OUTER_RADIUS)
			var g_out1: float = ray_cyl(core.outer_ring, p1, ax, CoreRig.RING_OUTER_RADIUS)
			var g_in1: float = ray_cyl(core.outer_ring, p1, ax, CoreRig.RING_INNER_RADIUS)
			var verdict: String = "?"
			if g_out0 <= 0.0:
				verdict = "!!收回已相交"
			elif g_out1 > 0.0:
				verdict = "够不到"
			elif g_in1 <= 0.0:
				verdict = "!!穿过内孔"
			else:
				verdict = "可压"
			print(" %+.3f  %.3f  %s   %+9.4f  %+9.4f   %+9.4f   %s" % [
				float(a), lat, "WE"[i], g_out0, g_out1, g_in1, verdict])
			rows.append({"angle": float(a), "side": i, "lat": lat,
				"gap_out0": g_out0, "gap_out1": g_out1, "gap_in1": g_in1,
				"verdict": verdict})

	# --- 关键：壁厚是否随横移变化 ---
	print("\n[壁厚不变量检验]")
	for a in [0.0, 0.087, 0.396, 0.577]:
		core.angle = float(a)
		core.omega = 0.0
		core._update_visuals(0.0)
		await physics_frame
		var ax: Vector3 = legs[0].global_transform.basis.x.normalized()
		var p: Vector3 = pad_face(0, 0.5)
		var t_out: float = ray_cyl(core.outer_ring, p, ax, CoreRig.RING_OUTER_RADIUS)
		var t_in: float = ray_cyl(core.outer_ring, p, ax, CoreRig.RING_INNER_RADIUS)
		print("  angle=%+.3f  沿射线壁厚 = %.4f m (应与角度无关)" % [float(a), t_out - t_in])

	core.angle = 0.0
	core._update_visuals(0.0)
	print("\nR4_GEOM_AUDIT_DONE rows=%d" % rows.size())
	quit(0)
