class_name Grid
extends Node3D
## The field: GRID_W x GRID_L floor plates in ONE MultiMeshInstance3D
## (the phone law — the grid is a single draw call, never 221 nodes).
##
## Rows can be flagged FALLING (after a CAPTURE): the whole row drops into
## the void with tumble. Plate transforms for falling rows are rewritten
## per-frame in advance(); vanished rows collapse to a zero-scale transform.
##
## Also owns the MARK plates (the classic rising mark square) — a small pool,
## one mesh shared, rise animation driven by Feel.MARK_RISE_TIME.

const PLATE_THICKNESS := 0.08
const PLATE_SPAN := 0.92             # fraction of CELL — the gap shows the grid
const MARK_SPAN := 0.80
const MARK_BURIED_Y := -0.06         # where the mark plate starts (under the floor)

var mm: MultiMesh
var mmi: MultiMeshInstance3D

var _rest: Array[Transform3D] = []   # index = z * GRID_W + x
var _falling := {}                   # row z -> { t: float, axis: Vector3, spin: float }
var _gone := {}                      # row z -> true
var _gone_order: Array[int] = []     # rows in the order they vanished (regrow stack)
var _marks := {}                     # Vector2i -> { node: MeshInstance3D, t: float, area: bool }
var _mark_mesh: BoxMesh
var _area_mark_mesh: BoxMesh


func _ready() -> void:
	_build()


# ------------------------------------------------------------------- build --

func _build() -> void:
	var plate := BoxMesh.new()
	plate.size = Vector3(Feel.CELL * PLATE_SPAN, PLATE_THICKNESS, Feel.CELL * PLATE_SPAN)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Feel.COL_PLATE
	mat.roughness = 1.0
	mat.metallic = 0.1
	plate.material = mat

	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plate
	mm.instance_count = Feel.GRID_W * Feel.GRID_L

	_rest.resize(mm.instance_count)
	var i := 0
	for z in Feel.GRID_L:
		for x in Feel.GRID_W:
			var pos := RollMath.cell_to_world(Vector2i(x, z)) \
				+ Vector3.DOWN * PLATE_THICKNESS * 0.5   # plate top sits at y = 0
			var xf := Transform3D(Basis.IDENTITY, pos)
			_rest[i] = xf
			mm.set_instance_transform(i, xf)
			i += 1

	mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

	_mark_mesh = BoxMesh.new()
	_mark_mesh.size = Vector3(Feel.CELL * MARK_SPAN, 0.05, Feel.CELL * MARK_SPAN)
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Feel.COL_MARK
	mmat.emission_enabled = true
	mmat.emission = Feel.COL_MARK
	mmat.emission_energy_multiplier = 1.6
	mmat.roughness = 0.8
	_mark_mesh.material = mmat

	_area_mark_mesh = BoxMesh.new()
	_area_mark_mesh.size = Vector3(Feel.CELL * MARK_SPAN, 0.05, Feel.CELL * MARK_SPAN)
	var amat := StandardMaterial3D.new()
	amat.albedo_color = Feel.COL_MARK_AREA
	amat.emission_enabled = true
	amat.emission = Feel.COL_MARK_AREA
	amat.emission_energy_multiplier = 1.6
	amat.roughness = 0.8
	_area_mark_mesh.material = amat


# ------------------------------------------------------------------ bounds --

## Active field bounds as a Rect2i (position = min cell, size = cell counts).
## M1: the full field. M2 shrinks this as gray cubes escape.
func bounds() -> Rect2i:
	return Rect2i(Vector2i.ZERO, Vector2i(Feel.GRID_W, Feel.GRID_L))


func in_bounds(cell: Vector2i) -> bool:
	return bounds().has_point(cell)


## True when the marker may occupy this cell: in bounds, row still solid.
func can_stand(cell: Vector2i) -> bool:
	return in_bounds(cell) and not _falling.has(cell.y) and not _gone.has(cell.y)


## Rows still standing: not falling, not gone. The HUD's "field rows" and the
## FIELD_MIN_ROWS death law both read this.
func solid_rows() -> int:
	return Feel.GRID_L - _falling.size() - _gone.size()


## The highest z (nearest the camera) still standing — where an escaped gray
## takes its bite. -1 when no row is solid.
func near_solid_row() -> int:
	for z in range(Feel.GRID_L - 1, -1, -1):
		if not _falling.has(z) and not _gone.has(z):
			return z
	return -1


func is_row_falling(z: int) -> bool:
	return _falling.has(z)


func is_row_gone(z: int) -> bool:
	return _gone.has(z)


## Current world y of a row's first plate — the "is it dropping" probe.
## Derived from the fall state rather than read back from the MultiMesh
## (the dummy/headless renderer does not preserve instance buffers).
func row_plate_y(z: int) -> float:
	if _gone.has(z):
		return -9999.0
	var base_y: float = _rest[z * Feel.GRID_W].origin.y
	if _falling.has(z):
		var f: Dictionary = _falling[z]
		var t_f: float = f.t
		return base_y - 0.5 * Feel.FALL_GRAVITY * t_f * t_f
	return base_y


