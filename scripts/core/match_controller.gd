class_name MatchController
extends RefCounted
## Core match rules: board setup, actions, win detection.

signal state_changed
signal action_log(message: String)
signal match_over(winner_id: int)
signal combat_event(event_type: String, data: Dictionary)

const BOARD_RADIUS: int = 4
const MOUNTAIN_COUNT: int = 9
const UNIQUE_TILES_PER_TYPE: int = 2

## Deployment corners and the two rearmost q-rows on each player's half.
const PLACEMENT_CORNERS: Array[Vector2i] = [Vector2i(-3, 2), Vector2i(3, -2)]
const PLACEMENT_BACK_ROWS: int = 2
const UNPLACED_HEX: Vector2i = Vector2i(999999, 999999)

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

var placement_active: bool = false
var placement_player: int = 0
var _match_started: bool = false


# --- Match setup: procedural board, team spawn, turn 1 ---
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
	_match_started = false

	_generate_board()
	_prepare_teams()
	placement_active = true
	placement_player = 0
	state_changed.emit()


## Called once both players have finished deploying their starting units.
func finalize_match_start() -> void:
	if not placement_active or _match_started:
		return
	placement_active = false
	_match_started = true
	turn_manager.start_match(0)
	state_changed.emit()


# --- Procedural generation: plain hidden tiles, mountains, team unique tiles ---
func _generate_board() -> void:
	var all_hexes: Array = HexCoords.within_radius(Vector2i.ZERO, BOARD_RADIUS)
	var reserved: Dictionary = _get_reserved_hexes(all_hexes)

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

	_reveal_starting_terrain("mountain")


func _reveal_starting_terrain(type_id: String) -> void:
	var hexes: Array[Vector2i] = []
	for hex in _pending_reveal.keys():
		if _pending_reveal[hex] == type_id:
			hexes.append(hex)
	for hex in hexes:
		_reveal_hex_if_hidden(hex)


# --- Keep deployment zones clear of random terrain features ---
func _get_reserved_hexes(all_hexes: Array) -> Dictionary:
	var reserved: Dictionary = {}
	for player_id in 2:
		for hex in _collect_placement_zone(all_hexes, player_id):
			reserved[hex] = true
			for neighbor in HexCoords.neighbors(hex):
				reserved[neighbor] = true
	return reserved


func get_placement_zone(player_id: int) -> Array[Vector2i]:
	return _collect_placement_zone(grid.get_all_hexes(), player_id)


