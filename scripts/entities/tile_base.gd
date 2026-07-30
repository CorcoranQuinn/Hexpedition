class_name TileBase
extends RefCounted
## Abstract base for hex tiles.
## Subclass to define reveal behavior, movement modifiers, and interactions.

var hex_position: Vector2i = Vector2i.ZERO
var revealed: bool = false
var display_name: String = "Tile"
var is_team_unique: bool = false
var team_id: int = -1  # -1 = neutral


func get_tile_type_id() -> String:
	return "tile_base"


func get_hidden_label() -> String:
	return "?"


func get_revealed_color() -> Color:
	return Color(0.35, 0.38, 0.42)


## Called once when a unit first steps on this tile (triggers reveal).
func on_unit_enter(_unit: UnitBase) -> void:
	pass


## Called when the tile becomes visible.
func on_reveal() -> void:
	pass


## Special tile interaction action (ActionType.TILE_INTERACT).
## Override for unique team tiles and interactive terrain.
func interact(unit: UnitBase, context: Dictionary) -> Dictionary:
	return {
		"success": false,
		"message": "Nothing to interact with here.",
	}


func can_interact(unit: UnitBase) -> bool:
	if not revealed:
		return false
	if is_team_unique and team_id >= 0:
		return unit.team_id == team_id
	return false


func movement_cost_modifier() -> int:
	return 0


func blocks_movement() -> bool:
	return false


func blocks_projectiles() -> bool:
	return false
