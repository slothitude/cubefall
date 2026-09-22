extends Node3D
## CUBEFALL stage — the grid, the void, the rolling cubes, the Marker.
##
## M1: builds the void fog environment in code (dark bg #05070c, fog law),
## drives the phone controls (swipe/drag steps through DragStepper, WASD or
## arrows too, tap-ahead raises the MARK), the big thumb-law CAPTURE button
## bottom-right, and the elevated behind-marker camera (Feel consts, slight
## dolly-out near edges).
##
## M2 (m2_laws = the taxonomy/wave/shrink law set): rows of mixed cubes spawn
## on an accelerating beat; GRAY capture scores, escape shrinks the field;
## BLACK capture is instant death, blacks roll off free; GREEN capture marks
## a 3x3 area whose first capture pays a bonus + a row of regrowth; clearing
## every gray+green of a wave with none escaped fires the ABSOLUTE; field
## under Feel.FIELD_MIN_ROWS, standing on a fallen row, or touching a black
## ends the run ("CUBE FALL" overlay + RETRY). Survive Feel.WAVES_PER_STAGE
## waves = stage clear (faster beat, more blacks).
##
## Tests set_process(false) and drive advance(dt) by hand.

signal score_changed(score: int)
signal captured(count: int)
signal wave_started(wave: int, stage: int)
signal wave_cleared(wave: int, absolute: bool)
signal absolute_fired(wave: int)
signal stage_cleared(stage: int)
signal field_shrank(rows_left: int)
signal field_regrew(rows_left: int)
signal game_over(cause: String)

const CUBE_SCENE := preload("res://scenes/cube.tscn")
const OFF_GRID := Vector2i(-9999, -9999)
const START_CELL := Vector2i(6, Feel.GRID_L - 3)   # center column, back from the near edge
const KEY_REPEAT := Feel.MARKER_STEP_REPEAT

var score := 0
var captures := 0
var spawning := true
var m2_laws := true                  # M1 replay runs with this false (M1 law set)
var wave := 1                        # wave index inside the stage (1-based)
var stage := 1
var stepper := DragStepper.new()
var rng := RandomNumberGenerator.new()

var cubes: Array[Cube] = []

var _wave_active := true
var _rows_spawned := 0               # rows spawned into the current wave
var _wg_spawned := 0                 # gray+green spawned this wave (blacks never count)
var _wg_resolved := 0                # gray+green captured or rolled off
var _wg_escaped := 0                 # gray+green that rolled off (voids the ABSOLUTE)
var _area_pending := 0               # green blessings awaiting their area capture
var _chain_queue: Array[Cube] = []   # ABSOLUTE chain reaction pops
var _chain_t := 0.0
var _chain_busy := false             # true while a chain pop is mid-start_capture

var _dead := false
var _death_t := -1.0                 # < 0 = not dying; counts up to the overlay
var _death_cause := ""
var _absolute_t := 0.0
var _toast_t := 0.0

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
var banner_label: Label
var flash_rect: ColorRect
var overlay: Control
var overlay_title: Label
var overlay_info: Label
var retry_button: Button


func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_ui()
	marker.setup(grid.can_stand, START_CELL)
	marker.position = RollMath.cell_to_world(START_CELL)
	marker.fell.connect(_on_marker_fell)
	_begin_wave(true)
	_update_camera(1.0)


func _process(delta: float) -> void:
	advance(delta)


