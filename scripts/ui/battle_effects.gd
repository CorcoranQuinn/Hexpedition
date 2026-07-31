class_name BattleEffects
extends Node2D
## Procedural combat and match-end visuals (lines, pulses, floating text).

const ATTACK_SLASH_TIME: float = 0.32
const HIT_FLASH_TIME: float = 0.22
const DEFEAT_TIME: float = 0.58
const ABILITY_TIME: float = 0.42
const MATCH_END_TIME: float = 2.4

var _hex_size: float = 36.0


# --- Public VFX entry points (called from game_board on combat_event) ---

func setup(hex_size: float) -> void:
	_hex_size = hex_size


## Slash line, impact sparks, damage number, and target flash on basic/minion attack.
func play_attack(from_pos: Vector2, to_pos: Vector2, damage: int, target_container: Node2D) -> void:
	var slash := Line2D.new()
	slash.width = 5.0
	slash.default_color = Color(1.0, 0.45, 0.2, 0.95)
	slash.points = PackedVector2Array([from_pos, to_pos])
	add_child(slash)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(slash, "modulate:a", 0.0, ATTACK_SLASH_TIME)
	tween.tween_property(slash, "width", 1.0, ATTACK_SLASH_TIME)
	tween.chain().tween_callback(slash.queue_free)

	_spawn_impact_burst(to_pos, Color(1.0, 0.35, 0.15))
	_spawn_damage_number(to_pos + Vector2(0, -18), str(damage), Color(1.0, 0.55, 0.35))

	if target_container and is_instance_valid(target_container):
		var body: CanvasItem = target_container.get_node_or_null("Body") as CanvasItem
		if body:
			var flash := create_tween()
			flash.tween_property(body, "modulate", Color(2.2, 0.6, 0.5), HIT_FLASH_TIME * 0.35)
			flash.tween_property(body, "modulate", Color(1.0, 1.0, 1.0), HIT_FLASH_TIME * 0.65)


## Team-specific ability visuals; Double Strike reuses play_attack when it has a target.
func play_ability(
	center: Vector2,
	ability_type: String,
	extra: Dictionary,
	get_unit_world_pos: Callable,
	get_unit_node: Callable = Callable(),
) -> void:
	match ability_type:
		"sentinel_leader":
			_play_heal_wave(center, get_unit_world_pos, extra)
		"veil_leader":
			_play_reveal_pulse(center, Color(0.35, 0.75, 1.0))
		"ember_leader":
			_play_buff_ring(center, Color(1.0, 0.45, 0.15))
		"ember_follower":
			if extra.has("target_id") and extra.has("damage"):
				var target_pos: Vector2 = get_unit_world_pos.call(extra["target_id"])
				if target_pos != Vector2.INF:
					var target_node: Node2D = null
					if get_unit_node.is_valid():
						target_node = get_unit_node.call(extra["target_id"])
					play_attack(center, target_pos, int(extra["damage"]), target_node)
		"sentinel_follower":
			_play_buff_ring(center, Color(0.55, 0.85, 1.0))
		"veil_follower":
			_play_buff_ring(center, Color(0.45, 0.95, 0.85))
		"swarm_leader", "swarm_follower":
			var summon_hex: Variant = extra.get("summon_hex")
			if summon_hex is Vector2i and summon_hex != Vector2i(-999, -999):
				var summon_pos: Vector2 = HexCoords.axial_to_pixel(summon_hex, _hex_size)
				_play_summon_burst(summon_pos)
			else:
				_play_buff_ring(center, Color(0.65, 0.35, 0.95))
		_:
			_play_buff_ring(center, Color(0.85, 0.85, 1.0))


## Shrink/spin/fade unit visual; callback runs before queue_free (match win timing).
func play_defeat(unit_container: Node2D, on_complete: Callable = Callable()) -> void:
	if unit_container == null or not is_instance_valid(unit_container):
		if on_complete.is_valid():
			on_complete.call()
		return

	var body: CanvasItem = unit_container.get_node_or_null("Body") as CanvasItem
	var pos: Vector2 = unit_container.position
	_spawn_impact_burst(pos, Color(0.95, 0.15, 0.15), 10)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(unit_container, "scale", Vector2(0.05, 0.05), DEFEAT_TIME)
	tween.tween_property(unit_container, "rotation", deg_to_rad(140.0), DEFEAT_TIME)
	tween.tween_property(unit_container, "modulate:a", 0.0, DEFEAT_TIME)
	if body:
		tween.tween_property(body, "modulate", Color(0.3, 0.05, 0.05), DEFEAT_TIME * 0.5)

	tween.chain().tween_callback(func() -> void:
		if on_complete.is_valid():
			on_complete.call()
		if is_instance_valid(unit_container):
			unit_container.queue_free()
	)


