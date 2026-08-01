class_name MatchAI
extends RefCounted
## Simple AI for solo mode and ai_controlled minions.

const MAX_MINIONS_PER_PLAYER: int = 4


# --- Opponent turn AI (solo mode): attack > summon > ability > move ---

static func pick_random_team_id(exclude: int = -1) -> int:
	return TeamRegistry.pick_random_team_id(exclude)


# --- Pre-game deployment for solo mode (AI player) ---

static func run_placement(match_ctrl: MatchController, player_id: int) -> void:
	var zone: Array[Vector2i] = match_ctrl.get_placement_zone(player_id)
	var to_place: Array[UnitBase] = match_ctrl.get_unplaced_units(player_id)
	to_place.sort_custom(func(a: UnitBase, b: UnitBase) -> bool:
		if a.is_leader != b.is_leader:
			return a.is_leader
		return a.id < b.id,
	)

	var corner: Vector2i = MatchController.PLACEMENT_CORNERS[player_id]
	zone.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return HexCoords.distance(a, corner) < HexCoords.distance(b, corner),
	)

	var chosen: Array[Vector2i] = []
	var assignments: Dictionary = {}
	for unit in to_place:
		var best_hex: Vector2i = zone[0]
		var best_score: float = -INF
		for hex in zone:
			if chosen.has(hex):
				continue
			var score: float = _score_placement_hex(hex, chosen, unit.is_leader, corner)
			if score > best_score:
				best_score = score
				best_hex = hex
		assignments[unit.id] = best_hex
		chosen.append(best_hex)

	match_ctrl.place_units_for_player(player_id, assignments)


static func _score_placement_hex(
	hex: Vector2i,
	placed: Array[Vector2i],
	prefer_back: bool,
	corner: Vector2i,
) -> float:
	var score: float = 0.0
	if prefer_back:
		score += float(HexCoords.distance(hex, corner)) * 2.0
	for other in placed:
		score += float(HexCoords.distance(hex, other)) * 1.5
	return score


static func run_turn(match_ctrl: MatchController, player_id: int) -> void:
	while match_ctrl.can_act(player_id):
		if _try_attack(match_ctrl, player_id):
			continue
		if _try_summon(match_ctrl, player_id):
			continue
		if _try_ability(match_ctrl, player_id):
			continue
		if _try_move(match_ctrl, player_id):
			continue
		_force_end_turn(match_ctrl)


# --- End-of-turn minion phase (AI-controlled units only) ---

static func run_minions(match_ctrl: MatchController, player_id: int) -> void:
	for unit in match_ctrl.units:
		if not unit.is_alive or unit.owner_id != player_id or not unit.is_ai_controlled:
			continue
		if _minion_attack(match_ctrl, unit):
			match_ctrl._check_win()
			continue
		_minion_move_toward_enemy(match_ctrl, unit)


# --- Turn action priorities (each returns true if it spent an AP) ---

static func _try_attack(match_ctrl: MatchController, player_id: int) -> bool:
	var best_attacker: UnitBase = null
	var best_target: UnitBase = null
	for unit in match_ctrl.get_units_for_player(player_id):
		if unit.is_ai_controlled:
			continue
		for enemy in match_ctrl.get_enemies_of(player_id):
			if unit.can_attack(enemy, func(a, b): return match_ctrl.has_line_of_sight(a, b)):
				if enemy.is_leader:
					best_attacker = unit
					best_target = enemy
					break
				if best_target == null or not best_target.is_leader:
					best_attacker = unit
					best_target = enemy
		if best_target != null and best_target.is_leader:
			break
	if best_attacker == null or best_target == null:
		return false
	var result: Dictionary = match_ctrl.perform_attack(player_id, best_attacker.id, best_target.id)
	return result.get("success", false)


static func _try_summon(match_ctrl: MatchController, player_id: int) -> bool:
	for unit in match_ctrl.get_units_for_player(player_id):
		if unit.is_ai_controlled:
			continue
		if unit.get_unit_type_id() != "swarm_leader" and unit.get_unit_type_id() != "swarm_follower":
			continue
		if not unit.can_use_ability(
			match_ctrl.resource_points[player_id],
			match_ctrl.turn_manager.can_spend_action(),
		):
			continue
		if _count_minions(match_ctrl, player_id) >= MAX_MINIONS_PER_PLAYER:
			continue
		var hex: Vector2i = _find_summon_hex(match_ctrl, unit)
		if hex == Vector2i(-999, -999):
			continue
		var result: Dictionary = match_ctrl.perform_ability(player_id, unit.id, {"summon_hex": hex})
		return result.get("success", false)
	return false


