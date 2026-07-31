extends Control

@onready var board_root: Node2D = %BoardRoot
@onready var turn_label: Label = %TurnLabel
@onready var actions_label: Label = %ActionsLabel
@onready var rp_label: Label = %RPLabel
@onready var log_label: Label = %LogLabel
@onready var move_button: Button = %MoveButton
@onready var attack_button: Button = %AttackButton
@onready var ability_button: Button = %AbilityButton
@onready var tile_button: Button = %TileButton
@onready var end_turn_button: Button = %EndTurnButton
@onready var unit_info: Label = %UnitInfo

const HEX_SIZE: float = 36.0

var match_ctrl: MatchController = MatchController.new()
var _selected_unit: UnitBase = null
var _action_mode: String = ""
var _move_targets: Dictionary = {}
var _tile_nodes: Dictionary = {}
var _unit_nodes: Dictionary = {}
var _ai_running: bool = false
var _hovered_unit_id: String = ""
var _battle_effects: BattleEffects
var _units_dying: Dictionary = {}
var _match_ending: bool = false


func _ready() -> void:
	move_button.pressed.connect(_set_mode.bind("move"))
	attack_button.pressed.connect(_set_mode.bind("attack"))
	ability_button.pressed.connect(_set_mode.bind("ability"))
	tile_button.pressed.connect(_set_mode.bind("tile"))
	end_turn_button.pressed.connect(_on_end_turn)

	match_ctrl.state_changed.connect(_refresh_ui)
	match_ctrl.action_log.connect(_append_log)
	match_ctrl.match_over.connect(_on_match_over)
	match_ctrl.combat_event.connect(_on_combat_event)
	NetworkManager.action_applied.connect(_on_network_action)

	if GameState.pending_rematch_same_teams:
		GameState.pending_rematch_same_teams = false
	elif GameState.pending_rematch_new_select:
		get_tree().change_scene_to_file("res://scenes/character_select.tscn")
		return

	var seed: int = GameState.match_seed if GameState.match_seed >= 0 else -1
	match_ctrl.setup_match(seed)
	_connect_turn_signals()
	_build_board_visuals()
	_battle_effects = BattleEffects.new()
	_battle_effects.setup(HEX_SIZE)
	board_root.add_child(_battle_effects)
	_refresh_ui()
	set_process(true)


func _connect_turn_signals() -> void:
	if not match_ctrl.turn_manager.turn_started.is_connected(_on_turn_started):
		match_ctrl.turn_manager.turn_started.connect(_on_turn_started)
	if not match_ctrl.turn_manager.player_changed.is_connected(_on_player_changed):
		match_ctrl.turn_manager.player_changed.connect(_on_player_changed)


func _on_player_changed(_player_id: int) -> void:
	_selected_unit = null
	_action_mode = ""
	_move_targets.clear()
	_update_move_button_label()
	_update_unit_visual_states()


func _build_board_visuals() -> void:
	for child in board_root.get_children():
		child.queue_free()
	_tile_nodes.clear()
	_unit_nodes.clear()

	for hex in match_ctrl.grid.get_all_hexes():
		var tile: TileBase = match_ctrl.grid.get_tile(hex)
		var poly := _make_hex_polygon(tile)
		board_root.add_child(poly)
		_tile_nodes[hex] = poly

	for unit in match_ctrl.units:
		_spawn_unit_visual(unit)


func _make_hex_polygon(tile: TileBase) -> Polygon2D:
	var poly := Polygon2D.new()
	var points: PackedVector2Array = PackedVector2Array()
	for i in 6:
		var angle: float = deg_to_rad(60 * i - 30)
		points.append(Vector2(cos(angle), sin(angle)) * HEX_SIZE)
	poly.polygon = points
	poly.position = HexCoords.axial_to_pixel(tile.hex_position, HEX_SIZE)
	poly.color = tile.get_revealed_color() if tile.revealed else Color(0.15, 0.16, 0.2)
	poly.set_meta("hex", tile.hex_position)

	var label := Label.new()
	label.text = tile.get_hidden_label() if not tile.revealed else tile.display_name.substr(0, 1)
	label.position = Vector2(-8, -10)
	label.add_theme_font_size_override("font_size", 12)
	poly.add_child(label)
	return poly


