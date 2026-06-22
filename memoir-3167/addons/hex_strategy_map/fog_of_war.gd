class_name FogOfWar
extends RefCounted
## Multiplayer fog of war system with three states.
##
## Manages which hexes are HIDDEN, EXPLORED or VISIBLE for each player.
## States are stored in the grid's HexCells (mark_explored/mark_visible),
## and in _visible_by_player to be able to clear active vision at the start of a turn.
##
## Typical turn flow:
##   fog.update_visibility(player_id, unit_pos, radius)
##   renderer.update_fog(hex_container, grid, player_id)
##
## For multiple units in the same turn, use update_visibility_multi()
## which does a single clearing pass before revealing all positions.
##
## LOS (line-of-sight): reveal_with_los() uses HexGrid.get_visible_cells()
## to block vision behind specific terrains.

## Emitted when the fog state of a cell changes for a player.
## Useful for updating the renderer incrementally without traversing the entire grid.
signal fog_changed(player_id: int, coord: Vector2i, old_state: int, new_state: int)
signal fog_changed(player_id: int, coord: Vector2i, old_state: int, new_state: int)

## Associated hexagonal grid. Does not change after _init.
## All public methods have a guard "if grid == null: return" — class invariant.
var grid: HexGrid = null
var _visible_by_player: Dictionary = {}  # player_id (int) → Dictionary (Vector2i → true)
var _visibility_radius_fn: Callable


## Creates the fog system linked to [param hex_grid].
## [param visibility_fn]: (unit_level: int) → int — vision radius based on level.
## If omitted, uses _default_visibility_radius (logarithmic scale, max 3).
func _init(hex_grid: HexGrid, visibility_fn: Callable = Callable()) -> void:
	grid = hex_grid
	_visibility_radius_fn = visibility_fn


## Returns the fog state of [param cell] for [param player_id] without instantiating FogOfWar.
## Useful when only needing to read the state without managing revealing.
static func get_state(cell: HexCell, player_id: int = 0) -> int:
	if cell == null:
		return FogState.HIDDEN
	if cell.is_visible_by(player_id):
		return FogState.VISIBLE
	if cell.is_explored_by(player_id):
		return FogState.EXPLORED
	return FogState.HIDDEN


## Returns the vision radius for [param unit_level] using the injected function,
## or _default_visibility_radius if none was provided.
func get_visibility_radius(unit_level: int) -> int:
	if _visibility_radius_fn.is_valid():
		return _visibility_radius_fn.call(unit_level)
	return _default_visibility_radius(unit_level)


## Reveals a circular area of [param radius] hexes around [param center]
## for [param player_id]. Does not consider LOS — all hexes in the ring become VISIBLE.
## For LOS, use reveal_with_los().
func reveal_around(player_id: int, center: Vector2i, radius: int) -> void:
	if grid == null:
		return
	_reveal_coord(player_id, center)
	for r in range(1, radius + 1):
		var ring := grid.get_ring(center, r)
		for coord in ring:
			_reveal_coord(player_id, coord)


## Reveals visible hexes from [param center] with radius [param radius] and LOS.
## [param blocking_terrains]: terrains that block vision (e.g., MOUNTAIN, FOREST).
## [param elevation_fn]: (coord: Vector2i) → float — elevation per cell for LOS with height.
## Hexes blocked by terrain do not become VISIBLE (they might remain EXPLORED from before).
func reveal_with_los(player_id: int, center: Vector2i, radius: int,
		blocking_terrains: Array[int] = [], elevation_fn: Callable = Callable()) -> void:
	if grid == null:
		return
	var visible := grid.get_visible_cells(center, radius, blocking_terrains, elevation_fn)
	for coord in visible:
		_reveal_coord(player_id, coord)


## Clears the active vision of [param player_id] and reveals around a single unit.
## For multiple units in the same turn, prefer update_visibility_multi().
func update_visibility(player_id: int, unit_pos: Vector2i, radius: int) -> void:
	update_visibility_multi(player_id, [unit_pos], func(_pos: Vector2i) -> int: return radius)


