class_name UnitRegistry
extends RefCounted
## Factory for placeholder and future unit types.

static var _factories: Dictionary = {
	"sentinel_leader": _make_sentinel_leader,
	"sentinel_follower": _make_sentinel_follower,
	"veil_leader": _make_veil_leader,
	"veil_follower": _make_veil_follower,
	"ember_leader": _make_ember_leader,
	"ember_follower": _make_ember_follower,
	"swarm_leader": _make_swarm_leader,
	"swarm_follower": _make_swarm_follower,
	"swarm_minion": _make_swarm_minion,
}


static func create(type_id: String, owner_id: int, team_id: int, unit_index: int) -> UnitBase:
	if not _factories.has(type_id):
		push_warning("Unknown unit type: %s" % type_id)
		return SentinelLeaderUnit.new(owner_id, team_id, unit_index)
	var unit: UnitBase = _factories[type_id].call()
	unit.owner_id = owner_id
	unit.team_id = team_id
	unit.id = "%d_%s_%d" % [owner_id, type_id, unit_index]
	return unit


static func create_minion(type_id: String, owner_id: int, team_id: int, unique_idx: int) -> UnitBase:
	if not _factories.has(type_id):
		push_warning("Unknown minion type: %s" % type_id)
		return SwarmMinionUnit.new()
	var unit: UnitBase = _factories[type_id].call()
	unit.owner_id = owner_id
	unit.team_id = team_id
	unit.id = "%d_%s_m%d" % [owner_id, type_id, unique_idx]
	return unit


# --- Sentinel faction (defensive, moderate range) ---

class SentinelLeaderUnit extends UnitBase:
	func _init(p_owner: int = 0, p_team: int = 0, idx: int = 0) -> void:
		display_name = "Sentinel Prime"
		is_leader = true
		max_health = 14
		move_range = 2
		attack_range = 1
		attack_die_sides = 4
		ability_cost = 3
		owner_id = p_owner
		team_id = p_team
		id = "%d_sentinel_leader_%d" % [p_owner, idx]
		health = max_health

	func get_unit_type_id() -> String:
		return "sentinel_leader"

	func use_ability(context: Dictionary) -> Dictionary:
		var allies: Array = context.get("allies", [])
		var healed: int = 0
		for ally in allies:
			if ally.owner_id == owner_id and ally.is_alive:
				ally.heal(2)
				healed += 1
		return {"success": true, "message": "Bulwark Pulse healed %d allies." % healed}

	func get_ability_description() -> String:
		return "Bulwark Pulse (3 RP): Heal all allied units by 2."


class SentinelFollowerUnit extends UnitBase:
	func _init(p_owner: int = 0, p_team: int = 0, idx: int = 0) -> void:
		display_name = "Sentinel Guard"
		max_health = 8
		move_range = 2
		attack_range = 1
		attack_die_sides = 3
		ability_cost = 2
		owner_id = p_owner
		team_id = p_team
		id = "%d_sentinel_follower_%d" % [p_owner, idx]
		health = max_health

	func get_unit_type_id() -> String:
		return "sentinel_follower"

	func use_ability(context: Dictionary) -> Dictionary:
		defense_bonus = 2
		return {"success": true, "message": "Guard Stance: +2 defense until next turn."}

	func get_ability_description() -> String:
		return "Guard Stance (2 RP): +2 defense until your next turn."


static func _make_sentinel_leader() -> UnitBase:
	return SentinelLeaderUnit.new()


static func _make_sentinel_follower() -> UnitBase:
	return SentinelFollowerUnit.new()


# --- Veil faction (mobility, recon) ---

class VeilLeaderUnit extends UnitBase:
	func _init(p_owner: int = 0, p_team: int = 0, idx: int = 0) -> void:
		display_name = "Veil Archon"
		is_leader = true
		max_health = 11
		move_range = 3
		attack_range = 2
		attack_die_sides = 4
		ability_cost = 2
		owner_id = p_owner
		team_id = p_team
		id = "%d_veil_leader_%d" % [p_owner, idx]
		health = max_health

	func get_unit_type_id() -> String:
		return "veil_leader"

	func use_ability(context: Dictionary) -> Dictionary:
		var grid: HexGrid = context.get("grid", null)
		var reveal_hex: Callable = context.get("reveal_hex", Callable())
		if grid == null or not reveal_hex.is_valid():
			return {"success": false, "message": "No reveal context."}
		var revealed_count: int = 0
		for neighbor in HexCoords.neighbors(hex_position):
			if grid.has_tile(neighbor):
				reveal_hex.call(neighbor)
				revealed_count += 1
		return {"success": true, "message": "Whisper Scan revealed %d adjacent tiles." % revealed_count}

	func get_ability_description() -> String:
		return "Whisper Scan (2 RP): Reveal all adjacent hidden tiles."


class VeilFollowerUnit extends UnitBase:
	func _init(p_owner: int = 0, p_team: int = 0, idx: int = 0) -> void:
		display_name = "Veil Scout"
		max_health = 6
		move_range = 3
		attack_range = 1
		attack_die_sides = 3
		ability_cost = 1
		owner_id = p_owner
		team_id = p_team
		id = "%d_veil_follower_%d" % [p_owner, idx]
		health = max_health

	func get_unit_type_id() -> String:
		return "veil_follower"

	func use_ability(_context: Dictionary) -> Dictionary:
		move_range += 1
		return {"success": true, "message": "Slipstream: +1 move range this turn."}

	func get_ability_description() -> String:
		return "Slipstream (1 RP): +1 move range for this turn."


static func _make_veil_leader() -> UnitBase:
	return VeilLeaderUnit.new()


