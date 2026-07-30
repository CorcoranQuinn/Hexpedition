extends Node
## Global session state: match mode, selected teams, rematch flags.

signal match_config_changed

enum MatchMode { LOCAL, SOLO, ONLINE_HOST, ONLINE_CLIENT }

var match_mode: MatchMode = MatchMode.LOCAL
var player_count: int = 2

# Selected team IDs per player slot (index = player_id)
var selected_team_ids: Array[int] = [-1, -1]

var last_winner_id: int = -1
var pending_rematch_same_teams: bool = false
var pending_rematch_new_select: bool = false
var match_seed: int = -1


func reset_match_state() -> void:
	selected_team_ids = [-1, -1]
	last_winner_id = -1
	pending_rematch_same_teams = false
	pending_rematch_new_select = false
	match_config_changed.emit()


func set_team_selection(player_id: int, team_id: int) -> void:
	if player_id >= 0 and player_id < selected_team_ids.size():
		selected_team_ids[player_id] = team_id
		match_config_changed.emit()


func all_teams_selected() -> bool:
	for tid in selected_team_ids:
		if tid < 0:
			return false
	return true


func is_online() -> bool:
	return match_mode == MatchMode.ONLINE_HOST or match_mode == MatchMode.ONLINE_CLIENT


func is_solo() -> bool:
	return match_mode == MatchMode.SOLO


func get_ai_player_id() -> int:
	return 1


func get_local_player_id() -> int:
	if match_mode == MatchMode.LOCAL:
		return -1  # both players on one device
	if match_mode == MatchMode.SOLO:
		return 0
	if match_mode == MatchMode.ONLINE_HOST:
		return 0
	return 1
