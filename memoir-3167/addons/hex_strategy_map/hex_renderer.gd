class_name HexRenderer
extends RefCounted
## Visual rendering of hexagons: node creation, highlighting, and fog.
##
## Node-per-hex: each hex is an Area2D with Bg/Border/Highlight/Fog children.
## Supports icons, textures, animations, overlays, and cell_pressed/cell_released signals.
## For large maps (200x200+) without icons/textures, use [HexBatchRenderer] directly.
##
## Node-per-hex visuals — children of the "Hex_X_Y" Area2D:
##   "Bg"        → terrain background (Polygon2D, Sprite2D, or AnimatedSprite2D).
##   "Border"    → Line2D border.
##   "Highlight" → range/selection overlay (hidden by default).
##   "Fog"       → fog overlay (visible by default — call update_fog() to update).
##   "CellIcon"  → optional Label if cell_icon_fn is injected.
##
## All Callables are optional — omit the ones that are not needed.

## Emitted per hex in node-per-hex mode (not batch). The consumer filters
## by button (event.button_index == MOUSE_BUTTON_LEFT) if it needs to restrict.
## Accepts mouse and touch (InputEventScreenTouch).
## If the user presses inside the hex and releases outside, cell_released might not
## be emitted from that hex (standard Area2D.input_event behavior).
## Do not assume that every cell_pressed has its paired cell_released on the same coord.
signal cell_pressed(coord: Vector2i, event: InputEvent)
signal cell_released(coord: Vector2i, event: InputEvent)

const DEFAULT_ICON_OFFSET := Vector2(-6, -6)
const DEFAULT_ICON_FONT_SIZE := 12

## Drawing strategy used by render_edges().
##   CENTERS — Line2D from the center of one hex to the center of the other (default, backward-compat).
##             Useful for "roads", "navigable rivers", or connections that cross both hexes.
##   SHARED_BORDER — Segment centered on the shared border, perpendicular to the
##                   center-to-center line and of length HEX_SIZE. Useful for "walls", "borders"
##                   or obstacles that separate two hexes without covering either.
enum EdgeRenderMode { CENTERS, SHARED_BORDER }

var _palette: HexPalette
var _cell_icon_fn: Callable
var _hex_size: float
var _tile_visual_fn: Callable
var _texture_fn: Callable
var _animation_fn: Callable
var _overlay_fn: Callable
var _fog_material: ShaderMaterial
var icon_offset: Vector2 = DEFAULT_ICON_OFFSET
var icon_font_size: int = DEFAULT_ICON_FONT_SIZE


## [param palette]: color palette and resolver. If null, uses [code]HexPalette.new()[/code] (defaults).
## [param hex_size]: hex size in pixels (circumscribed radius).
## [param callables]: optional dict with keys: cell_icon_fn, tile_visual_fn, texture_fn,
## animation_fn, overlay_fn, fog_material, icon_offset, icon_font_size.
func _init(
		palette: HexPalette = null,
		hex_size: float = HexGrid.HEX_SIZE,
		callables: Dictionary = {}) -> void:
	_palette = palette if palette != null else HexPalette.new()
	_hex_size = hex_size
	_cell_icon_fn = callables.get("cell_icon_fn", Callable())
	_tile_visual_fn = callables.get("tile_visual_fn", Callable())
	_texture_fn = callables.get("texture_fn", Callable())
	_animation_fn = callables.get("animation_fn", Callable())
	_overlay_fn = callables.get("overlay_fn", Callable())
	_fog_material = callables.get("fog_material", null)
	icon_offset = callables.get("icon_offset", DEFAULT_ICON_OFFSET)
	icon_font_size = callables.get("icon_font_size", DEFAULT_ICON_FONT_SIZE)


static func _hex_node_name(coord: Vector2i) -> String:
	return "Hex_%d_%d" % [coord.x, coord.y]


static func get_visual_for(container: Node2D, coord: Vector2i) -> Node2D:
	return container.get_node_or_null(_hex_node_name(coord))


static func get_visual_part(container: Node2D, coord: Vector2i, part_name: String) -> CanvasItem:
	var hex := get_visual_for(container, coord)
	if not hex:
		return null
	var node := hex.get_node_or_null(part_name)
	if node == null:
		return null
	var result := node as CanvasItem
	if result == null:
		push_warning("HexRenderer.get_visual_part: '%s' existe pero no es CanvasItem (%s)" % [part_name, node.get_class()])
	return result