func _collect_placement_zone(hexes: Array, player_id: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for hex in hexes:
		if _is_in_placement_zone(hex, player_id):
			result.append(hex)
	return result


func _is_on_player_side(hex: Vector2i, player_id: int) -> bool:
	var dist_p0: int = HexCoords.distance(hex, PLACEMENT_CORNERS[0])
	var dist_p1: int = HexCoords.distance(hex, PLACEMENT_CORNERS[1])
	if dist_p0 == dist_p1:
		return false
	return dist_p0 < dist_p1 if player_id == 0 else dist_p1 < dist_p0


func _is_in_placement_zone(hex: Vector2i, player_id: int) -> bool:
	if not _is_on_player_side(hex, player_id):
		return false
	var q: int = hex.x
	if player_id == 0:
		var back_q: int = -(BOARD_RADIUS - 1)
		var front_q: int = back_q + (PLACEMENT_BACK_ROWS - 1)
		return q >= back_q and q <= front_q
	var back_q: int = BOARD_RADIUS - 1
	var front_q: int = back_q - (PLACEMENT_BACK_ROWS - 1)
	return q <= back_q and q >= front_q


func is_unit_placed(unit: UnitBase) -> bool:
	return unit.hex_position != UNPLACED_HEX


func get_unplaced_units(player_id: int) -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	for unit in units:
		if unit.owner_id == player_id and not is_unit_placed(unit):
			result.append(unit)
	return result


func can_place_at(player_id: int, hex: Vector2i) -> bool:
	if not placement_active or placement_player != player_id:
		return false
	if get_unit_at(hex) != null:
		return false
	return _is_in_placement_zone(hex, player_id)


func place_unit(player_id: int, unit_id: String, hex: Vector2i) -> Dictionary:
	if not can_place_at(player_id, hex):
		return {"success": false, "message": "Can't deploy there."}
	var unit: UnitBase = _find_unit_by_id(unit_id)
	if unit == null or unit.owner_id != player_id or is_unit_placed(unit):
		return {"success": false, "message": "Invalid unit."}

	unit.hex_position = hex
	grid.on_unit_entered(hex, unit)
	if unit.is_leader:
		_mark_home_base(hex, player_id)

	var message: String = "%s deployed." % unit.display_name
	if get_unplaced_units(player_id).is_empty():
		_complete_player_placement(player_id)
		message = "%s deployed. Deployment complete." % unit.display_name

	state_changed.emit()
	return _make_placement_snapshot(unit_id, message)


func place_units_for_player(player_id: int, assignments: Dictionary) -> void:
	for unit_id in assignments:
		var hex: Vector2i = assignments[unit_id]
		var unit: UnitBase = _find_unit_by_id(unit_id)
		if unit == null or unit.owner_id != player_id or is_unit_placed(unit):
			continue
		if not can_place_at(player_id, hex):
			continue
		unit.hex_position = hex
		grid.on_unit_entered(hex, unit)
		if unit.is_leader:
			_mark_home_base(hex, player_id)
	_complete_player_placement(player_id)
	state_changed.emit()


func _complete_player_placement(player_id: int) -> void:
	if placement_player != player_id:
		return
	if player_id == 0:
		placement_player = 1
	else:
		finalize_match_start()


func _make_placement_snapshot(unit_id: String, message: String) -> Dictionary:
	return {
		"success": true,
		"message": message,
		"unit_id": unit_id,
		"hex": _find_unit_by_id(unit_id).hex_position if _find_unit_by_id(unit_id) != null else Vector2i.ZERO,
		"placement_player": placement_player,
		"placement_active": placement_active,
	}


func apply_placement_snapshot(snapshot: Dictionary) -> void:
	if not snapshot.get("success", false):
		return
	var unit: UnitBase = _find_unit_by_id(str(snapshot.get("unit_id", "")))
	if unit == null:
		return
	var hex: Vector2i = snapshot.get("hex", Vector2i.ZERO)
	if not is_unit_placed(unit):
		unit.hex_position = hex
		grid.on_unit_entered(hex, unit)
		if unit.is_leader:
			_mark_home_base(hex, unit.owner_id)

	var was_active: bool = placement_active
	placement_player = int(snapshot.get("placement_player", placement_player))
	placement_active = bool(snapshot.get("placement_active", placement_active))
	if was_active and not placement_active and not _match_started:
		finalize_match_start()
	state_changed.emit()


func _mark_home_base(hex: Vector2i, player_id: int) -> void:
	var tile: TileBase = grid.get_tile(hex)
	if tile == null:
		return
	tile.is_home_base = true
	tile.home_base_owner_id = player_id


func _find_unit_by_id(unit_id: String) -> UnitBase:
	for unit in units:
		if unit.id == unit_id:
			return unit
	return null


func find_unit_by_id(unit_id: String) -> UnitBase:
	return _find_unit_by_id(unit_id)


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


# --- Create each player's roster, waiting for the pre-game deployment phase ---
func _prepare_teams() -> void:
	for player_id in 2:
		var team_def: TeamDefinition = TeamRegistry.get_team(
			GameState.selected_team_ids[player_id]
		)
		resource_points[player_id] = mini(2, team_def.max_resource_points)
		var roster: Array[String] = team_def.get_roster_type_ids()
		for i in roster.size():
			var unit: UnitBase = UnitRegistry.create(
				roster[i], player_id, team_def.team_id, i
			)
			unit.hex_position = UNPLACED_HEX
			units.append(unit)


# --- Unit queries used by UI and AI ---
func get_units_for_player(player_id: int) -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	for u in units:
		if u.owner_id == player_id and u.is_alive:
			result.append(u)
	return result


func get_unit_at(hex: Vector2i) -> UnitBase:
	if hex == UNPLACED_HEX:
		return null
	for u in units:
		if u.is_alive and is_unit_placed(u) and u.hex_position == hex:
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


# --- Player actions (each costs 1 action point unless noted) ---

## BFS path for UI previews; respects pending batch-move occupancy.
func find_movement_path(unit: UnitBase, target: Vector2i, pending_moves: Dictionary = {}) -> Array[Vector2i]:
	var start: Vector2i = unit.hex_position
	if target == start:
		return [start]
	if not _can_move_unit(unit, target, pending_moves):
		return []

	var queue: Array[Vector2i] = [start]
	var came_from: Dictionary = {start: start}
	var dist: Dictionary = {start: 0}

	while not queue.is_empty():
		var hex: Vector2i = queue.pop_front()
		if hex == target:
			break
		var cost: int = dist[hex]
		if cost >= unit.move_range:
			continue
		for neighbor in HexCoords.neighbors(hex):
			if came_from.has(neighbor):
				continue
			if not _is_walkable_for_move(unit, neighbor, target, pending_moves):
				continue
			came_from[neighbor] = hex
			dist[neighbor] = cost + 1
			queue.append(neighbor)

	if not came_from.has(target):
		return []

	var path: Array[Vector2i] = []
	var current: Vector2i = target
	while current != start:
		path.push_front(current)
		current = came_from[current]
	path.push_front(start)
	return path


func can_move_unit_to(unit: UnitBase, target: Vector2i, pending_moves: Dictionary = {}) -> bool:
	return _can_move_unit(unit, target, pending_moves)


## Validate a batch move before spending AP (duplicate targets, range, occupancy).
func can_apply_moves(player_id: int, moves: Dictionary) -> Dictionary:
	for unit_id in moves:
		var unit: UnitBase = _find_unit(unit_id)
		if unit == null or unit.owner_id != player_id:
			return _fail("Invalid unit.")
		if not unit.is_player_controllable():
			return _fail("That unit is AI-controlled.")
		var target: Vector2i = moves[unit_id]
		if not _can_move_unit(unit, target, moves):
			return _fail("%s cannot reach that hex." % unit.display_name)
	var targets: Array[Vector2i] = []
	for unit_id in moves:
		var target: Vector2i = moves[unit_id]
		var unit: UnitBase = _find_unit(unit_id)
		if target == unit.hex_position:
			continue
		if target in targets:
			return _fail("Two units cannot move to the same hex.")
		targets.append(target)
	return {"success": true}


## Move all listed units for one AP; reveal fog along each path; grant +1 RP.
func perform_move(player_id: int, moves: Dictionary) -> Dictionary:
	## moves: { unit_id: Vector2i target_hex }
	if not can_act(player_id):
		return _fail("Not your turn or no actions left.")

	var check: Dictionary = can_apply_moves(player_id, moves)
	if not check.get("success", false):
		return check

	for unit_id in moves:
		var unit: UnitBase = _find_unit(unit_id)
		var target: Vector2i = moves[unit_id]
		if target != unit.hex_position:
			var path: Array[Vector2i] = find_movement_path(unit, target, moves)
			for hex in path:
				_reveal_hex_if_hidden(hex)
			unit.hex_position = target
			grid.on_unit_entered(target, unit)

	_add_resource(player_id, 1)
	var spent: Dictionary = _spend_action_point(player_id)
	if not spent.get("success", false):
		return spent
	action_log.emit("Player %d moved units (+1 RP)." % (player_id + 1))
	state_changed.emit()
	return {"success": true}


## Basic attack for 1 AP; emits combat_event for UI VFX.
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

	var spent: Dictionary = _spend_action_point(player_id)
	if not spent.get("success", false):
		return spent

	var damage: int = attacker.perform_basic_attack(target)
	_emit_combat_event("attack", {
		"attacker_id": attacker.id,
		"target_id": target.id,
		"damage": damage,
		"target_killed": not target.is_alive,
	})
	action_log.emit("%s hit %s for %d damage." % [
		attacker.display_name, target.display_name, damage
	])
	_check_win()
	state_changed.emit()
	return {"success": true, "damage": damage}


## Special ability for 1 AP + RP cost; context dict supplies allies, enemies, grid, targets.
func perform_ability(player_id: int, unit_id: String, extra: Dictionary = {}) -> Dictionary:
	if not can_act(player_id):
		return _fail("Not your turn or no actions left.")

	var unit: UnitBase = _find_unit(unit_id)
	if unit == null or unit.owner_id != player_id:
		return _fail("Invalid unit.")
	if not unit.is_player_controllable():
		return _fail("That unit is AI-controlled.")
	if not unit.can_use_ability(resource_points[player_id], turn_manager.can_spend_action()):
		if not turn_manager.can_spend_action():
			return _fail("No actions left.")
		return _fail("Not enough resource points (need %d)." % unit.ability_cost)

	var ctx: Dictionary = {
		"allies": units,
		"enemies": get_enemies_of(player_id),
		"grid": grid,
		"target": _resolve_ability_target(extra),
		"summon_hex": extra.get("summon_hex", Vector2i(-999, -999)),
		"line_of_sight_check": func(a, b): return has_line_of_sight(a, b),
		"reveal_hex": func(h): reveal_hex(h),
		"summon_minion": func(hex): return summon_minion(player_id, unit, hex),
	}
	var result: Dictionary = unit.use_ability(ctx)
	if not result.get("success", false):
		return result

	resource_points[player_id] -= unit.ability_cost

	var ability_event: Dictionary = {
		"unit_id": unit.id,
		"ability_type": unit.get_unit_type_id(),
	}
	if extra.has("summon_hex"):
		ability_event["summon_hex"] = extra["summon_hex"]
	if result.has("target_id"):
		ability_event["target_id"] = result["target_id"]
		var ability_target: UnitBase = _find_unit(result["target_id"])
		if ability_target != null:
			ability_event["target_killed"] = not ability_target.is_alive
	if result.has("damage"):
		ability_event["damage"] = result["damage"]
	if result.has("healed_unit_ids"):
		ability_event["healed_unit_ids"] = result["healed_unit_ids"]
	_emit_combat_event("ability", ability_event)
	var spent: Dictionary = _spend_action_point(player_id)
	if not spent.get("success", false):
		resource_points[player_id] += unit.ability_cost
		return spent
	action_log.emit(result.get("message", "Ability used."))
	_check_win()
	state_changed.emit()
	return result


## Resolve optional enemy target passed from UI (target_id string or UnitBase).
func _resolve_ability_target(extra: Dictionary) -> UnitBase:
	if extra.has("target_id"):
		return _find_unit(str(extra.get("target_id", "")))
	return extra.get("target", null)


## Stand on a unique tile and spend 1 AP for its interact effect (forge, hive, etc.).
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

	var spent: Dictionary = _spend_action_point(player_id)
	if not spent.get("success", false):
		return spent
	action_log.emit(result.get("message", "Tile interaction."))
	state_changed.emit()
	return result


# --- Minion summoning (Swarm teams; capped per player) ---

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


# --- Turn end: AI minions act, then pass to next player ---

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


## Spend one action point; auto-run minions and end turn when AP hits zero.
func _spend_action_point(player_id: int) -> Dictionary:
	if not turn_manager.can_spend_action():
		return _fail("No actions left.")
	turn_manager.spend_action()
	_after_action_spent(player_id)
	return {"success": true}


func _after_action_spent(player_id: int) -> void:
	if turn_manager.actions_remaining <= 0:
		run_minion_phase(player_id)
		turn_manager.end_turn()
		state_changed.emit()


# --- Movement validation (range BFS, occupancy, vacating units in batch moves) ---

func _can_move_unit(unit: UnitBase, target: Vector2i, pending_moves: Dictionary = {}) -> bool:
	if target == unit.hex_position:
		return true
	if not grid.has_tile(target):
		return false
	if _blocks_movement_at(target):
		return false
	var occupant: UnitBase = get_unit_at(target)
	if occupant != null:
		if pending_moves.has(occupant.id):
			var occupant_dest: Vector2i = pending_moves[occupant.id]
			if occupant_dest == target:
				return false
		else:
			return false
	var dist: int = _movement_distance(unit.hex_position, target, pending_moves)
	return dist >= 0 and dist <= unit.move_range


func _is_walkable_for_move(
	unit: UnitBase,
	hex: Vector2i,
	target: Vector2i,
	pending_moves: Dictionary,
) -> bool:
	if not grid.has_tile(hex):
		return false
	if _blocks_movement_at(hex):
		return false
	if hex == target:
		return true
	var occupant: UnitBase = get_unit_at(hex)
	if occupant == null:
		return true
	if occupant.id == unit.id:
		return true
	if pending_moves.has(occupant.id):
		var occupant_dest: Vector2i = pending_moves[occupant.id]
		return occupant_dest != hex
	return false


func _movement_distance(from_hex: Vector2i, to_hex: Vector2i, pending_moves: Dictionary = {}) -> int:
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
			if neighbor != to_hex and get_unit_at(neighbor) != null:
				var blocker: UnitBase = get_unit_at(neighbor)
				if not pending_moves.has(blocker.id):
					continue
				var vacating_dest: Vector2i = pending_moves[blocker.id]
				if vacating_dest == neighbor:
					continue
			visited[neighbor] = true
			queue.append([neighbor, cost + 1])
	return -1


# --- Fog of war reveal and line-of-sight checks ---

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


# --- Resource economy and internal helpers ---

func _add_resource(player_id: int, amount: int) -> void:
	var cap: int = get_max_resource(player_id)
	resource_points[player_id] = mini(cap, resource_points[player_id] + amount)


func _find_unit(unit_id: String) -> UnitBase:
	for u in units:
		if u.id == unit_id:
			return u
	return null


## Minion attacks during end-of-turn phase (no AP cost; still emits combat_event).
func perform_minion_attack(minion: UnitBase, target: UnitBase) -> Dictionary:
	if minion == null or target == null:
		return _fail("Unit not found.")
	if not minion.can_attack(target, func(a, b): return has_line_of_sight(a, b)):
		return _fail("Invalid minion attack.")

	var damage: int = minion.perform_basic_attack(target)
	_emit_combat_event("attack", {
		"attacker_id": minion.id,
		"target_id": target.id,
		"damage": damage,
		"target_killed": not target.is_alive,
	})
	action_log.emit("%s hit %s for %d damage." % [minion.display_name, target.display_name, damage])
	state_changed.emit()
	return {"success": true, "damage": damage}


func _emit_combat_event(event_type: String, data: Dictionary) -> void:
	combat_event.emit(event_type, data)


## Win when a player's leader is dead; emit match_over with surviving player.
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


## Swap a hidden placeholder tile for its real type when a unit walks onto it.
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
