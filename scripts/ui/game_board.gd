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

var match: MatchController = MatchController.new()
var _selected_unit: UnitBase = null
var _action_mode: String = ""
var _move_targets: Dictionary = {}
var _tile_nodes: Dictionary = {}
var _unit_nodes: Dictionary = {}


func _ready() -> void:
	move_button.pressed.connect(_set_mode.bind("move"))
	attack_button.pressed.connect(_set_mode.bind("attack"))
	ability_button.pressed.connect(_set_mode.bind("ability"))
	tile_button.pressed.connect(_set_mode.bind("tile"))
	end_turn_button.pressed.connect(_on_end_turn)

	match.state_changed.connect(_refresh_ui)
	match.action_log.connect(_append_log)
	match.match_over.connect(_on_match_over)
	match.turn_manager.player_changed.connect(func(_p): _selected_unit = null; _action_mode = "")
	NetworkManager.action_applied.connect(_on_network_action)

	if GameState.pending_rematch_same_teams:
		GameState.pending_rematch_same_teams = false
	elif GameState.pending_rematch_new_select:
		get_tree().change_scene_to_file("res://scenes/character_select.tscn")
		return

	var seed: int = GameState.match_seed if GameState.match_seed >= 0 else -1
	match.setup_match(seed)
	_build_board_visuals()
	_refresh_ui()


func _build_board_visuals() -> void:
	for child in board_root.get_children():
		child.queue_free()
	_tile_nodes.clear()
	_unit_nodes.clear()

	for hex in match.grid.get_all_hexes():
		var tile: TileBase = match.grid.get_tile(hex)
		var poly := _make_hex_polygon(tile)
		board_root.add_child(poly)
		_tile_nodes[hex] = poly

	for unit in match.units:
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


func _spawn_unit_visual(unit: UnitBase) -> void:
	if _unit_nodes.has(unit.id):
		return
	var marker := Polygon2D.new()
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(0, -14), Vector2(12, 10), Vector2(-12, 10)
	])
	marker.polygon = pts
	var team: TeamDefinition = TeamRegistry.get_team(GameState.selected_team_ids[unit.owner_id])
	marker.color = team.team_color
	if unit.is_leader:
		marker.scale = Vector2(1.3, 1.3)
	marker.position = HexCoords.axial_to_pixel(unit.hex_position, HEX_SIZE)
	board_root.add_child(marker)
	_unit_nodes[unit.id] = marker


func _refresh_ui() -> void:
	var pid: int = match.turn_manager.current_player
	turn_label.text = "Turn %d — Player %d" % [match.turn_manager.turn_number, pid + 1]
	actions_label.text = "Actions: %d / %d" % [
		match.turn_manager.actions_remaining, TurnManager.ACTIONS_PER_TURN
	]
	rp_label.text = "RP — P1: %d/%d  P2: %d/%d" % [
		match.resource_points[0], match.get_max_resource(0),
		match.resource_points[1], match.get_max_resource(1),
	]
	_update_board_colors()
	_update_unit_positions()
	_update_action_buttons()


func _update_board_colors() -> void:
	for hex in _tile_nodes:
		var tile: TileBase = match.grid.get_tile(hex)
		var poly: Polygon2D = _tile_nodes[hex]
		poly.color = tile.get_revealed_color() if tile.revealed else Color(0.15, 0.16, 0.2)
		var lbl: Label = poly.get_child(0) as Label
		if lbl:
			lbl.text = tile.get_hidden_label() if not tile.revealed else tile.display_name.substr(0, 1)


func _update_unit_positions() -> void:
	for unit in match.units:
		if not unit.is_alive:
			if _unit_nodes.has(unit.id):
				_unit_nodes[unit.id].queue_free()
				_unit_nodes.erase(unit.id)
			continue
		if not _unit_nodes.has(unit.id):
			_spawn_unit_visual(unit)
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
	if GameState.match_mode == GameState.MatchMode.LOCAL:
		return match.turn_manager.can_spend_action()
	var local_id: int = GameState.get_local_player_id()
	return match.turn_manager.current_player == local_id and match.turn_manager.can_spend_action()


func _get_active_player_id() -> int:
	if GameState.match_mode == GameState.MatchMode.LOCAL:
		return match.turn_manager.current_player
	return GameState.get_local_player_id()


func _set_mode(mode: String) -> void:
	_action_mode = mode
	_move_targets.clear()
	_selected_unit = null
	log_label.text = "Mode: %s — select a unit." % mode.capitalize()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hex: Vector2i = _pixel_to_hex(get_local_mouse_position())
		if not match.grid.has_tile(hex):
			return
		_handle_hex_click(hex)


func _execute_action(action_type: String, payload: Dictionary) -> Dictionary:
	var pid: int = payload.get("player_id", _get_active_player_id())
	match action_type:
		"move":
			return match.perform_move(pid, payload.get("moves", {}))
		"attack":
			return match.perform_attack(pid, payload.get("attacker_id", ""), payload.get("target_id", ""))
		"ability":
			return match.perform_ability(pid, payload.get("unit_id", ""), payload.get("extra", {}))
		"tile":
			return match.perform_tile_interact(pid, payload.get("unit_id", ""))
		"end_turn":
			while match.turn_manager.actions_remaining > 0:
				match.turn_manager.spend_action()
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
	if GameState.is_online() and not _can_local_player_act():
		return
	var pid: int = _get_active_player_id()
	var clicked_unit: UnitBase = match.get_unit_at(hex)

	match _action_mode:
		"":
			if clicked_unit and clicked_unit.owner_id == pid:
				_selected_unit = clicked_unit
				unit_info.text = _format_unit(clicked_unit)
		"move":
			if _selected_unit == null and clicked_unit and clicked_unit.owner_id == pid:
				_selected_unit = clicked_unit
				unit_info.text = _format_unit(clicked_unit)
			elif _selected_unit != null:
				_move_targets[_selected_unit.id] = hex
				_submit_action("move", {"moves": _move_targets.duplicate()})
				_move_targets.clear()
				_action_mode = ""
		"attack":
			if _selected_unit == null and clicked_unit and clicked_unit.owner_id == pid:
				_selected_unit = clicked_unit
			elif _selected_unit != null and clicked_unit and clicked_unit.owner_id != pid:
				_submit_action("attack", {
					"attacker_id": _selected_unit.id,
					"target_id": clicked_unit.id,
				})
				_selected_unit = null
				_action_mode = ""
		"ability":
			if _selected_unit == null and clicked_unit and clicked_unit.owner_id == pid:
				_selected_unit = clicked_unit
				_submit_action("ability", {"unit_id": _selected_unit.id})
				_selected_unit = null
				_action_mode = ""
		"tile":
			if _selected_unit == null and clicked_unit and clicked_unit.owner_id == pid:
				_selected_unit = clicked_unit
			elif _selected_unit != null:
				_submit_action("tile", {"unit_id": _selected_unit.id})
				_selected_unit = null
				_action_mode = ""


func _on_end_turn() -> void:
	_submit_action("end_turn", {})


func _format_unit(unit: UnitBase) -> String:
	return "%s%s\nHP: %d/%d  Move: %d  Range: %d\nAbility (%d RP): %s" % [
		unit.display_name,
		" [Leader]" if unit.is_leader else "",
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


func _on_match_over(winner_id: int) -> void:
	GameState.last_winner_id = winner_id
	get_tree().change_scene_to_file("res://scenes/end_game.tscn")
