extends Control
## Main in-match UI: renders the hex board, handles player input, and bridges
## MatchController rules to visuals (units, paths, tooltips, combat effects).

# --- Scene references (sidebar + board root from game_board.tscn) ---
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

# --- Constants & preloads ---
const HEX_SIZE: float = 36.0
const BattleEffectsScript = preload("res://scripts/ui/battle_effects.gd")
const TileArtScript = preload("res://scripts/ui/tile_art.gd")

# --- Isometric projection & camera ---
## The board is drawn on a squashed, rotatable ground plane while units stay
## upright, which gives a 2.5D look without needing real 3D assets.
const ISO_SQUASH: float = 0.58  ## Vertical foreshortening of the ground plane.
const CAMERA_ROTATION_STEP: float = PI / 3.0  ## 60 degrees — one hex face per press.
const CAMERA_TWEEN_TIME: float = 0.3
const UNIT_DEPTH_RANGE: int = 40  ## Largest z offset a unit may take from screen depth.

# --- Tile presentation ---
const TILE_BORDER_COLOR := Color(0.03, 0.03, 0.05, 0.9)
const TILE_BORDER_WIDTH: float = 2.0

# --- On-board unit popup ---
const UNIT_POPUP_WIDTH: float = 226.0
const UNIT_POPUP_GAP: float = 26.0  ## Horizontal clearance from the unit marker.

# --- Leader health panel layout (kept clear of the right-hand sidebar) ---
const SIDEBAR_WIDTH: float = 320.0
const LEADER_PANEL_WIDTH: float = 236.0
const LEADER_PANEL_MARGIN: float = 16.0

# --- Match state (rules live in MatchController; UI keeps selection & modes) ---
var match_ctrl: MatchController = MatchController.new()
var _selected_unit: UnitBase = null  ## Inspected unit; also the actor during action modes.
var _action_mode: String = ""  ## "", "move", "attack", "ability", or "tile".
var _move_targets: Dictionary = {}  ## Pending batch move: unit_id -> destination hex.
var _tile_nodes: Dictionary = {}  ## hex -> Polygon2D visual
var _unit_nodes: Dictionary = {}  ## unit_id -> Node2D container (body, highlight, outline)
var _ai_running: bool = false
var _hovered_unit_id: String = ""
var _battle_effects: BattleEffectsScript
var _units_dying: Dictionary = {}  ## Units waiting for defeat animation before removal.
var _match_ending: bool = false
var _path_overlay: Node2D  ## Draws move path lines/arrows above tiles.
var _tile_tooltip: PanelContainer  ## Follows cursor with tile name/effect on hover.
var _tile_tooltip_label: Label
var _hovered_hex: Vector2i = Vector2i(999999, 999999)
var _move_animating: bool = false
var _suppress_position_snap: Dictionary = {}  ## During move tween, don't snap unit nodes.
var _unit_actions_box: VBoxContainer  ## Quick-action buttons for the selected friendly unit.
var _unit_popup: PanelContainer  ## Floating inspector anchored to the selected unit.
var _unit_popup_title: Label
var _unit_popup_info: Label

# --- Camera state (see ISO_SQUASH notes above) ---
var _ground_layer: Node2D  ## Applies the isometric squash in screen space.
var _ground_pivot: Node2D  ## Applies camera yaw; tiles and move paths live here.
var _actor_layer: Node2D  ## Upright billboards (units, VFX) at projected positions.
var _base_yaw_by_player: Array[float] = [0.0, 0.0]  ## Yaw that puts each side nearest the camera.
var _manual_yaw: float = 0.0  ## Player-applied offset from the base angle.
var _camera_owner_id: int = -1  ## Whose side the camera is currently behind.
var _iso_enabled: bool = true
var _camera_tween: Tween
var _synced_yaw: float = INF  ## Guards against re-projecting when nothing moved.
var _synced_squash: float = INF

# --- Leader health bars (supports teams with any number of leaders) ---
var _player_leader_box: VBoxContainer
var _enemy_leader_box: VBoxContainer
var _leader_rows: Dictionary = {}  ## unit_id -> { panel, name, bar, fill, color }

# --- Move path preview colors ---
const PATH_COLOR_CONFIRMED := Color(0.35, 0.85, 0.95, 0.9)
const PATH_COLOR_PREVIEW := Color(1.0, 0.92, 0.45, 0.75)


# --- Lifecycle: wire signals, start or resume match, build visuals ---
func _ready() -> void:
	# Let board clicks fall through to _unhandled_input; child Controls such as
	# the sidebar and unit popup still capture their own input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_info.text = "Click a unit on the board to inspect it."

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

	# Layers must exist before setup_match, whose state_changed signal already
	# triggers a refresh that spawns unit visuals into the actor layer.
	_setup_board_layers()

	var match_seed: int = GameState.match_seed if GameState.match_seed >= 0 else -1
	match_ctrl.setup_match(match_seed)
	_connect_turn_signals()
	_build_board_visuals()
	_path_overlay = Node2D.new()
	_path_overlay.name = "MovePathOverlay"
	_path_overlay.z_index = 4
	_ground_pivot.add_child(_path_overlay)
	_battle_effects = BattleEffectsScript.new()
	_battle_effects.setup(HEX_SIZE)
	_battle_effects.z_index = 60
	_actor_layer.add_child(_battle_effects)
	_setup_tile_tooltip()
	_setup_unit_popup()
	_setup_camera_controls()
	_setup_leader_panels()
	_cache_base_yaws()
	_update_camera_for_active_player(false)
	_refresh_ui()
	set_process(true)


# --- Turn flow callbacks ---
func _connect_turn_signals() -> void:
	if not match_ctrl.turn_manager.turn_started.is_connected(_on_turn_started):
		match_ctrl.turn_manager.turn_started.connect(_on_turn_started)
	if not match_ctrl.turn_manager.player_changed.is_connected(_on_player_changed):
		match_ctrl.turn_manager.player_changed.connect(_on_player_changed)


func _on_player_changed(_player_id: int) -> void:
	_deselect_unit()
	_action_mode = ""
	_move_targets.clear()
	_update_move_button_label()
	_clear_move_paths()
	_update_unit_visual_states()
	# Hot-seat play swaps whose side the camera sits behind.
	_update_camera_for_active_player(true)


