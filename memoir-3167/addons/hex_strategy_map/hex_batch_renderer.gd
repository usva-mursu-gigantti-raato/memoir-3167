class_name HexBatchRenderer
extends RefCounted
## Batch rendering of hexagons via BatchHexLayer (terrain, fog, highlight).
##
## Alternative to HexRenderer's node-per-hex mode for large maps (200x200+):
## draws with direct [code]_draw()[/code] instead of instantiating an Area2D per cell.
## Does not support icons, injected textures, overlays, or [code]cell_pressed[/code] signals.
##
## Direct use (without HexRenderer):
## [codeblock]
## var palette := HexPalette.new()
## var batch := HexBatchRenderer.new(palette, HexGrid.HEX_SIZE)
## batch.render(container, grid)
## batch.update_fog(container, grid, 0)
## batch.track_viewport(container)  # call in _process
## [/codeblock]
##
## HexRenderer is node-per-hex only — for batch mode, instantiate this class directly.

const _BATCH_TERRAIN := "BatchTerrain"
const _BATCH_FOG := "BatchFog"
const _BATCH_HIGHLIGHT := "BatchHighlight"

var _palette: HexPalette
var _hex_size: float
var _ignored_callables_hint: PackedStringArray
# Container saved in render() so that the palette_changed handler can
# invalidate the 3 layers without the consumer having to manually hook them up again.
var _container: Node2D = null

var _batch_fog_pid: int = 0
var _batch_highlighted: Dictionary = {}
var _batch_los_visible: Array[Vector2i] = []
var _batch_los_blocked: Array[Vector2i] = []


## [param ignored_callables_hint] allows HexRenderer to emit a warning for
## ignored callables when delegating (cell_icon_fn, tile_visual_fn, overlay_fn).
## When instantiating HexBatchRenderer directly, leave empty.
func _init(palette: HexPalette, hex_size: float, ignored_callables_hint: PackedStringArray = []) -> void:
	_palette = palette
	_hex_size = hex_size
	_ignored_callables_hint = ignored_callables_hint
	if _palette and not _palette.palette_changed.is_connected(_on_palette_changed):
		_palette.palette_changed.connect(_on_palette_changed)


func _on_palette_changed() -> void:
	if not _container or not is_instance_valid(_container):
		return
	for layer_name in [_BATCH_TERRAIN, _BATCH_FOG, _BATCH_HIGHLIGHT]:
		var layer: BatchHexLayer = _container.get_node_or_null(layer_name)
		if layer:
			layer.mark_dirty()


## Initializes batch mode: creates three BatchHexLayers (terrain, fog, highlight)
## in [param container] and discards any previous children.
## After calling this method, use update_fog/update_*_highlight and track_viewport.
func render(container: Node2D, grid: HexGrid) -> void:
	if not _ignored_callables_hint.is_empty():
		push_warning("HexBatchRenderer.render(): los siguientes callables serán ignorados en modo batch: %s. Renderizalos en una capa separada (ver examples/large_world)." % ", ".join(_ignored_callables_hint))

	for child in container.get_children():
		child.queue_free()

	_container = container
	_batch_highlighted.clear()
	_batch_los_visible.clear()
	_batch_los_blocked.clear()

	var terrain := BatchHexLayer.new(grid, _hex_size, _draw_terrain)
	terrain.name = _BATCH_TERRAIN
	container.add_child(terrain)

	var fog := BatchHexLayer.new(grid, _hex_size, _draw_fog)
	fog.name = _BATCH_FOG
	container.add_child(fog)

	var highlight := BatchHexLayer.new(grid, _hex_size, _draw_highlight)
	highlight.name = _BATCH_HIGHLIGHT
	container.add_child(highlight)


## Marks the batch fog layer as dirty for [param player_id].
## Redraw happens on the next frame. Call after FogOfWar.update_visibility().
func update_fog(_container: Node2D, _grid: HexGrid, player_id: int = 0) -> void:
	_batch_fog_pid = player_id
	_mark_dirty(_container, _BATCH_FOG)


## Updates the batch highlight with the [param reachable] set.
## [param highlighted_hexes] is the same mutable cache as in HexRenderer.update_reachable_highlight().
func update_reachable_highlight(container: Node2D, _grid: HexGrid, reachable: Dictionary, highlighted_hexes: Dictionary) -> void:
	_batch_highlighted.clear()
	highlighted_hexes.clear()
	for coord in reachable:
		highlighted_hexes[coord] = true
	_batch_highlighted = highlighted_hexes.duplicate()
	_mark_dirty(container, _BATCH_HIGHLIGHT)


