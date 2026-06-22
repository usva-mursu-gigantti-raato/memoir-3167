class_name HexCell
extends RefCounted
## Data model for a hexagonal cell.
##
## HexGrid creates and stores the cells — they are rarely instantiated by hand.
## Centralizes the terrain type, fog state per player, and generic
## game data (tag, metadata, location_type/location_data).
##
## Fog per player: mark_explored/mark_visible/clear_visible and the
## is_*_by predicates receive a player_id. Use 0 for single-player.
## get_fog_state() combines both states into an ordinal FogState.

## Built-in terrain types. They are integers — they can be extended with
## custom constants without modifying the addon.
## The cost of each terrain is defined by HexGrid.terrain_cost.
enum Terrain {
	ROAD,      ## Road (default cost 1.0).
	PLAINS,    ## Plains (default cost 1.5).
	FOREST,    ## Forest (default cost 2.0).
	MOUNTAIN,  ## Mountain (default cost 3.0).
	WATER,     ## Water — impassable by default (cost -1.0).
}

## Offset coordinate (x = column, y = row) of the cell in the HexGrid.
var coord: Vector2i = Vector2i.ZERO
## Active terrain type. One of Terrain.* or a custom integer constant.
var terrain: int = Terrain.PLAINS
## Location type. 0 = no location. Define with custom constants (1 = city, 2 = dungeon…).
var location_type: int = 0
## Data attached to the location. The addon does not interpret them — free structure from game to game.
var location_data: Dictionary = {}
var _explored_by: Dictionary = {}   # player_id (int) → bool
var _visible_by: Dictionary = {}    # player_id (int) → bool
## Generic integer tag (team, faction, owner…). 0 = no tag.
var tag: int = 0
## Free game metadata. The addon does not read or write them — free structure.
var metadata: Dictionary = {}
## Cell elevation. 0.0 = sea level. Used by LOS with elevation (HexGrid.get_line_of_sight).
var elevation: float = 0.0


## Creates the cell at [param cell_coord] with [param cell_terrain].
## HexGrid calls this method internally during generate_cells().
func _init(cell_coord: Vector2i = Vector2i.ZERO, cell_terrain: int = Terrain.PLAINS) -> void:
	coord = cell_coord
	terrain = cell_terrain


## Returns the pixel position of the center of this cell.
## Equivalent to HexGrid.offset_to_pixel(coord).
func get_pixel_position() -> Vector2:
	return HexGrid.offset_to_pixel(coord)


## Returns true if location_type indicates a valid location (> 0).
func has_location() -> bool:
	return location_type > 0


## Returns true if tag != 0 (the cell has an assigned tag).
func has_tag() -> bool:
	return tag != 0


## Returns true if [param player_id] explored this cell at least once.
## An explored cell can remain in fog (EXPLORED) if it went out of the vision range.
## Hot path: inline validation (player_id < 0) — a helper wrapper added ~0.15µs/call.
func is_explored_by(player_id: int) -> bool:
	if player_id < 0:
		return false
	return _explored_by.get(player_id, false)


## Returns true if [param player_id] has active vision over this cell.
## Active vision is lost when calling clear_visible() — typically at the start of a turn.
## Hot path: inline validation.
func is_visible_by(player_id: int) -> bool:
	if player_id < 0:
		return false
	return _visible_by.get(player_id, false)


## Marks the cell as explored by [param player_id]. Exploration is permanent.
## Also call mark_visible() if the player currently has vision over it.
func mark_explored(player_id: int) -> void:
	if not _assert_valid_player_id(player_id):
		return
	_explored_by[player_id] = true


## Marks the cell as currently visible by [param player_id].
## Does not imply it is explored — call mark_explored() in parallel if applicable.
func mark_visible(player_id: int) -> void:
	if not _assert_valid_player_id(player_id):
		return
	_visible_by[player_id] = true


## Removes the active vision of [param player_id]. The cell remains EXPLORED if it was seen before.
## Call at the start of each turn before recalculating visibility.
func clear_visible(player_id: int) -> void:
	if not _assert_valid_player_id(player_id):
		return
	_visible_by.erase(player_id)


## Returns the consolidated FogState for [param player_id].
## Priority: VISIBLE > EXPLORED > HIDDEN. Use player_id = 0 for single-player.
## Hot path: reads the dicts directly (skips is_visible_by/is_explored_by) and
## validates inline. Each wrapper added ~0.15µs/call (measured) and get_fog_state is
## called up to N times per frame in update_fog.
func get_fog_state(player_id: int = 0) -> int:
	if player_id < 0:
		return FogState.HIDDEN
	if _visible_by.get(player_id, false):
		return FogState.VISIBLE
	if _explored_by.get(player_id, false):
		return FogState.EXPLORED
	return FogState.HIDDEN


# Validates player_id >= 0 — emits push_error and returns false if invalid.
static func _assert_valid_player_id(player_id: int) -> bool:
	if player_id < 0:
		push_error("HexCell: player_id debe ser >= 0, recibido %d" % player_id)
		return false
	return true


## Serializes the cell to a JSON-compatible Dictionary.
## Reconstruct with HexCell.deserialize(data).
## Note: _visible_by is not included — active visibility is recalculated upon loading.
func serialize() -> Dictionary:
	var explored_serial: Dictionary = {}
	for pid in _explored_by:
		explored_serial[str(pid)] = _explored_by[pid]
	return {
		"coord": [coord.x, coord.y],
		"terrain": terrain,
		"location_type": location_type,
		"location_data": location_data,
		"explored_by": explored_serial,
		"tag": tag,
		"metadata": metadata,
		"elevation": elevation,
	}


## Converts an Array [x, y] to Vector2i. Returns [param default] if the array is invalid.
static func parse_coord_array(arr, default: Vector2i = Vector2i.ZERO) -> Vector2i:
	if arr is Array and arr.size() >= 2:
		return Vector2i(int(arr[0]), int(arr[1]))
	return default


static func _parse_coord(data: Dictionary, key: String, default: Vector2i = Vector2i.ZERO) -> Vector2i:
	return parse_coord_array(data.get(key, [0, 0]), default)


## Reconstructs a HexCell from a Dictionary generated by serialize().
static func deserialize(data: Dictionary) -> HexCell:
	var cell_coord := _parse_coord(data, "coord")
	var cell := HexCell.new(cell_coord, data.get("terrain", Terrain.PLAINS))
	cell.location_type = data.get("location_type", 0)
	cell.location_data = data.get("location_data", {})
	var explored_raw: Dictionary = data.get("explored_by", {})
	for key in explored_raw:
		cell.mark_explored(int(key))
	cell.tag = data.get("tag", 0)
	cell.metadata = data.get("metadata", {})
	cell.elevation = data.get("elevation", 0.0)
	return cell
