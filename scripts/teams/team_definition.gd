class_name TeamDefinition
extends Resource
## Describes a selectable team: leader, followers, unique tile, resource cap.

@export var team_id: int = 0
@export var team_name: String = "Team"
@export var team_color: Color = Color.WHITE
@export var max_resource_points: int = 5
@export var description: String = ""

# Unit type IDs — resolved via UnitRegistry
@export var leader_type_id: String = ""
@export var follower_type_ids: Array[String] = []

# Tile type ID — resolved via TileRegistry
@export var unique_tile_type_id: String = ""


func get_roster_type_ids() -> Array[String]:
	var roster: Array[String] = [leader_type_id]
	for fid in follower_type_ids:
		roster.append(fid)
	return roster