func _spawn_unit_visual(unit: UnitBase, animate_spawn: bool = false) -> void:
	if _unit_nodes.has(unit.id):
		return

	var container := Node2D.new()
	container.set_meta("unit_id", unit.id)

	var highlight := Polygon2D.new()
	highlight.name = "Highlight"
	highlight.polygon = _make_unit_points(17)
	highlight.color = Color(1.0, 1.0, 1.0, 0.22)
	highlight.visible = false
	container.add_child(highlight)

	var outline := Line2D.new()
	outline.name = "Outline"
	outline.points = _make_unit_line_points(15)
	outline.default_color = Color(1.0, 0.92, 0.35, 0.95)
	outline.width = 3.0
	outline.closed = true
	outline.visible = false
	container.add_child(outline)

	var body := Polygon2D.new()
	body.name = "Body"
	body.polygon = _make_unit_points(14)
	var team: TeamDefinition = TeamRegistry.get_team(GameState.selected_team_ids[unit.owner_id])
	body.color = team.team_color
	if unit.is_minion:
		body.scale = Vector2(0.65, 0.65)
		highlight.scale = Vector2(0.65, 0.65)
		outline.scale = Vector2(0.65, 0.65)
	elif unit.is_leader:
		body.scale = Vector2(1.3, 1.3)
		highlight.scale = Vector2(1.3, 1.3)
		outline.scale = Vector2(1.3, 1.3)
	if unit.is_ai_controlled:
		body.modulate = Color(0.9, 0.95, 0.9)
	container.add_child(body)

	container.position = HexCoords.axial_to_pixel(unit.hex_position, HEX_SIZE)
	board_root.add_child(container)
	_unit_nodes[unit.id] = container
	if animate_spawn:
		container.scale = Vector2(0.2, 0.2)
		var pop := create_tween()
		pop.tween_property(container, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK)


func _make_unit_points(size: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -size), Vector2(size * 0.86, size * 0.72), Vector2(-size * 0.86, size * 0.72)
	])


func _make_unit_line_points(size: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -size), Vector2(size * 0.86, size * 0.72), Vector2(-size * 0.86, size * 0.72), Vector2(0, -size)
	])


func _update_unit_visual_states() -> void:
	for unit_id in _unit_nodes:
		var container: Node2D = _unit_nodes[unit_id]
		var highlight: Polygon2D = container.get_node("Highlight") as Polygon2D
		var outline: Line2D = container.get_node("Outline") as Line2D
		if highlight:
			highlight.visible = unit_id == _hovered_unit_id
		if outline:
			outline.visible = _selected_unit != null and _selected_unit.id == unit_id


func _refresh_ui() -> void:
	var pid: int = match_ctrl.turn_manager.current_player
	if GameState.is_solo():
		var who: String = "Your Turn" if pid == 0 else "AI Turn"
		turn_label.text = "Turn %d — %s" % [match_ctrl.turn_manager.turn_number, who]
	else:
		turn_label.text = "Turn %d — Player %d" % [match_ctrl.turn_manager.turn_number, pid + 1]
	actions_label.text = "Actions: %d / %d" % [
		match_ctrl.turn_manager.actions_remaining, TurnManager.ACTIONS_PER_TURN
	]
	rp_label.text = "RP — P1: %d/%d  P2: %d/%d" % [
		match_ctrl.resource_points[0], match_ctrl.get_max_resource(0),
		match_ctrl.resource_points[1], match_ctrl.get_max_resource(1),
	]
	_update_board_colors()
	_update_unit_positions()
	_update_unit_visual_states()
	_update_move_button_label()
	_update_action_buttons()


func _update_board_colors() -> void:
	for hex in _tile_nodes:
		var tile: TileBase = match_ctrl.grid.get_tile(hex)
		var poly: Polygon2D = _tile_nodes[hex]
		poly.color = tile.get_revealed_color() if tile.revealed else Color(0.15, 0.16, 0.2)
		var lbl: Label = poly.get_child(0) as Label
		if lbl:
			lbl.text = tile.get_hidden_label() if not tile.revealed else tile.display_name.substr(0, 1)


func _update_unit_positions() -> void:
	for unit in match_ctrl.units:
		if not unit.is_alive:
			if _units_dying.has(unit.id):
				continue
			if _unit_nodes.has(unit.id):
				_unit_nodes[unit.id].queue_free()
				_unit_nodes.erase(unit.id)
			continue
		if not _unit_nodes.has(unit.id):
			_spawn_unit_visual(unit, true)
		else:
			_unit_nodes[unit.id].position = HexCoords.axial_to_pixel(unit.hex_position, HEX_SIZE)


