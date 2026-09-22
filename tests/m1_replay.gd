extends SceneTree
## Milestone 1 scripted replay (headless, deterministic):
##   godot --headless --script res://tests/m1_replay.gd
## 15 simulated seconds through the REAL main scene: cubes spawn on the beat
## and roll toward the camera; the driver walks the Marker around (steps go
## through the same synthetic DragStepper the touch screen feeds), marks the
## cell ahead in an incoming cube's column, and CAPTURES as cubes roll over
## the marks — at least two captures, rows dropping after each one, the
## Marker never out of bounds and never standing on a dropped row, and no
## cube/stage invariant broken anywhere along the way.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const DT := 1.0 / 60.0
const RUN_SEC := 15.0
const STEP_PACE := 0.13              # driver step cadence (>= MARKER_STEP_TIME)
const CAPTURE_BUDGET := 2            # after this many captures, hands off and lets cubes roll
const FREE_LANE := 0                 # column whose cubes are never intercepted (void-fall lane)

var passes := 0
var fails := 0
var _cooldown := 0.0
var _fell_count := 0                # member var: lambdas capture self by reference


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.set_process(false)
	main.rng.seed = 20260922
	main.m2_laws = false                # M1 law set: no taxonomy waves / shrink / black death
	main.spawn_cube(FREE_LANE)          # the sacrificed cube: rolls the whole field into the void

	var frames := int(RUN_SEC / DT)
	var samples := 0
	var oob := 0
	var bad_rows := 0
	var max_cube_y := -1.0
	var seen := {}                    # cube instance ids -> true (spawn census)

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
			if not seen.has(id):
				seen[id] = true
				cube.fell_off.connect(func(_k): _fell_count += 1)
			max_cube_y = maxf(max_cube_y, cube.cell.y)
		samples += 1

	var rows_dropped := 0
	for z in Feel.GRID_L:
		if main.grid.is_row_falling(z) or main.grid.is_row_gone(z):
			rows_dropped += 1

	check("replay_runs_full_15s", samples == frames and is_instance_valid(main),
		"samples=%d/%d" % [samples, frames])
	check("replay_marker_never_left_bounds", oob == 0, "oob=%d" % oob)
	check("replay_marker_never_stood_on_a_dropped_row", bad_rows == 0, "bad=%d" % bad_rows)
	check("replay_captured_at_least_two", main.captures >= 2,
		"captures=%d" % main.captures)
	check("replay_score_accrued_per_gray", main.score >= 2 * Feel.SCORE_PER_GRAY,
		"score=%d" % main.score)
	check("replay_cubes_spawned_on_the_beat", seen.size() >= 6, "spawned=%d" % seen.size())
	check("replay_cubes_rolled_forward", max_cube_y >= 3.0, "max_y=%f" % max_cube_y)
	check("replay_rows_dropped_after_captures", rows_dropped >= main.captures \
		and main.captures >= 2, "rows=%d captures=%d" % [rows_dropped, main.captures])
	check("replay_uncaptured_cubes_tipped_into_the_void", _fell_count >= 1,
		"fell=%d" % _fell_count)

	main.queue_free()
	await process_frame

	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)


## The driver: capture anything over a mark; otherwise shepherd the Marker
## into (target column, one row past an interception row) facing UP, then
## mark the cell ahead of it in the cube's path.
func _drive(main, dt: float) -> void:
	# 0. capture budget spent: stop marking/capturing, let the cubes roll
	#    through and tip into the void off the near edge
	if main.captures >= CAPTURE_BUDGET:
		return

	# 1. CAPTURE: any rolling cube currently over a marked cell
	for cube in main.cubes.duplicate():
		if is_instance_valid(cube) and cube.state == Cube.State.ROLLING \
				and main.grid.is_marked(cube.current_cell()):
			main.do_capture()
			return

	# 2. target the deepest rolling cube (closest to the camera); the free
	#    lane is never intercepted — its cubes roll on into the void
	var target: Cube = null
	for cube in main.cubes:
		if is_instance_valid(cube) and cube.state == Cube.State.ROLLING \
				and cube.cell.x != FREE_LANE:
			if target == null or cube.cell.y > target.cell.y:
				target = cube
	if target == null:
		return
	var tx: int = target.current_cell().x
	var ty: int = target.current_cell().y

	# 3. already armed: a mark sits in the target's column ahead of it
	for cell in main.grid.marked_cells():
		if cell.x == tx and cell.y > ty:
			return

	# 4. interception row: first standable row below the cube's next step,
	#    with room under it for the Marker + its jog
	var m_row := -1
	for r in range(ty + 1, Feel.GRID_L - 1):
		if main.grid.can_stand(Vector2i(tx, r)):
			m_row = r
			break
	if m_row < 0:
		return
	var stand := Vector2i(tx, m_row + 1)

	# 5. in position: face UP (one-cell jog out and back = facing = movement dir)
	if main.marker.cell == stand:
		if main.marker.facing == RollMath.DIR_UP:
			main.mark_ahead()         # ahead = (tx, m_row) — in the cube's path
		elif _cooldown <= 0.0 and main.grid.can_stand(stand + Vector2i(0, 1)):
			if main.step_marker(RollMath.DIR_DOWN):
				main.step_marker(RollMath.DIR_UP)
			_cooldown = STEP_PACE
		return

	# 6. walk there, one paced step per frame, through the swipe input path
	if _cooldown > 0.0:
		return
	_cooldown = STEP_PACE
	if main.marker.cell.y < stand.y:
		_push_step(main, RollMath.DIR_DOWN)
	elif main.marker.cell.y > stand.y:
		_push_step(main, RollMath.DIR_UP)
	elif main.marker.cell.x < stand.x:
		_push_step(main, RollMath.DIR_RIGHT)
	elif main.marker.cell.x > stand.x:
		_push_step(main, RollMath.DIR_LEFT)


## Feed one swipe step through the same DragStepper the touch screen drives.
func _push_step(main, dir: Vector2i) -> void:
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
