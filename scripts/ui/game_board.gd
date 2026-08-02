extends Control
## Main in-match UI: renders the hex board, handles player input, and bridges
## MatchController rules to visuals (units, paths, tooltips, combat effects).

# --- Scene references (sidebar + board root from game_board.tscn) ---
@onready var board_root: Node2D = %BoardRoot
@onready var sidebar: VBoxContainer = %Sidebar
@onready var turn_label: Label = %TurnLabel
@onready var actions_label: Label = %ActionsLabel
@onready var rp_label: Label = %RPLabel
@onready var log_label: Label = %LogLabel
@onready var move_button: Button = %MoveButton
@onready var end_turn_button: Button = %EndTurnButton
@onready var leave_game_button: Button = %LeaveGameButton
@onready var unit_info: Label = %UnitInfo

# --- Constants & preloads ---
const HEX_SIZE: float = 62.0
const UNIT_VISUAL_SCALE: float = 0.76
const UNIT_HIT_RADIUS: float = 14.0
const UNIT_HIT_RADIUS_LEADER: float = 17.5
const UNIT_HIT_RADIUS_MINION: float = 10.5
const BattleEffectsScript = preload("res://scripts/ui/battle_effects.gd")
const TileArtScript = preload("res://scripts/ui/tile_art.gd")
const UnitArtScript = preload("res://scripts/ui/unit_art.gd")
const CameraOrientationScript = preload("res://scripts/ui/camera_orientation.gd")

# --- Isometric projection & camera ---
## The board is drawn on a squashed, rotatable ground plane while units stay
## upright, which gives a 2.5D look without needing real 3D assets.
const ISO_SQUASH: float = 0.58  ## Vertical foreshortening of the ground plane.
const CAMERA_ROTATION_STEP: float = PI / 2.0  ## 90 degrees — four views around the board.
const CAMERA_TWEEN_TIME: float = 0.3
const UNIT_DEPTH_RANGE: int = 40  ## Largest z offset a unit may take from screen depth.
const ZOOM_MIN: float = 0.55
const ZOOM_MAX: float = 2.1
const ZOOM_STEP: float = 0.08
const DEFAULT_ZOOM: float = 1.0

# --- Tile presentation ---
const TILE_BORDER_COLOR := Color(0.03, 0.03, 0.05, 0.9)
const TILE_BORDER_WIDTH: float = 2.0

# --- On-board unit popup ---
const UNIT_POPUP_WIDTH: float = 226.0
const UNIT_POPUP_GAP: float = 26.0  ## Horizontal clearance from the unit marker.

# --- Leader health panel layout (kept clear of the right-hand sidebar) ---
const SIDEBAR_WIDTH: float = 248.0
const SIDEBAR_WIDTH_MIN: float = 210.0
const SIDEBAR_WIDTH_MAX: float = 280.0
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
var _unit_popup_separator: Control
var _unit_popup_close_button: Button
var _turn_banner: PanelContainer
var _turn_banner_label: Label

# --- Camera state (see ISO_SQUASH notes above) ---
var _camera_rig: Node2D  ## Pan + zoom container for the whole battlefield view.
var _camera_pan: Vector2 = Vector2.ZERO
var _camera_zoom: float = DEFAULT_ZOOM
var _dragging_camera: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_pan: Vector2 = Vector2.ZERO
var _camera_rotating: bool = false
var _manual_camera: bool = false  ## User adjusted pan/zoom; skip auto-fit on resize.
var _scroll_background: Control
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
var _synced_orientation: int = -1

# --- Leader health bars (supports teams with any number of leaders) ---
var _player_leader_box: VBoxContainer
var _enemy_leader_box: VBoxContainer
var _leader_rows: Dictionary = {}  ## unit_id -> { panel, name, bar, fill, color }
var _player_panel_stats: Dictionary = {}  ## player_id -> Label (AP/RP under leader panel)
var _leave_game_dialog: AcceptDialog

# --- Match intro + pre-game unit deployment ---
var _intro_animating: bool = false
var _placement_active: bool = false
var _placement_overlay: Node2D
var _placement_zone_nodes: Dictionary = {}  ## hex -> Polygon2D highlight
var _placement_selected_unit_id: String = ""

# --- Move path preview colors ---
const PATH_COLOR_CONFIRMED := Color(0.35, 0.85, 0.95, 0.9)
const PATH_COLOR_PREVIEW := Color(1.0, 0.92, 0.45, 0.75)

# --- Match intro and pre-game deployment ---
const MAP_INTRO_TILE_DELAY: float = 0.018
const MAP_INTRO_TILE_DURATION: float = 0.14
const PLACEMENT_ZONE_COLOR := Color(0.35, 0.95, 0.55, 0.22)
const PLACEMENT_ZONE_BORDER := Color(0.45, 1.0, 0.65, 0.75)


# --- Lifecycle: wire signals, start or resume match, build visuals ---
func _ready() -> void:
	add_to_group("game_board")
	# Let board clicks fall through to _unhandled_input; child Controls such as
	# the sidebar and unit popup still capture their own input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_info.text = "Click a unit on the board to inspect it."

	move_button.pressed.connect(_set_mode.bind("move"))
	end_turn_button.pressed.connect(_on_end_turn)
	leave_game_button.pressed.connect(_on_leave_game_pressed)

	match_ctrl.state_changed.connect(_refresh_ui)
	match_ctrl.action_log.connect(_append_log)
	match_ctrl.match_over.connect(_on_match_over)
	match_ctrl.combat_event.connect(_on_combat_event)
	NetworkManager.action_applied.connect(_on_network_action)
	NetworkManager.placement_submit_received.connect(_on_placement_submit_received)
	NetworkManager.placement_snapshot_applied.connect(_on_network_placement_snapshot)

	if GameState.pending_rematch_same_teams:
		GameState.pending_rematch_same_teams = false
	elif GameState.pending_rematch_new_select:
		get_tree().change_scene_to_file("res://scenes/character_select.tscn")
		return

	var resuming_saved_match: bool = GameState.pending_saved_match_resume
	var saved_match_data: Dictionary = GameState.pending_saved_match_data
	if resuming_saved_match:
		GameState.pending_saved_match_resume = false
		GameState.pending_saved_match_data = {}

	# Layers must exist before setup_match / restore, whose state_changed signal already
	# triggers a refresh that spawns unit visuals into the actor layer.
	_setup_scroll_background()
	_setup_board_layers()
	if not resized.is_connected(_apply_viewport_layout):
		resized.connect(_apply_viewport_layout)
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	_apply_viewport_layout()

	if resuming_saved_match:
		await _bootstrap_saved_match(saved_match_data)
		return

	var match_seed: int = GameState.match_seed if GameState.match_seed >= 0 else -1
	match_ctrl.setup_match(match_seed)
	_connect_turn_signals()
	_build_board_visuals()
	_apply_viewport_layout()
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
	_setup_turn_banner()
	_setup_camera_controls()
	_setup_leader_panels()
	_setup_leave_game_dialog()
	actions_label.visible = false
	rp_label.visible = false
	_setup_placement_overlay()
	_update_action_buttons()
	set_process(true)
	await _play_map_intro()
	await _run_placement_phase()
	_cache_base_yaws()
	_update_camera_for_viewer(_get_viewer_player_id(), false)
	_apply_viewport_layout()
	_refresh_ui()


