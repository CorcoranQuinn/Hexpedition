class_name TileArt
extends RefCounted
## Procedural terrain markers drawn on top of each hex.
##
## Everything is built from primitives so the project stays asset-free. Art is
## parented to the tile's upright anchor, which cancels the board's isometric
## squash and yaw, so these read as features standing on the ground plane.


static func build(type_id: String, team_color: Color = Color.WHITE) -> Node2D:
	var root := Node2D.new()
	root.name = "Decor"
	match type_id:
		"plain":
			_build_plain(root)
		"rough":
			_build_rough(root)
		"mountain":
			_build_mountain(root)
		"vitality":
			_build_vitality(root)
		"sentinel_bastion":
			_build_bastion(root, team_color)
		"veil_mirror":
			_build_mirror(root, team_color)
		"ember_forge":
			_build_forge(root, team_color)
		"swarm_hive":
			_build_hive(root, team_color)
	return root


# --- Neutral terrain ---

## Sparse grass blades, kept low-contrast so units stay the focal point.
static func _build_plain(root: Node2D) -> void:
	var blade_color := Color(0.44, 0.60, 0.36)
	for origin in [Vector2(-9, 7), Vector2(3, 10), Vector2(9, 2)]:
		_line(root, PackedVector2Array([origin + Vector2(-3, 3), origin + Vector2(-1, -4)]), blade_color, 1.5)
		_line(root, PackedVector2Array([origin, origin + Vector2(0, -6)]), blade_color, 1.5)
		_line(root, PackedVector2Array([origin + Vector2(3, 3), origin + Vector2(1, -4)]), blade_color, 1.5)


## Scattered boulders for difficult terrain.
static func _build_rough(root: Node2D) -> void:
	var rocks := [
		{"at": Vector2(-8, 4), "scale": 1.0, "color": Color(0.52, 0.47, 0.42)},
		{"at": Vector2(6, 7), "scale": 0.75, "color": Color(0.44, 0.40, 0.36)},
		{"at": Vector2(4, -3), "scale": 0.9, "color": Color(0.58, 0.53, 0.47)},
	]
	for rock in rocks:
		var s: float = rock["scale"]
		_poly(root, PackedVector2Array([
			Vector2(-7, 4) * s, Vector2(-4, -4) * s, Vector2(3, -5) * s,
			Vector2(7, 1) * s, Vector2(4, 4) * s,
		]), rock["color"], rock["at"])


## Twin peaks with snow caps; the tallest reads as the impassable blocker.
static func _build_mountain(root: Node2D) -> void:
	_poly(root, PackedVector2Array([
		Vector2(-21, 9), Vector2(-12, -5), Vector2(-3, 9),
	]), Color(0.38, 0.40, 0.45))
	_poly(root, PackedVector2Array([
		Vector2(-14, 10), Vector2(0, -17), Vector2(14, 10),
	]), Color(0.50, 0.52, 0.58))
	_poly(root, PackedVector2Array([
		Vector2(-5.5, -3), Vector2(0, -17), Vector2(5.5, -3),
		Vector2(2, -6), Vector2(-2, -4),
	]), Color(0.88, 0.90, 0.95))
	_line(root, PackedVector2Array([
		Vector2(0, -17), Vector2(4, 0), Vector2(2, 10),
	]), Color(0.32, 0.34, 0.39, 0.7), 1.5)


## Healing tile: a bright cross with a soft halo.
static func _build_vitality(root: Node2D) -> void:
	var green := Color(0.40, 0.88, 0.48)
	_poly(root, _ring_points(11.0, 12), Color(0.25, 0.55, 0.30, 0.35))
	_poly(root, PackedVector2Array([
		Vector2(-3, -10), Vector2(3, -10), Vector2(3, -3),
		Vector2(10, -3), Vector2(10, 3), Vector2(3, 3),
		Vector2(3, 10), Vector2(-3, 10), Vector2(-3, 3),
		Vector2(-10, 3), Vector2(-10, -3), Vector2(-3, -3),
	]), green)