## Creates the visual Area2D for [param cell] at [param pixel] and adds it to [param hex_container].
## The node is named "Hex_X_Y" and contains Bg, Border, Highlight, Fog, and optionally CellIcon.
## Connects Area2D.input_event → cell_pressed / cell_released.
func create_hex_visual(hex_container: Node2D, coord: Vector2i, pixel: Vector2, cell: HexCell) -> void:
	var hex_area := Area2D.new()
	hex_area.position = pixel
	hex_area.name = _hex_node_name(coord)

	var points := HexGrid.hex_polygon_points(_hex_size)
	hex_area.add_child(_create_collision(points))
	hex_area.add_child(_create_bg_node(cell, _make_terrain_polygon(cell, points)))
	hex_area.add_child(_create_border(points))
	_add_icon(hex_area, cell)
	hex_area.add_child(_create_highlight(points))
	hex_area.add_child(_create_fog_overlay(points))
	_add_overlays(hex_area, cell)
	hex_area.input_event.connect(_on_hex_input.bind(coord))
	hex_container.add_child(hex_area)


func _on_hex_input(_viewport: Node, event: InputEvent, _shape_idx: int, coord: Vector2i) -> void:
	var pressed: bool
	if event is InputEventMouseButton:
		pressed = event.pressed
	elif event is InputEventScreenTouch:
		pressed = event.pressed
	else:
		return
	if pressed:
		cell_pressed.emit(coord, event)
	else:
		cell_released.emit(coord, event)


func _create_collision(points: PackedVector2Array) -> CollisionPolygon2D:
	var collision := CollisionPolygon2D.new()
	collision.polygon = points
	return collision


func _make_terrain_polygon(cell: HexCell, points: PackedVector2Array) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = _palette.resolve_cell_color(cell)
	return poly


func _create_border(points: PackedVector2Array) -> Line2D:
	var border := Line2D.new()
	border.points = points
	border.add_point(points[0])
	border.width = _palette.border_width
	border.default_color = _palette.border_color
	border.name = "Border"
	return border


func _add_icon(hex_area: Area2D, cell: HexCell) -> void:
	if not _cell_icon_fn.is_valid():
		return
	var icon_text: String = _cell_icon_fn.call(cell)
	if icon_text == "":
		return
	var icon := Label.new()
	icon.name = "CellIcon"
	icon.text = icon_text
	icon.position = icon_offset
	icon.add_theme_font_size_override("font_size", icon_font_size)
	hex_area.add_child(icon)


func _create_highlight(points: PackedVector2Array) -> Polygon2D:
	var highlight := Polygon2D.new()
	highlight.polygon = points
	highlight.color = _palette.reachable_color
	highlight.name = "Highlight"
	highlight.visible = false
	return highlight


func _create_fog_overlay(points: PackedVector2Array) -> Polygon2D:
	var fog_overlay := Polygon2D.new()
	fog_overlay.polygon = points
	fog_overlay.name = "Fog"
	var hidden_color: Color = _palette.fog_colors.get(FogState.HIDDEN, HexPalette.DEFAULT_FOG_COLORS[FogState.HIDDEN])
	if _fog_material:
		var mat: ShaderMaterial = _fog_material.duplicate()
		mat.set_shader_parameter("hex_radius", _hex_size)
		mat.set_shader_parameter("fog_color", hidden_color)
		fog_overlay.material = mat
	else:
		fog_overlay.color = hidden_color
	return fog_overlay


func _add_overlays(hex_area: Area2D, cell: HexCell) -> void:
	if not _overlay_fn.is_valid():
		return
	var overlays: Array[Node2D] = []
	overlays.assign(_overlay_fn.call(cell))
	for overlay_node in overlays:
		if overlay_node is Node2D:
			hex_area.add_child(overlay_node)


func _create_bg_node(cell: HexCell, fallback: Polygon2D) -> Node2D:
	var result := _try_custom_visual(cell)
	if result:
		return result
	result = _try_animation_bg(cell)
	if result:
		return result
	result = _try_texture_bg(cell)
	if result:
		return result
	return _as_bg(fallback)


func _try_custom_visual(cell: HexCell) -> Node2D:
	if not _tile_visual_fn.is_valid():
		return null
	var visual: Node2D = _tile_visual_fn.call(cell)
	if visual:
		visual.name = "Bg"
		return visual
	return null


func _try_animation_bg(cell: HexCell) -> Node2D:
	if not _animation_fn.is_valid():
		return null
	var frames: SpriteFrames = _animation_fn.call(cell)
	if not frames:
		return null
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = frames
	anim.name = "Bg"
	if frames.has_animation("idle"):
		anim.play("idle")
	elif frames.get_animation_names().size() > 0:
		anim.play(frames.get_animation_names()[0])
	return anim


