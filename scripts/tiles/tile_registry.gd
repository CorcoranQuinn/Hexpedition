class_name TileRegistry
extends RefCounted
## Factory for placeholder and future tile types.

static var _factories: Dictionary = {
	"hidden": _make_hidden,
	"plain": _make_plain,
	"rough": _make_rough,
	"mountain": _make_mountain,
	"sentinel_bastion": _make_sentinel_bastion,
	"veil_mirror": _make_veil_mirror,
	"ember_forge": _make_ember_forge,
	"swarm_hive": _make_swarm_hive,
}


static func create(type_id: String, hex: Vector2i, team_id: int = -1) -> TileBase:
	if not _factories.has(type_id):
		push_warning("Unknown tile type: %s" % type_id)
		return PlainTile.new(hex)
	var tile: TileBase = _factories[type_id].call(hex, team_id)
	return tile


static func create_random_hidden(hex: Vector2i, _rng: RandomNumberGenerator) -> TileBase:
	return create("plain", hex)


# --- Generic tiles ---

class HiddenTile extends TileBase:
	func _init(hex: Vector2i) -> void:
		hex_position = hex
		revealed = false
		display_name = "Unknown"

	func get_tile_type_id() -> String:
		return "hidden"

	func get_hidden_label() -> String:
		return "?"

	func get_revealed_color() -> Color:
		return Color(0.2, 0.22, 0.28)


class PlainTile extends TileBase:
	func _init(hex: Vector2i) -> void:
		hex_position = hex
		revealed = true
		display_name = "Plain"

	func get_tile_type_id() -> String:
		return "plain"

	func get_revealed_color() -> Color:
		return Color(0.45, 0.48, 0.42)


class MountainTile extends TileBase:
	func _init(hex: Vector2i) -> void:
		hex_position = hex
		revealed = true
		display_name = "Mountain"

	func get_tile_type_id() -> String:
		return "mountain"

	func get_revealed_color() -> Color:
		return Color(0.28, 0.30, 0.34)

	func blocks_movement() -> bool:
		return true

	func blocks_projectiles() -> bool:
		return true


class RoughTile extends TileBase:
	func _init(hex: Vector2i) -> void:
		hex_position = hex
		revealed = true
		display_name = "Rough"

	func get_tile_type_id() -> String:
		return "rough"

	func get_revealed_color() -> Color:
		return Color(0.38, 0.34, 0.30)

	func movement_cost_modifier() -> int:
		return 1


class VitalityTile extends TileBase:
	func _init(hex: Vector2i) -> void:
		hex_position = hex
		revealed = true
		display_name = "Vitality"

	func get_tile_type_id() -> String:
		return "vitality"

	func get_revealed_color() -> Color:
		return Color(0.32, 0.55, 0.38)

	func on_unit_enter(unit: UnitBase) -> void:
		unit.heal(1)


static func _make_hidden(hex: Vector2i, _team: int = -1) -> TileBase:
	return HiddenTile.new(hex)


static func _make_plain(hex: Vector2i, _team: int = -1) -> TileBase:
	return PlainTile.new(hex)


static func _make_mountain(hex: Vector2i, _team: int = -1) -> TileBase:
	return MountainTile.new(hex)


static func _make_rough(hex: Vector2i, _team: int = -1) -> TileBase:
	return RoughTile.new(hex)


static func _make_vitality(hex: Vector2i, _team: int = -1) -> TileBase:
	return VitalityTile.new(hex)


# --- Team-unique tiles ---

class SentinelBastionTile extends TileBase:
	func _init(hex: Vector2i, p_team: int) -> void:
		hex_position = hex
		revealed = true
		display_name = "Bastion"
		is_team_unique = true
		team_id = p_team

	func get_tile_type_id() -> String:
		return "sentinel_bastion"

	func get_revealed_color() -> Color:
		return Color(0.35, 0.45, 0.65)

	func interact(unit: UnitBase, _context: Dictionary) -> Dictionary:
		unit.defense_bonus += 3
		return {"success": true, "message": "Bastion grants +3 defense this turn."}

	func can_interact(unit: UnitBase) -> bool:
		return super.can_interact(unit)


class VeilMirrorTile extends TileBase:
	func _init(hex: Vector2i, p_team: int) -> void:
		hex_position = hex
		revealed = true
		display_name = "Mirror Veil"
		is_team_unique = true
		team_id = p_team

	func get_tile_type_id() -> String:
		return "veil_mirror"

	func get_revealed_color() -> Color:
		return Color(0.55, 0.42, 0.68)

	func interact(unit: UnitBase, context: Dictionary) -> Dictionary:
		var grid: HexGrid = context.get("grid", null)
		var reveal_hex: Callable = context.get("reveal_hex", Callable())
		if grid == null:
			return {"success": false, "message": "No grid context."}
		var far_hex: Vector2i = unit.hex_position + Vector2i(0, -2)
		if not grid.has_tile(far_hex):
			return {"success": false, "message": "No tile to scry."}
		var los_check: Callable = context.get("has_line_of_sight", Callable())
		if los_check.is_valid() and not los_check.call(unit.hex_position, far_hex):
			return {"success": false, "message": "Mountain blocks the scry."}
		if reveal_hex.is_valid():
			reveal_hex.call(far_hex)
		return {"success": true, "message": "Mirror Veil scried a distant tile."}


class EmberForgeTile extends TileBase:
	func _init(hex: Vector2i, p_team: int) -> void:
		hex_position = hex
		revealed = true
		display_name = "Ember Forge"
		is_team_unique = true
		team_id = p_team

	func get_tile_type_id() -> String:
		return "ember_forge"

	func get_revealed_color() -> Color:
		return Color(0.72, 0.38, 0.22)

	func interact(unit: UnitBase, _context: Dictionary) -> Dictionary:
		unit.damage_bonus += 2
		return {"success": true, "message": "Ember Forge empowers your next attack (+2)."}


class SwarmHiveTile extends TileBase:
	func _init(hex: Vector2i, p_team: int) -> void:
		hex_position = hex
		revealed = true
		display_name = "Swarm Hive"
		is_team_unique = true
		team_id = p_team

	func get_tile_type_id() -> String:
		return "swarm_hive"

	func get_revealed_color() -> Color:
		return Color(0.42, 0.62, 0.32)

	func interact(unit: UnitBase, context: Dictionary) -> Dictionary:
		var summon_minion: Callable = context.get("summon_minion", Callable())
		if not summon_minion.is_valid():
			return {"success": false, "message": "Cannot summon from hive."}
		for neighbor in HexCoords.neighbors(unit.hex_position):
			if summon_minion.call(neighbor) != null:
				return {"success": true, "message": "Swarm Hive spawned a minion."}
		return {"success": false, "message": "No adjacent space at the hive."}


static func _make_sentinel_bastion(hex: Vector2i, team: int) -> TileBase:
	return SentinelBastionTile.new(hex, team)


static func _make_veil_mirror(hex: Vector2i, team: int) -> TileBase:
	return VeilMirrorTile.new(hex, team)


static func _make_ember_forge(hex: Vector2i, team: int) -> TileBase:
	return EmberForgeTile.new(hex, team)


static func _make_swarm_hive(hex: Vector2i, team: int) -> TileBase:
	return SwarmHiveTile.new(hex, team)
