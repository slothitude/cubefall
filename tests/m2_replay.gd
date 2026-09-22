extends SceneTree
## Milestone 2 scripted replay (headless, deterministic):
##   godot --headless --script res://tests/m2_replay.gd
## 20 simulated seconds through the REAL main scene under the M2 laws:
## waves of mixed gray/black/green rows spawn on the beat and roll toward the
## camera. The driver walks the Marker (steps go through the same synthetic
## DragStepper the touch screen feeds), marks interception rows JUST for the
## columns of incoming GRAY/GREEN cubes — never a black's column — and
## CAPTURES in batches as cubes roll over the marks. Column 0 is the
## sacrificed lane: its cubes roll off the near edge, so a gray escape
## SHRINKS the field. When the wave clears (blacks excluded), the driver
## freezes the spawner and idles. Never dies, never locks.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const DT := 1.0 / 60.0
const RUN_SEC := 20.0
const STEP_PACE := 0.13              # driver step cadence (>= MARKER_STEP_TIME)
const FREE_LANE := 0                 # column never intercepted: the escape lane
const ARM_CELLS := 4                 # mark-arming window ahead of the mark row
const FAR_STAND := 5                 # the driver parks this deep (z) to outlive bites

var passes := 0
var fails := 0
var _cooldown := 0.0
var _cleared := 0                    # wave_cleared count
var _shrinks := 0                    # field_shrank count
var _escapes := 0                    # cubes tipping off the near edge
var _blacks_seen := 0
var _blacks_captured := 0
var _caps_gray := 0
var _caps_green := 0
var _death_causes: Array = []
var _seen := {}                      # cube instance ids -> true (spawn census)
var _frozen := false                 # spawner frozen after the target clear


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.set_process(false)
	main.rng.seed = 20260923
	main.game_over.connect(func(cause: String): _death_causes.append(cause))
	main.wave_cleared.connect(func(_w: int, _a: bool): _cleared += 1)
	main.field_shrank.connect(func(_r: int): _shrinks += 1)

	var frames := int(RUN_SEC / DT)
	var samples := 0
	var oob := 0
	var bad_rows := 0

	for i in frames:
		_drive(main, DT)
		main.advance(DT)
		main.stepper.drag_end()       # one deliberate step per frame, no hold-overs
		_cooldown -= DT

		var mc: Vector2i = main.marker.cell
		if not main.grid.in_bounds(mc):
			oob += 1
		if main.grid.is_row_falling(mc.y) or main.grid.is_row_gone(mc.y):
			bad_rows += 1
		for cube in main.cubes:
			if not is_instance_valid(cube):
				continue
			var id: int = cube.get_instance_id()
			if not _seen.has(id):
				_seen[id] = true
				cube.fell_off.connect(func(_k): _escapes += 1)
				cube.captured.connect(func(k):
					if k.law == Feel.CUBE_BLACK:
						_blacks_captured += 1)
				if cube.law == Feel.CUBE_BLACK:
					_blacks_seen += 1
		samples += 1

	check("replay_runs_full_20s", samples == frames and is_instance_valid(main),
		"samples=%d/%d" % [samples, frames])
	check("replay_marker_never_left_bounds", oob == 0, "oob=%d" % oob)
	check("replay_marker_never_stood_on_a_dropped_row", bad_rows == 0, "bad=%d" % bad_rows)
	check("replay_never_died_and_never_touched_a_black", main._dead == false \
		and _death_causes.is_empty() and _blacks_captured == 0,
		"dead=%s causes=%s blacks=%d" % [main._dead, str(_death_causes),
		_blacks_captured])
	check("replay_an_escape_shrunk_the_field", _escapes >= 1 and _shrinks >= 1,
		"escapes=%d shrinks=%d" % [_escapes, _shrinks])
	check("replay_blacks_spawned_and_rolled_off_free", _blacks_seen >= 1,
		"blacks=%d" % _blacks_seen)
	check("replay_wave_cleared_blacks_excluded", _cleared >= 1 and main.wave >= 2,
		"cleared=%d wave=%d" % [_cleared, main.wave])
	check("replay_captured_the_herd", main.captures >= 3 \
		and (_caps_gray + _caps_green) == main.captures,
		"caps=%d gray=%d green=%d" % [main.captures, _caps_gray, _caps_green])
	check("replay_score_matches_the_law", main.score >= main.captures \
		* Feel.SCORE_PER_GRAY + Feel.WAVE_CLEAR_BASE,
		"score=%d caps=%d" % [main.score, main.captures])
	check("replay_field_still_stands_no_softlock", main.grid.solid_rows() \
		>= Feel.FIELD_MIN_ROWS and _frozen and is_instance_valid(main.marker),
		"solid=%d frozen=%s" % [main.grid.solid_rows(), _frozen])

	main.queue_free()
	await process_frame

	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)