# --- Board layers: a squashed, rotatable ground plane plus upright actors ---
## Screen position = squash * yaw * board position, so the ground tilts away
## while units and effects stay readable at their projected spot.
func _setup_board_layers() -> void:
	_ground_layer = Node2D.new()
	_ground_layer.name = "GroundLayer"
	_ground_layer.scale = Vector2(1.0, ISO_SQUASH)
	board_root.add_child(_ground_layer)

	_ground_pivot = Node2D.new()
	_ground_pivot.name = "GroundPivot"
	_ground_layer.add_child(_ground_pivot)

	_actor_layer = Node2D.new()
	_actor_layer.name = "ActorLayer"
	# Must exceed UNIT_DEPTH_RANGE so that even the farthest unit, which takes
	# the most negative depth offset, still sorts above the ground plane.
	_actor_layer.z_index = 50
	board_root.add_child(_actor_layer)


func _project_point(board_point: Vector2) -> Vector2:
	var turned: Vector2 = board_point.rotated(_ground_pivot.rotation)
	return Vector2(turned.x, turned.y * _ground_layer.scale.y)


func _project_hex(hex: Vector2i) -> Vector2:
	return _project_point(HexCoords.axial_to_pixel(hex, HEX_SIZE))


# --- Procedural board rendering (hex tiles + unit triangles) ---
func _build_board_visuals() -> void:
	for child in _ground_pivot.get_children():
		child.queue_free()
	for child in _actor_layer.get_children():
		child.queue_free()
	_tile_nodes.clear()
	_unit_nodes.clear()

	for hex in match_ctrl.grid.get_all_hexes():
		var tile: TileBase = match_ctrl.grid.get_tile(hex)
		var poly := _make_hex_polygon(tile)
		_ground_pivot.add_child(poly)
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

	# Dark rim so adjacent tiles read as separate cells.
	var border := Line2D.new()
	border.name = "Border"
	border.points = points
	border.closed = true
	border.width = TILE_BORDER_WIDTH
	border.default_color = TILE_BORDER_COLOR
	border.antialiased = true
	border.joint_mode = Line2D.LINE_JOINT_ROUND
	poly.add_child(border)

	# The anchor cancels the ground plane's yaw and squash so terrain markers
	# and glyphs stay upright as the camera turns.
	var anchor := Node2D.new()
	anchor.name = "Upright"
	poly.add_child(anchor)

	var label := Label.new()
	label.name = "TileLabel"
	label.position = Vector2(-8, -10)
	label.add_theme_font_size_override("font_size", 12)
	anchor.add_child(label)

	_refresh_tile_decor(poly, tile)
	return poly


## Terrain markers are rebuilt only when a tile's identity changes, which in
## practice means the moment fog is lifted from it.
func _refresh_tile_decor(poly: Polygon2D, tile: TileBase) -> void:
	var type_id: String = tile.get_tile_type_id() if tile.revealed else "hidden"
	if str(poly.get_meta("art_type", "")) == type_id:
		return
	poly.set_meta("art_type", type_id)

	var anchor: Node2D = poly.get_node_or_null("Upright") as Node2D
	if anchor == null:
		return
	var previous: Node = anchor.get_node_or_null("Decor")
	if previous != null:
		anchor.remove_child(previous)
		previous.queue_free()

	var team_color: Color = Color.WHITE
	if tile.is_team_unique and tile.team_id >= 0:
		team_color = TeamRegistry.get_team(tile.team_id).team_color
	var decor: Node2D = TileArtScript.build(type_id, team_color)
	anchor.add_child(decor)
	anchor.move_child(decor, 0)

	# Revealed terrain speaks for itself; only fogged hexes need the glyph.
	var label: Label = anchor.get_node_or_null("TileLabel") as Label
	if label != null:
		label.text = tile.get_hidden_label() if not tile.revealed else ""


func _spawn_unit_visual(unit: UnitBase, animate_spawn: bool = false) -> void:
	if _unit_nodes.has(unit.id):
		return

	var container := Node2D.new()
	container.set_meta("unit_id", unit.id)

	# Squashed disc that grounds the upright billboard on the tilted plane.
	var shadow := Polygon2D.new()
	shadow.name = "Shadow"
	shadow.polygon = _make_ellipse_points(15.0, 15.0 * ISO_SQUASH)
	shadow.color = Color(0.0, 0.0, 0.0, 0.28)
	shadow.position = Vector2(0, 9)
	container.add_child(shadow)

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
		shadow.scale = Vector2(0.65, 0.65)
	elif unit.is_leader:
		body.scale = Vector2(1.3, 1.3)
		highlight.scale = Vector2(1.3, 1.3)
		outline.scale = Vector2(1.3, 1.3)
		shadow.scale = Vector2(1.3, 1.3)
	if unit.is_ai_controlled:
		body.modulate = Color(0.9, 0.95, 0.9)
	container.add_child(body)

	_actor_layer.add_child(container)
	_place_unit_node(container, unit.hex_position)
	_unit_nodes[unit.id] = container
	if animate_spawn:
		container.scale = Vector2(0.2, 0.2)
		var pop := create_tween()
		pop.tween_property(container, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK)


func _make_unit_points(radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -radius), Vector2(radius * 0.86, radius * 0.72), Vector2(-radius * 0.86, radius * 0.72)
	])


func _make_unit_line_points(radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -radius), Vector2(radius * 0.86, radius * 0.72), Vector2(-radius * 0.86, radius * 0.72), Vector2(0, -radius)
	])


func _make_ellipse_points(radius_x: float, radius_y: float, segments: int = 18) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i in segments:
		var angle: float = TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return points


## Units are billboards: placed at the projected hex, but never squashed or
## rotated. Depth sorting uses screen Y so nearer units overlap farther ones.
func _place_unit_node(node: Node2D, hex: Vector2i) -> void:
	var pos: Vector2 = _project_hex(hex)
	node.position = pos
	node.z_index = clampi(int(round(pos.y / 8.0)), -UNIT_DEPTH_RANGE, UNIT_DEPTH_RANGE)


# --- Hover highlight + selection outline on unit visuals ---
func _update_unit_visual_states() -> void:
	for unit_id in _unit_nodes:
		var container: Node2D = _unit_nodes[unit_id]
		var highlight: Polygon2D = container.get_node("Highlight") as Polygon2D
		var outline: Line2D = container.get_node("Outline") as Line2D
		if highlight:
			highlight.visible = unit_id == _hovered_unit_id
		if outline:
			outline.visible = _selected_unit != null and _selected_unit.id == unit_id


# --- Sidebar sync: turn counters, tile colors, unit positions, action buttons ---
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
	_update_unit_info_panel()
	_refresh_leader_panels()


func _update_board_colors() -> void:
	for hex in _tile_nodes:
		var tile: TileBase = match_ctrl.grid.get_tile(hex)
		var poly: Polygon2D = _tile_nodes[hex]
		poly.color = tile.get_revealed_color() if tile.revealed else Color(0.15, 0.16, 0.2)
		_refresh_tile_decor(poly, tile)