## Clears the active vision of [param player_id] and reveals around multiple positions.
## [param radius_fn]: (pos: Vector2i) → int — radius per position (allows variable radii).
## Does a single clearing pass, more efficient than calling update_visibility() N times.
func update_visibility_multi(player_id: int, positions: Array[Vector2i], radius_fn: Callable) -> void:
	if grid == null:
		return
	_clear_visible(player_id)
	for pos in positions:
		var radius: int = radius_fn.call(pos)
		reveal_around(player_id, pos, radius)


## Returns how many grid cells [param player_id] has explored (including currently visible ones).
func get_explored_count(player_id: int = 0) -> int:
	if grid == null:
		return 0
	var count := 0
	var all_cells := grid.get_all_cells()
	for coord in all_cells:
		var cell: HexCell = all_cells[coord]
		if cell.is_explored_by(player_id):
			count += 1
	return count


## Serializes the fog state to a JSON-compatible Dictionary.
## Only _visible_by_player is saved — explored_by lives in the HexCells
## and is serialized with HexGrid.serialize().
func serialize() -> Dictionary:
	var visible_data: Array = []
	for player_id in _visible_by_player:
		var coords: Dictionary = _visible_by_player[player_id]
		var coord_list: Array = []
		for coord in coords.keys():
			coord_list.append([coord.x, coord.y])
		visible_data.append({"player_id": player_id, "coords": coord_list})
	return {"visible_by_player": visible_data}


static func _parse_coord_pair(pair) -> Vector2i:
	return HexCell.parse_coord_array(pair)


## Reconstructs a FogOfWar from a Dictionary generated by serialize().
## [param hex_grid] must be the same grid (already deserialized with HexGrid.deserialize()).
static func deserialize(data: Dictionary, hex_grid: HexGrid) -> FogOfWar:
	var fog := FogOfWar.new(hex_grid)
	var visible_data: Array = data.get("visible_by_player", [])
	for entry in visible_data:
		var player_id: int = int(entry.get("player_id", 0))
		var coord_pairs: Array = entry.get("coords", [])
		fog._visible_by_player[player_id] = {}
		for pair in coord_pairs:
			var coord := _parse_coord_pair(pair)
			fog._visible_by_player[player_id][coord] = true
			var cell := hex_grid.get_cell(coord)
			if cell:
				cell.mark_explored(player_id)
				cell.mark_visible(player_id)
	return fog


## Default radius by level: scales slowly (max 3). Level 1 → 1, level 3 → 2, level 5 → 3.
static func _default_visibility_radius(unit_level: int) -> int:
	return mini(1 + floori(float(unit_level - 1) / 2.0), 3)


## Captures the state before and after mutating, and emits fog_changed only if it changed.
func _emit_state_change(cell: HexCell, player_id: int, coord: Vector2i, mutate: Callable) -> void:
	var old_state := get_state(cell, player_id)
	mutate.call()
	var new_state := get_state(cell, player_id)
	if old_state != new_state:
		fog_changed.emit(player_id, coord, old_state, new_state)


func _reveal_coord(player_id: int, coord: Vector2i) -> void:
	var cell := grid.get_cell(coord)
	if not cell:
		return
	_emit_state_change(cell, player_id, coord, func() -> void:
		cell.mark_explored(player_id)
		cell.mark_visible(player_id)
	)
	if not _visible_by_player.has(player_id):
		_visible_by_player[player_id] = {}
	_visible_by_player[player_id][coord] = true


func _clear_visible(player_id: int) -> void:
	if not _visible_by_player.has(player_id):
		return
	for coord in _visible_by_player[player_id]:
		var cell := grid.get_cell(coord)
		if cell:
			_emit_state_change(cell, player_id, coord, func() -> void:
				cell.clear_visible(player_id)
			)
	_visible_by_player[player_id] = {}