func _update_action_buttons() -> void:
	var can_act: bool = _can_local_player_act()
	move_button.disabled = not can_act
	attack_button.disabled = not can_act
	ability_button.disabled = not can_act
	tile_button.disabled = not can_act
	end_turn_button.disabled = not can_act


func _can_local_player_act() -> bool:
	if GameState.is_solo():
		return match_ctrl.turn_manager.current_player == 0 and match_ctrl.turn_manager.can_spend_action() and not _ai_running
	if GameState.match_mode == GameState.MatchMode.LOCAL:
		return match_ctrl.turn_manager.can_spend_action()
	var local_id: int = GameState.get_local_player_id()
	return match_ctrl.turn_manager.current_player == local_id and match_ctrl.turn_manager.can_spend_action()


func _on_turn_started(player_id: int) -> void:
	_refresh_ui()
	if GameState.is_solo() and player_id == GameState.get_ai_player_id():
		_run_ai_turn_async()


func _get_active_player_id() -> int:
	if GameState.match_mode == GameState.MatchMode.LOCAL:
		return match_ctrl.turn_manager.current_player
	if GameState.is_solo():
		return 0
	return GameState.get_local_player_id()


func _run_ai_turn_async() -> void:
	if _ai_running:
		return
	_ai_running = true
	_update_action_buttons()
	await get_tree().create_timer(0.5).timeout
	if GameState.is_solo() and match_ctrl.turn_manager.current_player == GameState.get_ai_player_id():
		MatchAI.run_turn(match_ctrl, GameState.get_ai_player_id())
		_refresh_ui()
		# Force end if the AI couldn't spend all remaining actions.
		if GameState.is_solo() and match_ctrl.turn_manager.current_player == GameState.get_ai_player_id():
			match_ctrl.end_turn_with_minions(GameState.get_ai_player_id())
			_refresh_ui()
	_ai_running = false
	_update_action_buttons()


func _is_summoner(unit: UnitBase) -> bool:
	var type_id: String = unit.get_unit_type_id()
	return type_id == "swarm_leader" or type_id == "swarm_follower"


func _set_mode(mode: String) -> void:
	if _action_mode == "move" and mode == "move":
		_confirm_move()
		return
	_action_mode = mode
	_move_targets.clear()
	_selected_unit = null
	_update_move_button_label()
	_update_unit_visual_states()
	log_label.text = "Mode: %s — select a unit." % mode.capitalize()
	if mode == "move":
		log_label.text = "Move each unit (0–range), then click Move again to confirm."


func _confirm_move() -> void:
	if not _can_local_player_act():
		return
	if _move_targets.is_empty():
		log_label.text = "Select unit destinations first, or choose another action."
		return
	var result: Dictionary = match_ctrl.can_apply_moves(_get_active_player_id(), _move_targets)
	if not result.get("success", false):
		log_label.text = result.get("message", "Invalid move.")
		return
	_submit_action("move", {"moves": _move_targets.duplicate()})
	_move_targets.clear()
	_action_mode = ""
	_selected_unit = null
	_update_move_button_label()
	_update_unit_visual_states()


func _update_move_button_label() -> void:
	if _action_mode == "move" and not _move_targets.is_empty():
		move_button.text = "Confirm Move (%d)" % _move_targets.size()
	else:
		move_button.text = "Move (+1 RP)"


func _process(_delta: float) -> void:
	if _ai_running:
		return
	var hex: Vector2i = _pixel_to_hex(get_local_mouse_position())
	var hovered_id: String = ""
	if match_ctrl.grid.has_tile(hex):
		var unit: UnitBase = match_ctrl.get_unit_at(hex)
		if unit != null and unit.is_alive:
			hovered_id = unit.id
	if hovered_id != _hovered_unit_id:
		_hovered_unit_id = hovered_id
		_update_unit_visual_states()


func _input(event: InputEvent) -> void:
	if _match_ending:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hex: Vector2i = _pixel_to_hex(get_local_mouse_position())
		if not match_ctrl.grid.has_tile(hex):
			return
		_handle_hex_click(hex)


func _execute_action(action_type: String, payload: Dictionary) -> Dictionary:
	var pid: int = payload.get("player_id", _get_active_player_id())
	match action_type:
		"move":
			return match_ctrl.perform_move(pid, payload.get("moves", {}))
		"attack":
			return match_ctrl.perform_attack(pid, payload.get("attacker_id", ""), payload.get("target_id", ""))
		"ability":
			return match_ctrl.perform_ability(pid, payload.get("unit_id", ""), payload.get("extra", {}))
		"tile":
			return match_ctrl.perform_tile_interact(pid, payload.get("unit_id", ""))
		"end_turn":
			match_ctrl.end_turn_with_minions(pid)
			return {"success": true}
	return {"success": false, "message": "Unknown action."}