func _update_unit_positions() -> void:
	for unit in match_ctrl.units:
		if not unit.is_alive:
			if _units_dying.has(unit.id):
				continue
			if _unit_nodes.has(unit.id):
				_unit_nodes[unit.id].queue_free()
				_unit_nodes.erase(unit.id)
			continue
		if _suppress_position_snap.has(unit.id):
			if not _unit_nodes.has(unit.id):
				_spawn_unit_visual(unit, false)
			continue
		if not _unit_nodes.has(unit.id):
			_spawn_unit_visual(unit, true)
		else:
			_place_unit_node(_unit_nodes[unit.id], unit.hex_position)


func _update_action_buttons() -> void:
	var can_act: bool = _can_local_player_act()
	move_button.disabled = not can_act
	attack_button.disabled = not can_act
	ability_button.disabled = not can_act
	tile_button.disabled = not can_act
	end_turn_button.disabled = not can_act
	if _action_mode != "move" or _move_targets.is_empty():
		move_button.text = "Move (1 AP, +1 RP)"
	attack_button.text = "Attack (1 AP)"
	ability_button.text = "Ability (1 AP + RP)"
	tile_button.text = "Tile Interact (1 AP)"


# --- Who may click actions (solo human, hot-seat, or online local player) ---
func _can_local_player_act() -> bool:
	if GameState.is_solo():
		return match_ctrl.turn_manager.current_player == 0 and match_ctrl.turn_manager.can_spend_action() and not _ai_running
	if GameState.match_mode == GameState.MatchMode.LOCAL:
		return match_ctrl.turn_manager.can_spend_action()
	var local_id: int = GameState.get_local_player_id()
	return match_ctrl.turn_manager.current_player == local_id and match_ctrl.turn_manager.can_spend_action()


# --- Solo AI: run opponent turn after a short delay ---
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


func _ability_needs_target_selection(unit: UnitBase) -> bool:
	return unit.ability_requires_enemy_target() or _is_summoner(unit)


# --- Action mode selection (sidebar buttons); move button double-press confirms ---
func _set_mode(mode: String) -> void:
	if _action_mode == "move" and mode == "move":
		_confirm_move()
		return
	_action_mode = mode
	_move_targets.clear()
	_deselect_unit()
	_update_move_button_label()
	_clear_move_paths()
	_update_unit_visual_states()
	log_label.text = "Mode: %s — select a unit." % mode.capitalize()
	if mode == "move":
		log_label.text = "Move each unit (0–range), then click Move again to confirm."


# --- Batch move: plan destinations, validate, animate, then apply rules ---
func _confirm_move() -> void:
	if not _can_local_player_act() or _move_animating:
		return
	if _move_targets.is_empty():
		log_label.text = "Select unit destinations first, or choose another action."
		return
	var moves: Dictionary = _move_targets.duplicate()
	var result: Dictionary = match_ctrl.can_apply_moves(_get_active_player_id(), moves)
	if not result.get("success", false):
		log_label.text = result.get("message", "Invalid move.")
		return
	_move_targets.clear()
	_action_mode = ""
	_deselect_unit()
	_update_move_button_label()
	_clear_move_paths()
	_run_move_action_async(moves)


func _run_move_action_async(moves: Dictionary) -> void:
	var anims: Array = _build_move_animations(moves)
	var pid: int = _get_active_player_id()
	var payload: Dictionary = {"player_id": pid, "moves": moves}
	if GameState.is_online() and not multiplayer.is_server():
		NetworkManager.rpc_submit_action.rpc_id(1, "move", payload)
	elif GameState.is_online() and multiplayer.is_server():
		var result: Dictionary = await _apply_move_with_animation(pid, moves, anims, true)
		NetworkManager.rpc_apply_action_result.rpc("move", payload, result)
	else:
		await _apply_move_with_animation(pid, moves, anims, true)


func _apply_move_with_animation(
	player_id: int,
	moves: Dictionary,
	anims: Array,
	run_logic: bool,
) -> Dictionary:
	_move_animating = true
	_update_action_buttons()
	for anim in anims:
		_suppress_position_snap[anim["unit_id"]] = true

	var result: Dictionary = {"success": true}
	if run_logic:
		result = match_ctrl.perform_move(player_id, moves)
		log_label.text = result.get("message", "Action resolved.")

	if result.get("success", false):
		_update_board_colors()
		await _animate_unit_paths(anims)

	for anim in anims:
		_suppress_position_snap.erase(anim["unit_id"])
	_move_animating = false
	_refresh_ui()
	_update_action_buttons()
	return result


func _build_move_animations(moves: Dictionary) -> Array:
	var anims: Array = []
	for unit_id in moves:
		var unit: UnitBase = _find_unit_by_id(unit_id)
		if unit == null:
			continue
		var dest: Vector2i = moves[unit_id]
		if dest == unit.hex_position:
			continue
		var path: Array[Vector2i] = match_ctrl.find_movement_path(unit, dest, moves)
		if path.size() >= 2:
			anims.append({"unit_id": unit_id, "path": path})
	return anims


func _animate_unit_paths(anims: Array) -> void:
	if anims.is_empty():
		return
	const STEP_TIME: float = 0.14
	var tweens: Array[Tween] = []
	for anim in anims:
		var unit_id: String = anim["unit_id"]
		var path: Array = anim["path"]
		if not _unit_nodes.has(unit_id) or path.size() < 2:
			continue
		var node: Node2D = _unit_nodes[unit_id]
		node.position = _project_hex(path[0])
		var tween := create_tween()
		for i in range(1, path.size()):
			var step_hex: Vector2i = path[i]
			var target_pos: Vector2 = _project_hex(step_hex)
			tween.tween_property(node, "position", target_pos, STEP_TIME)
			tween.tween_callback(func() -> void: _place_unit_node(node, step_hex))
		tweens.append(tween)
	for tween in tweens:
		await tween.finished


func _find_unit_by_id(unit_id: String) -> UnitBase:
	for unit in match_ctrl.units:
		if unit.id == unit_id:
			return unit
	return null


# --- Move button label reflects confirm state when destinations are queued ---
func _update_move_button_label() -> void:
	if _action_mode == "move" and not _move_targets.is_empty():
		move_button.text = "Confirm Move (%d)" % _move_targets.size()
	else:
		move_button.text = "Move (1 AP, +1 RP)"


