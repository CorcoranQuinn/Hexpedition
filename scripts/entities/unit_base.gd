class_name UnitBase
extends RefCounted
## Abstract base for all combat units.
## Subclass to define stats, ability behavior, and visual identity.

var id: String = ""
var display_name: String = "Unit"
var team_id: int = 0
var owner_id: int = 0  # player slot

var hex_position: Vector2i = Vector2i.ZERO

var max_health: int = 10
var health: int = 10
var move_range: int = 2
var attack_range: int = 1
var attack_die_sides: int = 4  # roll 1..N for basic attack damage

var ability_cost: int = 2
var is_leader: bool = false
var is_alive: bool = true
var is_ai_controlled: bool = false
var is_minion: bool = false
var summoner_id: String = ""

# Runtime buffs from abilities
var damage_bonus: int = 0
var defense_bonus: int = 0


func _init() -> void:
	health = max_health


func get_unit_type_id() -> String:
	return "unit_base"


func roll_basic_attack_damage() -> int:
	return randi_range(1, attack_die_sides) + damage_bonus


func perform_basic_attack(target: UnitBase) -> int:
	if not can_attack(target):
		return 0
	var raw: int = roll_basic_attack_damage()
	var damage: int = maxi(1, raw - target.defense_bonus)
	target.take_damage(damage)
	return damage


func can_attack(target: UnitBase, line_of_sight_check: Callable = Callable()) -> bool:
	if target == null or not is_alive or not target.is_alive:
		return false
	if target.owner_id == owner_id:
		return false
	if HexCoords.distance(hex_position, target.hex_position) > attack_range:
		return false
	if line_of_sight_check.is_valid() and not line_of_sight_check.call(hex_position, target.hex_position):
		return false
	return true


func take_damage(amount: int) -> void:
	if not is_alive:
		return
	health -= amount
	if health <= 0:
		health = 0
		is_alive = false


func heal(amount: int) -> void:
	if not is_alive:
		return
	health = mini(max_health, health + amount)


func can_use_ability(resource_points: int, actions_available: bool = true) -> bool:
	return is_alive and actions_available and resource_points >= ability_cost


## Override in subclasses for unique ability effects.
## Returns a Dictionary describing what happened for UI/log purposes.
func use_ability(context: Dictionary) -> Dictionary:
	return {
		"success": false,
		"message": "Ability not implemented.",
	}


func get_ability_description() -> String:
	return "No ability description."


func ability_requires_enemy_target() -> bool:
	return false


func reset_turn_modifiers() -> void:
	damage_bonus = 0
	defense_bonus = 0


func is_player_controllable() -> bool:
	return is_alive and not is_ai_controlled


func to_snapshot() -> Dictionary:
	return {
		"id": id,
		"type": get_unit_type_id(),
		"hex": hex_position,
		"health": health,
		"max_health": max_health,
		"alive": is_alive,
		"owner": owner_id,
		"team": team_id,
		"leader": is_leader,
	}
