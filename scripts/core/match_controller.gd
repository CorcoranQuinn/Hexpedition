class_name MatchController
extends RefCounted
## Core match rules: board setup, actions, win detection.

signal state_changed
signal action_log(message: String)
signal match_over(winner_id: int)

const BOARD_RADIUS: int = 4
const MOUNTAIN_COUNT: int = 9
const UNIQUE_TILES_PER_TYPE: int = 2

const UNIQUE_TILE_DEFS: Array[Dictionary] = [
	{"type": "sentinel_bastion", "team_id": 0},
	{"type": "veil_mirror", "team_id": 1},
	{"type": "ember_forge", "team_id": 2},
	{"type": "swarm_hive", "team_id": 3},
]

var grid: HexGrid = HexGrid.new()
var units: Array[UnitBase] = []
var turn_manager: TurnManager = TurnManager.new()
var resource_points: Array[int] = [0, 0]
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _pending_reveal: Dictionary = {}  # hex -> tile type id (hidden until walked)
var _pending_team_ids: Dictionary = {}  # hex -> team id for unique tiles


func setup_match(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	grid = HexGrid.new()
	units.clear()
	_pending_reveal.clear()
	_pending_team_ids.clear()
	resource_points = [0, 0]

	_generate_board()
	_spawn_teams()
	turn_manager.start_match(0)
	state_changed.emit()


func _generate_board() -> void:
	var all_hexes: Array = HexCoords.within_radius(Vector2i.ZERO, BOARD_RADIUS)
	var reserved: Dictionary = _get_reserved_hexes()

	for hex in all_hexes:
		_pending_reveal[hex] = "plain"
		grid.set_tile(hex, TileRegistry.create("hidden", hex))

	_scatter_tile_type("mountain", MOUNTAIN_COUNT, reserved)

	for tile_def in UNIQUE_TILE_DEFS:
		_scatter_unique_tile(
			tile_def["type"],
			tile_def["team_id"],
			UNIQUE_TILES_PER_TYPE,
			reserved,
		)


func _get_reserved_hexes() -> Dictionary:
	var reserved: Dictionary = {}
	for player_id in 2:
		for hex in _get_spawn_hexes(player_id):
			reserved[hex] = true
			for neighbor in HexCoords.neighbors(hex):
				reserved[neighbor] = true
	return reserved


func _scatter_tile_type(type_id: String, count: int, reserved: Dictionary) -> void:
	var candidates: Array[Vector2i] = []
	for hex in _pending_reveal.keys():
		if not reserved.has(hex):
			candidates.append(hex)
	_shuffle_array(candidates)

	var placed: int = 0
	for hex in candidates:
		if placed >= count:
			break
		_pending_reveal[hex] = type_id
		reserved[hex] = true
		placed += 1


func _scatter_unique_tile(type_id: String, team_id: int, count: int, reserved: Dictionary) -> void:
	var candidates: Array[Vector2i] = []
	for hex in _pending_reveal.keys():
		if not reserved.has(hex):
			candidates.append(hex)
	_shuffle_array(candidates)

	var placed: int = 0
	for hex in candidates:
		if placed >= count:
			break
		_pending_reveal[hex] = type_id
		_pending_team_ids[hex] = team_id
		reserved[hex] = true
		placed += 1


func _shuffle_array(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _spawn_teams() -> void:
	for player_id in 2:
		var team_def: TeamDefinition = TeamRegistry.get_team(
			GameState.selected_team_ids[player_id]
		)
		resource_points[player_id] = mini(2, team_def.max_resource_points)
		var spawn_hexes: Array[Vector2i] = _get_spawn_hexes(player_id)
		var roster: Array[String] = team_def.get_roster_type_ids()
		for i in roster.size():
			var unit: UnitBase = UnitRegistry.create(
				roster[i], player_id, team_def.team_id, i
			)
			unit.hex_position = spawn_hexes[i]
			units.append(unit)
			grid.on_unit_entered(unit.hex_position, unit)


func _get_spawn_hexes(player_id: int) -> Array[Vector2i]:
	if player_id == 0:
		return [Vector2i(-3, 1), Vector2i(-3, 2), Vector2i(-2, 1)]
	return [Vector2i(3, -1), Vector2i(3, -2), Vector2i(2, -1)]


func get_units_for_player(player_id: int) -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	for u in units:
		if u.owner_id == player_id and u.is_alive:
			result.append(u)
	return result


func get_unit_at(hex: Vector2i) -> UnitBase:
	for u in units:
		if u.is_alive and u.hex_position == hex:
			return u
	return null


func get_enemies_of(player_id: int) -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	for u in units:
		if u.owner_id != player_id and u.is_alive:
			result.append(u)
	return result


func get_max_resource(player_id: int) -> int:
	var team_def: TeamDefinition = TeamRegistry.get_team(
		GameState.selected_team_ids[player_id]
	)
	return team_def.max_resource_points


func can_act(player_id: int) -> bool:
	return turn_manager.current_player == player_id and turn_manager.can_spend_action()


# --- Actions ---

func perform_move(player_id: int, moves: Dictionary) -> Dictionary:
	## moves: { unit_id: Vector2i target_hex }
	if not can_act(player_id):
		return _fail("Not your turn or no actions left.")

	for unit_id in moves:
		var unit: UnitBase = _find_unit(unit_id)
		if unit == null or unit.owner_id != player_id:
			return _fail("Invalid unit.")
		if not unit.is_player_controllable():
			return _fail("That unit is AI-controlled.")
		var target: Vector2i = moves[unit_id]
		if not _can_move_unit(unit, target):
			return _fail("%s cannot reach that hex." % unit.display_name)

	for unit_id in moves:
		var unit: UnitBase = _find_unit(unit_id)
		var target: Vector2i = moves[unit_id]
		if target != unit.hex_position:
			unit.hex_position = target
			_reveal_hex_if_hidden(target)
			grid.on_unit_entered(target, unit)

	_add_resource(player_id, 1)
	turn_manager.spend_action()
	_after_action_spent(player_id)
	action_log.emit("Player %d moved units (+1 RP)." % (player_id + 1))
	state_changed.emit()
	return {"success": true}


func perform_attack(player_id: int, attacker_id: String, target_id: String) -> Dictionary:
	if not can_act(player_id):
		return _fail("Not your turn or no actions left.")

	var attacker: UnitBase = _find_unit(attacker_id)
	var target: UnitBase = _find_unit(target_id)
	if attacker == null or target == null:
		return _fail("Unit not found.")
	if attacker.owner_id != player_id:
		return _fail("Not your unit.")
	if not attacker.is_player_controllable():
		return _fail("That unit is AI-controlled.")
	if not attacker.can_attack(target, func(a, b): return has_line_of_sight(a, b)):
		return _fail("Target out of range, blocked by terrain, or invalid.")

	var damage: int = attacker.perform_basic_attack(target)
	turn_manager.spend_action()
	_after_action_spent(player_id)
	action_log.emit("%s hit %s for %d damage." % [
		attacker.display_name, target.display_name, damage
	])
	_check_win()
	state_changed.emit()
	return {"success": true, "damage": damage}


func perform_ability(player_id: int, unit_id: String, extra: Dictionary = {}) -> Dictionary:
	if not can_act(player_id):
		return _fail("Not your turn or no actions left.")

	var unit: UnitBase = _find_unit(unit_id)
	if unit == null or unit.owner_id != player_id:
		return _fail("Invalid unit.")
	if not unit.is_player_controllable():
		return _fail("That unit is AI-controlled.")
	if not unit.can_use_ability(resource_points[player_id]):
		return _fail("Not enough resource points (need %d)." % unit.ability_cost)

	var ctx: Dictionary = {
		"allies": units,
		"enemies": get_enemies_of(player_id),
		"grid": grid,
		"target": extra.get("target", null),
		"summon_hex": extra.get("summon_hex", Vector2i(-999, -999)),
		"line_of_sight_check": func(a, b): return has_line_of_sight(a, b),
		"reveal_hex": func(h): reveal_hex(h),
		"summon_minion": func(hex): return summon_minion(player_id, unit, hex),
	}
	var result: Dictionary = unit.use_ability(ctx)
	if not result.get("success", false):
		return result

	resource_points[player_id] -= unit.ability_cost
	turn_manager.spend_action()
	_after_action_spent(player_id)
	action_log.emit(result.get("message", "Ability used."))
	_check_win()
	state_changed.emit()
	return result


func perform_tile_interact(player_id: int, unit_id: String) -> Dictionary:
	if not can_act(player_id):
		return _fail("Not your turn or no actions left.")

	var unit: UnitBase = _find_unit(unit_id)
	if unit == null or unit.owner_id != player_id:
		return _fail("Invalid unit.")
	if not unit.is_player_controllable():
		return _fail("That unit is AI-controlled.")

	var tile: TileBase = grid.get_tile(unit.hex_position)
	if tile == null or not tile.can_interact(unit):
		return _fail("No interactable tile at unit position.")

	var result: Dictionary = tile.interact(unit, {
		"grid": grid,
		"units": units,
		"reveal_hex": func(h): reveal_hex(h),
		"has_line_of_sight": func(a, b): return has_line_of_sight(a, b),
		"summon_minion": func(hex): return summon_minion(player_id, unit, hex),
	})
	if not result.get("success", false):
		return result

	turn_manager.spend_action()
	_after_action_spent(player_id)
	action_log.emit(result.get("message", "Tile interaction."))
	state_changed.emit()
	return result


func can_summon_at(player_id: int, hex: Vector2i) -> bool:
	if not grid.has_tile(hex):
		return false
	if get_unit_at(hex) != null:
		return false
	if _blocks_movement_at(hex):
		return false
	return count_minions_for_player(player_id) < MatchAI.MAX_MINIONS_PER_PLAYER


func count_minions_for_player(player_id: int) -> int:
	var count: int = 0
	for u in units:
		if u.owner_id == player_id and u.is_minion and u.is_alive:
			count += 1
	return count


func summon_minion(player_id: int, summoner: UnitBase, hex: Vector2i, type_id: String = "swarm_minion") -> UnitBase:
	if not can_summon_at(player_id, hex):
		return null
	if HexCoords.distance(summoner.hex_position, hex) > 1:
		return null
	var minion: UnitBase = UnitRegistry.create_minion(
		type_id, player_id, summoner.team_id, units.size()
	)
	minion.summoner_id = summoner.id
	minion.hex_position = hex
	units.append(minion)
	_reveal_hex_if_hidden(hex)
	grid.on_unit_entered(hex, minion)
	state_changed.emit()
	return minion


func run_minion_phase(player_id: int) -> void:
	MatchAI.run_minions(self, player_id)


func end_turn_with_minions(player_id: int) -> void:
	if turn_manager.current_player != player_id:
		return
	run_minion_phase(player_id)
	turn_manager.actions_remaining = 0
	turn_manager.actions_changed.emit(0)
	turn_manager.end_turn()
	state_changed.emit()


func _after_action_spent(player_id: int) -> void:
	if turn_manager.actions_remaining <= 0:
		run_minion_phase(player_id)
		turn_manager.end_turn()
		state_changed.emit()


func _can_move_unit(unit: UnitBase, target: Vector2i) -> bool:
	if target == unit.hex_position:
		return true
	if not grid.has_tile(target):
		return false
	if _blocks_movement_at(target):
		return false
	if get_unit_at(target) != null:
		return false
	var dist: int = _movement_distance(unit.hex_position, target)
	return dist >= 0 and dist <= unit.move_range


func reveal_hex(hex: Vector2i) -> void:
	if not grid.has_tile(hex):
		return
	_reveal_hex_if_hidden(hex)
	state_changed.emit()


func has_line_of_sight(from_hex: Vector2i, to_hex: Vector2i) -> bool:
	var path: Array[Vector2i] = HexCoords.line_of_sight_path(from_hex, to_hex)
	for i in range(1, path.size() - 1):
		if _blocks_projectiles_at(path[i]):
			return false
	return true


func _movement_distance(from_hex: Vector2i, to_hex: Vector2i) -> int:
	if from_hex == to_hex:
		return 0
	if not grid.has_tile(to_hex) or _blocks_movement_at(to_hex):
		return -1

	var queue: Array = [[from_hex, 0]]
	var visited: Dictionary = {from_hex: true}

	while not queue.is_empty():
		var entry: Array = queue.pop_front()
		var hex: Vector2i = entry[0]
		var cost: int = entry[1]
		if hex == to_hex:
			return cost
		for neighbor in HexCoords.neighbors(hex):
			if visited.has(neighbor) or not grid.has_tile(neighbor):
				continue
			if _blocks_movement_at(neighbor):
				continue
			if get_unit_at(neighbor) != null and neighbor != to_hex:
				continue
			visited[neighbor] = true
			queue.append([neighbor, cost + 1])
	return -1


func _blocks_movement_at(hex: Vector2i) -> bool:
	var tile: TileBase = _peek_tile_at(hex)
	return tile.blocks_movement() if tile else true


func _blocks_projectiles_at(hex: Vector2i) -> bool:
	var tile: TileBase = _peek_tile_at(hex)
	return tile.blocks_projectiles() if tile else true


func _peek_tile_at(hex: Vector2i) -> TileBase:
	if _pending_reveal.has(hex):
		var team_id: int = _pending_team_ids.get(hex, -1)
		return TileRegistry.create(_pending_reveal[hex], hex, team_id)
	return grid.get_tile(hex)


func _add_resource(player_id: int, amount: int) -> void:
	var cap: int = get_max_resource(player_id)
	resource_points[player_id] = mini(cap, resource_points[player_id] + amount)


func _find_unit(unit_id: String) -> UnitBase:
	for u in units:
		if u.id == unit_id:
			return u
	return null


func _check_win() -> void:
	for player_id in 2:
		var leaders_alive: bool = false
		for u in units:
			if u.owner_id == player_id and u.is_leader and u.is_alive:
				leaders_alive = true
				break
		if not leaders_alive:
			var winner: int = 1 - player_id
			match_over.emit(winner)
			return


func _reveal_hex_if_hidden(hex: Vector2i) -> void:
	if not _pending_reveal.has(hex):
		return
	var type_id: String = _pending_reveal[hex]
	var team_id: int = _pending_team_ids.get(hex, -1)
	_pending_reveal.erase(hex)
	_pending_team_ids.erase(hex)
	grid.set_tile(hex, TileRegistry.create(type_id, hex, team_id))
	grid.get_tile(hex).revealed = true
	grid.get_tile(hex).on_reveal()


func _fail(msg: String) -> Dictionary:
	return {"success": false, "message": msg}