func _try_texture_bg(cell: HexCell) -> Node2D:
	if not _texture_fn.is_valid():
		return null
	var tex: Texture2D = _texture_fn.call(cell)
	if not tex:
		return null
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.name = "Bg"
	return sprite


func _as_bg(fallback: Polygon2D) -> Node2D:
	fallback.name = "Bg"
	return fallback


## Shows the Highlight overlay on the hexes in the [param reachable] set and hides the rest.
## [param highlighted_hexes] is used as a mutable cache — pass the same Dictionary between calls.
func update_reachable_highlight(hex_container: Node2D, grid: HexGrid, reachable: Dictionary, highlighted_hexes: Dictionary) -> void:
	_clear_highlights(hex_container, highlighted_hexes)

	for coord in reachable:
		highlighted_hexes[coord] = true
		var node := get_visual_for(hex_container, coord)
		if node:
			var highlight: Polygon2D = node.get_node_or_null("Highlight")
			if highlight:
				highlight.visible = true


func _clear_highlights(hex_container: Node2D, highlighted_hexes: Dictionary) -> void:
	for coord in highlighted_hexes:
		var node := get_visual_for(hex_container, coord)
		if node:
			var highlight: Polygon2D = node.get_node_or_null("Highlight")
			if highlight:
				highlight.visible = false


## Colors the Highlight overlay based on LOS: blue for visible, red for blocked.
## [param visible_color] and [param blocked_color] are optional — use defaults for standard UI.
func update_los_highlight(hex_container: Node2D,
		visible_coords: Array[Vector2i],
		blocked_coords: Array[Vector2i] = [],
		visible_color: Color = Color(0.3, 0.7, 1.0, 0.25),
		blocked_color: Color = Color(1.0, 0.2, 0.2, 0.15)) -> void:
	_apply_los_color(hex_container, visible_coords, visible_color)
	_apply_los_color(hex_container, blocked_coords, blocked_color)


func _apply_los_color(hex_container: Node2D, coords: Array[Vector2i], color: Color) -> void:
	for coord in coords:
		var node := get_visual_for(hex_container, coord)
		if not node:
			continue
		var h: Polygon2D = node.get_node_or_null("Highlight")
		if h:
			h.color = color
			h.visible = true


## Updates the Fog overlay of all hexes based on the fog state of [param player_id].
## Traverses the entire grid — call only when the state changes (not every frame).
## For incremental updates, connect FogOfWar.fog_changed and call
## [method update_cell_fog] only for the modified cells (O(1) per cell).
func update_fog(hex_container: Node2D, grid: HexGrid, player_id: int = 0) -> void:
	var all_cells := grid.get_all_cells()
	for coord in all_cells:
		update_cell_fog(hex_container, coord, all_cells[coord], player_id)


## Updates Fog/Bg/Border/CellIcon overlay of a single cell based on its FogState.
## Intended to be invoked from a FogOfWar.fog_changed handler (O(1)),
## avoiding the O(N) sweep of [method update_fog].
func update_cell_fog(hex_container: Node2D, coord: Vector2i, cell: HexCell, player_id: int = 0) -> void:
	var node := get_visual_for(hex_container, coord)
	if not node:
		return

	var state := cell.get_fog_state(player_id)
	var fog_overlay: Polygon2D = node.get_node_or_null("Fog")
	var bg: CanvasItem = node.get_node_or_null("Bg")
	var border: Line2D = node.get_node_or_null("Border")
	var icon: Label = node.get_node_or_null("CellIcon")

	match state:
		FogState.VISIBLE:
			_set_node_visibility(fog_overlay, false, Color())
			_set_node_visibility(bg, true, Color())
			_set_node_visibility(border, true, Color())
			_set_node_visibility(icon, true, Color())

		FogState.EXPLORED:
			_set_node_visibility(fog_overlay, true, _palette.fog_colors.get(FogState.EXPLORED, HexPalette.DEFAULT_FOG_COLORS[FogState.EXPLORED]))
			_set_node_visibility(bg, true, Color())
			_set_node_visibility(border, true, Color())
			_set_node_visibility(icon, false, Color())

		FogState.HIDDEN:
			_set_node_visibility(fog_overlay, true, _palette.fog_colors.get(FogState.HIDDEN, HexPalette.DEFAULT_FOG_COLORS[FogState.HIDDEN]))
			_set_node_visibility(bg, false, Color())
			_set_node_visibility(border, false, Color())
			_set_node_visibility(icon, false, Color())