# -------------------------------------------------------------- falling rows --

## Flag a row to drop into the void with tumble (fired by CAPTURE).
func fall_row(z: int) -> void:
	if _falling.has(z) or _gone.has(z):
		return
	var axis := Vector3(sin(float(z) * 1.7), 0.0, cos(float(z) * 1.7)).normalized()
	_falling[z] = {"t": 0.0, "axis": axis, "spin": 1.0 if z % 2 == 0 else -1.0}


## The FIELD SHRINK law: the near edge row falls (an escaped gray's bite).
## Returns the row z that fell, or -1 when nothing solid remains.
func shrink_near_row() -> int:
	var z := near_solid_row()
	if z < 0:
		return -1
	fall_row(z)
	return z


## The green blessing's regrow: restore the most recently vanished row.
## Returns true when a row came back.
func regrow_row() -> bool:
	if _gone_order.is_empty():
		return false
	var z: int = _gone_order.pop_back()
	_gone.erase(z)
	for x in Feel.GRID_W:
		mm.set_instance_transform(z * Feel.GRID_W + x, _rest[z * Feel.GRID_W + x])
	return true


## Fresh field: every row solid, every mark cleared (the RETRY path).
func reset() -> void:
	_falling.clear()
	_gone.clear()
	_gone_order.clear()
	for cell: Vector2i in _marks.keys():
		clear_mark(cell)
	for i in mm.instance_count:
		mm.set_instance_transform(i, _rest[i])


func advance(dt: float) -> void:
	_advance_marks(dt)
	_advance_falling(dt)


func _advance_falling(dt: float) -> void:
	if _falling.is_empty():
		return
	var finished: Array[int] = []
	for z: int in _falling:
		var f: Dictionary = _falling[z]
		f.t += dt
		var t_f: float = f.t
		var drop: float = 0.5 * Feel.FALL_GRAVITY * t_f * t_f
		var ang: float = float(f.spin) * Feel.FALL_TUMBLE_SPEED * t_f
		var b := Basis(Vector3(f.axis), ang)
		for x in Feel.GRID_W:
			var i := z * Feel.GRID_W + x
			var pos: Vector3 = _rest[i].origin + Vector3.DOWN * drop
			mm.set_instance_transform(i, Transform3D(b, pos))
		if _rest[z * Feel.GRID_W].origin.y - drop < Feel.VOID_Y:
			_vanish_row(z)
			finished.append(z)
	for z in finished:
		_falling.erase(z)


func _vanish_row(z: int) -> void:
	_gone[z] = true
	_gone_order.append(z)
	var dead := Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0.0, -9999.0, 0.0))
	for x in Feel.GRID_W:
		mm.set_instance_transform(z * Feel.GRID_W + x, dead)


# --------------------------------------------------------------- mark plates --

## Raise a mark plate. `area` marks (the green blessing) glow green; `force`
## lets a mark land on a falling row (the 3x3 blesses the row dying under it).
func set_mark(cell: Vector2i, area := false, force := false) -> bool:
	if _marks.has(cell) or (not force and not can_stand(cell)):
		return false
	var node := MeshInstance3D.new()
	node.mesh = _area_mark_mesh if area else _mark_mesh
	node.position = RollMath.cell_to_world(cell) + Vector3.UP * MARK_BURIED_Y
	add_child(node)
	_marks[cell] = {"node": node, "t": 0.0, "area": area}
	return true


## True when this cell's mark belongs to a green 3x3 area.
func is_area_mark(cell: Vector2i) -> bool:
	return _marks.has(cell) and bool(_marks[cell].area)


## Count of area marks currently up.
func area_mark_count() -> int:
	var n := 0
	for cell: Vector2i in _marks:
		if bool(_marks[cell].area):
			n += 1
	return n


func clear_mark(cell: Vector2i) -> void:
	if not _marks.has(cell):
		return
	var m: Dictionary = _marks[cell]
	(m.node as Node3D).queue_free()
	_marks.erase(cell)


func clear_row_marks(z: int) -> void:
	for cell: Vector2i in _marks.keys():
		if cell.y == z:
			clear_mark(cell)


func is_marked(cell: Vector2i) -> bool:
	return _marks.has(cell)


func marked_count() -> int:
	return _marks.size()


func marked_cells() -> Array:
	return _marks.keys()


func _advance_marks(dt: float) -> void:
	if _marks.is_empty():
		return
	for cell: Vector2i in _marks:
		var m: Dictionary = _marks[cell]
		m.t += dt
		var k: float = clampf(m.t / Feel.MARK_RISE_TIME, 0.0, 1.0)
		var eased := 1.0 - (1.0 - k) * (1.0 - k)
		var node := m.node as Node3D
		node.position.y = lerpf(MARK_BURIED_Y, Feel.MARK_RISE_HEIGHT, eased)