static func _try_ability(match_ctrl: MatchController, player_id: int) -> bool:
	for unit in match_ctrl.get_units_for_player(player_id):
		if unit.is_ai_controlled:
			continue
		if unit.get_unit_type_id() == "swarm_leader" or unit.get_unit_type_id() == "swarm_follower":
			continue
		if not unit.can_use_ability(
			match_ctrl.resource_points[player_id],
			match_ctrl.turn_manager.can_spend_action(),
		):
			continue
		var extra: Dictionary = {}
		if unit.ability_requires_enemy_target():
			var target: UnitBase = _best_ability_target(match_ctrl, unit)
			if target == null:
				continue
			extra["target_id"] = target.id
		var result: Dictionary = match_ctrl.perform_ability(player_id, unit.id, extra)
		if result.get("success", false):
			return true
	return false


static func _best_ability_target(match_ctrl: MatchController, unit: UnitBase) -> UnitBase:
	var best_target: UnitBase = null
	for enemy in match_ctrl.get_enemies_of(unit.owner_id):
		if unit.can_attack(enemy, func(a, b): return match_ctrl.has_line_of_sight(a, b)):
			if enemy.is_leader:
				return enemy
			if best_target == null or not best_target.is_leader:
				best_target = enemy
	return best_target


static func _try_move(match_ctrl: MatchController, player_id: int) -> bool:
	var enemies: Array[UnitBase] = match_ctrl.get_enemies_of(player_id)
	if enemies.is_empty():
		return false
	var moves: Dictionary = {}
	for unit in match_ctrl.get_units_for_player(player_id):
		if unit.is_ai_controlled:
			continue
		var target: Vector2i = _best_move_toward(match_ctrl, unit, enemies)
		if target != unit.hex_position:
			moves[unit.id] = target
	if moves.is_empty():
		return false
	var result: Dictionary = match_ctrl.perform_move(player_id, moves)
	return result.get("success", false)


# --- Minion behavior (free attacks/movement at end of owner turn) ---

static func _minion_attack(match_ctrl: MatchController, minion: UnitBase) -> bool:
	for enemy in match_ctrl.get_enemies_of(minion.owner_id):
		if minion.can_attack(enemy, func(a, b): return match_ctrl.has_line_of_sight(a, b)):
			var result: Dictionary = match_ctrl.perform_minion_attack(minion, enemy)
			if result.get("success", false):
				match_ctrl._check_win()
				return true
	return false


static func _minion_move_toward_enemy(match_ctrl: MatchController, minion: UnitBase) -> void:
	var enemies: Array[UnitBase] = match_ctrl.get_enemies_of(minion.owner_id)
	if enemies.is_empty():
		return
	var target: Vector2i = _best_move_toward(match_ctrl, minion, enemies)
	if target == minion.hex_position:
		return
	minion.hex_position = target
	match_ctrl._reveal_hex_if_hidden(target)
	match_ctrl.grid.on_unit_entered(target, minion)
	match_ctrl.action_log.emit("%s moved toward the enemy." % minion.display_name)
	match_ctrl.state_changed.emit()


# --- Pathfinding heuristics (move toward nearest enemy, summon adjacent hex) ---

static func _best_move_toward(match_ctrl: MatchController, unit: UnitBase, enemies: Array[UnitBase]) -> Vector2i:
	var best_hex: Vector2i = unit.hex_position
	var best_dist: int = 9999
	for enemy in enemies:
		var dist: int = HexCoords.distance(unit.hex_position, enemy.hex_position)
		if dist < best_dist:
			best_dist = dist
	for neighbor in HexCoords.within_radius(unit.hex_position, unit.move_range):
		if not match_ctrl._can_move_unit(unit, neighbor):
			continue
		var dist: int = 9999
		for enemy in enemies:
			dist = mini(dist, HexCoords.distance(neighbor, enemy.hex_position))
		if dist < best_dist:
			best_dist = dist
			best_hex = neighbor
	return best_hex


static func _find_summon_hex(match_ctrl: MatchController, summoner: UnitBase) -> Vector2i:
	for neighbor in HexCoords.neighbors(summoner.hex_position):
		if match_ctrl.can_summon_at(summoner.owner_id, neighbor):
			return neighbor
	return Vector2i(-999, -999)


static func _count_minions(match_ctrl: MatchController, player_id: int) -> int:
	var count: int = 0
	for unit in match_ctrl.units:
		if unit.owner_id == player_id and unit.is_minion and unit.is_alive:
			count += 1
	return count


static func _force_end_turn(match_ctrl: MatchController) -> void:
	if match_ctrl.turn_manager.actions_remaining > 0:
		match_ctrl.end_turn_with_minions(match_ctrl.turn_manager.current_player)
