class_name RollMath
extends RefCounted
## THE soul of CUBEFALL — pure roll math, battery-first, no scene required.
##
## A cube occupying cell (x, z) that rolls one cell in direction `dir` rotates
## exactly 90 degrees around its LEADING BOTTOM EDGE (the bottom edge of the
## face it is tipping onto) while its center travels the quarter-arc:
##
##   pivot   = cell center (floor level) + dir * half_size   (y = 0, the edge)
##   axis    = UP x dir_w                                     (horizontal, left of travel)
##   angle   = t * 90 degrees
##   center  = pivot + Basis(axis, angle) * (center_start - pivot)
##
## The center starts HALF above the floor and HALF behind the pivot, so its
## distance to the pivot is half*sqrt(2) for EVERY t — a true quarter-arc —
## and at t=0.5 it sits half*sqrt(2) ABOVE THE FLOOR (cube balanced on its
## edge). At t=1 it is HALF above the floor in the next cell. The same three
## lines serve all four cardinal directions; only the axis/pivot change.
##
## One cube = one BoxMesh (Feel.CUBE_SIZE^3). No mesh imports, ever.

const HALF := Feel.CUBE_SIZE * 0.5

const DIR_UP := Vector2i(0, -1)        # toward the far rows (fog horizon)
const DIR_DOWN := Vector2i(0, 1)       # toward the camera (the way cubes roll)
const DIR_LEFT := Vector2i(-1, 0)
const DIR_RIGHT := Vector2i(1, 0)
const ALL_DIRS := [DIR_UP, DIR_DOWN, DIR_LEFT, DIR_RIGHT]


## Grid cell -> world XZ center of a resting plate/cube footprint (y = 0).
static func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(
		(float(cell.x) - float(Feel.GRID_W - 1) * 0.5) * Feel.CELL,
		0.0,
		(float(cell.y) - float(Feel.GRID_L - 1) * 0.5) * Feel.CELL)


## World XZ -> nearest grid cell. Off-grid positions snap to the border cell.
static func world_to_cell(p: Vector3) -> Vector2i:
	var cx := roundi(p.x / Feel.CELL + float(Feel.GRID_W - 1) * 0.5)
	var cz := roundi(p.z / Feel.CELL + float(Feel.GRID_L - 1) * 0.5)
	return Vector2i(clampi(cx, 0, Feel.GRID_W - 1), clampi(cz, 0, Feel.GRID_L - 1))


## Cell-space cardinal dir -> world-space horizontal dir.
static func dir_world(dir: Vector2i) -> Vector3:
	return Vector3(float(dir.x), 0.0, float(dir.y))


## The rotation axis for a roll in `dir`: horizontal, perpendicular to travel,
## pointing so a positive angle tips the top of the cube toward `dir`.
static func axis_for(dir: Vector2i) -> Vector3:
	return Vector3.UP.cross(dir_world(dir))


## The leading bottom edge the cube pivots over: floor level, at the far side
## of the cell in the direction of travel.
static func pivot_for(from_cell: Vector2i, dir: Vector2i) -> Vector3:
	return cell_to_world(from_cell) + dir_world(dir) * HALF


## Roll angle in radians at roll progress t (0 -> 1 maps 0 -> 90 degrees).
static func angle_at(t: float) -> float:
	return clampf(t, 0.0, 1.0) * PI * 0.5


## The cube center's world position at roll progress t: the quarter-arc.
## The 90-degree rotation about the leading edge is exact; because
## CUBE_SIZE (0.98) is a hair under CELL (1.0), the pure edge-arc would
## advance the center only CUBE_SIZE per roll and drift 0.02/cell off the
## grid — so a compensating slide of (CELL - CUBE_SIZE) * t along dir is
## added. It is horizontal only: the arc's midpoint height (half*sqrt(2))
## and the 0 -> 90 deg rotation are untouched, and the cube lands exactly
## on the next cell centre (the grid-alignment law wins).
static func center_at(from_cell: Vector2i, dir: Vector2i, t: float) -> Vector3:
	return _center(from_cell, dir, angle_at(t))


## Interpolated cube transform (basis + center) at roll progress t.
## t = 0 -> resting in from_cell; t = 1 -> resting in cell_after(from_cell, dir).
static func roll_transform(from_cell: Vector2i, dir: Vector2i, t: float) -> Transform3D:
	var b := Basis(axis_for(dir), angle_at(t))
	var c := _center(from_cell, dir, angle_at(t))
	return Transform3D(b, c)


## The cell the cube occupies after a completed roll. Same law for all 4 dirs.
static func cell_after(from_cell: Vector2i, dir: Vector2i) -> Vector2i:
	return from_cell + dir


## True once the next roll in `dir` would leave the field's near edge.
static func leaves_field(from_cell: Vector2i, dir: Vector2i) -> bool:
	return not _in_bounds(cell_after(from_cell, dir))


# ------------------------------------------------------------------ internals --

static func _center(from_cell: Vector2i, dir: Vector2i, ang: float) -> Vector3:
	var pivot := pivot_for(from_cell, dir)
	var start := cell_to_world(from_cell) + Vector3.UP * HALF
	var b := Basis(axis_for(dir), ang)
	var c := pivot + b * (start - pivot)
	return c + dir_world(dir) * (Feel.CELL - Feel.CUBE_SIZE) * (ang / (PI * 0.5))


static func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < Feel.GRID_W and cell.y >= 0 and cell.y < Feel.GRID_L
