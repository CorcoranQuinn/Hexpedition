extends Control

@onready var team_list: ItemList = %TeamList
@onready var team_name_label: Label = %TeamNameLabel
@onready var team_desc_label: Label = %TeamDescLabel
@onready var roster_label: Label = %RosterLabel
@onready var p1_status: Label = %P1Status
@onready var p2_status: Label = %P2Status
@onready var confirm_button: Button = %ConfirmButton
@onready var random_button: Button = %RandomButton
@onready var start_button: Button = %StartButton
@onready var back_button: Button = %BackButton

var _teams: Array[TeamDefinition] = []
var _local_slot: int = 0


func _ready() -> void:
	_teams = TeamRegistry.get_all_teams()
	for team in _teams:
		team_list.add_item(team.team_name)
	team_list.select(0)
	team_list.item_selected.connect(_on_team_selected)
	confirm_button.pressed.connect(_on_confirm_pressed)
	random_button.pressed.connect(_on_random_pressed)
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)
	NetworkManager.selection_updated.connect(_on_selection_updated)
	NetworkManager.match_start_requested.connect(_on_match_start)
	NetworkManager.peer_connected.connect(_on_peer_connected)

	_resolve_local_slot()
	_refresh_team_details()
	_refresh_player_status()

	if GameState.match_mode == GameState.MatchMode.LOCAL:
		p2_status.visible = true
	elif GameState.is_solo():
		p2_status.visible = true
		p2_status.text = "AI: random team on confirm"
		confirm_button.text = "Confirm & Start"
	else:
		p2_status.visible = true
		if GameState.match_mode == GameState.MatchMode.ONLINE_HOST:
			start_button.visible = true


func _resolve_local_slot() -> void:
	if GameState.match_mode == GameState.MatchMode.LOCAL:
		_local_slot = 0
	elif GameState.is_solo():
		_local_slot = 0
	elif GameState.match_mode == GameState.MatchMode.ONLINE_HOST:
		_local_slot = 0
	else:
		_local_slot = 1


func _on_team_selected(_index: int) -> void:
	_refresh_team_details()


func _refresh_team_details() -> void:
	var idx: int = team_list.get_selected_items()[0] if team_list.get_selected_items().size() > 0 else 0
	var team: TeamDefinition = _teams[idx]
	team_name_label.text = team.team_name
	team_name_label.modulate = team.team_color
	team_desc_label.text = "%s\nMax RP: %d" % [team.description, team.max_resource_points]
	var roster_lines: PackedStringArray = PackedStringArray()
	roster_lines.append("Leader: %s" % team.leader_type_id)
	for i in team.follower_type_ids.size():
		roster_lines.append("Follower %d: %s" % [i + 1, team.follower_type_ids[i]])
	roster_lines.append("Unique tile: %s" % team.unique_tile_type_id)
	roster_label.text = "\n".join(roster_lines)


func _refresh_player_status() -> void:
	p1_status.text = _format_player_status(0)
	p2_status.text = _format_player_status(1)
	var ready: bool = GameState.all_teams_selected()
	start_button.disabled = not ready
	if GameState.match_mode == GameState.MatchMode.LOCAL:
		start_button.visible = ready
	elif GameState.is_solo():
		start_button.visible = false
	elif GameState.match_mode == GameState.MatchMode.ONLINE_HOST:
		start_button.visible = ready
	else:
		start_button.visible = false


func _format_player_status(player_id: int) -> String:
	var name: String = NetworkManager.get_display_name(player_id)
	var tid: int = GameState.selected_team_ids[player_id]
	if tid < 0:
		return "%s: Not selected" % name
	var team: TeamDefinition = TeamRegistry.get_team(tid)
	return "%s: %s" % [name, team.team_name]


func _on_random_pressed() -> void:
	var random_idx: int = randi() % _teams.size()
	team_list.select(random_idx)
	_refresh_team_details()


func _on_confirm_pressed() -> void:
	var idx: int = team_list.get_selected_items()[0]
	var team: TeamDefinition = _teams[idx]

	if GameState.is_solo():
		GameState.set_team_selection(0, team.team_id)
		var ai_team_id: int = TeamRegistry.pick_random_team_id(team.team_id)
		GameState.set_team_selection(1, ai_team_id)
		_refresh_player_status()
		NetworkManager.request_start_if_ready()
		return

	if GameState.match_mode == GameState.MatchMode.LOCAL:
		# Hot-seat: alternate between player slots
		var slot: int = _get_next_open_slot()
		if slot < 0:
			# Allow re-picking for local slot cycling
			slot = _local_slot
		GameState.set_team_selection(slot, team.team_id)
		if slot == 0 and GameState.selected_team_ids[1] < 0:
			_local_slot = 1
			p1_status.text = _format_player_status(0)
			team_desc_label.text += "\n\nPlayer 2 — select your team."
		else:
			NetworkManager.request_start_if_ready()
	else:
		NetworkManager.submit_team_selection(_local_slot, team.team_id)

	_refresh_player_status()


func _get_next_open_slot() -> int:
	for i in 2:
		if GameState.selected_team_ids[i] < 0:
			return i
	return -1


func _on_selection_updated(_player_id: int, _team_id: int) -> void:
	_refresh_player_status()


func _on_start_pressed() -> void:
	NetworkManager.request_start_if_ready()


func _on_match_start() -> void:
	get_tree().change_scene_to_file("res://scenes/game_board.tscn")


func _on_peer_connected(_id: int) -> void:
	p2_status.text = "Client connected — waiting for selection..."


func _on_back_pressed() -> void:
	NetworkManager.disconnect_game()
	GameState.reset_match_state()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