func _set_node_visibility(node: CanvasItem, visible: bool, color: Color) -> void:
	if not node:
		return
	node.visible = visible
	if color == Color():
		return
	var poly := node as Polygon2D
	if not poly:
		return
	var mat := poly.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("fog_color", color)
	else:
		poly.color = color


## Replaces the Bg node of the cell at [param coord] with a new one based on [param cell].
## More expensive than refresh_cell_color() — use when the visual type changes
## (e.g., terrain changing from Polygon2D to Sprite2D). To only change color, use refresh_cell_color().
func update_cell_visual(hex_container: Node2D, coord: Vector2i, cell: HexCell) -> void:
	var node := get_visual_for(hex_container, coord)
	if not node:
		return
	var old_bg := node.get_node_or_null("Bg")
	if old_bg:
		node.remove_child(old_bg)
		old_bg.queue_free()

	var points := HexGrid.hex_polygon_points(_hex_size)
	var new_bg := _create_bg_node(cell, _make_terrain_polygon(cell, points))
	node.add_child(new_bg)
	node.move_child(new_bg, 0)


## Fast-path for color repainting without recreating the Bg node.
## Uses color_fn if injected, otherwise terrain_colors. Polygon2D receives
## .color directly; Sprite2D/AnimatedSprite2D receive .modulate.
func refresh_cell_color(hex_container: Node2D, coord: Vector2i, cell: HexCell) -> void:
	var bg := get_visual_part(hex_container, coord, "Bg")
	if not bg:
		return
	var color := _palette.resolve_cell_color(cell)
	if bg is Polygon2D:
		bg.color = color
	else:
		bg.modulate = color


## Draws all edges of the grid as Line2D in [param edge_container].
## Clears previous children before drawing — call after set_edge() if they changed.
## [param mode] controls the segment geometry: CENTERS (default) or SHARED_BORDER.
func render_edges(edge_container: Node2D, grid: HexGrid, edge_color: Color = Color(0.2, 0.5, 0.8, 0.8), edge_width: float = 2.0, mode: EdgeRenderMode = EdgeRenderMode.CENTERS) -> void:
	for child in edge_container.get_children():
		child.queue_free()

	var drawn: Dictionary = {}
	for key in grid.edges:
		var parts = key.split("|")
		if parts.size() != 2:
			continue
		var pa = parts[0].split(",")
		var pb = parts[1].split(",")
		if pa.size() != 2 or pb.size() != 2:
			continue
		var a := Vector2i(int(pa[0]), int(pa[1]))
		var b := Vector2i(int(pb[0]), int(pb[1]))

		var pair_key := str(a) + "|" + str(b)
		if drawn.has(pair_key):
			continue
		drawn[pair_key] = true

		var endpoints := _compute_edge_endpoints(a, b, mode)
		var line := Line2D.new()
		line.add_point(endpoints[0])
		line.add_point(endpoints[1])
		line.width = edge_width
		line.default_color = edge_color
		line.name = "Edge_%s_%s" % [str(a), str(b)]
		edge_container.add_child(line)


# Line2D endpoints according to mode. SHARED_BORDER uses the midpoint of the pair of centers
# and the vector perpendicular to the center-to-center segment; the length (_hex_size) corresponds
# to the side of the regular pointy-top hex (which matches the center→vertex radius).
func _compute_edge_endpoints(a: Vector2i, b: Vector2i, mode: EdgeRenderMode) -> Array:
	var pixel_a := HexGrid.offset_to_pixel(a, _hex_size)
	var pixel_b := HexGrid.offset_to_pixel(b, _hex_size)
	if mode == EdgeRenderMode.SHARED_BORDER:
		var midpoint := (pixel_a + pixel_b) * 0.5
		var direction := (pixel_b - pixel_a).normalized()
		var perpendicular := Vector2(-direction.y, direction.x)
		var half := perpendicular * (_hex_size * 0.5)
		return [midpoint - half, midpoint + half]
	return [pixel_a, pixel_b]



## Creates a ShaderMaterial with the fog shader included in the addon.
## Useful as a starting point — the consumer can modify the uniforms before passing it to the renderer.
## Returns null if the shader is not found (e.g., addon installed in a non-standard path).
static func create_default_fog_material() -> ShaderMaterial:
	var shader := load("res://addons/hex_strategy_map/fog_overlay.gdshader")
	if not shader:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat
