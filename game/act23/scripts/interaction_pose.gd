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
        var motion: float = sin(float(device.get("clock")) * 2.2) * 0.018
        for side: float in [-1.0, 1.0]:
            targets.append(anchor + Vector3(0.10 * side, 0.09 + motion * side, 0.25))
    elif bool(actor.get("brace_active")):
        pose_kind = "brace"
        desired = 1.0
        var rail: Vector3 = actor.get("brace_target") as Vector3
        # Hands go on top of the grip bar, about shoulder width apart along the
        # rail, and a little closer to the body than a straight-arm reach so the
        # elbows flex. Straight arms at rail height read as "reaching", not
        # "holding on".
        var grip: Vector3 = rail + Vector3.UP * 0.005
        targets.append(grip - actor.global_basis.x * 0.24)
        targets.append(grip + actor.global_basis.x * 0.24)
    elif phase == "free" and core.global_position.distance_to(actor.global_position + Vector3.UP * 0.4) < 1.2:
        if bool(device.call("can_reach", actor, core.global_position + Vector3.UP * 0.48, 1.65)):
            pose_kind = "reach"
            desired = 0.32
            targets.append(core.global_position + Vector3.UP * 0.65 - actor.global_basis.x * 0.15)
            targets.append(core.global_position + Vector3.UP * 0.65 + actor.global_basis.x * 0.15)
    weight = move_toward(weight, desired, delta * (4.0 if desired > weight else 5.0))
    # Tell the locomotion rig that the IK owns the arms this frame. Without this
    # the gait's rotation.x writes landed after the solve and erased it.
    if visual != null:
        visual.set("arms_ik", weight > 0.01)
    hand_error = 0.0
    if targets.is_empty() or weight < 0.005:
        return
    for i: int in range(2):
        _solve(i, targets[i], weight, delta)
    var body: Node3D = visual.get("_body") as Node3D
    if body != null:
        var body_pitch: float = 0.045
        var body_shift: float = 0.0
        if pose_kind == "reach":
            body_pitch = 0.10
        elif pose_kind == "brace":
            # Chest-high rail + short stylised arms: the shoulders have to come
            # over the bar for the hands to touch it. Rotating the whole rig far
            # enough looks like the character is falling over the rail, so most
            # of the reach comes from a small forward shift of the body and only
            # a modest 10-degree pitch.
            body_pitch = -0.18
            body_shift = -0.14
        body.rotation.x = lerpf(body.rotation.x, body_pitch, weight * 0.45)
        body.position.z = lerpf(body.position.z, body_shift, weight * 0.35)

func _solve(index: int, goal: Vector3, blend: float, _delta: float) -> void:
    var arm: Node3D = _arms[index]
    var elbow: Node3D = _elbows[index]
    if arm == null or elbow == null:
        return
    var glove: Node3D = _gloves[index]
    var shoulder: Vector3 = arm.global_position
    var elbow_at: Vector3 = elbow.global_position
    var hand_at: Vector3 = glove.global_position if glove != null else elbow_at
    var length_a: float = (elbow_at - shoulder).length()
    var length_b: float = (hand_at - elbow_at).length()
    if length_a < 0.02 or length_b < 0.02:
        return
    var direction: Vector3 = goal - shoulder
    var distance: float = clampf(direction.length(), 0.04, length_a + length_b - 0.002)
    direction = direction.normalized()
    var side: float = -1.0 if index == 0 else 1.0
    var pole: Vector3 = (actor.global_basis.x * side * 0.7 + Vector3.DOWN * 0.8).normalized()
    pole = (pole - direction * pole.dot(direction)).normalized()
    var along: float = (distance * distance + length_a * length_a - length_b * length_b) / (2.0 * distance)
    var joint: Vector3 = shoulder + direction * along + pole * sqrt(maxf(0.00001, length_a * length_a - along * along))
    # The previous solve assumed each bone rests pointing world DOWN and built its
    # quaternion from that assumption; this rig's bones do not, so the hands
    # stopped ~0.35 m short while the arm rotated anyway. Aim each bone by the
    # world-space delta between its current end direction and the solved one,
    # then convert that delta into the bone's parent space.
    _aim_bone(arm, elbow_at, joint, blend)
    if glove != null:
        elbow_at = elbow.global_position
        hand_at = glove.global_position
        _aim_bone(elbow, hand_at, goal, blend)
        hand_error = maxf(hand_error, glove.global_position.distance_to(goal))

func _aim_bone(bone: Node3D, end_at: Vector3, want_at: Vector3, blend: float) -> void:
    var origin: Vector3 = bone.global_position
    var current: Vector3 = end_at - origin
    var wanted: Vector3 = want_at - origin
    if current.length() < 0.001 or wanted.length() < 0.001:
        return
    var turn: Quaternion = Quaternion(current.normalized(), wanted.normalized())
    if blend < 1.0:
        turn = Quaternion.IDENTITY.slerp(turn, clampf(blend, 0.0, 1.0))
    var parent: Node3D = bone.get_parent() as Node3D
    if parent == null:
        return
    var parent_basis: Basis = parent.global_basis.orthonormalized()
    var local_turn: Quaternion = (parent_basis.inverse() * Basis(turn) * parent_basis).get_rotation_quaternion()
    bone.quaternion = local_turn * bone.quaternion
