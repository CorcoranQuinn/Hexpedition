class_name MatchController
extends RefCounted
## Core match rules: board setup, actions, win detection.

signal state_changed
signal action_log(message: String)
signal match_over(winner_id: int)

const BOARD_RADIUS: int = 4

var grid: HexGrid = HexGrid.new()
var units: Array[UnitBase] = []
var turn_manager: TurnManager = TurnManager.new()
var resource_points: Array[int] = [0, 0]
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _pending_reveal: Dictionary = {}  # hex -> actual tile type id (hidden until walked)


func setup_match(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	grid = HexGrid.new()
	units.clear()
	_pending_reveal.clear()
	resource_points = [0, 0]

	_generate_board()
	_spawn_teams()
	turn_manager = TurnManager.new()
	turn_manager.start_match(0)
	state_changed.emit()


func _generate_board() -> void:
	for hex in HexCoords.within_radius(Vector2i.ZERO, BOARD_RADIUS):
		var actual_type: String = _pick_random_terrain_type()
		_pending_reveal[hex] = actual_type
		grid.set_tile(hex, TileRegistry.create("hidden", hex))


func _pick_random_terrain_type() -> String:
	var pool: Array[String] = ["plain", "plain", "plain", "rough", "vitality"]
	return pool[rng.randi_range(0, pool.size() - 1)]


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

		# Place team unique tile near spawn
		var unique_hex: Vector2i = spawn_hexes[0] + Vector2i(0, 1)
		if grid.has_tile(unique_hex):
			grid.set_tile(
				unique_hex,
				TileRegistry.create(team_def.unique_tile_type_id, unique_hex, team_def.team_id)
			)


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
	if not attacker.can_attack(target):
		return _fail("Target out of range or invalid.")

	var damage: int = attacker.perform_basic_attack(target)
	turn_manager.spend_action()
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
	if not unit.can_use_ability(resource_points[player_id]):
		return _fail("Not enough resource points (need %d)." % unit.ability_cost)

	var ctx: Dictionary = {
		"allies": units,
		"enemies": get_enemies_of(player_id),
		"grid": grid,
		"target": extra.get("target", null),
	}
	var result: Dictionary = unit.use_ability(ctx)
	if not result.get("success", false):
		return result

	resource_points[player_id] -= unit.ability_cost
	turn_manager.spend_action()
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

	var tile: TileBase = grid.get_tile(unit.hex_position)
	if tile == null or not tile.can_interact(unit):
		return _fail("No interactable tile at unit position.")

	var result: Dictionary = tile.interact(unit, {"grid": grid, "units": units})
	if not result.get("success", false):
		return result

	turn_manager.spend_action()
	action_log.emit(result.get("message", "Tile interaction."))
	state_changed.emit()
	return result


func _can_move_unit(unit: UnitBase, target: Vector2i) -> bool:
	if not grid.has_tile(target):
		return false
	if get_unit_at(target) != null and target != unit.hex_position:
		return false
	var dist: int = HexCoords.distance(unit.hex_position, target)
	if dist > unit.move_range:
		return false
	return true


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
	_pending_reveal.erase(hex)
	grid.set_tile(hex, TileRegistry.create(type_id, hex))
	grid.get_tile(hex).revealed = true
	grid.get_tile(hex).on_reveal()


func _fail(msg: String) -> Dictionary:
	return {"success": false, "message": msg}
