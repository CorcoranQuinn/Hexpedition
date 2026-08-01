extends SceneTree
## Verifies mountains are never placed on the center split band.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var center_mountains: int = 0
	var low_mountains: int = 0
	const TRIALS: int = 500

	for seed_value in TRIALS:
		var match_ctrl: MatchController = MatchController.new()
		match_ctrl.setup_match(seed_value)
		for hex in match_ctrl._pending_reveal.keys():
			if match_ctrl._pending_reveal[hex] == "mountain" \
					and match_ctrl._is_center_split_hex(hex):
				center_mountains += 1
				print("CENTER MOUNTAIN seed=", seed_value, " hex=", hex)
		var mountains: int = _count_tile_type(match_ctrl, "mountain")
		if mountains < 3:
			low_mountains += 1

	if center_mountains > 0:
		print("FAIL center-band mountains=", center_mountains, " across ", TRIALS, " seeds")
		quit(1)
		return

	print(
		"SUCCESS no center-band mountains for ",
		TRIALS,
		" seeds; low mountain count (<3) on ",
		low_mountains,
		" seeds",
	)
	quit(0)


func _count_tile_type(match_ctrl: MatchController, type_id: String) -> int:
	var count: int = 0
	for hex in match_ctrl._pending_reveal.keys():
		if match_ctrl._pending_reveal[hex] == type_id:
			count += 1
	return count