func _submit_action(action_type: String, payload: Dictionary) -> void:
	payload["player_id"] = _get_active_player_id()
	if GameState.is_online() and not multiplayer.is_server():
		NetworkManager.rpc_submit_action.rpc_id(1, action_type, payload)
	elif GameState.is_online() and multiplayer.is_server():
		var result: Dictionary = _execute_action(action_type, payload)
		log_label.text = result.get("message", "Action resolved.")
		NetworkManager.rpc_apply_action_result.rpc(action_type, payload, result)
	else:
		var result: Dictionary = _execute_action(action_type, payload)
		log_label.text = result.get("message", "Action resolved.")


func _on_network_action(action_type: String, payload: Dictionary, result: Dictionary) -> void:
	if result.is_empty() and multiplayer.is_server():
		result = _execute_action(action_type, payload)
		NetworkManager.rpc_apply_action_result.rpc(action_type, payload, result)
		log_label.text = result.get("message", "Action resolved.")
	elif not result.is_empty() and not multiplayer.is_server():
		_execute_action(action_type, payload)
		log_label.text = result.get("message", "Action resolved.")


func _handle_hex_click(hex: Vector2i) -> void:
	if _ai_running or _match_ending:
		return
	if GameState.is_online() and not _can_local_player_act():
		return
	if GameState.is_solo() and match_ctrl.turn_manager.current_player != 0:
		return
	var pid: int = _get_active_player_id()
	var clicked_unit: UnitBase = match_ctrl.get_unit_at(hex)

	match _action_mode:
		"":
			if clicked_unit and clicked_unit.owner_id == pid and clicked_unit.is_player_controllable():
				_selected_unit = clicked_unit
				unit_info.text = _format_unit(clicked_unit)
				_update_unit_visual_states()
		"move":
			if _selected_unit == null and clicked_unit and clicked_unit.owner_id == pid and clicked_unit.is_player_controllable():
				_selected_unit = clicked_unit
				unit_info.text = _format_unit(clicked_unit)
				if _move_targets.has(clicked_unit.id):
					log_label.text = "Re-select destination for %s." % clicked_unit.display_name
				else:
					log_label.text = "Choose a destination for %s." % clicked_unit.display_name
				_update_unit_visual_states()
			elif _selected_unit != null:
				for uid in _move_targets:
					if uid != _selected_unit.id and _move_targets[uid] == hex:
						log_label.text = "Another unit is already moving to that hex."
						return
				if not match_ctrl.can_move_unit_to(_selected_unit, hex, _move_targets):
					log_label.text = "%s cannot reach that hex." % _selected_unit.display_name
					return
				_move_targets[_selected_unit.id] = hex
				log_label.text = "%s destination set. Pick another unit or click Move to confirm." % _selected_unit.display_name
				_selected_unit = null
				_update_move_button_label()
				_update_unit_visual_states()
		"attack":
			if _selected_unit == null and clicked_unit and clicked_unit.owner_id == pid and clicked_unit.is_player_controllable():
				_selected_unit = clicked_unit
				_update_unit_visual_states()
			elif _selected_unit != null and clicked_unit and clicked_unit.owner_id != pid:
				_submit_action("attack", {
					"attacker_id": _selected_unit.id,
					"target_id": clicked_unit.id,
				})
				_selected_unit = null
				_action_mode = ""
				_update_unit_visual_states()
		"ability":
			if _selected_unit == null and clicked_unit and clicked_unit.owner_id == pid and clicked_unit.is_player_controllable():
				_selected_unit = clicked_unit
				if _is_summoner(_selected_unit):
					log_label.text = "Select an adjacent empty hex to summon."
					_update_unit_visual_states()
				else:
					_submit_action("ability", {"unit_id": _selected_unit.id})
					_selected_unit = null
					_action_mode = ""
					_update_unit_visual_states()
			elif _selected_unit != null and _is_summoner(_selected_unit):
				if HexCoords.distance(_selected_unit.hex_position, hex) == 1:
					_submit_action("ability", {
						"unit_id": _selected_unit.id,
						"extra": {"summon_hex": hex},
					})
				_selected_unit = null
				_action_mode = ""
				_update_unit_visual_states()
		"tile":
			if _selected_unit == null and clicked_unit and clicked_unit.owner_id == pid and clicked_unit.is_player_controllable():
				_selected_unit = clicked_unit
				_update_unit_visual_states()
			elif _selected_unit != null:
				_submit_action("tile", {"unit_id": _selected_unit.id})
				_selected_unit = null
				_action_mode = ""
				_update_unit_visual_states()