func _bootstrap_saved_match(save_data: Dictionary) -> void:
	GameState.match_seed = int(save_data.get("match_seed", GameState.match_seed))
	for player_id in 2:
		var team_ids: Array = save_data.get("selected_team_ids", [-1, -1])
		if player_id < team_ids.size() and int(team_ids[player_id]) >= 0:
			GameState.lock_team(player_id, int(team_ids[player_id]))
	match_ctrl.restore_from_snapshot(save_data.get("match", {}))
	_connect_turn_signals()
	_build_board_visuals()
	_apply_viewport_layout()
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
	_setup_turn_banner()
	_setup_camera_controls()
	_setup_leader_panels()
	_setup_leave_game_dialog()
	actions_label.visible = false
	rp_label.visible = false
	_setup_placement_overlay()
	_update_action_buttons()
	set_process(true)
	if match_ctrl.placement_active:
		await _run_placement_phase()
	_cache_base_yaws()
	_update_camera_for_viewer(_get_viewer_player_id(), false)
	_apply_viewport_layout()
	_refresh_ui()
	log_label.text = "Saved match resumed."


func _on_viewport_size_changed() -> void:
	call_deferred("_apply_viewport_layout")


func _apply_viewport_layout() -> void:
	if not is_node_ready() or board_root == null:
		return
	_sync_sidebar_layout()
	var board_area: Rect2 = _get_board_area_rect()
	board_root.position = board_area.position + board_area.size * 0.5
	if not _manual_camera:
		_fit_board_zoom_to_view(board_area)
	else:
		_apply_camera_transform()
	if _enemy_leader_box != null:
		var sidebar_width: float = _get_sidebar_width()
		_enemy_leader_box.offset_right = -(sidebar_width + LEADER_PANEL_MARGIN)
		_enemy_leader_box.offset_left = _enemy_leader_box.offset_right - LEADER_PANEL_WIDTH
	if _scroll_background:
		_scroll_background.set_size(size)
		_scroll_background.queue_redraw()
	_position_unit_popup()


func _sync_sidebar_layout() -> void:
	if sidebar == null:
		return
	var sidebar_width: float = _get_sidebar_width()
	sidebar.offset_left = -sidebar_width
	sidebar.offset_top = 0.0
	sidebar.offset_bottom = 0.0


func _get_board_area_rect() -> Rect2:
	var view_size: Vector2 = size
	if view_size.x < 8.0 or view_size.y < 8.0:
		view_size = get_viewport_rect().size
	var sidebar_width: float = _get_sidebar_width()
	var board_width: float = maxf(240.0, view_size.x - sidebar_width)
	return Rect2(Vector2.ZERO, Vector2(board_width, view_size.y))


func _get_sidebar_width() -> float:
	if size.x > 1.0:
		return clampf(size.x * 0.22, SIDEBAR_WIDTH_MIN, SIDEBAR_WIDTH_MAX)
	return SIDEBAR_WIDTH


func _estimate_board_pixel_radius() -> float:
	if match_ctrl != null and match_ctrl.grid != null:
		var max_dist: float = 0.0
		for hex in match_ctrl.grid.get_all_hexes():
			max_dist = maxf(max_dist, HexCoords.axial_to_pixel(hex, HEX_SIZE).length())
		return max_dist + HEX_SIZE * 1.25
	return float(MatchController.BOARD_RADIUS) * HEX_SIZE * 1.85


func _fit_board_zoom_to_view(board_area: Rect2) -> void:
	if _camera_rig == null:
		return
	var board_radius: float = _estimate_board_pixel_radius()
	var squash: float = ISO_SQUASH if _iso_enabled else 1.0
	var needed_w: float = board_radius * 2.2
	var needed_h: float = board_radius * 2.2 * squash
	if needed_w <= 0.0 or needed_h <= 0.0:
		return
	var fit_zoom: float = minf(board_area.size.x / needed_w, board_area.size.y / needed_h)
	_camera_zoom = clampf(fit_zoom, ZOOM_MIN, ZOOM_MAX)
	_apply_camera_transform()


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
	_update_camera_for_viewer(_get_viewer_player_id(), true)


func _setup_scroll_background() -> void:
	_scroll_background = ScrollBackground.new()
	_scroll_background.name = "ScrollBackground"
	_scroll_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll_background.set_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_scroll_background)
	move_child(_scroll_background, 0)


# --- Board layers: a squashed, rotatable ground plane plus upright actors ---
## Screen position = squash * yaw * board position, so the ground tilts away
## while units and effects stay readable at their projected spot.
func _setup_board_layers() -> void:
	_camera_rig = Node2D.new()
	_camera_rig.name = "CameraRig"
	board_root.add_child(_camera_rig)

	_ground_layer = Node2D.new()
	_ground_layer.name = "GroundLayer"
	_ground_layer.scale = Vector2(1.0, ISO_SQUASH)
	_camera_rig.add_child(_ground_layer)

	_ground_pivot = Node2D.new()
	_ground_pivot.name = "GroundPivot"
	_ground_layer.add_child(_ground_pivot)

	_actor_layer = Node2D.new()
	_actor_layer.name = "ActorLayer"
	# Must exceed UNIT_DEPTH_RANGE so that even the farthest unit, which takes
	# the most negative depth offset, still sorts above the ground plane.
	_actor_layer.z_index = 50
	_camera_rig.add_child(_actor_layer)
	_apply_camera_transform()


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
		if match_ctrl.is_unit_placed(unit):
			_spawn_unit_visual(unit)