## One deterministic frame of the whole stage. Tests call this directly.
func advance(dt: float) -> void:
	if not _dead:
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
	_advance_chain(dt)
	if spawning and not _dead:
		_advance_spawn(dt)
	if m2_laws and marker.mstate == MarkerFigure.MState.STANDING \
			and (grid.is_row_falling(marker.cell.y) or grid.is_row_gone(marker.cell.y)):
		marker.fall_into_void()      # the row under the figure fell: void death
	if _dead:
		_advance_death(dt)
	if _absolute_t > 0.0:
		_absolute_t = maxf(0.0, _absolute_t - dt)
		banner_label.visible = _absolute_t > 0.0
	if _toast_t > 0.0:
		_toast_t = maxf(0.0, _toast_t - dt)
		banner_label.visible = _toast_t > 0.0 and _absolute_t <= 0.0
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

	# HUD v1: score, wave #, field rows remaining, cubes left in the wave
	score_label = Label.new()
	score_label.text = "SCORE 0"
	score_label.add_theme_font_size_override("font_size", 20)
	score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	score_label.offset_left = 16.0
	score_label.offset_top = 12.0
	ui.add_child(score_label)

	# center banner: ABSOLUTE / stage toast
	banner_label = Label.new()
	banner_label.text = ""
	banner_label.add_theme_font_size_override("font_size", 44)
	banner_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner_label.offset_top = 120.0
	banner_label.offset_left = -160.0
	banner_label.offset_right = 160.0
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.visible = false
	ui.add_child(banner_label)

	# death flash: full-screen danger wash, fades over DEATH_FLASH_TIME
	flash_rect = ColorRect.new()
	flash_rect.color = Feel.COL_DANGER
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.modulate.a = 0.0
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(flash_rect)

	# the death overlay: "CUBE FALL" + score + wave + tap RETRY
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	ui.add_child(overlay)
	var panel := ColorRect.new()
	panel.color = Color(0.02, 0.02, 0.045, 0.88)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(panel)
	overlay_title = Label.new()
	overlay_title.text = "CUBE FALL"
	overlay_title.add_theme_font_size_override("font_size", 64)
	overlay_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	overlay_title.offset_top = -160.0
	overlay_title.offset_bottom = -80.0
	overlay_title.offset_left = -220.0
	overlay_title.offset_right = 220.0
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(overlay_title)
	overlay_info = Label.new()
	overlay_info.add_theme_font_size_override("font_size", 26)
	overlay_info.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	overlay_info.offset_top = -60.0
	overlay_info.offset_bottom = 40.0
	overlay_info.offset_left = -220.0
	overlay_info.offset_right = 220.0
	overlay_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(overlay_info)
	retry_button = Button.new()
	retry_button.text = "RETRY"
	retry_button.add_theme_font_size_override("font_size", 34)
	retry_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	retry_button.offset_top = 80.0
	retry_button.offset_bottom = 160.0
	retry_button.offset_left = -110.0
	retry_button.offset_right = 110.0
	retry_button.pressed.connect(retry)
	overlay.add_child(retry_button)


# -------------------------------------------------------------------- input --

func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return
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


# ------------------------------------------------------------------- waves --

## The beat accelerates per stage (spec roll.waves).
func current_beat() -> float:
	return Feel.SPAWN_BEAT_SEC * pow(Feel.WAVE_BEAT_ACCEL, float(stage - 1))


## Black share of the type weights — more blacks each stage, taken from gray.
func black_weight() -> float:
	return minf(Feel.WEIGHT_BLACK + float(stage - 1) * Feel.BLACK_WEIGHT_PER_STAGE,
		Feel.WEIGHT_BLACK + Feel.WEIGHT_GREEN)


func _roll_law() -> String:
	var r := rng.randf()
	if r < black_weight():
		return Feel.CUBE_BLACK
	if r < black_weight() + Feel.WEIGHT_GREEN:
		return Feel.CUBE_GREEN
	return Feel.CUBE_GRAY


## Open a wave: counters to zero, the beat rewinds (start delay on the first).
func _begin_wave(first := false) -> void:
	_rows_spawned = 0
	_wg_spawned = 0
	_wg_resolved = 0
	_wg_escaped = 0
	_wave_active = true
	_spawn_t = Feel.SPAWN_START_DELAY if first else current_beat()
	wave_started.emit(wave, stage)


## Test seam: reopen the CURRENT wave with fresh counters.
func begin_wave() -> void:
	_begin_wave(false)


## One row enters the current wave's spawn count (also the test seam).
func note_wave_row() -> void:
	_rows_spawned += 1


## One ROW of the wave, a weighted mix of cube types across the width.
func spawn_wave_row() -> int:
	note_wave_row()
	var n := 0
	for x in Feel.GRID_W:
		if rng.randf() < Feel.ROW_CUBE_CHANCE:
			spawn_wave_cube(_roll_law(), x)
			n += 1
	return n


## One cube accounted into the open wave (blacks never count toward it).
func spawn_wave_cube(law: String, col: int) -> Cube:
	var cube := spawn_cube(col, law)
	if law != Feel.CUBE_BLACK:
		_wg_spawned += 1
	_refresh_hud()
	return cube


func _advance_spawn(dt: float) -> void:
	if not m2_laws:
		# M1 law set: one gray cube per beat, no waves
		_spawn_t -= dt
		if _spawn_t <= 0.0:
			_spawn_t += Feel.SPAWN_BEAT_SEC
			spawn_cube()
		return
	if not _wave_active:
		return                      # wave open? rows spawn on the beat; else wait
	if _rows_spawned >= Feel.ROWS_PER_WAVE:
		return                      # the wave's rows are all out: resolve, then next
	_spawn_t -= dt
	if _spawn_t <= 0.0:
		_spawn_t += current_beat()
		spawn_wave_row()


# ------------------------------------------------------------------ cubes --