func _on_end_turn() -> void:
	_submit_action("end_turn", {})


func _format_unit(unit: UnitBase) -> String:
	var tags: String = ""
	if unit.is_leader:
		tags += " [Leader]"
	if unit.is_minion:
		tags += " [Minion]"
	if unit.is_ai_controlled:
		tags += " [AI]"
	return "%s%s\nHP: %d/%d  Move: %d  Range: %d\nAbility (%d RP): %s" % [
		unit.display_name, tags,
		unit.health, unit.max_health,
		unit.move_range, unit.attack_range,
		unit.ability_cost, unit.get_ability_description(),
	]


func _pixel_to_hex(pixel: Vector2) -> Vector2i:
	var board_pos: Vector2 = pixel - board_root.position
	# Rough inverse of axial_to_pixel
	var q: float = (sqrt(3.0) / 3.0 * board_pos.x - 1.0 / 3.0 * board_pos.y) / HEX_SIZE
	var r: float = (2.0 / 3.0 * board_pos.y) / HEX_SIZE
	return HexCoords.round_axial(q, r)


func _append_log(msg: String) -> void:
	log_label.text = msg


func _get_unit_world_pos(unit_id: String) -> Vector2:
	if not _unit_nodes.has(unit_id):
		return Vector2.INF
	return _unit_nodes[unit_id].position


func _get_unit_node(unit_id: String) -> Node2D:
	if not _unit_nodes.has(unit_id):
		return null
	return _unit_nodes[unit_id]


func _on_combat_event(event_type: String, data: Dictionary) -> void:
	match event_type:
		"attack":
			var attacker_id: String = data.get("attacker_id", "")
			var target_id: String = data.get("target_id", "")
			var damage: int = int(data.get("damage", 0))
			if not _unit_nodes.has(attacker_id) or not _unit_nodes.has(target_id):
				return
			var from_pos: Vector2 = _unit_nodes[attacker_id].position
			var to_pos: Vector2 = _unit_nodes[target_id].position
			var target_node: Node2D = _unit_nodes[target_id]
			_battle_effects.play_attack(from_pos, to_pos, damage, target_node)
			if data.get("target_killed", false):
				_start_defeat_animation(target_id)
		"ability":
			var unit_id: String = data.get("unit_id", "")
			if not _unit_nodes.has(unit_id):
				return
			var center: Vector2 = _unit_nodes[unit_id].position
			_battle_effects.play_ability(
				center,
				data.get("ability_type", ""),
				data,
				_get_unit_world_pos,
				_get_unit_node,
			)
			if data.get("target_killed", false):
				var target_id: String = data.get("target_id", "")
				if target_id != "":
					_start_defeat_animation(target_id)


func _start_defeat_animation(unit_id: String) -> void:
	if _units_dying.has(unit_id) or not _unit_nodes.has(unit_id):
		return
	_units_dying[unit_id] = true
	var container: Node2D = _unit_nodes[unit_id]
	_unit_nodes.erase(unit_id)
	_battle_effects.play_defeat(container, func() -> void:
		_units_dying.erase(unit_id)
	)


func _find_losing_leader_position(loser_id: int) -> Vector2:
	for unit in match_ctrl.units:
		if unit.owner_id == loser_id and unit.is_leader:
			return HexCoords.axial_to_pixel(unit.hex_position, HEX_SIZE)
	return Vector2.INF


func _on_match_over(winner_id: int) -> void:
	_match_ending = true
	GameState.last_winner_id = winner_id
	_update_action_buttons()

	var local_player_id: int = 0 if GameState.is_solo() else GameState.get_local_player_id()
	var loser_id: int = 1 - winner_id
	var leader_pos: Vector2 = _find_losing_leader_position(loser_id)

	if GameState.is_solo():
		log_label.text = "Victory!" if winner_id == 0 else "Defeat!"

	await _battle_effects.play_match_end(self, board_root, winner_id, local_player_id, leader_pos)
	get_tree().change_scene_to_file("res://scenes/end_game.tscn")
