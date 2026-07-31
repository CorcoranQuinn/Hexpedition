class_name HexGrid
extends RefCounted
## Manages hex tile instances keyed by axial coordinates.

var tiles: Dictionary = {}  # Vector2i -> TileBase


# --- Tile storage and lookup ---

func set_tile(hex: Vector2i, tile: TileBase) -> void:
	tile.hex_position = hex
	tiles[hex] = tile


func get_tile(hex: Vector2i) -> TileBase:
	return tiles.get(hex, null)


func has_tile(hex: Vector2i) -> bool:
	return tiles.has(hex)


# --- Reveal fog and notify tile when a unit steps on it ---

func reveal_tile(hex: Vector2i) -> TileBase:
	var tile: TileBase = get_tile(hex)
	if tile == null:
		return null
	if not tile.revealed:
		tile.revealed = true
		tile.on_reveal()
	return tile


func on_unit_entered(hex: Vector2i, unit: UnitBase) -> void:
	var tile: TileBase = get_tile(hex)
	if tile == null:
		return
	if not tile.revealed:
		reveal_tile(hex)
	tile.on_unit_enter(unit)


# --- Board iteration and procedural fill helper ---

func get_all_hexes() -> Array:
	return tiles.keys()


func generate_hidden_board(radius: int, tile_factory: Callable) -> void:
	tiles.clear()
	for hex in HexCoords.within_radius(Vector2i.ZERO, radius):
		var tile: TileBase = tile_factory.call(hex)
		set_tile(hex, tile)