func _prepare_tiles_for_intro() -> void:
	for hex in _tile_nodes:
		var poly: Polygon2D = _tile_nodes[hex]
		poly.scale = Vector2.ZERO
		poly.modulate = Color(1.0, 1.0, 1.0, 0.0)


func _play_map_intro() -> void:
	_intro_animating = true
	_prepare_tiles_for_intro()
	log_label.text = "Generating battlefield..."

	var hexes: Array = match_ctrl.grid.get_all_hexes()
	hexes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return HexCoords.distance(a, Vector2i.ZERO) < HexCoords.distance(b, Vector2i.ZERO),
	)

	for i in hexes.size():
		var hex: Vector2i = hexes[i]
		var poly: Polygon2D = _tile_nodes[hex]
		var delay: float = float(i) * MAP_INTRO_TILE_DELAY
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(poly, "scale", Vector2.ONE, MAP_INTRO_TILE_DURATION)\
			.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(poly, "modulate:a", 1.0, MAP_INTRO_TILE_DURATION * 0.7)\
			.set_delay(delay)

	await get_tree().create_timer(
		float(hexes.size()) * MAP_INTRO_TILE_DELAY + MAP_INTRO_TILE_DURATION + 0.08,
	).timeout
	_intro_animating = false
	log_label.text = "Choose deployment positions."


func _setup_placement_overlay() -> void:
	_placement_overlay = Node2D.new()
	_placement_overlay.name = "PlacementOverlay"
	_placement_overlay.z_index = 3
	_ground_pivot.add_child(_placement_overlay)


func _run_placement_phase() -> void:
	_placement_active = true
	_update_action_buttons()
	while match_ctrl.placement_active:
		var pid: int = match_ctrl.placement_player
		_camera_owner_id = -1
		_update_camera_for_viewer(_get_viewer_player_id(), true)
		if _is_local_placement_player(pid):
			_select_next_placement_unit(pid)
		_refresh_placement_highlights()
		_update_placement_ui()
		if _should_auto_place(pid):
			await get_tree().create_timer(0.55).timeout
			MatchAI.run_placement(match_ctrl, pid)
			_on_player_finished_placing(pid)
			continue
		await _wait_for_placement_player(pid)
	_placement_active = false
	_clear_placement_highlights()
	_update_action_buttons()


func _wait_for_placement_player(player_id: int) -> void:
	while match_ctrl.placement_active and match_ctrl.placement_player == player_id:
		await match_ctrl.state_changed
	_on_player_finished_placing(player_id)


func _on_player_finished_placing(player_id: int) -> void:
	for unit in match_ctrl.units:
		if unit.owner_id == player_id and match_ctrl.is_unit_placed(unit):
			if not _unit_nodes.has(unit.id):
				_spawn_unit_visual(unit, true)
	if _is_local_placement_player(match_ctrl.placement_player):
		_select_next_placement_unit(match_ctrl.placement_player)
	_refresh_placement_highlights()
	_update_placement_ui()


func _should_auto_place(player_id: int) -> bool:
	return GameState.is_solo() and player_id == GameState.get_ai_player_id()


func _is_local_placement_player(player_id: int) -> bool:
	if GameState.is_solo():
		return player_id == 0
	if GameState.match_mode == GameState.MatchMode.LOCAL:
		return true
	return player_id == GameState.get_local_player_id()


func _get_roster_units(player_id: int) -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	for unit in match_ctrl.units:
		if unit.owner_id == player_id:
			result.append(unit)
	return result


func _select_next_placement_unit(player_id: int) -> void:
	var unplaced: Array[UnitBase] = match_ctrl.get_unplaced_units(player_id)
	if unplaced.is_empty():
		_placement_selected_unit_id = ""
		return
	if _placement_selected_unit_id.is_empty():
		_placement_selected_unit_id = unplaced[0].id
		return
	for unit in unplaced:
		if unit.id == _placement_selected_unit_id:
			return
	_placement_selected_unit_id = unplaced[0].id


func _get_selected_placement_unit(player_id: int) -> UnitBase:
	if _placement_selected_unit_id.is_empty():
		return null
	for unit in match_ctrl.get_unplaced_units(player_id):
		if unit.id == _placement_selected_unit_id:
			return unit
	return null


func _refresh_placement_highlights() -> void:
	if _placement_overlay == null:
		return
	for hex in _placement_zone_nodes:
		var node: Polygon2D = _placement_zone_nodes[hex]
		if is_instance_valid(node):
			node.queue_free()
	_placement_zone_nodes.clear()

	if not _placement_active or not match_ctrl.placement_active:
		return

	var pid: int = match_ctrl.placement_player
	if not _is_local_placement_player(pid):
		return

	for hex in match_ctrl.get_placement_zone(pid):
		var poly := Polygon2D.new()
		var points: PackedVector2Array = PackedVector2Array()
		for i in 6:
			var angle: float = deg_to_rad(60 * i - 30)
			points.append(Vector2(cos(angle), sin(angle)) * (HEX_SIZE - 1.0))
		poly.polygon = points
		poly.color = PLACEMENT_ZONE_COLOR
		poly.position = HexCoords.axial_to_pixel(hex, HEX_SIZE)
		var border := Line2D.new()
		border.points = points
		border.closed = true
		border.width = 1.5
		border.default_color = PLACEMENT_ZONE_BORDER
		border.antialiased = true
		poly.add_child(border)
		_placement_overlay.add_child(poly)
		_placement_zone_nodes[hex] = poly


func _clear_placement_highlights() -> void:
	for hex in _placement_zone_nodes:
		var node: Polygon2D = _placement_zone_nodes[hex]
		if is_instance_valid(node):
			node.queue_free()
	_placement_zone_nodes.clear()


