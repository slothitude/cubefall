extends Node3D
## CUBEFALL M1 stage — the grid, the void, the rolling cubes, the Marker.
## Builds the void fog environment in code (dark bg #05070c, fog law),
## drives the phone controls (swipe/drag steps through DragStepper, WASD or
## arrows too, tap-ahead raises the MARK), the big thumb-law CAPTURE button
## bottom-right, and the elevated behind-marker camera (Feel consts, slight
## dolly-out near edges).
##
## Tests set_process(false) and drive advance(dt) by hand.

signal score_changed(score: int)
signal captured(count: int)

const CUBE_SCENE := preload("res://scenes/cube.tscn")
const OFF_GRID := Vector2i(-9999, -9999)
const START_CELL := Vector2i(6, Feel.GRID_L - 3)   # center column, back from the near edge
const KEY_REPEAT := Feel.MARKER_STEP_REPEAT

var score := 0
var captures := 0
var spawning := true
var stepper := DragStepper.new()
var rng := RandomNumberGenerator.new()

var cubes: Array[Cube] = []

var _spawn_t := Feel.SPAWN_START_DELAY
var _cam_zoom := 1.0
var _key_dir := Vector2i.ZERO
var _key_t := 0.0
var _tap_active := false
var _tap_anchor := Vector2.ZERO
var _tap_max := 0.0
var _tap_time := 0.0

# ---- scene nodes (from scenes/main.tscn) ----
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var cam: Camera3D = $Camera3D
@onready var grid: Grid = $Grid
@onready var marker: MarkerFigure = $Marker
@onready var cubes_root: Node3D = $Cubes
@onready var ui: CanvasLayer = $UI

var env: Environment
var capture_button: Button
var score_label: Label


func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_ui()
	marker.setup(grid.can_stand, START_CELL)
	marker.position = RollMath.cell_to_world(START_CELL)
	_update_camera(1.0)


func _process(delta: float) -> void:
	advance(delta)


## One deterministic frame of the whole stage. Tests call this directly.
func advance(dt: float) -> void:
	for dir in stepper.poll(dt):
		step_marker(dir)
	for dir in _key_steps(dt):
		step_marker(dir)
	if _tap_active:
		_tap_time += dt
	marker.advance(dt)
	grid.advance(dt)
	for cube in cubes.duplicate():
		if is_instance_valid(cube):
			cube.advance(dt)
	if spawning:
		_spawn_t -= dt
		if _spawn_t <= 0.0:
			_spawn_t += Feel.SPAWN_BEAT_SEC
			spawn_cube()
	_update_camera(dt)


# ------------------------------------------------------------------ building --

func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Feel.COL_VOID
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.42, 0.55)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Feel.COL_FOG
	env.fog_density = Feel.FOG_DENSITY
	env.fog_sky_affect = 1.0
	world_env.environment = env
	sun.rotation_degrees = Vector3(-58.0, 22.0, 0.0)
	sun.shadow_enabled = false           # PSX law: no shadows, blobs only
	sun.light_energy = 1.1


func _build_camera() -> void:
	cam.fov = 55.0
	cam.near = 0.05
	cam.far = 90.0
	cam.current = true


func _build_ui() -> void:
	# the CAPTURE button: big, bottom-right, thumb law
	capture_button = Button.new()
	capture_button.text = "CAPTURE"
	capture_button.add_theme_font_size_override("font_size", 30)
	capture_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	capture_button.offset_left = -206.0
	capture_button.offset_top = -136.0
	capture_button.offset_right = -24.0
	capture_button.offset_bottom = -40.0
	capture_button.pressed.connect(do_capture)
	ui.add_child(capture_button)

	score_label = Label.new()
	score_label.text = "SCORE 0"
	score_label.add_theme_font_size_override("font_size", 22)
	score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	score_label.offset_left = 16.0
	score_label.offset_top = 12.0
	ui.add_child(score_label)


# -------------------------------------------------------------------- input --

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			stepper.drag_begin(t.position.x, t.position.y)
			_tap_active = true
			_tap_anchor = t.position
			_tap_max = 0.0
			_tap_time = 0.0
		else:
			if _tap_active and _tap_max < Feel.TAP_SLOP_PX and _tap_time <= Feel.TAP_MAX_SEC:
				tap_at(t.position)
			_tap_active = false
			stepper.drag_end()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_tap_max = maxf(_tap_max, (d.position - _tap_anchor).length())
		stepper.drag_move(d.position.x, d.position.y)