static func _make_veil_follower() -> UnitBase:
	return VeilFollowerUnit.new()


# --- Ember faction (aggressive, high damage) ---

class EmberLeaderUnit extends UnitBase:
	func _init(p_owner: int = 0, p_team: int = 0, idx: int = 0) -> void:
		display_name = "Ember Warlord"
		is_leader = true
		max_health = 12
		move_range = 2
		attack_range = 1
		attack_die_sides = 6
		ability_cost = 3
		owner_id = p_owner
		team_id = p_team
		id = "%d_ember_leader_%d" % [p_owner, idx]
		health = max_health

	func get_unit_type_id() -> String:
		return "ember_leader"

	func use_ability(_context: Dictionary) -> Dictionary:
		damage_bonus = 2
		return {"success": true, "message": "Inferno Charge: +2 attack damage this turn."}

	func get_ability_description() -> String:
		return "Inferno Charge (3 RP): +2 attack damage this turn."


class EmberFollowerUnit extends UnitBase:
	func _init(p_owner: int = 0, p_team: int = 0, idx: int = 0) -> void:
		display_name = "Ember Raider"
		max_health = 7
		move_range = 2
		attack_range = 1
		attack_die_sides = 5
		ability_cost = 2
		owner_id = p_owner
		team_id = p_team
		id = "%d_ember_follower_%d" % [p_owner, idx]
		health = max_health

	func get_unit_type_id() -> String:
		return "ember_follower"

	func use_ability(context: Dictionary) -> Dictionary:
		var target: UnitBase = context.get("target", null)
		var los_check: Callable = context.get("line_of_sight_check", Callable())
		if target == null or not can_attack(target, los_check):
			return {"success": false, "message": "No valid target in range."}
		var dmg: int = perform_basic_attack(target)
		return {"success": true, "message": "Double Strike dealt %d damage." % dmg}

	func get_ability_description() -> String:
		return "Double Strike (2 RP): Immediately perform a basic attack."


static func _make_ember_leader() -> UnitBase:
	return EmberLeaderUnit.new()


static func _make_ember_follower() -> UnitBase:
	return EmberFollowerUnit.new()


# --- Swarm faction (summoner, minions) ---

class SwarmLeaderUnit extends UnitBase:
	func _init(p_owner: int = 0, p_team: int = 0, idx: int = 0) -> void:
		display_name = "Hive Matriarch"
		is_leader = true
		max_health = 10
		move_range = 2
		attack_range = 1
		attack_die_sides = 3
		ability_cost = 2
		owner_id = p_owner
		team_id = p_team
		id = "%d_swarm_leader_%d" % [p_owner, idx]
		health = max_health

	func get_unit_type_id() -> String:
		return "swarm_leader"

	func use_ability(context: Dictionary) -> Dictionary:
		var summon_minion: Callable = context.get("summon_minion", Callable())
		if not summon_minion.is_valid():
			return {"success": false, "message": "Cannot summon."}
		var summon_hex: Vector2i = context.get("summon_hex", Vector2i(-999, -999))
		if summon_hex != Vector2i(-999, -999):
			if summon_minion.call(summon_hex) != null:
				return {"success": true, "message": "Hive Matriarch spawned a minion."}
			return {"success": false, "message": "No room to summon there."}
		for neighbor in HexCoords.neighbors(hex_position):
			if summon_minion.call(neighbor) != null:
				return {"success": true, "message": "Hive Matriarch spawned a minion."}
		return {"success": false, "message": "No adjacent space to summon."}

	func get_ability_description() -> String:
		return "Spawn Minion (2 RP): Summon an AI-controlled minion on an adjacent hex."


class SwarmFollowerUnit extends UnitBase:
	func _init(p_owner: int = 0, p_team: int = 0, idx: int = 0) -> void:
		display_name = "Swarm Herald"
		max_health = 7
		move_range = 2
		attack_range = 1
		attack_die_sides = 3
		ability_cost = 1
		owner_id = p_owner
		team_id = p_team
		id = "%d_swarm_follower_%d" % [p_owner, idx]
		health = max_health

	func get_unit_type_id() -> String:
		return "swarm_follower"

	func use_ability(context: Dictionary) -> Dictionary:
		var summon_minion: Callable = context.get("summon_minion", Callable())
		if not summon_minion.is_valid():
			return {"success": false, "message": "Cannot summon."}
		for neighbor in HexCoords.neighbors(hex_position):
			var minion: Variant = summon_minion.call(neighbor)
			if minion != null:
				return {"success": true, "message": "Swarm Herald spawned a minion."}
		return {"success": false, "message": "No adjacent space to summon."}

	func get_ability_description() -> String:
		return "Call Drone (1 RP): Summon a weaker AI minion on an adjacent hex."


class SwarmMinionUnit extends UnitBase:
	func _init(_p_owner: int = 0, _p_team: int = 0, _idx: int = 0) -> void:
		display_name = "Swarm Drone"
		max_health = 3
		move_range = 1
		attack_range = 1
		attack_die_sides = 2
		ability_cost = 99
		is_ai_controlled = true
		is_minion = true
		health = max_health

	func get_unit_type_id() -> String:
		return "swarm_minion"

	func use_ability(_context: Dictionary) -> Dictionary:
		return {"success": false, "message": "Minions cannot use abilities."}

	func get_ability_description() -> String:
		return "AI-controlled — acts automatically at end of turn."


static func _make_swarm_leader() -> UnitBase:
	return SwarmLeaderUnit.new()


static func _make_swarm_follower() -> UnitBase:
	return SwarmFollowerUnit.new()


static func _make_swarm_minion() -> UnitBase:
	return SwarmMinionUnit.new()