func _update_placement_ui() -> void:
	if not _placement_active:
		return
	var pid: int = match_ctrl.placement_player
	var team: TeamDefinition = TeamRegistry.get_team(GameState.selected_team_ids[pid])
	var who: String = "You" if _is_local_placement_player(pid) else "Player %d" % (pid + 1)
	if GameState.is_solo() and pid == GameState.get_ai_player_id():
		who = "AI"

	var lines: PackedStringArray = PackedStringArray()
	lines.append("Deploy units — %s" % who)
	lines.append("Team: %s" % team.team_name)
	lines.append("")

	var is_local_turn: bool = _is_local_placement_player(pid)
	if is_local_turn:
		lines.append("Place each unit in the highlighted rear rows.")
		lines.append("Your leader's starting tile becomes your home base.")
	else:
		lines.append("Waiting for %s to finish deploying." % who)
	lines.append("")

	var unplaced: Array[UnitBase] = match_ctrl.get_unplaced_units(pid)
	for unit in _get_roster_units(pid):
		if match_ctrl.is_unit_placed(unit):
			lines.append("✓ %s — deployed" % unit.display_name)
		elif is_local_turn and unit.id == _placement_selected_unit_id:
			lines.append("► %s — click a highlighted hex" % unit.display_name)
		elif is_local_turn:
			lines.append("  %s — waiting" % unit.display_name)
		else:
			lines.append("  %s" % unit.display_name)

	if unplaced.is_empty():
		lines.append("")
		lines.append("Deployment complete.")
	unit_info.text = "\n".join(lines)
	_rebuild_placement_unit_picker(pid)


func _rebuild_placement_unit_picker(player_id: int) -> void:
	_clear_unit_action_buttons()
	if not _placement_active or not _is_local_placement_player(player_id):
		return
	if match_ctrl.placement_player != player_id:
		return
	for unit in match_ctrl.get_unplaced_units(player_id):
		var is_selected: bool = unit.id == _placement_selected_unit_id
		var label: String = ("► " if is_selected else "") + unit.display_name
		_add_unit_action_button(
			label,
			true,
			"Select this unit to deploy." if not is_selected else "Currently selected for deployment.",
			func() -> void:
				_placement_selected_unit_id = unit.id
				_update_placement_ui(),
		)


func _get_local_placement_player_id() -> int:
	if GameState.is_online():
		return GameState.get_local_player_id()
	if GameState.match_mode == GameState.MatchMode.LOCAL:
		return match_ctrl.placement_player
	return 0


func _ensure_placement_selection(player_id: int) -> void:
	if _get_selected_placement_unit(player_id) != null:
		return
	_select_next_placement_unit(player_id)


func _handle_placement_click(hex: Vector2i) -> void:
	if not _placement_active or not match_ctrl.placement_active:
		return
	var local_pid: int = _get_local_placement_player_id()
	if match_ctrl.placement_player != local_pid:
		return
	if not _is_local_placement_player(local_pid):
		return
	_ensure_placement_selection(local_pid)
	var unit: UnitBase = _get_selected_placement_unit(local_pid)
	if unit == null:
		log_label.text = "Select a unit to deploy."
		return
	if GameState.is_online() and not NetworkManager.is_server():
		log_label.text = "Deploying %s..." % unit.display_name
		NetworkManager.submit_placement_unit(local_pid, unit.id, hex)
		return
	if not match_ctrl.can_place_at(local_pid, hex):
		log_label.text = "Can't deploy there."
		return
	var result: Dictionary = match_ctrl.place_unit(local_pid, unit.id, hex)
	if not result.get("success", false):
		log_label.text = result.get("message", "Deployment failed.")
		return
	if GameState.is_online():
		NetworkManager.rpc_apply_placement_snapshot.rpc(result)
	else:
		_apply_placement_result(result)


func _on_placement_submit_received(player_id: int, unit_id: String, hex: Vector2i) -> void:
	if not GameState.is_online() or not NetworkManager.is_server():
		return
	var result: Dictionary = match_ctrl.place_unit(player_id, unit_id, hex)
	NetworkManager.rpc_apply_placement_snapshot.rpc(result)


func _on_network_placement_snapshot(snapshot: Dictionary) -> void:
	if not snapshot.get("success", false):
		if _placement_active:
			log_label.text = snapshot.get("message", "Deployment rejected.")
		return
	match_ctrl.apply_placement_snapshot(snapshot)
	_apply_placement_result(snapshot)


func _apply_placement_result(result: Dictionary) -> void:
	if not result.get("success", false):
		log_label.text = result.get("message", "Deployment failed.")
		return
	var unit: UnitBase = match_ctrl.find_unit_by_id(str(result.get("unit_id", "")))
	if unit == null:
		return
	log_label.text = result.get("message", "Deployed.")
	_spawn_unit_visual(unit, true)
	_select_next_placement_unit(match_ctrl.placement_player)
	_refresh_placement_highlights()
	_update_placement_ui()


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
	var previous: Node = anchor.get_node_or_null("OrientedDecor")
	if previous == null:
		previous = anchor.get_node_or_null("Decor")
	if previous != null:
		anchor.remove_child(previous)
		previous.queue_free()

	var team_color: Color = Color.WHITE
	if tile.is_team_unique and tile.team_id >= 0:
		team_color = TeamRegistry.get_team(tile.team_id).team_color
	var decor: OrientedVisual = TileArtScript.build_oriented(type_id, team_color)
	decor.name = "OrientedDecor"
	anchor.add_child(decor)
	anchor.move_child(decor, 0)
	_update_node_orientation(decor)

	# Revealed terrain speaks for itself; only fogged hexes need the glyph.
	var label: Label = anchor.get_node_or_null("TileLabel") as Label
	if label != null:
		label.text = tile.get_hidden_label() if not tile.revealed else ""


