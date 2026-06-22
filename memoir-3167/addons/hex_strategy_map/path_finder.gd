class_name PathFinder
extends RefCounted

# find_path_astar combines two fixes that only work together. Removing
# either of them regresses by one or two orders of magnitude in uniform-cost
# maps. The devlog docs/devlog_astar_tiebreak_followup.html explains the
# complete debugging process.
#
# 1) The base heuristic returns distance in HEXES (1 unit per step) and is
#    scaled by grid.min_passable_terrain_cost(). This keeps it tight on maps
#    with a single terrain (lens f = goal f) and keeps it admissible
#    on mixed terrain (we scale by the minimum). Without this, the entire lens
#    ends up with f < f_goal and A* traverses it completely (~55k pops in 250x250).
#
# 2) Cube-cross tiebreak. With the tight heuristic all optimal cells
#    tie in f and A* still expands the lens (~14k cells). Adding the cross
#    product in cube coords — |Δq_cn·Δr_sg − Δq_sg·Δr_cn| — perturbs the
#    priority to prefer cells aligned with the start→goal diagonal and
#    collapses the search to a narrow band (~370 pops for a path of 370).
#    ε must remain well below the minimum cost of a step so as not to
#    break admissibility on small maps.
const ASTAR_TIEBREAK_CROSS := 0.001
## Unified pathfinding for hexagonal maps.
## Dijkstra + A* with binary heap for O((V+E) log V).
##
## All public methods are static — do not instantiate PathFinder.
## Costs are read from HexGrid.terrain_cost and edges (HexGrid.edges).
##
## Main methods:
##   find_reachable()     → reachable hexes with N movement points (Dijkstra).
##   find_path()          → optimal path within a reachable set (Dijkstra).
##   find_path_astar()    → optimal path without cost limit (A*, faster on large maps).
##
## For group movement towards the same destination, use FlowField instead
## of calling find_path_astar() N times — it is equivalent but does a single Dijkstra pass.

class MinHeap:
	## Minimum binary heap. Items: [cost: float, coord: Vector2i].
	## Used internally by _search for the priority queue.
	var _data: Array = []

	## Inserts [param item] maintaining the minimum heap property.
	func push(item: Array) -> void:
		_data.append(item)
		_bubble_up(_data.size() - 1)

	## Extracts and returns the item with the lowest cost. Returns [] if empty.
	func pop() -> Array:
		if _data.is_empty():
			return []
		if _data.size() == 1:
			return _data.pop_back()
		var root: Array = _data[0]
		_data[0] = _data.pop_back()
		_sink_down(0)
		return root

	## Returns true if the heap has no elements.
	func is_empty() -> bool:
		return _data.is_empty()

	func _bubble_up(idx: int) -> void:
		while idx > 0:
			var parent := (idx - 1) / 2
			if _data[idx][0] >= _data[parent][0]:
				break
			var tmp = _data[idx]
			_data[idx] = _data[parent]
			_data[parent] = tmp
			idx = parent

	func _sink_down(idx: int) -> void:
		var size := _data.size()
		while true:
			var smallest := idx
			var left := 2 * idx + 1
			var right := 2 * idx + 2
			if left < size and _data[left][0] < _data[smallest][0]:
				smallest = left
			if right < size and _data[right][0] < _data[smallest][0]:
				smallest = right
			if smallest == idx:
				break
			var tmp = _data[idx]
			_data[idx] = _data[smallest]
			_data[smallest] = tmp
			idx = smallest


## Configuration for _search(). Groups the algorithm's Callables to avoid
## fragile positional signatures. Build with SearchConfig.new() and fill fields.
class SearchConfig:
	## (coord, neighbor) → bool — whether to include the neighbor in the expansion.
	var neighbor_filter: Callable
	## (neighbor, from_coord, new_cost) → void — callback when relaxing a node.
	var on_better_path: Callable
	## (coord) → bool — early exit; useful for A* with fixed destination.
	var should_exit: Callable
	## (coord, g_cost) → float — g_cost for Dijkstra, g+h for A*.
	var priority_fn: Callable
	## Maximum cost; more expensive hexes are left out. INF = no limit.
	var max_cost: float = INF
	## (from, to) → float — optional; defaults to terrain_cost + edge_cost from the grid.
	var cost_fn: Callable = Callable()


## Unified Dijkstra/A* core. Returns cost_so_far: Dictionary[Vector2i, float].
## All public methods delegate here via SearchConfig.
static func _search(
	start: Vector2i,
	grid: HexGrid,
	cfg: SearchConfig,
) -> Dictionary:
	var _resolve_cost := cfg.cost_fn if cfg.cost_fn.is_valid() else func(from: Vector2i, to: Vector2i) -> float:
		return grid.get_movement_cost(to) + grid.get_edge_cost(from, to)

	var cost_so_far: Dictionary = {}
	var queue := MinHeap.new()
	cost_so_far[start] = 0.0
	cfg.on_better_path.call(start, start, 0.0)
	queue.push([cfg.priority_fn.call(start, 0.0), start])

	while not queue.is_empty():
		var current: Array = queue.pop()
		var coord: Vector2i = current[1]

		if cfg.should_exit.call(coord):
			break

		if current[0] > cfg.priority_fn.call(coord, cost_so_far.get(coord, INF)):
			continue

		for neighbor: Vector2i in HexGrid.get_neighbors(coord):
			if not cfg.neighbor_filter.call(coord, neighbor):
				continue
			var new_cost: float = cost_so_far[coord] + _resolve_cost.call(coord, neighbor)
			if new_cost > cfg.max_cost:
				continue
			if not cost_so_far.has(neighbor) or new_cost < cost_so_far[neighbor]:
				cost_so_far[neighbor] = new_cost
				cfg.on_better_path.call(neighbor, coord, new_cost)
				queue.push([cfg.priority_fn.call(neighbor, new_cost), neighbor])

	return cost_so_far