## Full-screen overlay when a leader dies; delays before game_board loads end scene.
func play_match_end(
	parent_ui: Control,
	board_root: Node2D,
	winner_id: int,
	local_player_id: int,
	losing_leader_pos: Vector2,
) -> void:
	var overlay := ColorRect.new()
	overlay.name = "MatchEndOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.02, 0.02, 0.06, 0.0)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	parent_ui.add_child(overlay)
	parent_ui.move_child(overlay, -1)

	var won: bool = winner_id == local_player_id
	var title := Label.new()
	title.text = "VICTORY!" if won else "DEFEAT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.offset_left = -260.0
	title.offset_right = 260.0
	title.offset_top = -48.0
	title.offset_bottom = 48.0
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.35) if won else Color(0.95, 0.35, 0.35))
	title.modulate.a = 0.0
	title.scale = Vector2(0.4, 0.4)
	overlay.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Leader eliminated"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.set_anchors_preset(Control.PRESET_CENTER)
	subtitle.offset_left = -220.0
	subtitle.offset_right = 220.0
	subtitle.offset_top = 36.0
	subtitle.offset_bottom = 72.0
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.modulate.a = 0.0
	overlay.add_child(subtitle)

	if losing_leader_pos != Vector2.INF:
		_spawn_impact_burst(losing_leader_pos, Color(1.0, 0.2, 0.15), 14)
		_spawn_shockwave(losing_leader_pos, Color(1.0, 0.35, 0.2))

	var board_tween := create_tween()
	board_tween.tween_property(board_root, "scale", Vector2(1.06, 1.06), 0.35).set_trans(Tween.TRANS_BACK)
	board_tween.tween_property(board_root, "scale", Vector2(1.0, 1.0), 0.55)

	var ui_tween := create_tween()
	ui_tween.tween_property(overlay, "color:a", 0.72, 0.45)
	ui_tween.parallel().tween_property(title, "modulate:a", 1.0, 0.35)
	ui_tween.parallel().tween_property(title, "scale", Vector2(1.0, 1.0), 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ui_tween.tween_property(subtitle, "modulate:a", 1.0, 0.35)

	await get_tree().create_timer(MATCH_END_TIME).timeout

	if is_instance_valid(overlay):
		var fade := create_tween()
		fade.tween_property(overlay, "modulate:a", 0.0, 0.35)
		await fade.finished
		overlay.queue_free()


# --- Ability-specific effect helpers ---

func _play_heal_wave(center: Vector2, get_unit_world_pos: Callable, extra: Dictionary) -> void:
	_play_buff_ring(center, Color(0.35, 0.95, 0.45))
	for ally_id in extra.get("healed_unit_ids", []):
		var pos: Vector2 = get_unit_world_pos.call(ally_id)
		if pos == Vector2.INF:
			continue
		_spawn_rising_spark(pos, Color(0.4, 1.0, 0.55))


func _play_reveal_pulse(center: Vector2, color: Color) -> void:
	_spawn_shockwave(center, color)
	_spawn_impact_burst(center, color.lightened(0.2), 8)


func _play_buff_ring(center: Vector2, color: Color) -> void:
	var ring := Line2D.new()
	ring.width = 4.0
	ring.default_color = color
	ring.closed = true
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 6:
		var angle: float = deg_to_rad(60 * i - 30)
		pts.append(center + Vector2(cos(angle), sin(angle)) * (_hex_size * 0.55))
	ring.points = pts
	add_child(ring)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2(1.8, 1.8), ABILITY_TIME)
	tween.tween_property(ring, "modulate:a", 0.0, ABILITY_TIME)
	tween.chain().tween_callback(ring.queue_free)


func _play_summon_burst(pos: Vector2) -> void:
	_spawn_shockwave(pos, Color(0.75, 0.35, 1.0))
	_spawn_impact_burst(pos, Color(0.85, 0.5, 1.0), 12)
	_spawn_damage_number(pos + Vector2(0, -12), "SUMMON", Color(0.85, 0.55, 1.0))


# --- Reusable particle/text primitives (no external assets) ---

func _spawn_impact_burst(pos: Vector2, color: Color, count: int = 6) -> void:
	for i in count:
		var spark := Polygon2D.new()
		spark.polygon = PackedVector2Array([
			Vector2(-3, 0), Vector2(0, -5), Vector2(3, 0), Vector2(0, 5),
		])
		spark.color = color
		spark.position = pos
		add_child(spark)
		var dir := Vector2.RIGHT.rotated(TAU * float(i) / float(count))
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(spark, "position", pos + dir * randf_range(18.0, 34.0), 0.35)
		tween.tween_property(spark, "modulate:a", 0.0, 0.35)
		tween.tween_property(spark, "scale", Vector2(0.2, 0.2), 0.35)
		tween.chain().tween_callback(spark.queue_free)


func _spawn_shockwave(center: Vector2, color: Color) -> void:
	var ring := Line2D.new()
	ring.width = 3.0
	ring.default_color = color
	ring.closed = true
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 6:
		var angle: float = deg_to_rad(60 * i - 30)
		pts.append(Vector2(cos(angle), sin(angle)) * (_hex_size * 0.35))
	ring.points = pts
	ring.position = center
	add_child(ring)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2(2.6, 2.6), 0.5)
	tween.tween_property(ring, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(ring.queue_free)


func _spawn_rising_spark(pos: Vector2, color: Color) -> void:
	var spark := Polygon2D.new()
	spark.polygon = PackedVector2Array([Vector2(0, -6), Vector2(4, 2), Vector2(-4, 2)])
	spark.color = color
	spark.position = pos
	add_child(spark)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(spark, "position", pos + Vector2(0, -28), 0.45)
	tween.tween_property(spark, "modulate:a", 0.0, 0.45)
	tween.chain().tween_callback(spark.queue_free)


func _spawn_damage_number(pos: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", pos + Vector2(0, -26), 0.55)
	tween.tween_property(label, "modulate:a", 0.0, 0.55)
	tween.chain().tween_callback(label.queue_free)
