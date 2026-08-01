extends Node
## Host-side persistence for in-progress online matches.

const SAVE_PATH := "user://hex_tactics_multiplayer_save.json"
const SAVE_VERSION := 1

signal save_discarded


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	save_discarded.emit()


func build_snapshot(match_ctrl: MatchController) -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"selected_team_ids": GameState.selected_team_ids.duplicate(),
		"match_seed": GameState.match_seed,
		"match": match_ctrl.export_snapshot(),
	}


func save_snapshot(snapshot: Dictionary) -> bool:
	if GameState.match_mode != GameState.MatchMode.ONLINE_HOST:
		return false
	var payload: Dictionary = snapshot.duplicate(true)
	payload["version"] = SAVE_VERSION
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Failed to open save file for writing.")
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	return true


func load_save() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func get_save_summary(data: Dictionary = {}) -> Dictionary:
	if data.is_empty():
		data = load_save()
	if data.is_empty():
		return {}

	var match_data: Dictionary = data.get("match", {})
	var turn_data: Dictionary = match_data.get("turn_manager", {})
	var team_ids: Array = data.get("selected_team_ids", [-1, -1])
	var resource_points: Array = match_data.get("resource_points", [0, 0])
	var current_player: int = int(turn_data.get("current_player", 0))
	var actions_remaining: int = int(turn_data.get("actions_remaining", TurnManager.ACTIONS_PER_TURN))
	var turn_number: int = int(turn_data.get("turn_number", 1))

	var players: Array[Dictionary] = []
	for player_id in 2:
		var team_id: int = int(team_ids[player_id]) if player_id < team_ids.size() else -1
		var team_name: String = "Unknown"
		var rp_max: int = 0
		if team_id >= 0:
			var team: TeamDefinition = TeamRegistry.get_team(team_id)
			team_name = team.team_name
			rp_max = team.max_resource_points
		var rp: int = int(resource_points[player_id]) if player_id < resource_points.size() else 0
		var ap_text: String
		if player_id == current_player:
			ap_text = "%d / %d" % [actions_remaining, TurnManager.ACTIONS_PER_TURN]
		else:
			ap_text = "—"
		players.append({
			"player_id": player_id,
			"display_name": NetworkManager.get_display_name(player_id),
			"team_name": team_name,
			"ap_text": ap_text,
			"rp": rp,
			"rp_max": rp_max,
		})

	return {
		"turn_number": turn_number,
		"current_player": current_player,
		"current_player_name": NetworkManager.get_display_name(current_player),
		"players": players,
		"in_placement": bool(match_data.get("placement_active", false)),
	}