## Updates the batch highlight with LOS: blue for visible, red for blocked.
## Clears the previous reachable highlight if one was active.
func update_los_highlight(container: Node2D,
		visible_coords: Array[Vector2i],
		blocked_coords: Array[Vector2i] = []) -> void:
	_batch_los_visible = visible_coords
	_batch_los_blocked = blocked_coords
	_batch_highlighted.clear()
	_mark_dirty(container, _BATCH_HIGHLIGHT)


## Marks the batch terrain layer as dirty after changing the terrain at [param coord].
## The entire grid is redrawn (batch does not have per-cell granularity).
func update_cell(container: Node2D, _grid: HexGrid, _coord: Vector2i) -> void:
	_mark_dirty(container, _BATCH_TERRAIN)


## Calls check_viewport() on all three batch layers. Invoke from the consumer's _process().
## Automatically marks as dirty when the camera has moved more than one hex since the last redraw.
func track_viewport(container: Node2D) -> void:
	for layer_name in [_BATCH_TERRAIN, _BATCH_FOG, _BATCH_HIGHLIGHT]:
		var layer: BatchHexLayer = container.get_node_or_null(layer_name)
		if layer:
			layer.check_viewport()


func _mark_dirty(container: Node2D, layer_name: String) -> void:
	var layer := _get_batch_layer(container, layer_name)
	if layer:
		layer.mark_dirty()


static func _get_batch_layer(container: Node2D, layer_name: String) -> BatchHexLayer:
	var layer: BatchHexLayer = container.get_node_or_null(layer_name)
	if not layer:
		push_error("HexBatchRenderer: batch layer '%s' not found — call render() first" % layer_name)
		return null
	return layer


func _draw_terrain(layer: BatchHexLayer, grid: HexGrid, hex_size: float, min_coord: Vector2i, max_coord: Vector2i) -> void:
	var pts := HexGrid.hex_polygon_points(hex_size)
	for y in range(min_coord.y, max_coord.y + 1):
		for x in range(min_coord.x, max_coord.x + 1):
			var coord := Vector2i(x, y)
			var cell: HexCell = grid.get_cell(coord)
			if not cell:
				continue
			var pixel := HexGrid.offset_to_pixel(coord, hex_size)
			var translated := HexGrid.translated_hex_polygon(pts, pixel)
			layer.draw_colored_polygon(translated, _palette.resolve_cell_color(cell))
			layer.draw_polyline(translated, _palette.border_color, _palette.border_width)


func _draw_fog(layer: BatchHexLayer, grid: HexGrid, hex_size: float, min_coord: Vector2i, max_coord: Vector2i) -> void:
	var pts := HexGrid.hex_polygon_points(hex_size)
	for y in range(min_coord.y, max_coord.y + 1):
		for x in range(min_coord.x, max_coord.x + 1):
			var coord := Vector2i(x, y)
			var cell: HexCell = grid.get_cell(coord)
			if not cell:
				continue
			var state := cell.get_fog_state(_batch_fog_pid)
			if state == FogState.VISIBLE:
				continue
			var pixel := HexGrid.offset_to_pixel(coord, hex_size)
			var translated := HexGrid.translated_hex_polygon(pts, pixel)
			var fog_color: Color = _palette.fog_colors.get(state, HexPalette.DEFAULT_FOG_COLORS.get(state, Color.BLACK))
			layer.draw_colored_polygon(translated, fog_color)


func _draw_highlight(layer: BatchHexLayer, _grid: HexGrid, hex_size: float, min_coord: Vector2i, max_coord: Vector2i) -> void:
	var pts := HexGrid.hex_polygon_points(hex_size)
	var has_los := _batch_los_visible.size() > 0 or _batch_los_blocked.size() > 0
	var coords_to_draw: Dictionary = {}
	if has_los:
		for coord in _batch_los_visible:
			coords_to_draw[coord] = Color(0.3, 0.7, 1.0, 0.25)
		for coord in _batch_los_blocked:
			coords_to_draw[coord] = Color(1.0, 0.2, 0.2, 0.15)
	else:
		for coord in _batch_highlighted:
			coords_to_draw[coord] = _palette.reachable_color

	for coord_key in coords_to_draw:
		var coord: Vector2i = coord_key
		if coord.x < min_coord.x or coord.x > max_coord.x or coord.y < min_coord.y or coord.y > max_coord.y:
			continue
		var pixel := HexGrid.offset_to_pixel(coord, hex_size)
		var translated := HexGrid.translated_hex_polygon(pts, pixel)
		layer.draw_colored_polygon(translated, coords_to_draw[coord_key])
