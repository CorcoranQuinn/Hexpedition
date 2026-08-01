class_name ScrollBackground
extends Control
## Fantasy parchment backdrop behind the hex battlefield.


const PARCHMENT := Color(0.82, 0.72, 0.54)
const PARCHMENT_DARK := Color(0.62, 0.50, 0.34)
const INK := Color(0.28, 0.20, 0.12, 0.35)
const STAIN := Color(0.45, 0.32, 0.18, 0.08)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(rect, PARCHMENT_DARK)
	draw_rect(rect.grow(-18), PARCHMENT)

	# Soft vignette toward the edges like aged paper.
	for i in 4:
		var inset: float = 12.0 + float(i) * 14.0
		var alpha: float = 0.05 + float(i) * 0.03
		draw_rect(rect.grow(-inset), Color(0.35, 0.22, 0.10, alpha), false, 2.0)

	_draw_torn_edge(rect, true)
	_draw_torn_edge(rect, false)
	_draw_corner_ornament(rect.position + Vector2(28, 28), 1.0)
	_draw_corner_ornament(rect.position + Vector2(rect.size.x - 28, 28), -1.0)
	_draw_corner_ornament(rect.position + Vector2(28, rect.size.y - 28), 1.0)
	_draw_corner_ornament(rect.position + Vector2(rect.size.x - 28, rect.size.y - 28), -1.0)
	_draw_parchment_stains(rect)
	_draw_map_frame(rect)


func _draw_torn_edge(rect: Rect2, top: bool) -> void:
	var y: float = rect.position.y + 8.0 if top else rect.position.y + rect.size.y - 8.0
	var points: PackedVector2Array = PackedVector2Array()
	var step: float = 26.0
	var x: float = rect.position.x + 10.0
	while x <= rect.position.x + rect.size.x - 10.0:
		var jag: float = -5.0 if top else 5.0
		if int(x / step) % 2 == 0:
			jag *= -1.0
		points.append(Vector2(x, y + jag))
		x += step
	if points.size() >= 2:
		draw_polyline(points, INK, 2.0, true)


func _draw_corner_ornament(origin: Vector2, flip: float) -> void:
	var c: Color = INK
	draw_arc(origin, 18.0, PI * 0.1, PI * 0.55, 12, c, 2.0, true)
	draw_arc(origin + Vector2(8.0 * flip, 8.0), 10.0, PI * 0.2, PI * 0.75, 10, c, 1.5, true)
	draw_line(origin, origin + Vector2(22.0 * flip, 0.0), c, 1.5, true)
	draw_line(origin, origin + Vector2(0.0, 22.0), c, 1.5, true)


func _draw_parchment_stains(rect: Rect2) -> void:
	var spots: Array[Vector2] = [
		Vector2(rect.size.x * 0.18, rect.size.y * 0.22),
		Vector2(rect.size.x * 0.72, rect.size.y * 0.35),
		Vector2(rect.size.x * 0.42, rect.size.y * 0.78),
		Vector2(rect.size.x * 0.85, rect.size.y * 0.68),
	]
	for spot in spots:
		draw_circle(rect.position + spot, 34.0, STAIN)
		draw_circle(rect.position + spot + Vector2(12, -8), 18.0, STAIN.lightened(0.08))


func _draw_map_frame(rect: Rect2) -> void:
	var inner: Rect2 = rect.grow(-48)
	draw_rect(inner, Color(0.22, 0.14, 0.08, 0.18), false, 3.0)
	draw_rect(inner.grow(-6), Color(0.45, 0.30, 0.16, 0.25), false, 1.0)