# --- Per-frame hover: unit highlight, tile tooltip, move path preview ---
func _process(_delta: float) -> void:
	_sync_camera_dependent_visuals()
	_position_unit_popup()
	if _ai_running or _match_ending or _move_animating:
		if _match_ending:
			_tile_tooltip.visible = false
		return
	var hex: Vector2i = _hex_under_mouse()
	var hovered_id: String = ""
	if match_ctrl.grid.has_tile(hex):
		var unit: UnitBase = match_ctrl.get_unit_at(hex)
		if unit != null and unit.is_alive:
			hovered_id = unit.id
	if hovered_id != _hovered_unit_id:
		_hovered_unit_id = hovered_id
		_update_unit_visual_states()

	if match_ctrl.grid.has_tile(hex):
		if hex != _hovered_hex:
			_hovered_hex = hex
			_update_tile_tooltip_content(hex)
		_position_tile_tooltip()
		if _action_mode == "move":
			_update_move_path_preview(hex)
	else:
		_hovered_hex = Vector2i(999999, 999999)
		_tile_tooltip.visible = false
		if _action_mode == "move":
			_update_move_path_preview(Vector2i(999999, 999999))


## Board input is deliberately "unhandled": the sidebar and the unit popup are
## ordinary Controls that swallow their own clicks, so a press only reaches the
## board when it landed on empty space.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				_rotate_camera(-1)
				return
			KEY_E:
				_rotate_camera(1)
				return
			KEY_R:
				_reset_camera_view()
				return
			KEY_ESCAPE:
				_deselect_unit()
				return
	if _match_ending or _move_animating:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hex: Vector2i = _hex_under_mouse()
		if not match_ctrl.grid.has_tile(hex):
			return
		_handle_hex_click(hex)


# --- Dispatch player actions to MatchController (local rules authority) ---
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


# --- Online: host authoritative; moves get special animation sync path ---
func _on_network_action(action_type: String, payload: Dictionary, result: Dictionary) -> void:
	if action_type == "move":
		var moves: Dictionary = payload.get("moves", {})
		var pid: int = payload.get("player_id", 0)
		var anims: Array = _build_move_animations(moves)
		if result.is_empty() and multiplayer.is_server():
			var move_result: Dictionary = await _apply_move_with_animation(pid, moves, anims, true)
			NetworkManager.rpc_apply_action_result.rpc(action_type, payload, move_result)
		elif not result.is_empty() and not multiplayer.is_server():
			for anim in anims:
				_suppress_position_snap[anim["unit_id"]] = true
			_move_animating = true
			var move_result: Dictionary = _execute_action(action_type, payload)
			log_label.text = move_result.get("message", "Action resolved.")
			if move_result.get("success", false):
				_update_board_colors()
				await _animate_unit_paths(anims)
			for anim in anims:
				_suppress_position_snap.erase(anim["unit_id"])
			_move_animating = false
			_refresh_ui()
			_update_action_buttons()
		return
	if result.is_empty() and multiplayer.is_server():
		result = _execute_action(action_type, payload)
		NetworkManager.rpc_apply_action_result.rpc(action_type, payload, result)
		log_label.text = result.get("message", "Action resolved.")
	elif not result.is_empty() and not multiplayer.is_server():
		_execute_action(action_type, payload)
		log_label.text = result.get("message", "Action resolved.")


# --- Board clicks: behavior depends on current _action_mode ---
func _handle_hex_click(hex: Vector2i) -> void:
	if _ai_running or _match_ending or _move_animating:
		return
	if GameState.is_online() and not _can_local_player_act():
		return
	if GameState.is_solo() and match_ctrl.turn_manager.current_player != 0:
		return
	var pid: int = _get_active_player_id()
	var clicked_unit: UnitBase = match_ctrl.get_unit_at(hex)

	match _action_mode:
		"":
			if clicked_unit and clicked_unit.is_alive:
				_select_unit(clicked_unit)
			else:
				_deselect_unit()
		"move":
			if _selected_unit == null and clicked_unit and clicked_unit.owner_id == pid and clicked_unit.is_player_controllable():
				_select_unit(clicked_unit)
				if _move_targets.has(clicked_unit.id):
					log_label.text = "Re-select destination for %s." % clicked_unit.display_name
				else:
					log_label.text = "Choose a destination for %s." % clicked_unit.display_name
				_update_move_path_preview(_hovered_hex)
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
				_deselect_unit()
				_update_move_button_label()
				_update_move_path_preview(hex)
		"attack":
			if _selected_unit == null and clicked_unit and clicked_unit.owner_id == pid and clicked_unit.is_player_controllable():
				_select_unit(clicked_unit)
			elif _selected_unit != null and clicked_unit and clicked_unit.owner_id != pid:
				_submit_action("attack", {
					"attacker_id": _selected_unit.id,
					"target_id": clicked_unit.id,
				})
				_action_mode = ""
				_deselect_unit()
		"ability":
			if _selected_unit == null and clicked_unit and clicked_unit.owner_id == pid and clicked_unit.is_player_controllable():
				_select_unit(clicked_unit)
				if _ability_needs_target_selection(_selected_unit):
					if _is_summoner(_selected_unit):
						log_label.text = "Select an adjacent empty hex to summon."
					else:
						log_label.text = "Select an enemy to strike with Double Strike."
					_update_unit_visual_states()
				else:
					_submit_action("ability", {"unit_id": _selected_unit.id})
					_action_mode = ""
					_deselect_unit()
			elif _selected_unit != null and _selected_unit.ability_requires_enemy_target():
				if clicked_unit and clicked_unit.owner_id != pid:
					if not _selected_unit.can_attack(
						clicked_unit,
						func(a, b): return match_ctrl.has_line_of_sight(a, b),
					):
						log_label.text = "That enemy is out of range or blocked."
						return
					_submit_action("ability", {
						"unit_id": _selected_unit.id,
						"extra": {"target_id": clicked_unit.id},
					})
					_action_mode = ""
					_deselect_unit()
			elif _selected_unit != null and _is_summoner(_selected_unit):
				if HexCoords.distance(_selected_unit.hex_position, hex) == 1:
					_submit_action("ability", {
						"unit_id": _selected_unit.id,
						"extra": {"summon_hex": hex},
					})
				_action_mode = ""
				_deselect_unit()
		"tile":
			if _selected_unit == null and clicked_unit and clicked_unit.owner_id == pid and clicked_unit.is_player_controllable():
				_select_unit(clicked_unit)
			elif _selected_unit != null:
				_submit_action("tile", {"unit_id": _selected_unit.id})
				_action_mode = ""
				_deselect_unit()


func _on_end_turn() -> void:
	_submit_action("end_turn", {})


