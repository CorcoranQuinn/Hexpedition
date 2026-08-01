extends Control

const ICON_SIZE := Vector2(72, 72)
const PREVIEW_SIZE := Vector2(120, 120)
const LOCKED_BORDER_WIDTH := 4

@onready var local_preview_slot: Control = %LocalPreviewSlot
@onready var opponent_preview_slot: Control = %OpponentPreviewSlot
@onready var local_preview_label: Label = %LocalPreviewLabel
@onready var opponent_preview_label: Label = %OpponentPreviewLabel
@onready var team_icon_grid: GridContainer = %TeamIconGrid
@onready var team_name_label: Label = %TeamNameLabel
@onready var team_desc_label: Label = %TeamDescLabel
@onready var roster_label: Label = %RosterLabel
@onready var p1_status: Label = %P1Status
@onready var p2_status: Label = %P2Status
@onready var confirm_button: Button = %ConfirmButton
@onready var unlock_button: Button = %UnlockButton
@onready var random_button: Button = %RandomButton
@onready var start_button: Button = %StartButton
@onready var back_button: Button = %BackButton

var _teams: Array[TeamDefinition] = []
var _local_slot: int = 0
var _active_slot: int = 0
var _local_hover_index: int = 0
var _icon_buttons: Array[Button] = []
var _preview_nodes: Dictionary = {}  # slot -> Node2D


func _ready() -> void:
	_teams = TeamRegistry.get_all_teams()
	_build_team_icons()
	_resolve_local_slot()
	_active_slot = _local_slot if GameState.match_mode != GameState.MatchMode.LOCAL else 0

	confirm_button.pressed.connect(_on_confirm_pressed)
	unlock_button.pressed.connect(_on_unlock_pressed)
	random_button.pressed.connect(_on_random_pressed)
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)
	NetworkManager.selection_updated.connect(_on_selection_updated)
	NetworkManager.hover_updated.connect(_on_hover_updated)
	NetworkManager.lock_updated.connect(_on_lock_updated)
	NetworkManager.match_start_requested.connect(_on_match_start)
	NetworkManager.peer_connected.connect(_on_peer_connected)

	_set_local_hover(0)
	_refresh_ui()

	if GameState.is_solo():
		opponent_preview_label.text = "AI"
		p2_status.text = "AI: random team on lock-in"
		confirm_button.text = "Lock In"
		confirm_button.tooltip_text = "Or double-click a leader icon."
	else:
		confirm_button.tooltip_text = "Double-click a leader icon to lock in without starting."


func _can_local_player_start() -> bool:
	return GameState.match_mode != GameState.MatchMode.ONLINE_CLIENT


func _resolve_local_slot() -> void:
	if GameState.match_mode == GameState.MatchMode.ONLINE_CLIENT:
		_local_slot = 1
	else:
		_local_slot = 0


func _build_team_icons() -> void:
	for child in team_icon_grid.get_children():
		child.queue_free()
	_icon_buttons.clear()

	for i in _teams.size():
		var team: TeamDefinition = _teams[i]
		var wrapper := PanelContainer.new()
		wrapper.custom_minimum_size = ICON_SIZE

		var button := Button.new()
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = ICON_SIZE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.gui_input.connect(_on_icon_gui_input.bind(i))

		var slot := Control.new()
		slot.custom_minimum_size = ICON_SIZE
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.set_anchors_preset(Control.PRESET_FULL_RECT)
		button.add_child(slot)

		var art_root := _make_icon_art(team)
		art_root.position = ICON_SIZE * 0.5
		slot.add_child(art_root)

		wrapper.add_child(button)
		team_icon_grid.add_child(wrapper)
		_icon_buttons.append(button)


func _make_icon_art(team: TeamDefinition) -> Node2D:
	var icon := UnitArt.build_leader_icon(team.leader_type_id, team.team_color)
	icon.scale = Vector2(0.95, 0.95)
	UnitArt.attach_idle_animation(icon)
	return icon


func _set_local_hover(index: int) -> void:
	if index < 0 or index >= _teams.size():
		return
	_local_hover_index = index
	var team: TeamDefinition = _teams[index]
	var slot: int = _get_control_slot()
	if not GameState.team_locked[slot]:
		NetworkManager.submit_team_hover(slot, team.team_id)
	_refresh_team_details(team)
	_refresh_ui()


func _on_icon_gui_input(event: InputEvent, index: int) -> void:
	if _is_slot_locked(_get_control_slot()):
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_set_local_hover(index)
		if event.double_click:
			_lock_current_selection()


