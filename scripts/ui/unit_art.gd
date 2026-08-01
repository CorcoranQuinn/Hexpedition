class_name UnitArt
extends RefCounted
## Procedural leader icons and idle motion for character select.


static func build_leader_icon(type_id: String, team_color: Color) -> Node2D:
	var root := Node2D.new()
	root.name = "LeaderIcon"

	var shadow := Polygon2D.new()
	shadow.polygon = _ellipse_points(16.0, 10.0)
	shadow.color = Color(0.0, 0.0, 0.0, 0.25)
	shadow.position = Vector2(0, 10)
	root.add_child(shadow)

	var body := Polygon2D.new()
	body.name = "Body"
	body.polygon = _triangle_points(18.0)
	body.color = team_color
	root.add_child(body)

	var accent := Node2D.new()
	accent.name = "Accent"
	root.add_child(accent)
	match type_id:
		"sentinel_leader":
			_build_sentinel_accent(accent)
		"veil_leader":
			_build_veil_accent(accent)
		"ember_leader":
			_build_ember_accent(accent)
		"swarm_leader":
			_build_swarm_accent(accent)
		_:
			_poly(accent, _ring_points(6.0, 8), Color(1, 1, 1, 0.35))

	return root


static func build_oriented_board_unit(
	type_id: String,
	team_color: Color,
	is_leader: bool,
	is_minion: bool,
) -> OrientedVisual:
	var visual := OrientedVisual.new()
	visual.name = "OrientedBody"
	var layers: Array[Node2D] = []
	for i in CameraOrientation.ORIENTATION_COUNT:
		var layer := Node2D.new()
		layer.name = "Orientation%d" % i
		var body := _build_board_figure(type_id, team_color, is_leader, is_minion)
		CameraOrientation.apply_orientation_pose(body, i)
		layer.add_child(body)
		layers.append(layer)
	visual.setup(layers)
	return visual


static func _build_board_figure(
	type_id: String,
	team_color: Color,
	is_leader: bool,
	is_minion: bool,
) -> Node2D:
	var root := Node2D.new()
	var scale_factor: float = 0.65 if is_minion else (1.3 if is_leader else 1.0)
	var radius: float = 14.0 * scale_factor

	var shadow := Polygon2D.new()
	shadow.polygon = _ellipse_points(16.0 * scale_factor, 10.0 * scale_factor)
	shadow.color = Color(0.0, 0.0, 0.0, 0.25)
	shadow.position = Vector2(0, 9.0 * scale_factor)
	root.add_child(shadow)

	var body := Polygon2D.new()
	body.name = "Body"
	body.polygon = _triangle_points(radius)
	body.color = team_color
	root.add_child(body)

	var accent := Node2D.new()
	root.add_child(accent)
	match type_id:
		"sentinel_leader", "sentinel_follower":
			_build_sentinel_accent(accent)
		"veil_leader", "veil_follower":
			_build_veil_accent(accent)
		"ember_leader", "ember_follower":
			_build_ember_accent(accent)
		"swarm_leader", "swarm_follower", "swarm_minion":
			_build_swarm_accent(accent)
		_:
			_poly(accent, _ring_points(6.0, 8), Color(1, 1, 1, 0.35))

	if is_minion:
		root.scale = Vector2(0.92, 0.92)
	return root


static func attach_idle_animation(node: Node2D) -> void:
	var body: Node2D = node.get_node_or_null("Body") as Node2D
	if body == null:
		body = node
	var tween := node.create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(body, "position:y", -4.0, 0.85)
	tween.tween_property(body, "position:y", 2.0, 0.85)


static func _build_sentinel_accent(root: Node2D) -> void:
	_poly(root, PackedVector2Array([
		Vector2(-8, -2), Vector2(-8, 8), Vector2(8, 8), Vector2(8, -2),
		Vector2(4, -2), Vector2(0, -10), Vector2(-4, -2),
	]), Color(0.82, 0.88, 0.96))
	_line(root, PackedVector2Array([Vector2(-5, 0), Vector2(5, 0)]), Color(0.35, 0.45, 0.62), 2.0)


static func _build_veil_accent(root: Node2D) -> void:
	_poly(root, _ring_points(9.0, 12), Color(0.72, 0.58, 0.92, 0.45))
	_poly(root, _ellipse_points(5.0, 7.0), Color(0.92, 0.88, 1.0))
	_poly(root, PackedVector2Array([
		Vector2(-2, -1), Vector2(2, -1), Vector2(1, 2), Vector2(-1, 2),
	]), Color(0.42, 0.32, 0.58))


static func _build_ember_accent(root: Node2D) -> void:
	_poly(root, PackedVector2Array([
		Vector2(0, -14), Vector2(6, 2), Vector2(0, 8), Vector2(-6, 2),
	]), Color(1.0, 0.72, 0.28))
	_poly(root, PackedVector2Array([
		Vector2(0, -10), Vector2(3, 0), Vector2(0, 4), Vector2(-3, 0),
	]), Color(1.0, 0.92, 0.55))


static func _build_swarm_accent(root: Node2D) -> void:
	for offset in [Vector2(-7, -2), Vector2(0, -6), Vector2(7, -2)]:
		_poly(root, _ellipse_points(4.0, 5.0), Color(0.78, 0.95, 0.55), offset)
	_poly(root, PackedVector2Array([
		Vector2(-10, 6), Vector2(0, 12), Vector2(10, 6),
	]), Color(0.36, 0.52, 0.24))


static func _triangle_points(radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -radius),
		Vector2(radius * 0.86, radius * 0.72),
		Vector2(-radius * 0.86, radius * 0.72),
	])


static func _ellipse_points(radius_x: float, radius_y: float, segments: int = 16) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i in segments:
		var angle: float = TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return points


static func _ring_points(inner: float, outer: float, segments: int = 16) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i in segments + 1:
		var angle: float = TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle) * outer, sin(angle) * outer))
	for i in segments + 1:
		var angle: float = TAU * float(segments - i) / float(segments)
		points.append(Vector2(cos(angle) * inner, sin(angle) * inner))
	return points


static func _poly(parent: Node2D, points: PackedVector2Array, color: Color, offset: Vector2 = Vector2.ZERO) -> void:
	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = color
	poly.position = offset
	parent.add_child(poly)


static func _line(parent: Node2D, points: PackedVector2Array, color: Color, width: float) -> void:
	var line := Line2D.new()
	line.points = points
	line.default_color = color
	line.width = width
	line.antialiased = true
	parent.add_child(line)
