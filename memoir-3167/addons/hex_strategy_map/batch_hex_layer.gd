class_name BatchHexLayer
extends Node2D
## Batch rendering layer for hexagons. Uses direct _draw() instead of nodes.
## Supports viewport culling: only draws hexes within the camera's visible area.
##
## HexBatchRenderer creates three instances: BatchTerrain, BatchFog, BatchHighlight.
## Do not instantiate directly — use HexBatchRenderer.render().
##
## draw_fn receives (layer, grid, hex_size, min_coord, max_coord) and calls the
## draw_* methods of CanvasItem (draw_colored_polygon, draw_polyline, etc.)
## on the layer itself. Culling limits min/max_coord to the viewport + margin.
##
## To update the content: call mark_dirty() — enqueues a queue_redraw().
## To track the camera: call check_viewport() from the consumer's _process().
var _grid: HexGrid
var _hex_size: float
## Callable injected by HexRenderer. Signature: (layer, grid, hex_size, min_coord, max_coord) → void.
var _draw_fn: Callable
var _viewport_origin: Vector2 = Vector2.INF
var _dirty: bool = true

## Creates the batch layer linked to [param grid] with the given [param hex_size].
## [param draw_fn] is the callable that implements the drawing — provided by HexRenderer.
func _init(grid: HexGrid, hex_size: float, draw_fn: Callable) -> void:
	_grid = grid
	_hex_size = hex_size
	_draw_fn = draw_fn

## Calculates the viewport's AABB with a one-hex margin and calls _draw_fn
## only for coordinates within the visible area. Avoids drawing off-screen hexes.
func _draw() -> void:
	if not _draw_fn.is_valid() or not _grid:
		return
	var viewport := get_viewport()
	if not viewport:
		return

	var canvas := viewport.canvas_transform
	var zoom := canvas.get_scale()
	if zoom.x == 0.0 or zoom.y == 0.0:
		return
	var screen_size := viewport.get_visible_rect().size
	var visible := Rect2(-canvas.origin / zoom, screen_size / zoom)
	visible = visible.grow(_hex_size * 2.0)

	var min_coord := HexGrid.pixel_to_offset(visible.position, _hex_size)
	var max_coord := HexGrid.pixel_to_offset(visible.end, _hex_size)
	min_coord = Vector2i(maxi(min_coord.x - 1, 0), maxi(min_coord.y - 1, 0))
	max_coord = Vector2i(mini(max_coord.x + 1, _grid.width - 1), mini(max_coord.y + 1, _grid.height - 1))

	_draw_fn.call(self, _grid, _hex_size, min_coord, max_coord)
	_dirty = false


## Marks the layer as dirty and enqueues a redraw on the next frame.
func mark_dirty() -> void:
	_dirty = true
	queue_redraw()


## Call in the consumer's _process(). Only marks dirty if the camera moved
## more than 1 hex since the last redraw.
func check_viewport() -> void:
	var viewport := get_viewport()
	if not viewport:
		return
	var origin := viewport.canvas_transform.origin
	if _viewport_origin == Vector2.INF:
		_viewport_origin = origin
		return
	var delta := (origin - _viewport_origin).abs()
	var threshold := _hex_size * 1.5
	if delta.x > threshold or delta.y > threshold:
		_viewport_origin = origin
		mark_dirty()
