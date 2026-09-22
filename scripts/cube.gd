class_name Cube
extends Node3D
## A cube of the taxonomy — GRAY (steel, normal), BLACK (matte, forbidden),
## GREEN (deep green, advantage) — one BoxMesh (Feel.CUBE_SIZE^3, the slight
## gap shows the grid). Spawns on a far row and rolls toward the camera row
## after row using RollMath — real 90-degree rotation around the leading
## bottom edge, never a slide. Passing the near edge it tips into the void:
## tumble + gravity, despawned below Feel.VOID_Y. Blacks roll off the same
## way (the forbidden law: they are ALLOWED to escape; capturing one is death).

enum State { ROLLING, FALLING, CAPTURING, DEAD }

signal fell_off(cube)                 # tipped over the near edge
signal captured(cube)                 # start_capture accepted
signal despawned(cube)                # gone below the void (or popped)

var law: String = Feel.CUBE_GRAY
var cell := Vector2i.ZERO             # the cell the current roll starts from
var dir := RollMath.DIR_DOWN          # cubes roll toward the camera (+Z)
var state: int = State.ROLLING

var _t := 0.0                         # progress through the current cell roll
var _fall_vel := Vector3.ZERO
var _flash_t := 0.0
var _mat: StandardMaterial3D

@onready var mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * Feel.CUBE_SIZE
	_mat = StandardMaterial3D.new()
	box.material = _mat
	mesh.mesh = box
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_law(law)


## Set the cube's taxonomy law and restyle its material to match.
## Legal before or after the node enters the tree.
func setup(new_law: String) -> void:
	law = new_law
	if _mat != null:
		_apply_law(law)


## The material look per spec palette: gray steel, matte black, deep green.
func _apply_law(which: String) -> void:
	match which:
		Feel.CUBE_BLACK:
			_mat.albedo_color = Feel.COL_CUBE_BLACK
			_mat.metallic = 0.0
			_mat.emission_enabled = false
		Feel.CUBE_GREEN:
			_mat.albedo_color = Feel.COL_CUBE_GREEN
			_mat.metallic = 0.1
			_mat.emission_enabled = true
			_mat.emission = Feel.COL_CUBE_GREEN
			_mat.emission_energy_multiplier = 0.35
		_:
			_mat.albedo_color = Feel.COL_CUBE_GRAY
			_mat.metallic = 0.1
			_mat.emission_enabled = false
	_mat.roughness = 1.0


## The law's palette color (the flash overwrite hides it mid-capture).
func law_color() -> Color:
	match law:
		Feel.CUBE_BLACK:
			return Feel.COL_CUBE_BLACK
		Feel.CUBE_GREEN:
			return Feel.COL_CUBE_GREEN
	return Feel.COL_CUBE_GRAY


## Place resting in a cell (bottom face on the floor, y = 0).
func spawn_at(at_cell: Vector2i) -> void:
	cell = at_cell
	_t = 0.0
	state = State.ROLLING
	global_transform = Transform3D(Basis.IDENTITY,
		RollMath.cell_to_world(at_cell) + Vector3.UP * RollMath.HALF)


func advance(dt: float) -> void:
	match state:
		State.ROLLING:
			_advance_roll(dt)
		State.FALLING:
			_advance_fall(dt)
		State.CAPTURING:
			_advance_capture(dt)


## Nearest cell under the cube's center — the capture window test.
## While mid-roll (t < 0.5) the cube is still "over" the cell it left.
func current_cell() -> Vector2i:
	return RollMath.world_to_cell(global_position)


## The capture law: flash white, shrink-pop over CAPTURE_FLASH_TIME.
func start_capture() -> bool:
	if state != State.ROLLING:
		return false
	state = State.CAPTURING
	_flash_t = 0.0
	_mat.albedo_color = Feel.COL_FLASH
	_mat.emission_enabled = true
	_mat.emission = Feel.COL_FLASH
	_mat.emission_energy_multiplier = 3.0
	captured.emit(self)
	return true


# ----------------------------------------------------------------- internals --

func _advance_roll(dt: float) -> void:
	_t += dt * Feel.ROLL_CELLS_PER_SEC
	while _t >= 1.0 and state == State.ROLLING:
		_t -= 1.0
		cell = RollMath.cell_after(cell, dir)
		if RollMath.leaves_field(cell, dir):
			_start_fall()
			return
	if state == State.ROLLING:
		global_transform = RollMath.roll_transform(cell, dir, _t)


## Off the near edge: keep the roll's momentum, add gravity + tumble.
func _start_fall() -> void:
	state = State.FALLING
	_fall_vel = RollMath.dir_world(dir) * (Feel.ROLL_CELLS_PER_SEC * Feel.CELL)
	fell_off.emit(self)


func _advance_fall(dt: float) -> void:
	_fall_vel.y -= Feel.FALL_GRAVITY * dt
	global_position += _fall_vel * dt
	rotate(RollMath.axis_for(dir), Feel.FALL_TUMBLE_SPEED * dt)
	if global_position.y < Feel.VOID_Y:
		state = State.DEAD
		despawned.emit(self)
		queue_free()


func _advance_capture(dt: float) -> void:
	_flash_t += dt
	var k := clampf(_flash_t / Feel.CAPTURE_FLASH_TIME, 0.0, 1.0)
	scale = Vector3.ONE * maxf(0.001, 1.0 - k)
	global_position.y = RollMath.HALF + k * 0.25   # pops up as it shrinks
	if k >= 1.0:
		state = State.DEAD
		despawned.emit(self)
		queue_free()
