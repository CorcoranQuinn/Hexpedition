class_name HexCoords
extends RefCounted
## Axial hex coordinate utilities (q, r).

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = abs(a.x - b.x)
	var dr: int = abs(a.y - b.y)
	var ds: int = abs((a.x + a.y) - (b.x + b.y))
	return maxi(maxi(dq, dr), ds)


static func neighbors(hex: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in DIRECTIONS:
		result.append(hex + dir)
	return result


static func ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	if radius == 0:
		return [center]
	var results: Array[Vector2i] = []
	var hex: Vector2i = center + DIRECTIONS[4] * radius
	for i in 6:
		for _j in radius:
			results.append(hex)
			hex += DIRECTIONS[i]
	return results


static func within_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(max(-radius, -q - radius), min(radius, -q + radius) + 1):
			results.append(center + Vector2i(q, r))
	return results


static func axial_to_pixel(hex: Vector2i, size: float) -> Vector2:
	var x: float = size * (sqrt(3.0) * hex.x + sqrt(3.0) / 2.0 * hex.y)
	var y: float = size * (3.0 / 2.0 * hex.y)
	return Vector2(x, y)


static func line_of_sight_path(from_hex: Vector2i, to_hex: Vector2i) -> Array[Vector2i]:
	var dist: int = distance(from_hex, to_hex)
	if dist == 0:
		return [from_hex]
	var results: Array[Vector2i] = []
	for i in dist + 1:
		var t: float = float(i) / float(dist)
		var q: float = lerpf(float(from_hex.x), float(to_hex.x), t)
		var r: float = lerpf(float(from_hex.y), float(to_hex.y), t)
		results.append(round_axial(q, r))
	return results


static func round_axial(q: float, r: float) -> Vector2i:
	var s: float = -q - r
	var rq: int = int(round(q))
	var rr: int = int(round(r))
	var rs: int = int(round(s))
	var q_diff: float = abs(float(rq) - q)
	var r_diff: float = abs(float(rr) - r)
	var s_diff: float = abs(float(rs) - s)
	if q_diff > r_diff and q_diff > s_diff:
		rq = -rr - rs
	elif r_diff > s_diff:
		rr = -rq - rs
	return Vector2i(rq, rr)
