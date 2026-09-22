class_name MarkerFigure
extends Node3D
## The Marker — an abstract glowing figure, CODE-BUILT low-poly only
## (art_source_law: walker <= 300 tris; capsule 8x2 + sphere 8x4 come in far
## under that). No shadows under PSX law: a dark radial-gradient quad lies
## flat under the figure as the blob. Coded animation only — cell steps tween,
## the body bobs, the emissive pulses. No mocap, no imports.
##
## Movement is cell-to-cell and grid-aligned; step() clamps against a
## can_stand provider (the grid's law). Facing = the direction of movement.

const BODY_RADIUS := 0.09
const BODY_HEIGHT := 0.44
const HEAD_RADIUS := 0.085
const BLOB_SPAN := 0.52
const STEP_LERP := 18.0             # yaw smoothing toward the facing dir
const PULSE_HZ := 4.0

var cell := Vector2i(6, Feel.GRID_L - 3)
var facing := RollMath.DIR_UP
var can_stand_provider: Callable     # func(cell: Vector2i) -> bool

var _move_t := -1.0                  # < 0 = standing still
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _age := 0.0
var _target_yaw := 0.0

@onready var body: MeshInstance3D = $Body
@onready var head: MeshInstance3D = $Head
@onready var blob: MeshInstance3D = $Blob
@onready var _mat: StandardMaterial3D = StandardMaterial3D.new()


func _ready() -> void:
	_build()


func setup(provider: Callable, start_cell: Vector2i) -> void:
	can_stand_provider = provider
	cell = start_cell
	facing = RollMath.DIR_UP
	if is_inside_tree():
		position = RollMath.cell_to_world(cell)


func _build() -> void:
	# slim capsule body — 8 radial segments x 2 rings, ~40 tris
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = BODY_RADIUS
	body_mesh.height = BODY_HEIGHT
	body_mesh.radial_segments = 8
	body_mesh.rings = 2
	_mat.albedo_color = Feel.COL_MARKER
	_mat.emission_enabled = true
	_mat.emission = Feel.COL_MARKER
	_mat.emission_energy_multiplier = 1.4
	_mat.roughness = 0.6
	body_mesh.material = _mat
	body.mesh = body_mesh
	body.position = Vector3.UP * (BODY_HEIGHT * 0.5 + 0.08)

	# small head sphere — 8 x 4, ~64 tris
	var head_mesh := SphereMesh.new()
	head_mesh.radius = HEAD_RADIUS
	head_mesh.height = HEAD_RADIUS * 2.0
	head_mesh.radial_segments = 8
	head_mesh.rings = 4
	head_mesh.material = _mat
	head.mesh = head_mesh
	head.position = Vector3.UP * (BODY_HEIGHT + 0.08 + HEAD_RADIUS + 0.06)

	# the blob "shadow": flat dark radial-gradient quad, nearest-filtered
	var blob_mesh := QuadMesh.new()
	blob_mesh.orientation = PlaneMesh.FACE_Y
	blob_mesh.size = Vector2(BLOB_SPAN, BLOB_SPAN)
	var bmat := StandardMaterial3D.new()
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(0.0, 0.0, 0.0, 0.55)
	bmat.albedo_texture = _blob_texture()
	bmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	bmat.no_depth_test = false
	blob_mesh.material = bmat
	blob.mesh = blob_mesh
	blob.position = Vector3.UP * 0.012

	_target_yaw = _yaw_for(facing)
	rotation.y = _target_yaw
	position = RollMath.cell_to_world(cell)


## Radial black->transparent gradient, generated in code (no assets).
func _blob_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	g.colors = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.85),
		Color(0.0, 0.0, 0.0, 0.35),
		Color(0.0, 0.0, 0.0, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	return tex


# ----------------------------------------------------------------- movement --

## Attempt one cell step in `dir`. Turns to face the input either way;
## returns false (and stays put) when the target is not standable.
func step(dir: Vector2i) -> bool:
	facing = dir
	_target_yaw = _yaw_for(dir)
	var target := cell + dir
	if not _standable(target):
		return false
	_from = position
	_to = RollMath.cell_to_world(target)
	cell = target
	_move_t = 0.0
	return true


func advance(dt: float) -> void:
	_age += dt
	if _move_t >= 0.0:
		_move_t += dt
		var k := clampf(_move_t / Feel.MARKER_STEP_TIME, 0.0, 1.0)
		position = _from.lerp(_to, k)
		if k >= 1.0:
			_move_t = -1.0
	rotation.y = lerp_angle(rotation.y, _target_yaw, minf(1.0, dt * STEP_LERP))
	# coded life: gentle bob + emissive pulse
	body.position.y = (BODY_HEIGHT * 0.5 + 0.08) + sin(_age * PULSE_HZ) * 0.015
	_mat.emission_energy_multiplier = 1.4 + 0.3 * (0.5 + 0.5 * sin(_age * PULSE_HZ * 1.5))


func is_moving() -> bool:
	return _move_t >= 0.0


## The cell "in front of" the marker — the only cell v1 reach allows marking.
func ahead_cell() -> Vector2i:
	return cell + facing


# ----------------------------------------------------------------- internals --

func _standable(cell_v: Vector2i) -> bool:
	if can_stand_provider.is_valid():
		return can_stand_provider.call(cell_v)
	return cell_v.x >= 0 and cell_v.x < Feel.GRID_W \
		and cell_v.y >= 0 and cell_v.y < Feel.GRID_L


## Yaw so the figure's -Z faces `dir` (grid dirs are xz ints).
static func _yaw_for(dir: Vector2i) -> float:
	return atan2(float(-dir.x), float(-dir.y))
