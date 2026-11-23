extends SceneTree

## Verifies that every GLB the Act 4 level actually loads is a valid imported
## PackedScene before shipping.
##
## The old version checked `res://assets/resonance/models/resonance_module_hero.glb`,
## an asset from an early art direction that no longer exists in the project, so
## the probe was permanently red (3/3 failures) and told nobody anything.
## The list below mirrors `scripts/act4/level_builder.gd` (CRYSTAL_DIR / ROCK_DIR).

const CRYSTAL_DIR := "res://assets/crystals/"
const ROCK_DIR := "res://assets/rocks/"

const REQUIRED: Array[String] = [
	CRYSTAL_DIR + "res_crys_blade_cyan_a_lod0.glb",
	CRYSTAL_DIR + "res_crys_blade_violet_a_lod0.glb",
	CRYSTAL_DIR + "res_crys_cluster_env02_a_lod0.glb",
	CRYSTAL_DIR + "res_crys_cluster_mid_a_lod0.glb",
	CRYSTAL_DIR + "res_crys_cluster_west_a_lod0.glb",
	ROCK_DIR + "res_rock_thrust_a_lod0.glb",
	ROCK_DIR + "res_rock_shelf_a_lod0.glb",
	ROCK_DIR + "res_rock_cap_a_lod0.glb",
	ROCK_DIR + "res_rock_knuckle_a_lod0.glb",
	ROCK_DIR + "res_rock_apron_a_lod0.glb",
	ROCK_DIR + "res_rock_tongue_a_lod0.glb",
	ROCK_DIR + "res_rock_lip_a_lod0.glb",
	ROCK_DIR + "res_rock_fissure_host_a_lod0.glb",
	ROCK_DIR + "res_rock_flank_a_lod0.glb",
]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func run() -> void:
	print("RESONANCE_MODEL_IMPORT: start")
	for path: String in REQUIRED:
		check(ResourceLoader.exists(path), "资源不存在：%s" % path)
		if not ResourceLoader.exists(path):
			continue
		var loaded: Resource = ResourceLoader.load(path)
		check(loaded is PackedScene, "没有导入为 PackedScene：%s" % path)
		if not (loaded is PackedScene):
			continue
		var instance: Node = (loaded as PackedScene).instantiate()
		check(instance != null, "实例化失败：%s" % path)
		if instance == null:
			continue
		root.add_child(instance)
		var meshes: Array[Node] = instance.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() > 0, "网格为空：%s" % path)
		var tris: int = 0
		for node: Node in meshes:
			var mi: MeshInstance3D = node as MeshInstance3D
			if mi != null and mi.mesh != null:
				for surface: int in range(mi.mesh.get_surface_count()):
					var arrays: Array = mi.mesh.surface_get_arrays(surface)
					if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
						tris += int((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()) / 3
		print("MODEL ", path.get_file(), " meshes=", meshes.size(), " tris=", tris)
		check(tris > 0, "网格没有三角面：%s" % path)
		instance.queue_free()
	await process_frame
	print("RESONANCE_MODEL_IMPORT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