## The driver: batch-capture anything over a mark (never while a black sits
## on one); otherwise shepherd the Marker onto (target column, stand_row)
## facing UP so mark_ahead() lands on the mark row right in front of it.
## Only gray/green columns are armed: blacks roll through untouched.
func _drive(main, dt: float) -> void:
	# 0a. a dead run is inert: never drive a ghost
	if main._dead:
		return
	# 0b. the wave is cleared: freeze the spawner and idle. Nothing can hurt
	#    the Marker now — the wave's grays/greens are all resolved and the
	#    blacks still rolling tip off free (no bites, no spawner).
	if _cleared >= 1:
		if not _frozen:
			_frozen = true
			main.spawning = false
		return

	# 1. CAPTURE: rolling cubes over marks — but the forbidden law first: if
	#    a BLACK is over any mark, hands off and let it roll clear (marks wait).
	var hit := false
	var black_over := false
	for cube in main.cubes:
		if is_instance_valid(cube) and cube.state == Cube.State.ROLLING \
				and main.grid.is_marked(cube.current_cell()):
			if cube.law == Feel.CUBE_BLACK:
				black_over = true
				continue
			hit = true
			if cube.law == Feel.CUBE_GRAY:
				_caps_gray += 1
			elif cube.law == Feel.CUBE_GREEN:
				_caps_green += 1
	if black_over:
		return                        # never do_capture while a black sits on a mark
	if hit:
		main.do_capture()
		return

	# 2. interception geometry. Fallen rows are full-width: the Marker can
	#    never cross one, so its world is the contiguous solid BAND it stands
	#    in. It parks DEEP (FAR_STAND, away from the near edge: void bites
	#    always eat the near-most solid row, so depth is survival) and marks
	#    the row right in front of it (stand - 1, so ahead_cell() == mark).
	#    The triple (mark, stand, jog) must all be solid: the jog cell behind
	#    stand is the out-and-back that turns the Marker to face UP.
	if not main.grid.can_stand(main.marker.cell):
		return                          # stranded (never while alive, defensively)
	var my: int = main.marker.cell.y
	var lo := my
	while lo - 1 >= 0 and main.grid.can_stand(Vector2i(6, lo - 1)):
		lo -= 1
	var stand_row := -1
	var mark_row := -1
	var z: int = maxi(lo, FAR_STAND)
	while z < Feel.GRID_L - 1:
		if main.grid.can_stand(Vector2i(6, z - 1)) \
				and main.grid.can_stand(Vector2i(6, z)) \
				and main.grid.can_stand(Vector2i(6, z + 1)):
			stand_row = z
			mark_row = z - 1
			break
		z += 1
	if mark_row < 0:
		return

	# 3. deepest approaching gray/green whose column has no mark waiting.
	#    ARMING WINDOW: only when the target is within ARM_CELLS of the mark
	#    row — a mark must never sit waiting in a column an older BLACK still
	#    has to cross (blacks and grays roll 5.3 cells apart row-to-row, so 4
	#    cells of window leaves the black >1 cell clear behind the mark).
	var target: Cube = null
	for cube in main.cubes:
		if is_instance_valid(cube) and cube.state == Cube.State.ROLLING \
				and cube.law != Feel.CUBE_BLACK and cube.cell.x != FREE_LANE \
				and cube.cell.y < mark_row \
				and cube.cell.y >= mark_row - ARM_CELLS \
				and not main.grid.is_marked(Vector2i(cube.cell.x, mark_row)):
			if target == null or cube.cell.y > target.cell.y:
				target = cube
	if target == null:
		return
	var stand := Vector2i(target.cell.x, stand_row)

	# 4. in position: face UP (one-cell jog out and back = facing = movement dir)
	if main.marker.cell == stand:
		if main.marker.facing == RollMath.DIR_UP:
			main.mark_ahead()         # ahead = (tx, mark_row) — in the cube's path
		elif _cooldown <= 0.0 and main.grid.can_stand(stand + Vector2i(0, 1)):
			if main.step_marker(RollMath.DIR_DOWN):
				main.step_marker(RollMath.DIR_UP)
			_cooldown = STEP_PACE
		return

	# 5. walk there, one paced step per frame, through the swipe input path.
	#    If the y-step would land in a hole, sidestep along x instead.
	if _cooldown > 0.0:
		return
	_cooldown = STEP_PACE
	var y_dir := Vector2i.ZERO
	if main.marker.cell.y < stand.y:
		y_dir = RollMath.DIR_DOWN
	elif main.marker.cell.y > stand.y:
		y_dir = RollMath.DIR_UP
	if y_dir != Vector2i.ZERO:
		if main.grid.can_stand(main.marker.cell + y_dir):
			_push(main, y_dir)
			return
	var x_dir := Vector2i.ZERO
	if main.marker.cell.x < stand.x:
		x_dir = RollMath.DIR_RIGHT
	elif main.marker.cell.x > stand.x:
		x_dir = RollMath.DIR_LEFT
	if x_dir != Vector2i.ZERO:
		_push(main, x_dir)


## Feed one swipe step through the same DragStepper the touch screen drives.
func _push(main, dir: Vector2i) -> void:
	var s: DragStepper = main.stepper
	s.drag_begin(0.0, 0.0)
	s.push_delta(float(dir.x) * Feel.SWIPE_STEP_PX, float(dir.y) * Feel.SWIPE_STEP_PX)


## ------------------------------------------------------------------ utils --

func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passes += 1
		print("PASS: " + name)
	else:
		fails += 1
		print("FAIL: " + name + "  (" + detail + ")")