# --- Unit inspection popup: stats and quick actions beside the unit itself ---
## Anchored to the clicked unit rather than the sidebar so the player's focus
## stays on the board. Buttons consume their own clicks, which is why board
## input runs through _unhandled_input.
func _setup_unit_popup() -> void:
	_unit_popup = PanelContainer.new()
	_unit_popup.name = "UnitPopup"
	_unit_popup.visible = false
	_unit_popup.z_index = 250

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.96)
	style.border_color = Color(0.45, 0.5, 0.6, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(8)
	_unit_popup.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	_unit_popup.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	vbox.add_child(header)

	_unit_popup_title = Label.new()
	_unit_popup_title.add_theme_font_size_override("font_size", 15)
	_unit_popup_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_unit_popup_title)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.tooltip_text = "Close (Esc)."
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(24, 0)
	close_button.pressed.connect(_deselect_unit)
	header.add_child(close_button)

	_unit_popup_info = Label.new()
	_unit_popup_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unit_popup_info.custom_minimum_size = Vector2(UNIT_POPUP_WIDTH, 0)
	_unit_popup_info.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_unit_popup_info)

	vbox.add_child(HSeparator.new())

	_unit_actions_box = VBoxContainer.new()
	_unit_actions_box.add_theme_constant_override("separation", 4)
	vbox.add_child(_unit_actions_box)

	add_child(_unit_popup)


func _select_unit(unit: UnitBase) -> void:
	_selected_unit = unit
	_update_unit_info_panel()
	_update_unit_visual_states()


func _deselect_unit() -> void:
	_selected_unit = null
	_clear_unit_action_buttons()
	if _unit_popup != null:
		_unit_popup.visible = false
	_update_unit_visual_states()


func _update_unit_info_panel() -> void:
	_clear_unit_action_buttons()
	if _unit_popup == null:
		return
	if _selected_unit == null or not _selected_unit.is_alive:
		_unit_popup.visible = false
		return
	_unit_popup_title.text = _selected_unit.display_name
	_unit_popup_info.text = _build_unit_info_text(_selected_unit)
	_rebuild_unit_action_buttons(_selected_unit)
	_unit_popup.visible = true
	_position_unit_popup()


## Keeps the popup pinned beside its unit, flipping sides and clamping so it
## never slides under the sidebar or off-screen.
func _position_unit_popup() -> void:
	if _unit_popup == null or not _unit_popup.visible or _selected_unit == null:
		return
	if not _unit_nodes.has(_selected_unit.id):
		_unit_popup.visible = false
		return

	var unit_node: Node2D = _unit_nodes[_selected_unit.id]
	var anchor: Vector2 = get_global_transform().affine_inverse() * _actor_layer.to_global(unit_node.position)
	var popup_size: Vector2 = _unit_popup.size.max(_unit_popup.get_combined_minimum_size())
	var right_limit: float = size.x - SIDEBAR_WIDTH - popup_size.x - 8.0

	var pos: Vector2 = Vector2(anchor.x + UNIT_POPUP_GAP, anchor.y - popup_size.y * 0.5)
	if pos.x > right_limit:
		pos.x = anchor.x - UNIT_POPUP_GAP - popup_size.x
	pos.x = clampf(pos.x, 8.0, maxf(8.0, right_limit))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, size.y - popup_size.y - 8.0))
	_unit_popup.position = pos


func _build_unit_info_text(unit: UnitBase) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var team: TeamDefinition = TeamRegistry.get_team(unit.team_id)
	var owner_label: String = "Player %d" % (unit.owner_id + 1)
	if GameState.is_solo():
		owner_label = "You" if unit.owner_id == 0 else "AI"

	# The name is omitted here: the popup shows it as the panel title.
	var tags: PackedStringArray = PackedStringArray()
	if unit.is_leader:
		tags.append("Leader")
	if unit.is_minion:
		tags.append("Minion")
	if unit.is_ai_controlled:
		tags.append("AI-controlled")
	if not tags.is_empty():
		lines.append("[%s]" % ", ".join(tags))

	lines.append("Team: %s (%s)" % [team.team_name, owner_label])
	lines.append("HP: %d / %d" % [unit.health, unit.max_health])
	lines.append("Move: %d  |  Range: %d  |  Attack die: d%d" % [
		unit.move_range, unit.attack_range, unit.attack_die_sides,
	])
	lines.append("Ability (%d RP): %s" % [unit.ability_cost, unit.get_ability_description()])

	if unit.damage_bonus > 0:
		lines.append("Buff: +%d attack damage this turn" % unit.damage_bonus)
	if unit.defense_bonus > 0:
		lines.append("Buff: +%d defense this turn" % unit.defense_bonus)

	var tile: TileBase = match_ctrl.grid.get_tile(unit.hex_position)
	if tile != null:
		if tile.revealed:
			lines.append("Tile: %s — %s" % [tile.display_name, tile.get_effect_description()])
		else:
			lines.append("Tile: Unknown (unrevealed)")

	var pid: int = _get_active_player_id()
	if unit.owner_id != pid:
		lines.append("")
		lines.append(_build_enemy_interaction_summary(unit, pid))
	elif not unit.is_player_controllable():
		lines.append("")
		lines.append("This unit acts automatically at end of turn.")
	elif not _can_local_player_act():
		lines.append("")
		lines.append("Not your turn — viewing only.")
	else:
		lines.append("")
		lines.append("Available this turn:")

	return "\n".join(lines)


func _build_enemy_interaction_summary(enemy: UnitBase, pid: int) -> String:
	var attackers: PackedStringArray = PackedStringArray()
	for unit in match_ctrl.get_units_for_player(pid):
		if not unit.is_player_controllable():
			continue
		if unit.can_attack(enemy, func(a, b): return match_ctrl.has_line_of_sight(a, b)):
			attackers.append(unit.display_name)
	if attackers.is_empty():
		return "No friendly units can attack this target right now."
	return "Can be attacked by: %s" % ", ".join(attackers)


