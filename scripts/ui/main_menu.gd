extends Control

@onready var local_button: Button = %LocalButton
@onready var solo_button: Button = %SoloButton
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var address_input: LineEdit = %AddressInput
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	local_button.pressed.connect(_on_local_pressed)
	solo_button.pressed.connect(_on_solo_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	address_input.text = "127.0.0.1"


func _on_local_pressed() -> void:
	GameState.reset_match_state()
	GameState.match_mode = GameState.MatchMode.LOCAL
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")


func _on_solo_pressed() -> void:
	GameState.reset_match_state()
	GameState.match_mode = GameState.MatchMode.SOLO
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")


func _on_host_pressed() -> void:
	GameState.reset_match_state()
	var err: Error = NetworkManager.host_game()
	if err != OK:
		status_label.text = "Failed to host (port in use?)"
		return
	status_label.text = "Hosting on port %d..." % NetworkManager.DEFAULT_PORT
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")


func _on_join_pressed() -> void:
	GameState.reset_match_state()
	var addr: String = address_input.text.strip_edges()
	if addr.is_empty():
		status_label.text = "Enter a host address."
		return
	var err: Error = NetworkManager.join_game(addr)
	if err != OK:
		status_label.text = "Failed to start client."
		return
	status_label.text = "Connecting to %s..." % addr
	host_button.disabled = true
	join_button.disabled = true


func _on_connected() -> void:
	status_label.text = "Connected!"
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")


func _on_connection_failed() -> void:
	status_label.text = "Connection failed."
	host_button.disabled = false
	join_button.disabled = false