func _spawn_unit_visual(unit: UnitBase, animate_spawn: bool = false) -> void:
	if not match_ctrl.is_unit_placed(unit):
		return
	if _unit_nodes.has(unit.id):
		return

	var container := Node2D.new()
	container.set_meta("unit_id", unit.id)
	container.scale = Vector2(UNIT_VISUAL_SCALE, UNIT_VISUAL_SCALE)

	var shadow_rx: float = HEX_SIZE * 0.42
	var shadow_ry: float = shadow_rx * ISO_SQUASH
	if unit.is_minion:
		shadow_rx *= 0.65
		shadow_ry *= 0.65
	elif unit.is_leader:
		shadow_rx *= 1.15
		shadow_ry *= 1.15

	var shadow := Polygon2D.new()
	shadow.name = "Shadow"
	shadow.polygon = _make_ellipse_points(shadow_rx, shadow_ry)
	shadow.color = Color(0.0, 0.0, 0.0, 0.28)
	shadow.position = Vector2(0, HEX_SIZE * 0.24)
	container.add_child(shadow)

	var team: TeamDefinition = TeamRegistry.get_team(GameState.selected_team_ids[unit.owner_id])
	var oriented_body: OrientedVisual = UnitArtScript.build_oriented_board_unit(
		unit.get_unit_type_id(),
		team.team_color,
		unit.is_leader,
		unit.is_minion,
	)
	oriented_body.name = "OrientedBody"
	if unit.is_ai_controlled:
		oriented_body.modulate = Color(0.9, 0.95, 0.9)
	container.add_child(oriented_body)
	_update_node_orientation(oriented_body)

	_actor_layer.add_child(container)
	_place_unit_node(container, unit.hex_position)
	_unit_nodes[unit.id] = container
	if animate_spawn:
		container.scale = Vector2(0.2, 0.2)
		var pop := create_tween()
		var target_scale := Vector2.ONE * UNIT_VISUAL_SCALE
		pop.tween_property(container, "scale", target_scale, 0.28).set_trans(Tween.TRANS_BACK)


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
		var oriented: OrientedVisual = container.get_node_or_null("OrientedBody") as OrientedVisual
		if oriented == null:
			continue
		oriented.set_hover_highlight(unit_id == _hovered_unit_id)
		var selected: bool = _selected_unit != null and _selected_unit.id == unit_id
		oriented.set_selection_outline(selected)


# --- Sidebar sync: turn counters, tile colors, unit positions, action buttons ---
func _refresh_ui() -> void:
	if match_ctrl.placement_active or _placement_active:
		_update_placement_ui()
		_update_action_buttons()
		return
	var pid: int = match_ctrl.turn_manager.current_player
	if GameState.is_solo():
		var who: String = "Your Turn" if pid == 0 else "AI Turn"
		turn_label.text = "Turn %d — %s" % [match_ctrl.turn_manager.turn_number, who]
	else:
		turn_label.text = "Turn %d — Player %d" % [match_ctrl.turn_manager.turn_number, pid + 1]
	_update_board_colors()
	_update_unit_positions()
	_update_unit_visual_states()
	_update_move_button_label()
	_update_action_buttons()
	_update_unit_popup()
	_refresh_leader_panels()


func _update_board_colors() -> void:
	for hex in _tile_nodes:
		var tile: TileBase = match_ctrl.grid.get_tile(hex)
		var poly: Polygon2D = _tile_nodes[hex]
		poly.color = tile.get_revealed_color() if tile.revealed else Color(0.15, 0.16, 0.2)
		_refresh_tile_decor(poly, tile)


func _update_unit_positions() -> void:
	for unit in match_ctrl.units:
		if not match_ctrl.is_unit_placed(unit):
			continue
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
	move_button.disabled = not can_act or match_ctrl.placement_active
	end_turn_button.disabled = not can_act or match_ctrl.placement_active
	if _action_mode != "move" or _move_targets.is_empty():
		move_button.text = "Move (+1 RP)"


# --- Who may click actions (solo human, hot-seat, or online local player) ---
func _can_local_player_act() -> bool:
	if _intro_animating or _placement_active or match_ctrl.placement_active:
		return false
	if GameState.is_solo():
		return match_ctrl.turn_manager.current_player == 0 and match_ctrl.turn_manager.can_spend_action() and not _ai_running
	if GameState.match_mode == GameState.MatchMode.LOCAL:
		return match_ctrl.turn_manager.can_spend_action()
	var local_id: int = GameState.get_local_player_id()
	return match_ctrl.turn_manager.current_player == local_id and match_ctrl.turn_manager.can_spend_action()


# --- Solo AI: run opponent turn after a short delay ---
func _on_turn_started(player_id: int) -> void:
	_refresh_ui()
	_play_turn_banner(player_id)
	if GameState.is_solo() and player_id == GameState.get_ai_player_id():
		_run_ai_turn_async()


func _get_active_player_id() -> int:
	if match_ctrl.placement_active:
		if GameState.is_solo():
			return 0
		if GameState.match_mode == GameState.MatchMode.LOCAL:
			return match_ctrl.placement_player
		return GameState.get_local_player_id()
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
		move_button.text = "Move (+1 RP)"


# --- Per-frame hover: unit highlight, tile tooltip, move path preview ---
func _process(_delta: float) -> void:
	_sync_camera_dependent_visuals()
	if _intro_animating:
		return
	if _placement_active or match_ctrl.placement_active:
		return
	if _ai_running or _match_ending or _move_animating:
		if _match_ending:
			_tile_tooltip.visible = false
		return
	var hex: Vector2i = _hex_under_mouse()
	var unit_under_mouse: UnitBase = _get_unit_under_mouse()
	var hovered_id: String = unit_under_mouse.id if unit_under_mouse != null else ""
	if hovered_id != _hovered_unit_id:
		_hovered_unit_id = hovered_id
		_update_unit_visual_states()

	if _unit_popup != null and _unit_popup.visible:
		_position_unit_popup()

	if unit_under_mouse == null and match_ctrl.grid.has_tile(hex):
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
			_update_move_path_preview(hex if match_ctrl.grid.has_tile(hex) else Vector2i(999999, 999999))