func _refresh_team_details(team: TeamDefinition) -> void:
	team_name_label.text = team.team_name
	team_name_label.modulate = team.team_color
	team_desc_label.text = "%s\nMax RP: %d" % [team.description, team.max_resource_points]
	var roster_lines: PackedStringArray = PackedStringArray()
	roster_lines.append("Leader")
	roster_lines.append(_format_roster_unit_entry(team.leader_type_id, team.team_id))

	var follower_counts: Dictionary = {}
	for follower_id in team.follower_type_ids:
		var key: String = String(follower_id)
		follower_counts[key] = int(follower_counts.get(key, 0)) + 1
	for follower_id in follower_counts.keys():
		var count: int = follower_counts[follower_id]
		var heading: String = "Follower" if count == 1 else "Followers (×%d)" % count
		roster_lines.append(heading)
		roster_lines.append(_format_roster_unit_entry(follower_id, team.team_id))

	var unique_tile: TileBase = TileRegistry.create(team.unique_tile_type_id, Vector2i.ZERO, team.team_id)
	roster_lines.append("Unique tile: %s" % unique_tile.display_name)
	roster_lines.append("  %s" % unique_tile.get_effect_description())
	roster_label.text = "\n".join(roster_lines)


func _format_roster_unit_entry(type_id: String, team_id: int) -> String:
	var unit: UnitBase = UnitRegistry.create(type_id, 0, team_id, 0)
	return "  %s\n  HP %d | Move %d | Range %d | Attack d%d\n  %s" % [
		unit.display_name,
		unit.max_health,
		unit.move_range,
		unit.attack_range,
		unit.attack_die_sides,
		unit.get_ability_description(),
	]


func _refresh_ui() -> void:
	var display_slot: int = _active_slot if GameState.match_mode == GameState.MatchMode.LOCAL else _local_slot
	_refresh_preview(local_preview_slot, display_slot, local_preview_label)
	var opponent_slot: int = 1 - display_slot
	_refresh_preview(opponent_preview_slot, opponent_slot, opponent_preview_label)
	_refresh_player_status()
	_refresh_icon_highlights()
	_refresh_action_buttons()


func _refresh_preview(slot: Control, player_id: int, caption: Label) -> void:
	var player_name: String = NetworkManager.get_display_name(player_id)
	var team_id: int = GameState.get_preview_team_id(player_id)
	var status_suffix: String = " (locked)" if GameState.team_locked[player_id] else ""
	if team_id < 0:
		caption.text = "%s — choose a leader%s" % [player_name, status_suffix]
	else:
		var team: TeamDefinition = TeamRegistry.get_team(team_id)
		caption.text = "%s — %s%s" % [player_name, team.team_name, status_suffix]
	_set_preview_art(slot, player_id, team_id)


func _set_preview_art(slot: Control, player_id: int, team_id: int) -> void:
	if _preview_nodes.has(player_id):
		var old: Node = _preview_nodes[player_id]
		if is_instance_valid(old):
			old.queue_free()
		_preview_nodes.erase(player_id)

	if team_id < 0:
		return

	var team: TeamDefinition = TeamRegistry.get_team(team_id)
	var art := _make_icon_art(team)
	art.scale = Vector2(1.15, 1.15)
	art.position = PREVIEW_SIZE * 0.5 + Vector2(0, 8)
	slot.add_child(art)
	_preview_nodes[player_id] = art


func _refresh_icon_highlights() -> void:
	var control_slot: int = _get_control_slot()
	var slot_locked: bool = _is_slot_locked(control_slot)
	var hover_team_id: int = -1
	var locked_team_id: int = -1

	if slot_locked:
		locked_team_id = GameState.selected_team_ids[control_slot]
	else:
		hover_team_id = _teams[_local_hover_index].team_id

	for i in _icon_buttons.size():
		var wrapper: PanelContainer = _icon_buttons[i].get_parent() as PanelContainer
		if wrapper == null:
			continue
		var team: TeamDefinition = _teams[i]
		var is_locked_pick: bool = slot_locked and team.team_id == locked_team_id
		var is_hovered: bool = not slot_locked and team.team_id == hover_team_id
		var style := StyleBoxFlat.new()
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8

		if is_locked_pick:
			style.bg_color = Color(0.34, 0.42, 0.56)
			style.border_color = team.team_color.lightened(0.25)
			style.set_border_width_all(LOCKED_BORDER_WIDTH)
			style.shadow_color = Color(team.team_color, 0.45)
			style.shadow_size = 6
			wrapper.modulate = Color.WHITE
		elif slot_locked:
			style.bg_color = Color(0.12, 0.13, 0.16)
			style.border_color = Color(0.22, 0.23, 0.28)
			style.set_border_width_all(1)
			wrapper.modulate = Color(0.38, 0.38, 0.42, 1.0)
		elif is_hovered:
			style.bg_color = Color(0.28, 0.34, 0.48)
			style.border_color = team.team_color
			style.set_border_width_all(2)
			wrapper.modulate = Color.WHITE
		else:
			style.bg_color = Color(0.18, 0.20, 0.26)
			style.border_color = Color(0.32, 0.34, 0.40)
			style.set_border_width_all(1)
			wrapper.modulate = Color.WHITE

		wrapper.add_theme_stylebox_override("panel", style)
		_icon_buttons[i].disabled = slot_locked


