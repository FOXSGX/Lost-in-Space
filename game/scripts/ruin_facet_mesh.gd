extends RefCounted
class_name RuinFacetMesh

# 腐墟星感染体专用的低多边形球面。与主角（protagonist_visual.gd）用的是同一套做法：
#   1. 二十面体细分一次，得到 80 个面；
#   2. 法线用球面法线（平滑），顶点色烘一层浅方向的明暗，替掉缺少的环境光遮蔽；
#   3. 顶点顺序按 Godot 的正面规则输出，避免外表面被剔除。
# 感染体的部件全部复用同一份网格，只在实例上用 scale 变形，
# 这样 20 多个部件只有一个 mesh 资源，批次不会被撑爆。
#
# 单独成文件（而不是并进主角那份）是为了不碰其他星球的资源。

static var _cached: ArrayMesh

static func icosphere() -> ArrayMesh:
    if _cached != null:
        return _cached
    var gold := (1.0 + sqrt(5.0)) / 2.0
    var points: Array[Vector3] = [
        Vector3(-1, gold, 0), Vector3(1, gold, 0), Vector3(-1, -gold, 0), Vector3(1, -gold, 0),
        Vector3(0, -1, gold), Vector3(0, 1, gold), Vector3(0, -1, -gold), Vector3(0, 1, -gold),
        Vector3(gold, 0, -1), Vector3(gold, 0, 1), Vector3(-gold, 0, -1), Vector3(-gold, 0, 1),
    ]
    var faces := [
        [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
        [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
        [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
        [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
    ]
    var verts := PackedVector3Array()
    var normals := PackedVector3Array()
    var colors := PackedColorArray()
    for face in faces:
        var a := points[face[0]].normalized()
        var b := points[face[1]].normalized()
        var c := points[face[2]].normalized()
        var ab := (a + b).normalized()
        var bc := (b + c).normalized()
        var ca := (c + a).normalized()
        for triangle in [[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]]:
            var normal: Vector3 = (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).normalized()
            if normal.dot(triangle[0]) < 0.0:
                triangle.reverse()
                normal = -normal
            triangle.reverse()
            var shade := clampf(0.80 + 0.18 * normal.dot(Vector3(-0.45, 0.78, -0.38).normalized()), 0.62, 0.98)
            for vertex in triangle:
                verts.append(vertex)
                normals.append(vertex.normalized())
                colors.append(Color(shade, shade, shade, 1.0))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_COLOR] = colors
    _cached = ArrayMesh.new()
    _cached.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return _cached
