extends Node3D
## Present by KeJi
## Date: 2026-06-08
##
## PathLine3D — 3D 路径线条（ImmediateMesh）


func set_points(points: Array) -> void:
	# 清除旧绘制
	for c in get_children():
		c.queue_free()

	if points.size() < 2:
		return

	# 用 MeshInstance3D + ImmediateMesh 画线段
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	mi.material_override = StandardMaterial3D.new()
	mi.material_override.albedo_color = Color(1.0, 0.82, 0.25)  # 黄色
	mi.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	im.surface_begin(Mesh.PRIMITIVE_LINES)
	const SCALE := 16.0
	for p in points:
		var pos := Vector3(
			p.get("x", 0.0) * SCALE,
			p.get("y", 0.0) * SCALE,
			p.get("z", 0.0) * SCALE
		)
		im.surface_add_vertex(pos)
	im.surface_end()

	add_child(mi)