## Board input is deliberately "unhandled": the sidebar and the unit popup are
## ordinary Controls that swallow their own clicks, so a press only reaches the
## board when it landed on empty space.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_set_zoom(_camera_zoom + ZOOM_STEP)
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_set_zoom(_camera_zoom - ZOOM_STEP)
				return
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if event.pressed:
					_dragging_camera = true
					_drag_start_mouse = event.position
					_drag_start_pan = _camera_pan
				else:
					_dragging_camera = false
				return
	if event is InputEventMouseMotion and _dragging_camera:
		_manual_camera = true
		_camera_pan = _drag_start_pan + (event.position - _drag_start_mouse) / maxf(_camera_zoom, 0.05)
		_apply_camera_transform()
		return
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
				if _placement_active:
					return
				_deselect_unit()
				return
	if _intro_animating:
		return
	if _placement_active or match_ctrl.placement_active:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var hex: Vector2i = _hex_under_mouse()
			if match_ctrl.grid.has_tile(hex):
				_handle_placement_click(hex)
		return
	if _match_ending or _move_animating:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hex: Vector2i = _hex_under_mouse()
		if not match_ctrl.grid.has_tile(hex):
			_deselect_unit()
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
	var clicked_unit: UnitBase = _get_unit_under_mouse()

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
	_unit_popup_close_button = close_button

	_unit_popup_info = Label.new()
	_unit_popup_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unit_popup_info.custom_minimum_size = Vector2(UNIT_POPUP_WIDTH, 0)
	_unit_popup_info.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_unit_popup_info)

	_unit_popup_separator = HSeparator.new()
	vbox.add_child(_unit_popup_separator)

	_unit_actions_box = VBoxContainer.new()
	_unit_actions_box.add_theme_constant_override("separation", 4)
	vbox.add_child(_unit_actions_box)

	add_child(_unit_popup)


func _setup_leave_game_dialog() -> void:
	if _leave_game_dialog != null:
		return
	_leave_game_dialog = AcceptDialog.new()
	_leave_game_dialog.title = "Leave Game"
	_leave_game_dialog.dialog_text = "Leave this match?"
	_leave_game_dialog.add_cancel_button("Cancel")
	if GameState.match_mode == GameState.MatchMode.ONLINE_HOST:
		_leave_game_dialog.add_button("Save & Exit", false, "save_exit")
		_leave_game_dialog.add_button("Exit without Saving", false, "exit")
	else:
		_leave_game_dialog.add_button("Leave Game", false, "exit")
	_leave_game_dialog.custom_action.connect(_on_leave_game_dialog_action)
	add_child(_leave_game_dialog)


func _on_leave_game_pressed() -> void:
	if _leave_game_dialog == null:
		_setup_leave_game_dialog()
	if GameState.is_online() and match_ctrl.can_save_match() and not _match_ending:
		_leave_game_dialog.popup_centered()
	else:
		_exit_to_main_menu(false)


func _on_leave_game_dialog_action(action: StringName) -> void:
	if String(action) == "save_exit":
		_exit_to_main_menu(true)
	elif String(action) == "exit":
		_exit_to_main_menu(false)


func _exit_to_main_menu(save_first: bool) -> void:
	if save_first and GameState.match_mode == GameState.MatchMode.ONLINE_HOST:
		var snapshot: Dictionary = SaveGameManager.build_snapshot(match_ctrl)
		if not SaveGameManager.save_snapshot(snapshot):
			log_label.text = "Failed to save match."
			return
	NetworkManager.disconnect_game()
	GameState.reset_match_state()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _setup_turn_banner() -> void:
	_turn_banner = PanelContainer.new()
	_turn_banner.name = "TurnBanner"
	_turn_banner.visible = false
	_turn_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_banner.z_index = 300
	_turn_banner.set_anchors_preset(Control.PRESET_CENTER)
	_turn_banner.offset_left = -220.0
	_turn_banner.offset_right = 220.0
	_turn_banner.offset_top = -36.0
	_turn_banner.offset_bottom = 36.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.14, 0.9)
	style.border_color = Color(0.72, 0.78, 0.88, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	_turn_banner.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_turn_banner.add_child(margin)

	_turn_banner_label = Label.new()
	_turn_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_turn_banner_label.add_theme_font_size_override("font_size", 30)
	margin.add_child(_turn_banner_label)
	add_child(_turn_banner)


func _play_turn_banner(player_id: int) -> void:
	if _turn_banner == null or match_ctrl.placement_active or _placement_active:
		return

	_turn_banner_label.text = _format_turn_banner_text(player_id)
	var team: TeamDefinition = TeamRegistry.get_team(GameState.selected_team_ids[player_id])
	_turn_banner_label.modulate = team.team_color.lightened(0.35)

	_turn_banner.visible = true
	_turn_banner.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_turn_banner.scale = Vector2(0.88, 0.88)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_turn_banner, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_turn_banner, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK)
	tween.chain().tween_interval(1.15)
	tween.tween_property(_turn_banner, "modulate:a", 0.0, 0.32).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(func() -> void: _turn_banner.visible = false)


func _format_turn_banner_text(player_id: int) -> String:
	if GameState.is_solo():
		return "Your Turn" if player_id == 0 else "AI Turn"
	if GameState.is_online():
		if player_id == GameState.get_local_player_id():
			return "Your Turn"
		return "Opponent's Turn"
	return "Player %d's Turn" % (player_id + 1)


func _select_unit(unit: UnitBase) -> void:
	_selected_unit = unit
	_update_unit_popup()
	_update_unit_visual_states()


func _deselect_unit() -> void:
	_selected_unit = null
	_clear_unit_action_buttons()
	if _unit_popup != null:
		_unit_popup.visible = false
	_update_unit_visual_states()


func _update_unit_popup() -> void:
	if _unit_popup == null:
		return
	if _selected_unit == null or not _selected_unit.is_alive:
		_unit_popup.visible = false
		return

	var unit: UnitBase = _selected_unit
	_unit_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_unit_popup_title.text = unit.display_name
	_unit_popup_info.text = _build_unit_info_text(unit)
	_unit_popup_close_button.visible = true

	_clear_unit_action_buttons()
	var show_actions: bool = false
	if unit.owner_id == _get_active_player_id() \
			and unit.is_player_controllable() \
			and _can_local_player_act():
		_rebuild_unit_action_buttons(unit)
		show_actions = _unit_actions_box.get_child_count() > 0
	_unit_popup_separator.visible = show_actions
	_unit_actions_box.visible = show_actions

	_unit_popup.visible = true
	_position_unit_popup()


