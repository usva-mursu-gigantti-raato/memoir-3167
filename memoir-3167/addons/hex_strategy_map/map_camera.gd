class_name MapCamera
extends RefCounted
## Camera controller for hexagonal maps.
##
## Wraps a Godot Camera2D and adds follow, right-button drag,
## scroll zoom, and edge-scroll (the camera moves when the mouse
## reaches the edge of the screen).
##
## Typical usage:
##   cam_ctrl = MapCamera.new(camera, get_viewport())
##   # in _process:    cam_ctrl.process(delta, target_pos)
##   # in _unhandled_input: cam_ctrl.handle_input(event)
##
## Follow vs free: follow_target = true lerps towards target_position.
## Deactivates automatically when dragging. Reactivate with Space or
## by assigning follow_target = true from code.

## Reference to the controlled Camera2D.
var camera: Camera2D = null
## Associated viewport (necessary for edge-scroll and screen_to_world).
var viewport: Viewport = null
## true → the camera follows the target_position passed to process().
## false → the camera is controlled with drag / edge-scroll.
var follow_target: bool = true

## Follow interpolation speed (lerp). Typical values: 4–12.
var lerp_speed: float = 8.0
## Width in pixels of the screen edge that activates edge-scroll.
var edge_margin: float = 30.0
## Edge-scroll speed in pixels per second.
var edge_speed: float = 500.0
## Minimum allowed zoom (zoomed out). Values < 1.0 zoom out the camera.
var zoom_min: float = 0.6
## Maximum allowed zoom (zoomed in). Values > 1.0 zoom in the camera.
var zoom_max: float = 3.0
## Zoom increment for each scroll wheel tick.
var zoom_step: float = 0.15

var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _camera_drag_start: Vector2 = Vector2.ZERO


## Initializes the controller with the root node's camera and viewport.
## [param p_params] overwrites any parameter by its name:
##   lerp_speed, edge_margin, edge_speed, zoom_min, zoom_max, zoom_step.
func _init(p_camera: Camera2D, p_viewport: Viewport, p_params: Dictionary = {}) -> void:
	camera = p_camera
	viewport = p_viewport
	lerp_speed = p_params.get("lerp_speed", lerp_speed)
	edge_margin = p_params.get("edge_margin", edge_margin)
	edge_speed = p_params.get("edge_speed", edge_speed)
	zoom_min = p_params.get("zoom_min", zoom_min)
	zoom_max = p_params.get("zoom_max", zoom_max)
	zoom_step = p_params.get("zoom_step", zoom_step)


## Updates the camera. Call from _process() with the frame delta.
## [param target_position] is the world position to lerp towards when follow_target = true.
## If follow_target = false and there is no active drag, activates edge-scroll.
func process(delta: float, target_position: Vector2) -> void:
	if follow_target:
		camera.position = camera.position.lerp(target_position, lerp_speed * delta)
	elif not _is_dragging:
		_edge_scroll(delta)


## Processes input events. Call from _unhandled_input().
## Default controls:
##   Right-button drag → free pan (deactivates follow).
##   Scroll wheel       → zoom within [zoom_min, zoom_max].
##   Space              → reactivates follow_target.
func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_is_dragging = true
		_drag_start = event.global_position
		_camera_drag_start = camera.position
		follow_target = false

	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_is_dragging = false

	if event is InputEventMouseMotion and _is_dragging:
		if camera.zoom.x == 0.0:
			return
		var drag_delta: Vector2 = (event.global_position - _drag_start) / camera.zoom.x
		camera.position = _camera_drag_start - drag_delta

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = Vector2.ONE * clampf(camera.zoom.x + zoom_step, zoom_min, zoom_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = Vector2.ONE * clampf(camera.zoom.x - zoom_step, zoom_min, zoom_max)

	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		follow_target = true


## Converts a screen position (pixels) to world coordinates.
## Useful for transforming InputEventMouseButton.position to map space.
## Returns Vector2.ZERO if zoom is zero (invalid situation).
func screen_to_world(screen_pixel: Vector2) -> Vector2:
	if camera.zoom.x == 0.0:
		return Vector2.ZERO
	return screen_pixel / camera.zoom + camera.global_position - viewport.get_visible_rect().size / camera.zoom / 2.0


## Pans the camera based on the mouse position near the edges.
## Only acts if the mouse is within the margin defined by edge_margin.
func _edge_scroll(delta: float) -> void:
	var mouse_pos := viewport.get_mouse_position()
	var screen_size := viewport.get_visible_rect().size
	var pan := Vector2.ZERO

	if mouse_pos.x < edge_margin:
		pan.x -= 1.0
	elif mouse_pos.x > screen_size.x - edge_margin:
		pan.x += 1.0

	if mouse_pos.y < edge_margin:
		pan.y -= 1.0
	elif mouse_pos.y > screen_size.y - edge_margin:
		pan.y += 1.0

	if pan != Vector2.ZERO:
		follow_target = false
		camera.position += pan.normalized() * edge_speed * delta