func _rebuild_unit_action_buttons(unit: UnitBase) -> void:
	var pid: int = _get_active_player_id()
	if unit.owner_id != pid or not unit.is_player_controllable() or not _can_local_player_act():
		return

	var los_check := func(a, b): return match_ctrl.has_line_of_sight(a, b)
	var rp: int = match_ctrl.resource_points[pid]
	var can_spend: bool = match_ctrl.turn_manager.can_spend_action()

	_add_unit_action_button(
		"Move (1 AP, +1 RP)",
		can_spend,
		"Plan movement for this unit." if can_spend else "No actions remaining.",
		func() -> void:
			_set_mode("move")
			_select_unit(unit),
	)

	var targets_in_range: int = _count_attack_targets(unit, los_check)
	_add_unit_action_button(
		"Attack (1 AP)" + (" — %d target(s)" % targets_in_range if targets_in_range > 0 else ""),
		can_spend and targets_in_range > 0,
		"Select an enemy in range to attack." if can_spend and targets_in_range > 0 else "No valid targets in range.",
		func() -> void:
			_set_mode("attack")
			_select_unit(unit)
			log_label.text = "Select an enemy for %s to attack." % unit.display_name,
	)

	var ability_check: Dictionary = _get_ability_action_status(unit, rp, can_spend)
	_add_unit_action_button(
		"Ability (1 AP + %d RP)" % unit.ability_cost,
		ability_check.get("enabled", false),
		ability_check.get("hint", ""),
		func() -> void:
			_begin_ability_with_unit(unit),
	)

	var tile: TileBase = match_ctrl.grid.get_tile(unit.hex_position)
	var can_tile: bool = can_spend and tile != null and tile.can_interact(unit)
	_add_unit_action_button(
		"Tile Interact (1 AP)",
		can_tile,
		"Use the tile beneath this unit." if can_tile else "No interactable tile here.",
		func() -> void:
			_set_mode("tile")
			_select_unit(unit)
			log_label.text = "Confirm tile interaction for %s." % unit.display_name,
	)


func _get_ability_action_status(unit: UnitBase, rp: int, can_spend: bool) -> Dictionary:
	if not can_spend:
		return {"enabled": false, "hint": "No actions remaining."}
	if rp < unit.ability_cost:
		return {"enabled": false, "hint": "Need %d RP (have %d)." % [unit.ability_cost, rp]}
	if unit.ability_requires_enemy_target():
		return {"enabled": true, "hint": "Select an enemy for Double Strike."}
	if _is_summoner(unit):
		return {"enabled": true, "hint": "Select an adjacent empty hex to summon."}
	return {"enabled": true, "hint": unit.get_ability_description()}


func _begin_ability_with_unit(unit: UnitBase) -> void:
	_set_mode("ability")
	_select_unit(unit)
	if _is_summoner(unit):
		log_label.text = "Select an adjacent empty hex to summon."
	elif unit.ability_requires_enemy_target():
		log_label.text = "Select an enemy to strike with Double Strike."
	else:
		_submit_action("ability", {"unit_id": unit.id})
		_action_mode = ""
		_deselect_unit()


func _count_attack_targets(unit: UnitBase, los_check: Callable) -> int:
	var count: int = 0
	for enemy in match_ctrl.get_enemies_of(unit.owner_id):
		if unit.can_attack(enemy, los_check):
			count += 1
	return count


func _add_unit_action_button(text: String, enabled: bool, hint: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.disabled = not enabled
	btn.tooltip_text = hint
	btn.add_theme_font_size_override("font_size", 12)
	btn.pressed.connect(callback)
	_unit_actions_box.add_child(btn)


func _clear_unit_action_buttons() -> void:
	if _unit_actions_box == null:
		return
	# Detached immediately rather than only queued, so the popup never measures
	# itself against a stale set of buttons on the frame it is rebuilt.
	for child in _unit_actions_box.get_children():
		_unit_actions_box.remove_child(child)
		child.queue_free()


func _format_unit(unit: UnitBase) -> String:
	return _build_unit_info_text(unit)


# --- Mouse position -> axial hex (inverse of HexCoords.axial_to_pixel) ---
## Reading the mouse in the pivot's own space undoes the board offset, camera
## yaw, and isometric squash in one step, so picking survives any camera angle.
func _hex_under_mouse() -> Vector2i:
	if _ground_pivot == null:
		return Vector2i(999999, 999999)
	var board_pos: Vector2 = _ground_pivot.get_local_mouse_position()
	var q: float = (sqrt(3.0) / 3.0 * board_pos.x - 1.0 / 3.0 * board_pos.y) / HEX_SIZE
	var r: float = (2.0 / 3.0 * board_pos.y) / HEX_SIZE
	return HexCoords.round_axial(q, r)


func _append_log(msg: String) -> void:
	log_label.text = msg


# --- Camera: orient behind the viewing player's side, allow manual rotation ---

## Angle that swings a player's starting corner toward the bottom of the
## screen, so "your" side is always the near edge of the board.
func _compute_base_yaw(player_id: int) -> float:
	var centroid: Vector2 = Vector2.ZERO
	var count: int = 0
	for unit in match_ctrl.units:
		if unit.owner_id == player_id:
			centroid += HexCoords.axial_to_pixel(unit.hex_position, HEX_SIZE)
			count += 1
	if count == 0:
		return 0.0
	centroid /= float(count)
	if centroid.length_squared() < 0.01:
		return 0.0
	return PI / 2.0 - centroid.angle()


## Cached from spawn positions, since units drift once the match is underway.
func _cache_base_yaws() -> void:
	for pid in 2:
		_base_yaw_by_player[pid] = _compute_base_yaw(pid)


func _update_camera_for_active_player(animate: bool) -> void:
	var viewer: int = _get_active_player_id()
	if viewer < 0 or viewer >= _base_yaw_by_player.size():
		return
	if viewer == _camera_owner_id:
		return
	_camera_owner_id = viewer
	_apply_camera_orientation(animate)


func _apply_camera_orientation(animate: bool) -> void:
	if _ground_pivot == null:
		return
	var base_yaw: float = 0.0
	if _camera_owner_id >= 0 and _camera_owner_id < _base_yaw_by_player.size():
		base_yaw = _base_yaw_by_player[_camera_owner_id]
	var target_yaw: float = base_yaw + _manual_yaw
	var target_squash: float = ISO_SQUASH if _iso_enabled else 1.0

	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	if not animate:
		_ground_pivot.rotation = target_yaw
		_ground_layer.scale.y = target_squash
		_sync_camera_dependent_visuals()
		return

	_camera_tween = create_tween()
	_camera_tween.set_parallel(true)
	_camera_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_camera_tween.tween_property(_ground_pivot, "rotation", target_yaw, CAMERA_TWEEN_TIME)
	_camera_tween.tween_property(_ground_layer, "scale:y", target_squash, CAMERA_TWEEN_TIME)


func _rotate_camera(direction: int) -> void:
	if _match_ending or _move_animating:
		return
	_manual_yaw += CAMERA_ROTATION_STEP * float(direction)
	_apply_camera_orientation(true)


func _reset_camera_view() -> void:
	if _match_ending or _move_animating:
		return
	_manual_yaw = 0.0
	_apply_camera_orientation(true)


func _toggle_isometric(enabled: bool) -> void:
	_iso_enabled = enabled
	_apply_camera_orientation(true)


## Tiles ride the ground plane, but their glyphs and the unit billboards must
## be re-derived whenever the camera moves.
func _sync_camera_dependent_visuals() -> void:
	if _ground_pivot == null or _ground_layer == null:
		return
	var yaw: float = _ground_pivot.rotation
	var squash: float = _ground_layer.scale.y
	if is_equal_approx(yaw, _synced_yaw) and is_equal_approx(squash, _synced_squash):
		return
	_synced_yaw = yaw
	_synced_squash = squash

	var inverse_squash: float = 1.0 / maxf(squash, 0.05)
	for hex in _tile_nodes:
		var anchor: Node2D = _tile_nodes[hex].get_node_or_null("Upright") as Node2D
		if anchor != null:
			anchor.rotation = -yaw
			anchor.scale = Vector2(1.0, inverse_squash)

	for unit in match_ctrl.units:
		if not _unit_nodes.has(unit.id) or _suppress_position_snap.has(unit.id):
			continue
		_place_unit_node(_unit_nodes[unit.id], unit.hex_position)


func _setup_camera_controls() -> void:
	var sidebar: Node = rp_label.get_parent()
	var box := VBoxContainer.new()
	box.name = "CameraControls"
	box.add_theme_constant_override("separation", 4)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_make_camera_button("Rotate L", "Rotate the board counter-clockwise (Q).", _rotate_camera.bind(-1)))
	row.add_child(_make_camera_button("Rotate R", "Rotate the board clockwise (E).", _rotate_camera.bind(1)))
	row.add_child(_make_camera_button("Reset", "Face your own side again (R).", _reset_camera_view))
	box.add_child(row)

	var iso_toggle := CheckButton.new()
	iso_toggle.text = "Isometric View"
	iso_toggle.tooltip_text = "Toggle between the tilted board and a flat top-down view."
	iso_toggle.button_pressed = _iso_enabled
	iso_toggle.toggled.connect(_toggle_isometric)
	box.add_child(iso_toggle)

	sidebar.add_child(box)
	sidebar.move_child(box, rp_label.get_index() + 1)