## Keeps the popup pinned beside its unit, flipping sides and clamping so it
## never slides under the sidebar or off-screen.
func _position_unit_popup() -> void:
	if _unit_popup == null or not _unit_popup.visible:
		return
	if _selected_unit == null or not _unit_nodes.has(_selected_unit.id):
		_unit_popup.visible = false
		return

	var unit: UnitBase = _selected_unit
	var unit_node: Node2D = _unit_nodes[unit.id]
	var anchor: Vector2 = get_global_transform().affine_inverse() * _actor_layer.to_global(unit_node.position)
	var popup_size: Vector2 = _unit_popup.size.max(_unit_popup.get_combined_minimum_size())
	var right_limit: float = size.x - _get_sidebar_width() - popup_size.x - 8.0
	var mouse_local: Vector2 = get_local_mouse_position()

	var pos_right: Vector2 = Vector2(anchor.x + UNIT_POPUP_GAP, anchor.y - popup_size.y * 0.5)
	var pos_left: Vector2 = Vector2(anchor.x - UNIT_POPUP_GAP - popup_size.x, anchor.y - popup_size.y * 0.5)
	var use_right: bool

	if _action_mode == "move":
		var rect_right: Rect2 = Rect2(pos_right, popup_size)
		var rect_left: Rect2 = Rect2(pos_left, popup_size)
		if rect_right.has_point(mouse_local):
			use_right = false
		elif rect_left.has_point(mouse_local):
			use_right = true
		else:
			use_right = pos_right.x <= right_limit
	else:
		use_right = pos_right.x <= right_limit

	var pos: Vector2 = pos_right if use_right else pos_left
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

	var targets_in_range: int = _count_attack_targets(unit, los_check)
	_add_unit_action_button(
		"Attack" + (" — %d target(s)" % targets_in_range if targets_in_range > 0 else ""),
		can_spend and targets_in_range > 0,
		"Select an enemy in range to attack." if can_spend and targets_in_range > 0 else "No valid targets in range.",
		func() -> void:
			_set_mode("attack")
			_select_unit(unit)
			log_label.text = "Select an enemy for %s to attack." % unit.display_name,
	)

	var ability_check: Dictionary = _get_ability_action_status(unit, rp, can_spend)
	_add_unit_action_button(
		"Ability (%d RP)" % unit.ability_cost,
		ability_check.get("enabled", false),
		ability_check.get("hint", ""),
		func() -> void:
			_begin_ability_with_unit(unit),
	)

	var tile: TileBase = match_ctrl.grid.get_tile(unit.hex_position)
	var can_tile: bool = can_spend and tile != null and tile.can_interact(unit)
	_add_unit_action_button(
		"Tile Interact",
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


func _get_unit_under_mouse() -> UnitBase:
	if _actor_layer == null:
		return null
	var mouse_pos: Vector2 = _actor_layer.get_local_mouse_position()
	var closest: UnitBase = null
	var closest_dist: float = INF
	for unit in match_ctrl.units:
		if not unit.is_alive or not match_ctrl.is_unit_placed(unit):
			continue
		if not _unit_nodes.has(unit.id):
			continue
		var node: Node2D = _unit_nodes[unit.id]
		var dist: float = mouse_pos.distance_to(node.position)
		var radius: float = _get_unit_hit_radius(unit)
		if dist <= radius and dist < closest_dist:
			closest = unit
			closest_dist = dist
	return closest


func _get_unit_hit_radius(unit: UnitBase) -> float:
	if unit.is_minion:
		return UNIT_HIT_RADIUS_MINION
	if unit.is_leader:
		return UNIT_HIT_RADIUS_LEADER
	return UNIT_HIT_RADIUS


func _append_log(msg: String) -> void:
	log_label.text = msg


# --- Camera: orient behind the viewing player's side, allow manual rotation ---

## Angle that swings a player's starting corner toward the bottom of the
## screen, so "your" side is always the near edge of the board.
func _compute_base_yaw(player_id: int) -> float:
	var centroid: Vector2 = Vector2.ZERO
	var count: int = 0
	for unit in match_ctrl.units:
		if unit.owner_id == player_id and match_ctrl.is_unit_placed(unit):
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


func _update_camera_for_viewer(viewer: int, animate: bool) -> void:
	if viewer < 0 or viewer >= _base_yaw_by_player.size():
		return
	if viewer != _camera_owner_id:
		_camera_owner_id = viewer
		_apply_camera_orientation(animate)
	elif animate:
		_apply_camera_orientation(true)
	_focus_camera_on_player(viewer)


func _get_viewer_player_id() -> int:
	if GameState.match_mode == GameState.MatchMode.LOCAL:
		if match_ctrl.placement_active:
			return match_ctrl.placement_player
		return match_ctrl.turn_manager.current_player
	if GameState.is_solo() or GameState.is_online():
		return GameState.get_local_player_id()
	return match_ctrl.turn_manager.current_player


func _focus_camera_on_player(player_id: int) -> void:
	if player_id < 0 or player_id >= _base_yaw_by_player.size():
		return
	var centroid: Vector2 = Vector2.ZERO
	var count: int = 0
	for unit in match_ctrl.units:
		if unit.owner_id == player_id and match_ctrl.is_unit_placed(unit):
			centroid += HexCoords.axial_to_pixel(unit.hex_position, HEX_SIZE)
			count += 1
	if count == 0:
		var corner: Vector2i = MatchController.PLACEMENT_CORNERS[player_id]
		centroid = HexCoords.axial_to_pixel(corner, HEX_SIZE)
	else:
		centroid /= float(count)
	var projected: Vector2 = _project_point(centroid)
	_camera_pan = -projected * 0.28
	_apply_camera_transform()


func _apply_camera_transform() -> void:
	if _camera_rig == null:
		return
	_camera_rig.position = _camera_pan
	_camera_rig.scale = Vector2.ONE * _camera_zoom


func _set_zoom(next_zoom: float) -> void:
	_manual_camera = true
	_camera_zoom = clampf(next_zoom, ZOOM_MIN, ZOOM_MAX)
	_apply_camera_transform()


func _update_camera_for_active_player(animate: bool) -> void:
	_update_camera_for_viewer(_get_viewer_player_id(), animate)


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
		_camera_rotating = false
		_sync_camera_dependent_visuals()
		return

	_camera_rotating = true
	_camera_tween = create_tween()
	_camera_tween.set_parallel(true)
	_camera_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_camera_tween.tween_property(_ground_pivot, "rotation", target_yaw, CAMERA_TWEEN_TIME)
	_camera_tween.tween_property(_ground_layer, "scale:y", target_squash, CAMERA_TWEEN_TIME)
	_camera_tween.finished.connect(_on_camera_tween_finished)


func _on_camera_tween_finished() -> void:
	_camera_rotating = false
	_sync_camera_dependent_visuals()


func _rotate_camera(direction: int) -> void:
	if _match_ending or _move_animating:
		return
	_manual_yaw += CAMERA_ROTATION_STEP * float(direction)
	_apply_camera_orientation(true)


func _reset_camera_view() -> void:
	if _match_ending or _move_animating:
		return
	_manual_yaw = 0.0
	_manual_camera = false
	_apply_camera_orientation(true)
	_focus_camera_on_player(_get_viewer_player_id())
	_apply_viewport_layout()


func _toggle_isometric(enabled: bool) -> void:
	_iso_enabled = enabled
	_apply_camera_orientation(true)


## Tiles ride the ground plane; oriented decor and unit billboards swap between
## eight camera-relative sprite sets (four settled, four mid-rotation).
func _sync_camera_dependent_visuals() -> void:
	if _ground_pivot == null or _ground_layer == null:
		return
	var yaw: float = _ground_pivot.rotation
	var squash: float = _ground_layer.scale.y
	var orientation: int = CameraOrientationScript.get_orientation_index(yaw, _camera_rotating)
	var visuals_changed: bool = not is_equal_approx(yaw, _synced_yaw) \
		or not is_equal_approx(squash, _synced_squash) \
		or orientation != _synced_orientation
	if not visuals_changed:
		return
	_synced_yaw = yaw
	_synced_squash = squash
	_synced_orientation = orientation

	var inverse_squash: float = 1.0 / maxf(squash, 0.05)
	for hex in _tile_nodes:
		var anchor: Node2D = _tile_nodes[hex].get_node_or_null("Upright") as Node2D
		if anchor != null:
			anchor.rotation = -yaw
			anchor.scale = Vector2(1.0, inverse_squash)
			var decor: Node = anchor.get_node_or_null("OrientedDecor")
			if decor is OrientedVisual:
				(decor as OrientedVisual).set_orientation(orientation)

	for unit_id in _unit_nodes:
		var container: Node2D = _unit_nodes[unit_id]
		var oriented: Node = container.get_node_or_null("OrientedBody")
		if oriented is OrientedVisual:
			var visual := oriented as OrientedVisual
			visual.set_orientation(orientation)
			visual.set_hover_highlight(unit_id == _hovered_unit_id)
			var selected: bool = _selected_unit != null and _selected_unit.id == unit_id
			visual.set_selection_outline(selected)

	for unit in match_ctrl.units:
		if not _unit_nodes.has(unit.id) or _suppress_position_snap.has(unit.id):
			continue
		_place_unit_node(_unit_nodes[unit.id], unit.hex_position)


func _update_node_orientation(node: OrientedVisual) -> void:
	if _ground_pivot == null:
		return
	var orientation: int = CameraOrientationScript.get_orientation_index(
		_ground_pivot.rotation,
		_camera_rotating,
	)
	node.set_orientation(orientation)


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

	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 4)
	var zoom_out := _make_camera_button("Zoom -", "Zoom out (mouse wheel down).", Callable())
	zoom_out.pressed.connect(func() -> void: _set_zoom(_camera_zoom - ZOOM_STEP))
	var zoom_in := _make_camera_button("Zoom +", "Zoom in (mouse wheel up).", Callable())
	zoom_in.pressed.connect(func() -> void: _set_zoom(_camera_zoom + ZOOM_STEP))
	zoom_row.add_child(zoom_out)
	zoom_row.add_child(zoom_in)
	box.add_child(zoom_row)

	var hint := Label.new()
	hint.text = "Drag with right or middle mouse to pan."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.82, 0.84, 0.88)
	box.add_child(hint)

	var iso_toggle := CheckButton.new()
	iso_toggle.text = "Isometric View"
	iso_toggle.tooltip_text = "Toggle between the tilted board and a flat top-down view."
	iso_toggle.button_pressed = _iso_enabled
	iso_toggle.toggled.connect(_toggle_isometric)
	box.add_child(iso_toggle)

	sidebar.add_child(box)
	sidebar.move_child(box, rp_label.get_index() + 1)


