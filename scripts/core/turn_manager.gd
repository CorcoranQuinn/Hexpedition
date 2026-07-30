class_name TurnManager
extends RefCounted
## Tracks per-turn action points and current active player.

signal turn_started(player_id: int)
signal turn_ended(player_id: int)
signal actions_changed(remaining: int)
signal player_changed(player_id: int)

enum ActionType { MOVE, ATTACK, ABILITY, TILE_INTERACT }

const ACTIONS_PER_TURN: int = 3

var current_player: int = 0
var actions_remaining: int = ACTIONS_PER_TURN
var turn_number: int = 1


func start_match(starting_player: int = 0) -> void:
	current_player = starting_player
	turn_number = 1
	actions_remaining = ACTIONS_PER_TURN
	turn_started.emit(current_player)
	actions_changed.emit(actions_remaining)


func can_spend_action() -> bool:
	return actions_remaining > 0


func spend_action() -> bool:
	if actions_remaining <= 0:
		return false
	actions_remaining -= 1
	actions_changed.emit(actions_remaining)
	return true


func end_turn() -> void:
	turn_ended.emit(current_player)
	current_player = 1 - current_player
	if current_player == 0:
		turn_number += 1
	actions_remaining = ACTIONS_PER_TURN
	player_changed.emit(current_player)
	turn_started.emit(current_player)
	actions_changed.emit(actions_remaining)


func get_action_name(action: ActionType) -> String:
	match action:
		ActionType.MOVE: return "Move"
		ActionType.ATTACK: return "Attack"
		ActionType.ABILITY: return "Ability"
		ActionType.TILE_INTERACT: return "Tile Interact"
	return "Unknown"