## Returns Dictionary[Vector2i, float] with each reachable hex and its accumulated cost.
## Hexes with cost > [param max_cost] are left out of the result.
## Pass the result to find_path() to trace the path to a specific destination.
static func find_reachable(origin: Vector2i, max_cost: float, grid: HexGrid) -> Dictionary:
	if grid == null or not grid.is_valid(origin) or max_cost < 0.0:
		return {}
	var cfg := SearchConfig.new()
	cfg.neighbor_filter = _default_neighbor_filter(grid)
	cfg.on_better_path = func(_n: Vector2i, _c: Vector2i, _cost: float) -> void: pass
	cfg.should_exit = func(_c: Vector2i) -> bool: return false
	cfg.priority_fn = func(_c: Vector2i, g: float) -> float: return g
	cfg.max_cost = max_cost
	return _search(origin, grid, cfg)


## Finds the shortest path between [param from] and [param to] using Dijkstra.
## If [param reachable] is provided, it only expands within the reachable set.
## If [param reachable] is empty, it expands the entire passable grid (no cost limit).
## Returns Array[Vector2i] excluding [param from]. Returns [] if there is no path.
static func find_path(from: Vector2i, to: Vector2i, grid: HexGrid, reachable: Dictionary = {}) -> Array[Vector2i]:
	var valid := _validate_path_args_strict(from, to, grid) if reachable.is_empty() else \
		_validate_path_args_basic(from, to, grid)
	if not valid:
		return []
	var neighbor_filter := _default_neighbor_filter(grid) if reachable.is_empty() else \
		func(_c: Vector2i, n: Vector2i) -> bool: return reachable.has(n)
	return _find_path_impl(from, to, grid, neighbor_filter,
		func(_c: Vector2i, g: float) -> float: return g)


## Optimal path with A* (hex-distance heuristic scaled by the grid's minimum
## terrain cost + cube-cross tiebreak). See the comment block
## on ASTAR_TIEBREAK_CROSS for design details.
## Faster than find_path() without reachable on large maps; on
## uniform-cost maps it collapses to ~O(path length).
## Requires the cube-cross tiebreak defined in ASTAR_TIEBREAK_CROSS to
## collapse on uniform maps; removing it regresses by an order of magnitude.
## Admissible heuristic as long as terrain_cost is not modified afterwards
## (scaling is cached in grid.min_passable_terrain_cost()).
## Returns [] if there is no path.
static func find_path_astar(from: Vector2i, to: Vector2i, grid: HexGrid) -> Array[Vector2i]:
	if not _validate_path_args_strict(from, to, grid):
		return []
	var h_scale := grid.min_passable_terrain_cost()
	var cube_to := HexGrid.offset_to_cube(to)
	var cube_from := HexGrid.offset_to_cube(from)
	var dq_sg := cube_from.x - cube_to.x
	var dr_sg := cube_from.z - cube_to.z
	return _find_path_impl(from, to, grid, _default_neighbor_filter(grid),
		func(c: Vector2i, g: float) -> float:
			var h := float(HexGrid.distance(c, to)) * h_scale
			var cn := HexGrid.offset_to_cube(c)
			var dq_cg := cn.x - cube_to.x
			var dr_cg := cn.z - cube_to.z
			var cross: float = absf(float(dq_cg) * dr_sg - dq_sg * float(dr_cg))
			return g + h + cross * ASTAR_TIEBREAK_CROSS)


## Shared core of find_path and find_path_astar. They only differ in neighbor_filter and priority_fn.
static func _find_path_impl(from: Vector2i, to: Vector2i, grid: HexGrid, neighbor_filter: Callable, priority_fn: Callable) -> Array[Vector2i]:
	var came_from: Dictionary = {}
	var cfg := SearchConfig.new()
	cfg.neighbor_filter = neighbor_filter
	cfg.on_better_path = func(n: Vector2i, c: Vector2i, _cost: float) -> void: came_from[n] = c
	cfg.should_exit = func(c: Vector2i) -> bool: return c == to
	cfg.priority_fn = priority_fn
	_search(from, grid, cfg)
	return _reconstruct_path(came_from, from, to)


## Default neighbor filter: the neighbor must be valid in the grid and passable.
static func _default_neighbor_filter(grid: HexGrid) -> Callable:
	return func(_c: Vector2i, n: Vector2i) -> bool:
		return grid.is_valid(n) and grid.is_passable(n)


## Validates basic args: grid not null, from valid, from != to.
static func _validate_path_args_basic(from: Vector2i, to: Vector2i, grid: HexGrid) -> bool:
	return grid != null and grid.is_valid(from) and from != to


## Validates args for search without reachable: includes passability check for to.
static func _validate_path_args_strict(from: Vector2i, to: Vector2i, grid: HexGrid) -> bool:
	return _validate_path_args_basic(from, to, grid) \
		and grid.is_valid(to) and grid.is_passable(to)


## Reconstructs the path from the came_from dictionary traversing backwards from to.
## Returns [] if to was not reached (not in came_from).
static func _reconstruct_path(came_from: Dictionary, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not came_from.has(to):
		return []
	var path: Array[Vector2i] = []
	var step := to
	while step != from:
		path.append(step)
		step = came_from[step]
	path.reverse()
	return path