func _refresh_action_buttons() -> void:
	var control_slot: int = _get_control_slot()
	var slot_locked: bool = _is_slot_locked(control_slot)
	var all_locked: bool = GameState.all_teams_locked()

	confirm_button.disabled = slot_locked or _teams.is_empty()
	unlock_button.disabled = not slot_locked
	random_button.disabled = slot_locked
	start_button.disabled = not all_locked or not _can_local_player_start()


func _refresh_player_status() -> void:
	p1_status.text = _format_player_status(0)
	p2_status.text = _format_player_status(1)


func _format_player_status(player_id: int) -> String:
	var player_name: String = NetworkManager.get_display_name(player_id)
	if GameState.team_locked[player_id]:
		var team: TeamDefinition = TeamRegistry.get_team(GameState.selected_team_ids[player_id])
		return "%s: %s (locked)" % [player_name, team.team_name]
	var hover_id: int = GameState.hover_team_ids[player_id]
	if hover_id >= 0:
		var hover_team: TeamDefinition = TeamRegistry.get_team(hover_id)
		return "%s: %s (click to select)" % [player_name, hover_team.team_name]
	return "%s: not selected" % player_name


func _on_random_pressed() -> void:
	if _is_slot_locked(_get_control_slot()):
		return
	var random_idx: int = randi() % _teams.size()
	_set_local_hover(random_idx)


func _on_confirm_pressed() -> void:
	_lock_current_selection()


func _lock_current_selection() -> void:
	if _is_slot_locked(_get_control_slot()):
		return
	var team: TeamDefinition = _teams[_local_hover_index]

	if GameState.is_solo():
		GameState.lock_team(0, team.team_id)
		var ai_team_id: int = TeamRegistry.pick_random_team_id(team.team_id)
		GameState.lock_team(1, ai_team_id)
		_refresh_ui()
		return

	if GameState.match_mode == GameState.MatchMode.LOCAL:
		NetworkManager.submit_team_selection(_active_slot, team.team_id)
		if _active_slot == 0 and not GameState.team_locked[1]:
			_active_slot = 1
			_local_hover_index = 0
			NetworkManager.submit_team_hover(1, _teams[0].team_id)
			team_desc_label.text += "\n\nPlayer 2 — pick and lock a leader."
		_refresh_ui()
		return

	NetworkManager.submit_team_selection(_local_slot, team.team_id)
	_refresh_ui()


func _on_unlock_pressed() -> void:
	var slot: int = _get_control_slot()
	if not _is_slot_locked(slot):
		return
	if GameState.is_solo():
		GameState.unlock_team(0)
		GameState.unlock_team(1)
		_refresh_ui()
		return
	NetworkManager.submit_team_unlock(slot)
	if GameState.match_mode == GameState.MatchMode.LOCAL:
		_active_slot = slot
	_refresh_ui()


func _get_control_slot() -> int:
	return _active_slot if GameState.match_mode == GameState.MatchMode.LOCAL else _local_slot


func _on_start_pressed() -> void:
	NetworkManager.request_start_if_ready()


func _on_selection_updated(_player_id: int, _team_id: int) -> void:
	_refresh_ui()


func _on_hover_updated(_player_id: int, _team_id: int) -> void:
	_refresh_ui()


func _on_lock_updated(_player_id: int, _team_id: int, _locked: bool) -> void:
	_refresh_ui()


func _on_match_start() -> void:
	get_tree().change_scene_to_file("res://scenes/game_board.tscn")


func _on_peer_connected(_id: int) -> void:
	p2_status.text = "Client connected — waiting for selection..."


func _on_back_pressed() -> void:
	NetworkManager.disconnect_game()
	GameState.reset_match_state()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _is_slot_locked(player_id: int) -> bool:
	return GameState.team_locked[player_id]
