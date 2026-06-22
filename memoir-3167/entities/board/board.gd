extends Node2D

@onready var hex_container: Node2D = $HexContainer
@onready var edge_container: Node2D = $EdgeContainer

var grid: HexGrid
var renderer: HexRenderer


func _ready() -> void:
	# 15 columns, 10 rows, default terrain costs, hex radius 32 px
	grid = HexGrid.new(15, 10)
	grid.generate_cells()   # fills grid.cells with HexCell objects
	var my_colors := {
		HexGrid.Terrain.ROAD:     Color(0.5, 0.4, 0.3),
		HexGrid.Terrain.PLAINS:   Color(0.3, 0.6, 0.2),
		HexGrid.Terrain.FOREST:   Color(0.1, 0.3, 0.1),
		HexGrid.Terrain.MOUNTAIN: Color(0.5, 0.5, 0.5),
		HexGrid.Terrain.WATER:    Color(0.1, 0.3, 0.7),
	}
	renderer = HexRenderer.new(my_colors)

	for coord in grid.cells:
		var cell: HexCell = grid.cells[coord]
		var pixel: Vector2 = HexGrid.offset_to_pixel(coord)
		renderer.create_hex_visual(hex_container, coord, pixel, cell)

	renderer.render_edges(edge_container, grid)
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