func spawn_cube(col := -1, law := Feel.CUBE_GRAY) -> Cube:
	if col < 0:
		col = rng.randi_range(0, Feel.GRID_W - 1)
	var cube: Cube = CUBE_SCENE.instantiate()
	cubes_root.add_child(cube)
	if law != Feel.CUBE_GRAY:
		cube.setup(law)
	cube.spawn_at(Vector2i(col, 0))
	cube.captured.connect(_on_cube_captured)
	cube.fell_off.connect(_on_cube_fell_off)
	cube.despawned.connect(_on_cube_despawned)
	cubes.append(cube)
	return cube


func _on_cube_despawned(cube: Cube) -> void:
	cubes.erase(cube)


## Wave accounting for a CAPTURED cube. Score lives in do_capture only, so
## ABSOLUTE chain pops (which re-enter here) never re-score.
func _on_cube_captured(cube: Cube) -> void:
	if not m2_laws or not _wave_active or _chain_busy \
			or cube.law == Feel.CUBE_BLACK:
		return
	_wg_resolved += 1
	_maybe_complete_wave()


## Wave accounting for an ESCAPED cube: blacks roll off free and never count;
## a gray escape counts AND takes a row of field with it; a green escape
## counts without touching the field.
func _on_cube_fell_off(cube: Cube) -> void:
	if not m2_laws or not _wave_active or cube.law == Feel.CUBE_BLACK:
		return
	_wg_resolved += 1
	_wg_escaped += 1
	if cube.law == Feel.CUBE_GRAY:
		shrink_field()
	_maybe_complete_wave()


## FIELD SHRINK: the near edge row falls into the void. Under
## Feel.FIELD_MIN_ROWS the field is lost = game over.
func shrink_field() -> int:
	var z := grid.shrink_near_row()
	if z < 0:
		return -1
	var rows_left := grid.solid_rows()
	_refresh_hud()
	field_shrank.emit(rows_left)
	if m2_laws and rows_left < Feel.FIELD_MIN_ROWS:
		_game_over("field")
	return z


## GREEN BLESSING: mark the 3x3 around the green's cell (over the dying row
## too — force) and bank one area capture (bonus + a row of regrowth).
func _bless_area(center: Vector2i) -> void:
	for dy in range(-Feel.GREEN_AREA_SPAN, Feel.GREEN_AREA_SPAN + 1):
		for dx in range(-Feel.GREEN_AREA_SPAN, Feel.GREEN_AREA_SPAN + 1):
			grid.set_mark(Vector2i(center.x + dx, center.y + dy), true, true)
	_area_pending += 1


## THE CAPTURE: every cube currently OVER a marked cell pops — gray +100,
## green +250 (+ the 3x3 blessing), a pop on a blessed cell +150 and a row
## of regrowth. The touched rows' marks clear and the rows drop with tumble.
## Capturing a BLACK is instant game over. Returns how many cubes were captured.
func do_capture() -> int:
	var pops: Array[Cube] = []
	var black_hit := false
	for cube in cubes:
		if cube.state != Cube.State.ROLLING:
			continue
		var under := cube.current_cell()
		if not grid.is_marked(under):
			continue
		if cube.law == Feel.CUBE_BLACK:
			black_hit = true
			continue
		pops.append(cube)
	if black_hit:
		_game_over("forbidden")      # instant: no score, no pops, no appeal
		return 0
	var n := 0
	var rows := {}
	var area_pops := 0
	var greens: Array[Vector2i] = []
	for cube in pops:
		var under := cube.current_cell()
		if not cube.start_capture():
			continue
		n += 1
		captures += 1
		rows[under.y] = true
		if cube.law == Feel.CUBE_GREEN:
			score += Feel.SCORE_PER_GREEN
			greens.append(under)
		else:
			score += Feel.SCORE_PER_GRAY
		if grid.is_area_mark(under) and _area_pending > 0:
			_area_pending -= 1
			area_pops += 1
	for z: int in rows:
		grid.clear_row_marks(z)
		grid.fall_row(z)
	for gcell in greens:             # bless AFTER the row clearing: the 3x3
		_bless_area(gcell)           # outlives the row dying under the green
	if area_pops > 0:
		for i in area_pops:
			score += Feel.SCORE_GREEN_AREA
			if grid.regrow_row():
				_refresh_hud()
				field_regrew.emit(grid.solid_rows())
	if n > 0:
		_refresh_hud()
		score_changed.emit(score)
		captured.emit(captures)
	return n


