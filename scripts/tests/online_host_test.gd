extends SceneTree
## Online multiplayer host-side integration test.

const PORT: int = 7788
const TEST_SEED: int = 424242

var failures: Array[String] = []
var _board: Node = null


func check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
	print("[HOST] " + ("PASS  " if ok else "FAIL  ") + msg)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gs: Node = root.get_node("/root/GameState")
	var nm: Node = root.get_node("/root/NetworkManager")

	var connected: bool = false
	nm.peer_connected.connect(func(_id: int) -> void: connected = true)

	var err: Error = nm.host_game(PORT)
	check(err == OK, "host_game returned OK")

	var deadline: int = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if connected or nm.has_remote_peer():
			connected = true
			break
		await process_frame
	check(connected, "client peer connected")

	nm.submit_team_selection(0, 0)

	for i in 600:
		if gs.selected_team_ids[1] >= 0:
			break
		await process_frame
	check(gs.selected_team_ids[1] >= 0, "received client team selection (team %d)" % gs.selected_team_ids[1])
	check(gs.all_teams_selected(), "both teams selected on host (%s)" % [gs.selected_team_ids])
	check(nm.is_server(), "host is server")

	deadline = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		if gs.match_seed >= 0:
			break
		await process_frame
	check(gs.match_seed >= 0, "match seed assigned (%d)" % gs.match_seed)

	_board = load("res://scenes/game_board.tscn").instantiate()
	root.add_child(_board)

	await _wait_for_intro()
	await _deploy_player(0)
	await _wait_for_match_start()

	_write_positions("host")

	check(not _board.match_ctrl.placement_active, "placement finished on host")
	check(_board.match_ctrl._match_started, "match started on host")

	_board._submit_action("end_turn", {"player_id": 0})

	for i in 180:
		await process_frame

	check(
		_board.match_ctrl.turn_manager.current_player == 1,
		"host turn advanced to player 1 (got %d)" % _board.match_ctrl.turn_manager.current_player,
	)

	_write_failures("host")
	quit(0 if failures.is_empty() else 1)


func _wait_for_intro() -> void:
	for i in 300:
		if not _board._intro_animating:
			return
		await process_frame


func _deploy_player(player_id: int) -> void:
	var nm: Node = root.get_node("/root/NetworkManager")
	for i in 300:
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
		var unit = unplaced[0]
		_board._placement_selected_unit_id = unit.id
		var result: Dictionary = _board.match_ctrl.place_unit(player_id, unit.id, target)
		if result.get("success", false):
			nm.rpc_apply_placement_snapshot.rpc(result)
			_board._apply_placement_result(result)
		await process_frame


func _wait_for_match_start() -> void:
	for i in 600:
		if _board.match_ctrl._match_started:
			return
		await process_frame
	check(false, "timed out waiting for match start on host")


func _write_positions(label: String) -> void:
	var gs: Node = root.get_node("/root/GameState")
	var lines: PackedStringArray = PackedStringArray()
	lines.append("seed=%d" % gs.match_seed)
	for unit in _board.match_ctrl.units:
		if _board.match_ctrl.is_unit_placed(unit):
			lines.append("%s=%s,%s" % [unit.id, unit.hex_position.x, unit.hex_position.y])
	var path: String = ProjectSettings.globalize_path("user://online_%s_positions.txt" % label)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(lines))
		file.close()


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