func _make_camera_button(text: String, hint: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = hint
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(callback)
	return btn


# --- Leader health readouts: yours bottom-left, the enemy's top-right ---
## Both panels list every leader a team fields, so rosters with more than one
## leader (or none) render without special-casing.
func _setup_leader_panels() -> void:
	_player_leader_box = _make_leader_panel_container(false)
	_enemy_leader_box = _make_leader_panel_container(true)


func _make_leader_panel_container(is_enemy: bool) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "EnemyLeaderPanel" if is_enemy else "PlayerLeaderPanel"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.z_index = 200
	box.add_theme_constant_override("separation", 6)

	# Zero-height anchors plus a growth direction let the box expand to fit
	# however many leaders the team has.
	if is_enemy:
		box.anchor_left = 1.0
		box.anchor_right = 1.0
		box.anchor_top = 0.0
		box.anchor_bottom = 0.0
		box.offset_right = -(SIDEBAR_WIDTH + LEADER_PANEL_MARGIN)
		box.offset_left = box.offset_right - LEADER_PANEL_WIDTH
		box.offset_top = LEADER_PANEL_MARGIN
		box.offset_bottom = LEADER_PANEL_MARGIN
		box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		box.grow_vertical = Control.GROW_DIRECTION_END
	else:
		box.anchor_left = 0.0
		box.anchor_right = 0.0
		box.anchor_top = 1.0
		box.anchor_bottom = 1.0
		box.offset_left = LEADER_PANEL_MARGIN
		box.offset_right = LEADER_PANEL_MARGIN + LEADER_PANEL_WIDTH
		box.offset_top = -LEADER_PANEL_MARGIN
		box.offset_bottom = -LEADER_PANEL_MARGIN
		box.grow_horizontal = Control.GROW_DIRECTION_END
		box.grow_vertical = Control.GROW_DIRECTION_BEGIN

	add_child(box)
	return box


func _get_leaders_for_player(player_id: int) -> Array[UnitBase]:
	var leaders: Array[UnitBase] = []
	for unit in match_ctrl.units:
		if unit.owner_id == player_id and unit.is_leader:
			leaders.append(unit)
	return leaders


func _refresh_leader_panels() -> void:
	var viewer: int = _get_active_player_id()
	if viewer < 0:
		viewer = 0
	_populate_leader_panel(_player_leader_box, viewer)
	_populate_leader_panel(_enemy_leader_box, 1 - viewer)


func _populate_leader_panel(box: VBoxContainer, player_id: int) -> void:
	if box == null:
		return
	var leaders: Array[UnitBase] = _get_leaders_for_player(player_id)

	# Fallen leaders stay listed, so the roster only changes on rebuild.
	var ids: PackedStringArray = PackedStringArray()
	for leader in leaders:
		ids.append(leader.id)
	var signature: String = "%d|%s" % [player_id, "|".join(ids)]
	if str(box.get_meta("signature", "")) != signature:
		_rebuild_leader_panel(box, player_id, leaders)
		box.set_meta("signature", signature)

	for leader in leaders:
		if _leader_rows.has(leader.id):
			_update_leader_row(_leader_rows[leader.id], leader)


func _rebuild_leader_panel(box: VBoxContainer, player_id: int, leaders: Array[UnitBase]) -> void:
	for child in box.get_children():
		var child_id: String = str(child.get_meta("unit_id", ""))
		if child_id != "":
			_leader_rows.erase(child_id)
		box.remove_child(child)
		child.queue_free()

	var team: TeamDefinition = TeamRegistry.get_team(GameState.selected_team_ids[player_id])
	box.add_child(_make_leader_header(player_id, team))
	for leader in leaders:
		box.add_child(_make_leader_row(leader, team.team_color))


func _make_leader_header(player_id: int, team: TeamDefinition) -> Label:
	var header := Label.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.text = "%s — %s" % [NetworkManager.get_display_name(player_id), team.team_name]
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", team.team_color)
	return header


func _make_leader_row(leader: UnitBase, team_color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_meta("unit_id", leader.id)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.1, 0.8)
	style.border_color = Color(team_color, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(name_label)

	var fill := StyleBoxFlat.new()
	fill.bg_color = team_color
	fill.set_corner_radius_all(3)

	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.11, 0.12, 0.15)
	background.set_corner_radius_all(3)

	var bar := ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	vbox.add_child(bar)

	_leader_rows[leader.id] = {
		"panel": panel,
		"name": name_label,
		"bar": bar,
		"fill": fill,
		"color": team_color,
	}
	return panel


func _update_leader_row(row: Dictionary, leader: UnitBase) -> void:
	var panel: PanelContainer = row["panel"]
	var name_label: Label = row["name"]
	var bar: ProgressBar = row["bar"]
	var fill: StyleBoxFlat = row["fill"]
	var team_color: Color = row["color"]

	bar.max_value = maxi(1, leader.max_health)
	bar.value = leader.health

	if not leader.is_alive:
		name_label.text = "%s — DEFEATED" % leader.display_name
		fill.bg_color = Color(0.3, 0.3, 0.34)
		panel.modulate = Color(0.6, 0.6, 0.65)
		return

	name_label.text = "%s   %d / %d" % [leader.display_name, leader.health, leader.max_health]
	panel.modulate = Color.WHITE
	# Bleed the fill toward red as the leader nears defeat.
	var ratio: float = float(leader.health) / float(maxi(1, leader.max_health))
	var danger: float = clampf(inverse_lerp(0.55, 0.15, ratio), 0.0, 1.0)
	fill.bg_color = team_color.lerp(Color(0.9, 0.2, 0.2), danger)


# --- Tile hover tooltip (name + effect for revealed/hidden tiles) ---
func _setup_tile_tooltip() -> void:
	_tile_tooltip = PanelContainer.new()
	_tile_tooltip.visible = false
	_tile_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tile_tooltip.z_index = 300
	add_child(_tile_tooltip)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_tile_tooltip.add_child(margin)
	_tile_tooltip_label = Label.new()
	_tile_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tile_tooltip_label.custom_minimum_size = Vector2(190, 0)
	margin.add_child(_tile_tooltip_label)


func _update_tile_tooltip_content(hex: Vector2i) -> void:
	var tile: TileBase = match_ctrl.grid.get_tile(hex)
	if tile == null:
		_tile_tooltip.visible = false
		return
	var title: String = tile.display_name if tile.revealed else "Unknown"
	var effect: String = tile.get_effect_description() if tile.revealed else "Hidden tile — move a unit here to reveal."
	_tile_tooltip_label.text = "%s\n%s" % [title, effect]
	_tile_tooltip.visible = true


func _position_tile_tooltip() -> void:
	if not _tile_tooltip.visible:
		return
	var mouse_pos: Vector2 = get_local_mouse_position()
	var tooltip_size: Vector2 = _tile_tooltip.get_minimum_size()
	var pos: Vector2 = mouse_pos + Vector2(16, 16)
	pos.x = minf(pos.x, size.x - tooltip_size.x - 8.0)
	pos.y = minf(pos.y, size.y - tooltip_size.y - 8.0)
	_tile_tooltip.position = pos


# --- Move path preview: confirmed paths (cyan) + hover preview (gold) ---
func _clear_move_paths() -> void:
	if _path_overlay == null:
		return
	for child in _path_overlay.get_children():
		child.queue_free()


func _update_move_path_preview(hover_hex: Vector2i) -> void:
	_clear_move_paths()
	if _action_mode != "move" or _match_ending:
		return

	for unit in match_ctrl.units:
		if not unit.is_alive or not unit.is_player_controllable():
			continue
		if unit.owner_id != _get_active_player_id():
			continue
		if not _move_targets.has(unit.id):
			continue
		var dest: Vector2i = _move_targets[unit.id]
		if dest == unit.hex_position:
			continue
		var path: Array[Vector2i] = match_ctrl.find_movement_path(unit, dest, _move_targets)
		_draw_move_path(path, PATH_COLOR_CONFIRMED)

	if _selected_unit != null:
		var preview_dest: Vector2i = hover_hex
		var is_taken: bool = false
		for uid in _move_targets:
			if uid != _selected_unit.id and _move_targets[uid] == preview_dest:
				is_taken = true
				break
		if not is_taken and preview_dest != _selected_unit.hex_position:
			if match_ctrl.can_move_unit_to(_selected_unit, preview_dest, _move_targets):
				var preview_path: Array[Vector2i] = match_ctrl.find_movement_path(
					_selected_unit, preview_dest, _move_targets
				)
				_draw_move_path(preview_path, PATH_COLOR_PREVIEW)


func _draw_move_path(path: Array[Vector2i], color: Color) -> void:
	if path.size() < 2:
		return
	var points: PackedVector2Array = PackedVector2Array()
	for hex in path:
		points.append(HexCoords.axial_to_pixel(hex, HEX_SIZE))
	var line := Line2D.new()
	line.points = points
	line.width = 3.5
	line.default_color = color
	line.antialiased = true
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_path_overlay.add_child(line)
	_add_path_arrowhead(points[points.size() - 2], points[points.size() - 1], color)


func _add_path_arrowhead(from: Vector2, to: Vector2, color: Color) -> void:
	var delta: Vector2 = to - from
	if delta.length_squared() < 0.001:
		return
	var dir: Vector2 = delta.normalized()
	var tip: Vector2 = to
	var wing: Vector2 = Vector2(-dir.y, dir.x) * 7.0
	var arrow := Polygon2D.new()
	arrow.polygon = PackedVector2Array([
		tip,
		tip - dir * 14.0 + wing,
		tip - dir * 14.0 - wing,
	])
	arrow.color = color
	_path_overlay.add_child(arrow)


func _get_unit_world_pos(unit_id: String) -> Vector2:
	if not _unit_nodes.has(unit_id):
		return Vector2.INF
	return _unit_nodes[unit_id].position


func _get_unit_node(unit_id: String) -> Node2D:
	if not _unit_nodes.has(unit_id):
		return null
	return _unit_nodes[unit_id]


# --- Combat visuals: listen to MatchController.combat_event, play VFX ---
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
			# Summon bursts need the projected hex, not raw board coordinates.
			var summon_hex: Variant = data.get("summon_hex")
			if summon_hex is Vector2i and summon_hex != Vector2i(-999, -999):
				data["summon_pos"] = _project_hex(summon_hex)
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
			return _project_hex(unit.hex_position)
	return Vector2.INF


# --- Victory/defeat overlay then transition to end_game scene ---
func _on_match_over(winner_id: int) -> void:
	_match_ending = true
	GameState.last_winner_id = winner_id
	_deselect_unit()
	_update_action_buttons()

	var local_player_id: int = 0 if GameState.is_solo() else GameState.get_local_player_id()
	var loser_id: int = 1 - winner_id
	var leader_pos: Vector2 = _find_losing_leader_position(loser_id)

	if GameState.is_solo():
		log_label.text = "Victory!" if winner_id == 0 else "Defeat!"

	await _battle_effects.play_match_end(self, board_root, winner_id, local_player_id, leader_pos)
	get_tree().change_scene_to_file("res://scenes/end_game.tscn")
