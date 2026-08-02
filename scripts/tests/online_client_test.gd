extends SceneTree
## Online multiplayer client-side integration test.

const PORT: int = 7788

var failures: Array[String] = []
var _board: Node = null


func check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
	print("[CLIENT] " + ("PASS  " if ok else "FAIL  ") + msg)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	await process_frame

	var gs: Node = root.get_node("/root/GameState")
	var nm: Node = root.get_node("/root/NetworkManager")

	var connected: bool = false
	nm.connection_succeeded.connect(func() -> void: connected = true)

	var err: Error = nm.join_game("127.0.0.1", PORT)
	check(err == OK, "join_game returned OK")

	var deadline: int = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if connected or nm.is_connected_online():
			connected = true
			break
		if nm.peer and nm.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			connected = true
			break
		await process_frame
	check(connected, "connected to host")

	nm.submit_team_selection(1, 1)

	deadline = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		if gs.match_seed >= 0:
			break
		await process_frame
	check(gs.match_seed >= 0, "match seed received (%d)" % gs.match_seed)

	_board = load("res://scenes/game_board.tscn").instantiate()
	root.add_child(_board)

	await _wait_for_intro()
	await _deploy_player(1)
	await _wait_for_match_start()

	check(not _board.match_ctrl.placement_active, "placement finished on client")
	check(
		_board.match_ctrl._match_started or _board.match_ctrl.turn_manager.turn_number >= 1,
		"match started on client",
	)

	for i in 180:
		await process_frame

	check(
		_board.match_ctrl.turn_manager.current_player == 1,
		"client sees turn on player 1 after host ended (got %d)" % _board.match_ctrl.turn_manager.current_player,
	)

	_compare_with_host_positions()
	_write_failures("client")
	quit(0 if failures.is_empty() else 1)


func _wait_for_intro() -> void:
	for i in 300:
		if not _board._intro_animating:
			return
		await process_frame


func _deploy_player(player_id: int) -> void:
	var nm: Node = root.get_node("/root/NetworkManager")
	for i in 400:
		if not _board.match_ctrl.placement_active:
			return
		if _board.match_ctrl.placement_player != player_id:
			await process_frame
			continue
		var unplaced: Array = _board.match_ctrl.get_unplaced_units(player_id)
		if unplaced.is_empty():
			return
		var zone: Array = _board.match_ctrl.get_placement_zone(player_id)
		var target: Vector2i = zone[0]
		for hex in zone:
			if _board.match_ctrl.get_unit_at(hex) == null:
				target = hex
				break
		nm.submit_placement_unit(player_id, unplaced[0].id, target)
		await process_frame


func _wait_for_match_start() -> void:
	for i in 600:
		if _board.match_ctrl._match_started or not _board.match_ctrl.placement_active:
			return
		await process_frame
	check(false, "timed out waiting for match start on client")


func _compare_with_host_positions() -> void:
	var path: String = ProjectSettings.globalize_path("user://online_host_positions.txt")
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(path):
			break
		await process_frame
	if not FileAccess.file_exists(path):
		check(false, "missing host position file for comparison")
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		check(false, "could not read host position file")
		return
	var host_lines: PackedStringArray = file.get_as_text().strip_edges().split("\n")
	file.close()

	var host_positions: Dictionary = {}
	for line in host_lines:
		if "=" not in line or line.begins_with("seed"):
			continue
		var parts: PackedStringArray = line.split("=")
		host_positions[parts[0]] = parts[1]

	for unit in _board.match_ctrl.units:
		if not _board.match_ctrl.is_unit_placed(unit):
			check(false, "client unit not placed: %s" % unit.id)
			continue
		var expected: String = str(host_positions.get(unit.id, ""))
		var actual: String = "%d,%d" % [unit.hex_position.x, unit.hex_position.y]
		check(expected == actual, "unit %s synced (%s vs %s)" % [unit.id, actual, expected])


func _write_failures(label: String) -> void:
	var path: String = ProjectSettings.globalize_path("user://online_%s_result.txt" % label)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	if failures.is_empty():
		file.store_string("PASS\n")
	else:
		file.store_string("FAIL\n")
		for f in failures:
			file.store_line(f)
	file.close()
