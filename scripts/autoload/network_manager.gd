extends Node
## P2P networking via ENet. Host is authoritative for game actions.

signal connection_succeeded
signal connection_failed
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal selection_updated(player_id: int, team_id: int)
signal match_start_requested
signal rematch_requested(same_teams: bool)
signal action_applied(action_type: String, payload: Dictionary, result: Dictionary)
signal placement_submit_received(player_id: int, unit_id: String, hex: Vector2i)
signal placement_snapshot_applied(snapshot: Dictionary)

const DEFAULT_PORT: int = 7777

var peer: ENetMultiplayerPeer = null
var _signals_bound: bool = false


func _mp() -> MultiplayerAPI:
	return get_tree().get_multiplayer()


func _ensure_signals_bound() -> void:
	if _signals_bound:
		return
	var mp: MultiplayerAPI = _mp()
	mp.peer_connected.connect(_on_peer_connected)
	mp.peer_disconnected.connect(_on_peer_disconnected)
	mp.connected_to_server.connect(_on_connected_to_server)
	mp.connection_failed.connect(_on_connection_failed)
	mp.server_disconnected.connect(_on_server_disconnected)
	_signals_bound = true


# --- ENet lifecycle: host, join, disconnect ---

func host_game(port: int = DEFAULT_PORT) -> Error:
	_ensure_signals_bound()
	_cleanup_peer()
	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, 1)
	if err != OK:
		return err
	_mp().multiplayer_peer = peer
	GameState.match_mode = GameState.MatchMode.ONLINE_HOST
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	_ensure_signals_bound()
	_cleanup_peer()
	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err != OK:
		return err
	_mp().multiplayer_peer = peer
	GameState.match_mode = GameState.MatchMode.ONLINE_CLIENT
	return OK


func disconnect_game() -> void:
	_cleanup_peer()
	GameState.match_mode = GameState.MatchMode.LOCAL


func is_connected_online() -> bool:
	if peer == null:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func has_remote_peer() -> bool:
	return _mp().get_peers().size() > 0


func is_server() -> bool:
	return _mp().is_server()


func get_display_name(player_id: int) -> String:
	if GameState.is_solo():
		return "You" if player_id == 0 else "AI"
	if GameState.match_mode == GameState.MatchMode.LOCAL:
		return "Player %d" % (player_id + 1)
	if player_id == 0:
		return "Host"
	return "Client"


# --- RPC: team pick sync and match start (host picks seed) ---

@rpc("any_peer", "call_local", "reliable")
func rpc_submit_team_selection(player_id: int, team_id: int) -> void:
	if not _mp().is_server():
		return
	_apply_team_selection(player_id, team_id)


@rpc("authority", "call_local", "reliable")
func rpc_sync_team_selection(player_id: int, team_id: int) -> void:
	GameState.set_team_selection(player_id, team_id)
	selection_updated.emit(player_id, team_id)


@rpc("authority", "call_local", "reliable")
func rpc_start_match(seed_value: int) -> void:
	GameState.match_seed = seed_value
	match_start_requested.emit()


# --- RPC: client submits action; host validates and broadcasts result ---

@rpc("any_peer", "call_local", "reliable")
func rpc_submit_action(action_type: String, payload: Dictionary) -> void:
	if not _mp().is_server():
		return
	action_applied.emit(action_type, payload, {})


@rpc("authority", "call_local", "reliable")
func rpc_apply_action_result(action_type: String, payload: Dictionary, result: Dictionary) -> void:
	action_applied.emit(action_type, payload, result)


# --- RPC: pre-game deployment (host authoritative) ---

@rpc("any_peer", "call_local", "reliable")
func rpc_submit_placement_unit(player_id: int, unit_id: String, hex: Vector2i) -> void:
	if not _mp().is_server():
		return
	placement_submit_received.emit(player_id, unit_id, hex)


@rpc("authority", "call_local", "reliable")
func rpc_apply_placement_snapshot(snapshot: Dictionary) -> void:
	placement_snapshot_applied.emit(snapshot)


# --- RPC: rematch flow ---

@rpc("any_peer", "call_local", "reliable")
func rpc_request_rematch(same_teams: bool) -> void:
	if not _mp().is_server():
		return
	rpc_notify_rematch.rpc(same_teams)


@rpc("authority", "call_local", "reliable")
func rpc_notify_rematch(same_teams: bool) -> void:
	rematch_requested.emit(same_teams)


# --- Local wrappers: route to RPC or emit directly for offline play ---

func submit_action(action_type: String, payload: Dictionary) -> void:
	if GameState.match_mode == GameState.MatchMode.LOCAL:
		action_applied.emit(action_type, payload, {})
	elif _mp().is_server():
		rpc_apply_action_result.rpc(action_type, payload, {})
	else:
		rpc_submit_action.rpc_id(1, action_type, payload)


func submit_team_selection(player_id: int, team_id: int) -> void:
	if GameState.match_mode == GameState.MatchMode.LOCAL:
		GameState.set_team_selection(player_id, team_id)
		selection_updated.emit(player_id, team_id)
	elif _mp().is_server():
		_apply_team_selection(player_id, team_id)
	else:
		rpc_submit_team_selection.rpc_id(1, player_id, team_id)


func request_start_if_ready() -> void:
	if not GameState.all_teams_selected():
		return
	if GameState.match_seed >= 0:
		return
	if GameState.match_mode == GameState.MatchMode.LOCAL or GameState.is_solo():
		match_start_requested.emit()
	elif _mp().is_server():
		var seed_value: int = randi()
		GameState.match_seed = seed_value
		rpc_start_match.rpc(seed_value)


func request_rematch(same_teams: bool) -> void:
	if GameState.match_mode == GameState.MatchMode.LOCAL:
		rematch_requested.emit(same_teams)
	elif _mp().is_server():
		rpc_request_rematch.rpc(same_teams)
	else:
		rpc_request_rematch.rpc_id(1, same_teams)


# --- Internal peer cleanup and connection callbacks ---

func _cleanup_peer() -> void:
	if peer:
		peer.close()
		peer = null
	if is_inside_tree():
		_mp().multiplayer_peer = null


func _apply_team_selection(player_id: int, team_id: int) -> void:
	if not _is_authority_for_selection(player_id):
		return
	rpc_sync_team_selection.rpc(player_id, team_id)
	if GameState.all_teams_selected():
		var seed_value: int = randi()
		GameState.match_seed = seed_value
		rpc_start_match.rpc(seed_value)


func _is_authority_for_selection(player_id: int) -> bool:
	if GameState.match_mode == GameState.MatchMode.LOCAL:
		return true
	if not _mp().is_server():
		return false
	var sender: int = _mp().get_remote_sender_id()
	if sender == 0:
		return player_id == 0
	return player_id == 1


func _on_peer_connected(id: int) -> void:
	peer_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	peer_disconnected.emit(id)


func _on_connected_to_server() -> void:
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	connection_failed.emit()
	disconnect_game()


func _on_server_disconnected() -> void:
	disconnect_game()
