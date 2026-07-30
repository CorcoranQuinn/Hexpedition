extends Control

@onready var winner_label: Label = %WinnerLabel
@onready var rematch_button: Button = %RematchButton
@onready var new_select_button: Button = %NewSelectButton
@onready var disconnect_button: Button = %DisconnectButton


func _ready() -> void:
	var winner_id: int = GameState.last_winner_id
	if GameState.is_solo():
		winner_label.text = "You win!" if winner_id == 0 else "AI wins!"
	else:
		winner_label.text = "Player %d wins!" % (winner_id + 1)
	rematch_button.pressed.connect(_on_rematch)
	new_select_button.pressed.connect(_on_new_select)
	disconnect_button.pressed.connect(_on_disconnect)
	NetworkManager.rematch_requested.connect(_on_remote_rematch)

	if GameState.match_mode == GameState.MatchMode.LOCAL or GameState.is_solo():
		disconnect_button.text = "Back to Menu"


func _on_remote_rematch(same_teams: bool) -> void:
	if same_teams:
		GameState.pending_rematch_same_teams = true
		get_tree().change_scene_to_file("res://scenes/game_board.tscn")
	else:
		GameState.pending_rematch_new_select = true
		GameState.selected_team_ids = [-1, -1]
		get_tree().change_scene_to_file("res://scenes/character_select.tscn")


func _on_rematch() -> void:
	GameState.pending_rematch_same_teams = true
	if GameState.is_online():
		NetworkManager.request_rematch(true)
	get_tree().change_scene_to_file("res://scenes/game_board.tscn")


func _on_new_select() -> void:
	GameState.pending_rematch_new_select = true
	GameState.selected_team_ids = [-1, -1]
	if GameState.is_online():
		NetworkManager.request_rematch(false)
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")


func _on_disconnect() -> void:
	NetworkManager.disconnect_game()
	GameState.reset_match_state()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