## ABSOLUTE chain reaction: every still-rolling non-black cube pops in a
## stagger (no score — the wave's cubes were already paid; the 1000 is the
## bonus). Blacks are spared: the forbidden law outlives everything.
func _chain_reaction() -> void:
	_chain_queue = []
	for cube in cubes:
		if is_instance_valid(cube) and cube.state == Cube.State.ROLLING \
				and cube.law != Feel.CUBE_BLACK:
			_chain_queue.append(cube)
	_chain_t = Feel.CHAIN_POP_STAGGER


func _advance_chain(dt: float) -> void:
	if _chain_queue.is_empty():
		return
	_chain_t -= dt
	if _chain_t > 0.0:
		return
	var cube: Cube = _chain_queue.pop_front()
	if is_instance_valid(cube) and cube.state == Cube.State.ROLLING:
		_chain_busy = true
		cube.start_capture()
		_chain_busy = false
	_chain_t = Feel.CHAIN_POP_STAGGER


## Wave completeness: every row spawned, every gray+green captured or rolled
## off (blacks excluded). None escaped = the ABSOLUTE.
func _maybe_complete_wave() -> void:
	if not _wave_active:
		return
	if _rows_spawned < Feel.ROWS_PER_WAVE or _wg_resolved < _wg_spawned:
		return
	_wave_active = false
	var absolute := _wg_escaped == 0 and _wg_spawned > 0
	score += wave * Feel.WAVE_CLEAR_BASE
	if absolute:
		score += Feel.SCORE_ABSOLUTE
		_absolute_t = Feel.ABSOLUTE_LABEL_TIME
		banner_label.text = "ABSOLUTE"
		banner_label.add_theme_color_override("font_color", Feel.COL_ABSOLUTE)
		banner_label.visible = true
		_chain_reaction()
		absolute_fired.emit(wave)
	wave_cleared.emit(wave, absolute)
	wave += 1
	if wave > Feel.WAVES_PER_STAGE:
		stage += 1
		wave = 1
		_toast_t = Feel.TOAST_TIME
		banner_label.text = "STAGE %d" % stage
		banner_label.add_theme_color_override("font_color", Feel.COL_MARK)
		banner_label.visible = true
		stage_cleared.emit(stage)
	_begin_wave(false)
	_refresh_hud()                   # after the wave/stage step, so the HUD
	                                 # shows the wave that is now open


# ------------------------------------------------------------------- death --

## Death per spec: a captured black ("forbidden"), the void under a fallen
## row ("void"), the field under Feel.FIELD_MIN_ROWS ("field").
func _game_over(cause: String) -> void:
	if _dead:
		return
	_dead = true
	_death_cause = cause
	_death_t = 0.0
	spawning = false
	_chain_queue = []
	flash_rect.modulate.a = 0.62
	game_over.emit(cause)


func _advance_death(dt: float) -> void:
	if _death_t < 0.0:
		return
	_death_t += dt
	flash_rect.modulate.a = maxf(0.0, 0.62 * (1.0 - _death_t / Feel.DEATH_FLASH_TIME))
	if _death_t >= Feel.DEATH_FLASH_TIME and not overlay.visible:
		var cause_line := ""
		match _death_cause:
			"forbidden":
				cause_line = "YOU TOUCHED THE BLACK CUBE"
			"void":
				cause_line = "THE VOID TOOK YOU"
			"field":
				cause_line = "THE FIELD FELL AWAY"
		overlay_title.text = "CUBE FALL"
		overlay_info.text = "%s\nSCORE %d   WAVE %d   STAGE %d" \
			% [cause_line, score, wave, stage]
		overlay.visible = true
		retry_button.grab_focus()


func _on_marker_fell() -> void:
	_game_over("void")


## The RETRY path: a fresh run — score, waves, field, marker, overlay.
func retry() -> void:
	for cube in cubes:
		if is_instance_valid(cube):
			cube.queue_free()
	cubes.clear()
	grid.reset()
	score = 0
	captures = 0
	wave = 1
	stage = 1
	_dead = false
	_death_t = -1.0
	_death_cause = ""
	_absolute_t = 0.0
	_toast_t = 0.0
	_area_pending = 0
	_chain_queue = []
	flash_rect.modulate.a = 0.0
	overlay.visible = false
	banner_label.visible = false
	spawning = true
	marker.setup(grid.can_stand, START_CELL)
	marker.position = RollMath.cell_to_world(START_CELL)
	_begin_wave(true)
	_refresh_hud()


# --------------------------------------------------------------------- HUD --

func _refresh_hud() -> void:
	score_label.text = "SCORE %d\nWAVE %d   STAGE %d\nROWS %d   CUBES %d" \
		% [score, wave, stage, grid.solid_rows(),
		maxi(0, _wg_spawned - _wg_resolved)]


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