## WASD / arrow keys with hold-repeat (desktop lane of the same grammar).
func _key_steps(dt: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dir := Vector2i.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir = RollMath.DIR_UP
	elif Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir = RollMath.DIR_DOWN
	elif Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir = RollMath.DIR_LEFT
	elif Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir = RollMath.DIR_RIGHT
	if dir == Vector2i.ZERO:
		_key_dir = Vector2i.ZERO
		return out
	if dir != _key_dir:
		_key_dir = dir
		_key_t = 0.0
		out.append(dir)
	else:
		_key_t += dt
		if _key_t >= KEY_REPEAT:
			_key_t = 0.0
			out.append(dir)
	return out


## One marker step (clamped by the grid's can_stand law).
func step_marker(dir: Vector2i) -> bool:
	return marker.step(dir)


# -------------------------------------------------------------- mark + tap --

## Screen point -> grid cell via camera ray onto the floor plane (y = 0).
func screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var origin := cam.project_ray_origin(screen_pos)
	var normal := cam.project_ray_normal(screen_pos)
	if absf(normal.y) < 0.0001:
		return OFF_GRID
	var dist := -origin.y / normal.y
	if dist < 0.0:
		return OFF_GRID
	return RollMath.world_to_cell(origin + normal * dist)


## A tap: raise the MARK if it hit the cell ahead (classic v1 reach law).
func tap_at(screen_pos: Vector2) -> bool:
	return try_mark(screen_to_cell(screen_pos))


## Only the cell ahead of the marker may be marked.
func try_mark(cell: Vector2i) -> bool:
	if cell != marker.ahead_cell():
		return false
	return grid.set_mark(cell)


## Convenience: mark the ahead cell directly (replay/test lane).
func mark_ahead() -> bool:
	return grid.set_mark(marker.ahead_cell())


# ------------------------------------------------------------------ cubes --

func spawn_cube(col := -1) -> Cube:
	if col < 0:
		col = rng.randi_range(0, Feel.GRID_W - 1)
	var cube: Cube = CUBE_SCENE.instantiate()
	cubes_root.add_child(cube)
	cube.spawn_at(Vector2i(col, 0))
	cube.despawned.connect(_on_cube_despawned)
	cubes.append(cube)
	return cube


func _on_cube_despawned(cube: Cube) -> void:
	cubes.erase(cube)


## THE CAPTURE: every cube currently OVER a marked cell pops (+100 stub),
## its row's marks clear, and the row drops into the void with tumble.
## Returns how many cubes were captured.
func do_capture() -> int:
	var n := 0
	for cube in cubes:
		if cube.state != Cube.State.ROLLING:
			continue
		var under := cube.current_cell()
		if not grid.is_marked(under):
			continue
		if cube.start_capture():
			score += Feel.SCORE_PER_GRAY
			captures += 1
			grid.clear_row_marks(under.y)
			grid.fall_row(under.y)
			n += 1
	if n > 0:
		score_label.text = "SCORE %d" % score
		score_changed.emit(score)
		captured.emit(captures)
	return n


# ------------------------------------------------------------------ camera --

## Elevated behind-marker follow (Feel consts). Dolly-out slightly as the
## marker nears a field edge.
func _update_camera(dt: float) -> void:
	var mpos := marker.global_position
	var d_edge := minf(
		minf(float(marker.cell.x), float(Feel.GRID_W - 1 - marker.cell.x)),
		minf(float(marker.cell.y), float(Feel.GRID_L - 1 - marker.cell.y)))
	var target_zoom := 1.0 + Feel.GRID_DOLLY_MAX * (1.0 - clampf(d_edge / 3.0, 0.0, 1.0))
	_cam_zoom = lerpf(_cam_zoom, target_zoom, minf(1.0, dt * 4.0))
	cam.global_position = mpos + Vector3(0.0, Feel.CAMERA_HEIGHT, Feel.CAMERA_BACK) * _cam_zoom
	# pitch = CAMERA_TILT_DEG by construction: height / (back + forward) = tan(tilt)
	var forward := Feel.CAMERA_HEIGHT / tan(deg_to_rad(Feel.CAMERA_TILT_DEG)) - Feel.CAMERA_BACK
	cam.look_at(mpos + Vector3(0.0, 0.0, -forward), Vector3.UP)
