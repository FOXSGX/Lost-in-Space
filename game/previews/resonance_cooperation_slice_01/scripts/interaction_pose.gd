extends RefCounted

# Two-bone analytic arms over the existing ranger shoulder/elbow pivots. The
# original visual script still owns locomotion and the lower-body gait.
var actor: CharacterBody3D
var visual: Node3D
var weight: float = 0.0
var hand_error: float = 0.0
var pose_kind: String = "idle"
var _arms: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _gloves: Array[Node3D] = []

func setup(player: CharacterBody3D, model: Node3D) -> void:
    actor = player
    visual = model
    for side: String in ["left", "right"]:
        _arms.append(visual.get("_" + side + "_arm") as Node3D)
        _elbows.append(visual.get("_" + side + "_elbow") as Node3D)
        _gloves.append(visual.find_child(side.capitalize() + "Glove", true, false) as Node3D)

func tick(delta: float, device: Node3D) -> void:
    var targets: Array[Vector3] = []
    var desired: float = 0.0
    pose_kind = "idle"
    var core: RigidBody3D = device.get("core") as RigidBody3D
    var phase: String = str(device.get("phase"))
    var carrier: int = int(device.get("carrier_id"))
    if carrier == int(actor.get("peer_id")) and phase in ["held", "placing", "inserting"]:
        pose_kind = "carry" if phase == "held" else phase
        desired = 1.0
        if phase == "inserting":
            desired = 1.0 - smoothstep(0.35, 0.85, float(device.get("elapsed")))
        for side: float in [-1.0, 1.0]:
            targets.append(core.global_position + Vector3.UP * 0.62 + core.global_basis.x * side * 0.16 + core.global_basis.z * 0.235)
    elif str(actor.get("operating_role")) != "":
        pose_kind = "control"
        desired = 0.95
        var anchor: Vector3 = device.call("control_anchor", str(actor.get("operating_role"))) as Vector3
        for side: float in [-1.0, 1.0]:
            targets.append(anchor + Vector3(0.10 * side, 0.09, 0.25))
    elif bool(actor.get("brace_active")):
        pose_kind = "brace"
        desired = 0.95
        var rail: Vector3 = actor.get("brace_target") as Vector3
        targets.append(rail - actor.global_basis.x * 0.12)
        targets.append(rail + actor.global_basis.x * 0.12)
    elif phase == "free" and core.global_position.distance_to(actor.global_position + Vector3.UP * 0.4) < 1.2:
        if bool(device.call("can_reach", actor, core.global_position + Vector3.UP * 0.48, 1.65)):
            pose_kind = "reach"
            desired = 0.32
            targets.append(core.global_position + Vector3.UP * 0.65 - actor.global_basis.x * 0.15)
            targets.append(core.global_position + Vector3.UP * 0.65 + actor.global_basis.x * 0.15)
    weight = move_toward(weight, desired, delta * (4.0 if desired > weight else 5.0))
    hand_error = 0.0
    if targets.is_empty() or weight < 0.005:
        return
    for i: int in range(2):
        _solve(i, targets[i], weight, delta)
    var body: Node3D = visual.get("_body") as Node3D
    if body != null:
        body.rotation.x = lerpf(body.rotation.x, 0.10 if pose_kind == "reach" else 0.045, weight * 0.45)

func _solve(index: int, goal: Vector3, blend: float, _delta: float) -> void:
    var arm: Node3D = _arms[index]
    var elbow: Node3D = _elbows[index]
    if arm == null or elbow == null:
        return
    var shoulder: Vector3 = arm.global_position
    var length_a: float = elbow.position.length() * visual.global_basis.get_scale().y
    var length_b: float = 0.27 * visual.global_basis.get_scale().y
    var direction: Vector3 = goal - shoulder
    var distance: float = clampf(direction.length(), 0.04, length_a + length_b - 0.003)
    direction = direction.normalized()
    var side: float = -1.0 if index == 0 else 1.0
    var pole: Vector3 = (actor.global_basis.x * side * 0.7 + Vector3.DOWN * 0.8).normalized()
    pole = (pole - direction * pole.dot(direction)).normalized()
    var along: float = (distance * distance + length_a * length_a - length_b * length_b) / (2.0 * distance)
    var joint: Vector3 = shoulder + direction * along + pole * sqrt(maxf(0.00001, length_a * length_a - along * along))
    var upper_local: Vector3 = ((arm.get_parent() as Node3D).global_basis.inverse() * (joint - shoulder)).normalized()
    var upper: Quaternion = Quaternion(Vector3.DOWN, upper_local)
    # Locomotion rewrites only the original x axis before this blend.
    arm.quaternion = arm.quaternion.slerp(upper, clampf(blend, 0.0, 1.0))
    var lower_local: Vector3 = (arm.global_basis.inverse() * (goal - elbow.global_position)).normalized()
    elbow.quaternion = elbow.quaternion.slerp(Quaternion(Vector3.DOWN, lower_local), clampf(blend, 0.0, 1.0))
    if _gloves[index] != null:
        hand_error = maxf(hand_error, _gloves[index].global_position.distance_to(goal))