# --- Team-unique tiles, tinted with the owning team's colour ---

## Sentinels: a battlemented keep.
static func _build_bastion(root: Node2D, team_color: Color) -> void:
	var stone: Color = team_color.lerp(Color(0.85, 0.88, 0.95), 0.25)
	var shade: Color = team_color.darkened(0.35)
	_poly(root, PackedVector2Array([
		Vector2(-9, 11), Vector2(-9, -5), Vector2(9, -5), Vector2(9, 11),
	]), stone)
	_poly(root, PackedVector2Array([
		Vector2(2, 11), Vector2(2, -5), Vector2(9, -5), Vector2(9, 11),
	]), shade)
	for x in [-9.0, -3.0, 3.0]:
		_poly(root, PackedVector2Array([
			Vector2(x, -5), Vector2(x, -10), Vector2(x + 4, -10), Vector2(x + 4, -5),
		]), stone)
	_poly(root, PackedVector2Array([
		Vector2(-2, 11), Vector2(-2, 3), Vector2(2, 3), Vector2(2, 11),
	]), shade)


## Veilborne: a scrying mirror on a stand.
static func _build_mirror(root: Node2D, team_color: Color) -> void:
	var glass: Color = team_color.lerp(Color(0.92, 0.95, 1.0), 0.45)
	_poly(root, PackedVector2Array([
		Vector2(0, -14), Vector2(10, 0), Vector2(0, 14), Vector2(-10, 0),
	]), team_color.darkened(0.2))
	_poly(root, PackedVector2Array([
		Vector2(0, -10), Vector2(7, 0), Vector2(0, 10), Vector2(-7, 0),
	]), glass)
	_poly(root, PackedVector2Array([
		Vector2(-3, -3), Vector2(1, -6), Vector2(2, 1), Vector2(-2, 4),
	]), Color(1.0, 1.0, 1.0, 0.65))


## Emberclad: an anvil under a flame.
static func _build_forge(root: Node2D, team_color: Color) -> void:
	var iron := Color(0.30, 0.30, 0.34)
	_poly(root, PackedVector2Array([
		Vector2(-11, 0), Vector2(9, 0), Vector2(11, 4), Vector2(4, 4),
		Vector2(4, 8), Vector2(8, 12), Vector2(-8, 12), Vector2(-4, 8), Vector2(-4, 4),
	]), iron)
	_poly(root, PackedVector2Array([
		Vector2(0, -16), Vector2(6, -7), Vector2(3, -3), Vector2(-4, -3), Vector2(-6, -8),
	]), team_color)
	_poly(root, PackedVector2Array([
		Vector2(0, -11), Vector2(3, -6), Vector2(0, -4), Vector2(-3, -6),
	]), Color(1.0, 0.88, 0.45))


## Swarmbound: a cluster of honeycomb cells.
static func _build_hive(root: Node2D, team_color: Color) -> void:
	var cell: Color = team_color.lerp(Color(0.95, 0.85, 0.35), 0.4)
	for centre in [Vector2(0, -8), Vector2(-8, 4), Vector2(8, 4)]:
		_poly(root, _hex_points(8.0), team_color.darkened(0.3), centre)
		_poly(root, _hex_points(5.5), cell, centre)


# --- Primitive helpers ---

static func _poly(
	parent: Node2D,
	points: PackedVector2Array,
	color: Color,
	offset: Vector2 = Vector2.ZERO,
) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = color
	poly.position = offset
	parent.add_child(poly)
	return poly


static func _line(
	parent: Node2D,
	points: PackedVector2Array,
	color: Color,
	width: float,
) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.default_color = color
	line.width = width
	line.antialiased = true
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	parent.add_child(line)
	return line


static func _hex_points(radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i in 6:
		var angle: float = deg_to_rad(60.0 * i - 30.0)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


static func _ring_points(radius: float, segments: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i in segments:
		var angle: float = TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
