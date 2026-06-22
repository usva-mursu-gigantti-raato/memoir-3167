class_name HexPalette
extends Resource
## Color palette and cell color resolver shared by HexRenderer and HexBatchRenderer.
##
## Centralizes the visual configuration that previously lived scattered in HexRenderer.
## Allows both renderers to receive the same source of truth without duplicating parameters.
##
## Exported properties (border_color/width, reachable_color): configurable in .tres.
## Non-exported properties (terrain_colors, fog_colors, color_fn): assignable in code —
## Dictionary and Callable are not reliably serializable as exports.

const DEFAULT_TERRAIN_COLORS: Dictionary = {
	HexCell.Terrain.ROAD: Color(0.36, 0.25, 0.20),
	HexCell.Terrain.PLAINS: Color(0.18, 0.35, 0.22),
	HexCell.Terrain.FOREST: Color(0.10, 0.22, 0.12),
	HexCell.Terrain.MOUNTAIN: Color(0.40, 0.38, 0.35),
	HexCell.Terrain.WATER: Color(0.12, 0.22, 0.42),
}

const DEFAULT_FOG_COLORS: Dictionary = {
	FogState.HIDDEN: Color(0.02, 0.02, 0.04, 1.0),
	FogState.EXPLORED: Color(0.05, 0.05, 0.08, 0.5),
}

const REACHABLE_COLOR := Color(0.9, 0.85, 0.3, 0.3)
const BORDER_COLOR := Color(0.2, 0.2, 0.2, 0.5)
const BORDER_WIDTH := 1.0

## Sentinel that a color_fn can return to indicate "no opinion, use terrain_colors".
## Negative RGBA is not a valid color — it does not collide with any real color.
const SKIP_COLOR := Color(-1, -1, -1, -1)

## Emitted when terrain_colors or fog_colors change via setter. Allows batch renderers
## to invalidate their visual cache without the consumer having to call mark_dirty manually.
signal palette_changed()

@export var border_color: Color = BORDER_COLOR
@export var border_width: float = BORDER_WIDTH
@export var reachable_color: Color = REACHABLE_COLOR

var terrain_colors: Dictionary = DEFAULT_TERRAIN_COLORS.duplicate():
	set(value):
		terrain_colors = value
		palette_changed.emit()
var fog_colors: Dictionary = DEFAULT_FOG_COLORS.duplicate():
	set(value):
		fog_colors = value
		palette_changed.emit()
## Optional Callable `(HexCell) → Color`. Return [constant SKIP_COLOR] to
## delegate to the lookup in [member terrain_colors].
var color_fn: Callable = Callable()


## Resolves the color of [param cell]. If [member color_fn] is assigned and does not return
## [constant SKIP_COLOR], it uses that value. Otherwise, it searches in [member terrain_colors] by
## terrain id; fallback to [code]Color.GRAY[/code] if it is not mapped.
func resolve_cell_color(cell: HexCell) -> Color:
	if color_fn.is_valid():
		var c: Color = color_fn.call(cell)
		if c != SKIP_COLOR:
			return c
	return terrain_colors.get(cell.terrain, Color.GRAY)


## Creates a palette with all defaults. Equivalent to [code]HexPalette.new()[/code]
## but more explicit in intent when used as a factory.
static func create_default() -> HexPalette:
	return HexPalette.new()
