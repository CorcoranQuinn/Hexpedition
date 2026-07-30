class_name MatchAI
extends RefCounted
## Simple AI for solo mode and ai_controlled minions.

const MAX_MINIONS_PER_PLAYER: int = 4


static func pick_random_team_id(exclude: int = -1) -> int:
	return TeamRegistry.pick_random_team_id(exclude)


static func run_turn(match: MatchController, player_id: int) -> void:
	while match.can_act(player_id):
		if _try_attack(match, player_id):
			continue
		if _try_summon(match, player_id):
			continue
		if _try_ability(match, player_id):
			continue
		if _try_move(match, player_id):
			continue
		_force_end_turn(match)


static func run_minions(match: MatchController, player_id: int) -> void:
	for unit in match.units:
		if not unit.is_alive or unit.owner_id != player_id or not unit.is_ai_controlled:
			continue
		if _minion_attack(match, unit):
			match._check_win()
			continue
		_minion_move_toward_enemy(match, unit)


static func _try_attack(match: MatchController, player_id: int) -> bool:
	var best_attacker: UnitBase = null
	var best_target: UnitBase = null
	for unit in match.get_units_for_player(player_id):
		if unit.is_ai_controlled:
			continue
		for enemy in match.get_enemies_of(player_id):
			if unit.can_attack(enemy, func(a, b): return match.has_line_of_sight(a, b)):
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
	var result: Dictionary = match.perform_attack(player_id, best_attacker.id, best_target.id)
	return result.get("success", false)


static func _try_summon(match: MatchController, player_id: int) -> bool:
	for unit in match.get_units_for_player(player_id):
		if unit.is_ai_controlled:
			continue
		if unit.get_unit_type_id() != "swarm_leader" and unit.get_unit_type_id() != "swarm_follower":
			continue
		if not unit.can_use_ability(match.resource_points[player_id]):
			continue
		if _count_minions(match, player_id) >= MAX_MINIONS_PER_PLAYER:
			continue
		var hex: Vector2i = _find_summon_hex(match, unit)
		if hex == Vector2i(-999, -999):
			continue
		var result: Dictionary = match.perform_ability(player_id, unit.id, {"summon_hex": hex})
		return result.get("success", false)
	return false


static func _try_ability(match: MatchController, player_id: int) -> bool:
	for unit in match.get_units_for_player(player_id):
		if unit.is_ai_controlled:
			continue
		if unit.get_unit_type_id() == "swarm_leader" or unit.get_unit_type_id() == "swarm_follower":
			continue
		if not unit.can_use_ability(match.resource_points[player_id]):
			continue
		var result: Dictionary = match.perform_ability(player_id, unit.id)
		if result.get("success", false):
			return true
	return false


static func _try_move(match: MatchController, player_id: int) -> bool:
	var enemies: Array[UnitBase] = match.get_enemies_of(player_id)
	if enemies.is_empty():
		return false
	var moves: Dictionary = {}
	for unit in match.get_units_for_player(player_id):
		if unit.is_ai_controlled:
			continue
		var target: Vector2i = _best_move_toward(match, unit, enemies)
		if target != unit.hex_position:
			moves[unit.id] = target
	if moves.is_empty():
		return false
	var result: Dictionary = match.perform_move(player_id, moves)
	return result.get("success", false)


static func _minion_attack(match: MatchController, minion: UnitBase) -> bool:
	for enemy in match.get_enemies_of(minion.owner_id):
		if minion.can_attack(enemy, func(a, b): return match.has_line_of_sight(a, b)):
			minion.perform_basic_attack(enemy)
			match.action_log.emit("%s attacked %s." % [minion.display_name, enemy.display_name])
			match.state_changed.emit()
			return true
	return false


static func _minion_move_toward_enemy(match: MatchController, minion: UnitBase) -> void:
	var enemies: Array[UnitBase] = match.get_enemies_of(minion.owner_id)
	if enemies.is_empty():
		return
	var target: Vector2i = _best_move_toward(match, minion, enemies)
	if target == minion.hex_position:
		return
	minion.hex_position = target
	match._reveal_hex_if_hidden(target)
	match.grid.on_unit_entered(target, minion)
	match.action_log.emit("%s moved toward the enemy." % minion.display_name)
	match.state_changed.emit()


static func _best_move_toward(match: MatchController, unit: UnitBase, enemies: Array[UnitBase]) -> Vector2i:
	var best_hex: Vector2i = unit.hex_position
	var best_dist: int = 9999
	for enemy in enemies:
		var dist: int = HexCoords.distance(unit.hex_position, enemy.hex_position)
		if dist < best_dist:
			best_dist = dist
	for neighbor in HexCoords.within_radius(unit.hex_position, unit.move_range):
		if not match._can_move_unit(unit, neighbor):
			continue
		var dist: int = 9999
		for enemy in enemies:
			dist = mini(dist, HexCoords.distance(neighbor, enemy.hex_position))
		if dist < best_dist:
			best_dist = dist
			best_hex = neighbor
	return best_hex


static func _find_summon_hex(match: MatchController, summoner: UnitBase) -> Vector2i:
	for neighbor in HexCoords.neighbors(summoner.hex_position):
		if match.can_summon_at(summoner.owner_id, neighbor):
			return neighbor
	return Vector2i(-999, -999)


static func _count_minions(match: MatchController, player_id: int) -> int:
	var count: int = 0
	for unit in match.units:
		if unit.owner_id == player_id and unit.is_minion and unit.is_alive:
			count += 1
	return count


static func _force_end_turn(match: MatchController) -> void:
	if match.turn_manager.actions_remaining > 0:
		match.end_turn_with_minions(match.turn_manager.current_player)