func _make_camera_button(text: String, hint: String, callback: Callable = Callable()) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = hint
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if callback.is_valid():
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
	_update_player_panel_stats(viewer)
	_update_player_panel_stats(1 - viewer)


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
	box.add_child(_make_player_stats_label(player_id))


func _make_player_stats_label(player_id: int) -> Label:
	var stats := Label.new()
	stats.name = "PlayerStats"
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_theme_font_size_override("font_size", 11)
	stats.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	_player_panel_stats[player_id] = stats
	_update_player_panel_stats(player_id)
	return stats


func _update_player_panel_stats(player_id: int) -> void:
	if not _player_panel_stats.has(player_id):
		return
	var label: Label = _player_panel_stats[player_id]
	var rp: int = match_ctrl.resource_points[player_id]
	var rp_max: int = match_ctrl.get_max_resource(player_id)
	var ap_part: String
	if match_ctrl.placement_active or _placement_active:
		ap_part = "AP: —"
	elif match_ctrl.turn_manager.current_player == player_id:
		ap_part = "AP: %d / %d" % [
			match_ctrl.turn_manager.actions_remaining,
			TurnManager.ACTIONS_PER_TURN,
		]
	else:
		ap_part = "AP: —"
	label.text = "%s  |  RP: %d / %d" % [ap_part, rp, rp_max]


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
	if GameState.match_mode == GameState.MatchMode.ONLINE_HOST:
		SaveGameManager.delete_save()
	_deselect_unit()
	_update_action_buttons()

	var local_player_id: int = 0 if GameState.is_solo() else GameState.get_local_player_id()
	var loser_id: int = 1 - winner_id
	var leader_pos: Vector2 = _find_losing_leader_position(loser_id)

	if GameState.is_solo():
		log_label.text = "Victory!" if winner_id == 0 else "Defeat!"

	await _battle_effects.play_match_end(self, board_root, winner_id, local_player_id, leader_pos)
	get_tree().change_scene_to_file("res://scenes/end_game.tscn")
