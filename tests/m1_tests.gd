extends SceneTree
## Milestone 1 battery — GRID CORE. Run headless:
##   godot --headless --script res://tests/m1_tests.gd
## Done = 2x consecutive green. Covers: RollMath quarter-arc correctness
## (0 -> 90 deg, arc radius constant, midpoint height half*sqrt(2), exact
## landing for all 4 dirs), a rolling cube reaching the next cell at
## ROLL_DURATION, the void fall below VOID_Y, capture pop + score stub,
## spare cubes, the falling row, marker steps/clamps/facing, the tap-ahead
## mark law (exactly one, ahead only), swipe/hold input mapping, and a boot
## smoke of the whole stage (221-plate multimesh + cubes + marker + fog law).

const MAIN_SCENE := preload("res://scenes/main.tscn")
const MARKER_SCENE := preload("res://scenes/marker.tscn")
const CUBE_SCENE := preload("res://scenes/cube.tscn")
const DT := 1.0 / 60.0
const EPS := 0.001

var passes := 0
var fails := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	# ======================= RollMath — the soul, pure =====================
	var c := Vector2i(6, 8)

	var pivot_ok := true
	for d in RollMath.ALL_DIRS:
		var p := RollMath.pivot_for(c, d)
		pivot_ok = pivot_ok and nearv3(p,
			RollMath.cell_to_world(c) + RollMath.dir_world(d) * RollMath.HALF, EPS) \
			and absf(p.y) < EPS                                    # floor level
		var ax := RollMath.axis_for(d)
		pivot_ok = pivot_ok and nearf(ax.length(), 1.0, EPS) and absf(ax.y) < EPS
	check("roll_pivot_is_leading_bottom_edge_all_dirs", pivot_ok, str(pivot_ok))

	var rest := RollMath.roll_transform(c, RollMath.DIR_DOWN, 0.0)
	var rest_center := RollMath.cell_to_world(c) + Vector3.UP * RollMath.HALF
	check("roll_t0_is_resting_in_from_cell", nearv3(rest.origin, rest_center, EPS) \
		and rest.basis.is_equal_approx(Basis.IDENTITY),
		"origin=%s want=%s" % [rest.origin, rest_center])

	var pivot := RollMath.pivot_for(c, RollMath.DIR_DOWN)
	var radius := sqrt(2.0) * RollMath.HALF
	var arc_ok := true
	for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var ctr := RollMath.center_at(c, RollMath.DIR_DOWN, t)
		# the (CELL - CUBE_SIZE) = 0.02 grid-alignment slide perturbs the
		# distance to the static pivot by at most 0.02 — the path is the
		# quarter-arc plus that slide
		arc_ok = arc_ok and nearf((ctr - pivot).length(), radius, 0.021)
	check("roll_arc_radius_constant_quarter_arc", arc_ok, "radius=%f" % radius)

	var mid := RollMath.center_at(c, RollMath.DIR_DOWN, 0.5)
	check("roll_midpoint_height_is_half_sqrt2", nearf(mid.y, RollMath.HALF * sqrt(2.0), EPS) \
		and nearf(mid.z, pivot.z + 0.5 * (Feel.CELL - Feel.CUBE_SIZE), EPS),
		"y=%f want=%f" % [mid.y, RollMath.HALF * sqrt(2.0)])

	var rot_ok := true
	var land_ok := true
	for d in RollMath.ALL_DIRS:
		var x1 := RollMath.roll_transform(c, d, 1.0)
		rot_ok = rot_ok and nearv3(x1.basis.y, RollMath.dir_world(d), EPS)  # top -> travel dir
		rot_ok = rot_ok and nearf(x1.origin.y, RollMath.HALF, EPS)          # resting again
		var want := RollMath.cell_to_world(RollMath.cell_after(c, d)) + Vector3.UP * RollMath.HALF
		land_ok = land_ok and nearv3(x1.origin, want, EPS)
	check("roll_rotates_0_to_90_top_becomes_travel", rot_ok, str(rot_ok))
	check("roll_lands_exact_next_cell_all_dirs", land_ok, str(land_ok))

	var after_ok := true
	for d in RollMath.ALL_DIRS:
		after_ok = after_ok and RollMath.cell_after(c, d) == c + d
	check("cell_after_exact_all_dirs", after_ok \
		and RollMath.cell_after(Vector2i(0, 0), RollMath.DIR_LEFT) == Vector2i(-1, 0),
		str(after_ok))

	# ======================= the rolling cube ==============================
	var cube: Cube = CUBE_SCENE.instantiate()
	root.add_child(cube)
	await process_frame
	cube.spawn_at(Vector2i(6, 3))
	var roll_frames := int(ceil(Feel.ROLL_DURATION / DT))
	for i in roll_frames:
		cube.advance(DT)
	check("cube_reaches_next_cell_at_roll_duration",
		cube.cell == Vector2i(6, 4) and cube.state == Cube.State.ROLLING \
		and nearv3(cube.global_position,
			RollMath.cell_to_world(Vector2i(6, 4)) + Vector3.UP * RollMath.HALF, 0.05),
		"cell=%s pos=%s" % [cube.cell, cube.global_position])
	cube.free()

	var fell := []
	var gone := []
	var cube2: Cube = CUBE_SCENE.instantiate()
	root.add_child(cube2)
	await process_frame
	cube2.fell_off.connect(func(k): fell.append(k))
	cube2.despawned.connect(func(k): gone.append(k))
	cube2.spawn_at(Vector2i(6, Feel.GRID_L - 2))
	for i in roll_frames:
		cube2.advance(DT)
	var tipped := cube2.state == Cube.State.FALLING and fell.size() == 1
	var min_y := 1e9
	for i in 300:                                  # 5 s of void fall
		if not is_instance_valid(cube2):
			break
		cube2.advance(DT)
		min_y = minf(min_y, cube2.global_position.y)
	var dead := cube2.state == Cube.State.DEAD and gone.size() == 1 and min_y < Feel.VOID_Y
	await process_frame
	check("cube_tips_off_near_edge_and_despawns_below_void",
		tipped and dead and not is_instance_valid(cube2),
		"tipped=%s dead=%s min_y=%f" % [tipped, dead, min_y])

	var caps := []
	var cube3: Cube = CUBE_SCENE.instantiate()
	root.add_child(cube3)
	await process_frame
	cube3.captured.connect(func(k): caps.append(k))
	cube3.spawn_at(Vector2i(2, 5))
	var accepted := cube3.start_capture()
	var refused_twice := not cube3.start_capture()
	for i in int(ceil(Feel.CAPTURE_FLASH_TIME / DT)) + 1:
		cube3.advance(DT)
	var popped := cube3.state == Cube.State.DEAD
	await process_frame
	check("cube_capture_flashes_pops_and_despawns",
		accepted and refused_twice and caps.size() == 1 and popped \
		and not is_instance_valid(cube3),
		"accepted=%s refused=%s caps=%d popped=%s" % [accepted, refused_twice, caps.size(), popped])

	# ======================= the marker ====================================
	var grid := Grid.new()
	root.add_child(grid)
	await process_frame
	var marker: MarkerFigure = MARKER_SCENE.instantiate()
	root.add_child(marker)
	await process_frame
	marker.setup(grid.can_stand, Vector2i(6, 8))

	var step_ok := marker.step(RollMath.DIR_UP) and marker.cell == Vector2i(6, 7) \
		and marker.facing == RollMath.DIR_UP and marker.ahead_cell() == Vector2i(6, 6) \
		and marker.step(RollMath.DIR_RIGHT) and marker.cell == Vector2i(7, 7) \
		and marker.facing == RollMath.DIR_RIGHT
	for i in int(ceil(Feel.MARKER_STEP_TIME / DT)):
		marker.advance(DT)
	step_ok = step_ok and nearv3(marker.position,
		RollMath.cell_to_world(Vector2i(7, 7)), 0.02) and not marker.is_moving()
	check("marker_steps_faces_and_ahead_tracks", step_ok, str(step_ok))

	for i in 20:
		marker.step(RollMath.DIR_LEFT)             # walk to the west edge
	var west_clamp := marker.cell.x == 0 and not marker.step(RollMath.DIR_LEFT) \
		and marker.cell.x == 0
	for i in 20:
		marker.step(RollMath.DIR_DOWN)             # walk to the near edge
	var south_clamp := marker.cell.y == Feel.GRID_L - 1 \
		and not marker.step(RollMath.DIR_DOWN) and marker.cell.y == Feel.GRID_L - 1
	check("marker_clamps_at_field_edges", west_clamp and south_clamp,
		"west=%s south=%s cell=%s" % [west_clamp, south_clamp, marker.cell])
	marker.free()

	# ======================= the stage: marks + capture ====================
	var main = MAIN_SCENE.instantiate()
	main.spawning = false                            # tests spawn by hand
	main.rng.seed = 20260922
	root.add_child(main)
	await process_frame
	await process_frame
	main.set_process(false)

	var boot_ok: bool = main.grid.mm.instance_count == Feel.GRID_W * Feel.GRID_L \
		and is_instance_valid(main.marker) \
		and main.marker.cell == main.START_CELL \
		and main.env.fog_enabled and nearf(main.env.fog_density, Feel.FOG_DENSITY, 1e-6) \
		and nearf(main.env.background_color.r, Feel.COL_VOID.r, 1e-4) \
		and main.sun.shadow_enabled == false \
		and main.capture_button != null and main.capture_button.is_inside_tree() \
		and main.cubes.size() == 0
	check("boot_smoke_grid_cubes_marker_fog_button", boot_ok,
		"plates=%d fog=%s button=%s" % [main.grid.mm.instance_count,
		main.env.fog_density, main.capture_button != null])
	for i in 3:
		main.spawn_cube()
	check("boot_smoke_three_cubes_on_stage", main.cubes.size() == 3,
		"cubes=%d" % main.cubes.size())

	var ahead: Vector2i = main.marker.ahead_cell()
	var marked_once: bool = main.mark_ahead() and main.grid.is_marked(ahead) \
		and main.grid.marked_count() == 1
	var marked_once_only: bool = not main.mark_ahead() and main.grid.marked_count() == 1
	check("tap_ahead_raises_exactly_one_mark", marked_once and marked_once_only,
		"once=%s only=%s" % [marked_once, marked_once_only])

	var other := Vector2i(2, 4)
	if other == ahead:
		other = Vector2i(3, 4)
	var refused: bool = not main.try_mark(other) and main.grid.marked_count() == 1
	var ray_cell: Vector2i = main.screen_to_cell(
		main.cam.unproject_position(RollMath.cell_to_world(ahead)))
	check("tap_off_ahead_cell_refused_and_ray_roundtrip",
		refused and ray_cell == ahead, "refused=%s ray=%s want=%s" % [refused, ray_cell, ahead])

	var cube_a: Cube = main.spawn_cube(ahead.x)
	cube_a.spawn_at(ahead)                           # resting exactly on the mark
	var n: int = main.do_capture()
	var cap_ok: bool = n == 1 and main.score == Feel.SCORE_PER_GRAY and main.captures == 1 \
		and cube_a.state == Cube.State.CAPTURING \
		and not main.grid.is_marked(ahead) and main.grid.marked_count() == 0 \
		and main.grid.is_row_falling(ahead.y)
	check("capture_pops_cube_over_mark_scores_clears_row", cap_ok,
		"n=%d score=%d state=%d row_falling=%s" % [n, main.score, cube_a.state,
		main.grid.is_row_falling(ahead.y)])

	var cube_b: Cube = main.spawn_cube(9)
	cube_b.spawn_at(Vector2i(9, 5))
	main.grid.set_mark(Vector2i(3, 3))               # a mark nothing stands over
	var spared: bool = main.do_capture() == 0 \
		and cube_b.state == Cube.State.ROLLING \
		and cube_b.current_cell() == Vector2i(9, 5) \
		and main.score == Feel.SCORE_PER_GRAY
	check("capture_spares_cube_not_over_any_mark", spared,
		"spared=%s score=%d" % [spared, main.score])
	main.grid.clear_mark(Vector2i(3, 3))

	var row := ahead.y
	var y0: float = main.grid.row_plate_y(row)
	for i in int(0.4 / DT):
		main.grid.advance(DT)
	var y1: float = main.grid.row_plate_y(row)
	check("capture_drops_the_row_with_tumble",
		main.grid.is_row_falling(row) and y1 < y0 - 0.5,
		"y %f -> %f" % [y0, y1])

	# ======================= swipe / hold input mapping ====================
	var sw_ok := true
	for pair in [[Vector2(0, -1), RollMath.DIR_UP], [Vector2(0, 1), RollMath.DIR_DOWN],
			[Vector2(-1, 0), RollMath.DIR_LEFT], [Vector2(1, 0), RollMath.DIR_RIGHT]]:
		var v: Vector2 = pair[0]
		var s := DragStepper.new()
		s.drag_begin(0.0, 0.0)
		s.push_delta(v.x * Feel.SWIPE_STEP_PX, v.y * Feel.SWIPE_STEP_PX)
		var fired: Array[Vector2i] = s.poll(DT)
		sw_ok = sw_ok and fired.size() == 1 and fired[0] == pair[1]
	var long := DragStepper.new()
	long.drag_begin(0.0, 0.0)
	long.push_delta(0.0, Feel.SWIPE_STEP_PX * 2.5)   # one long downward flick
	var flick: Array[Vector2i] = long.poll(DT)       # frame 1: travel step (54 px still banked)
	var soon: Array[Vector2i] = long.poll(DT)        # frame 2: second travel step
	var late: Array[Vector2i] = long.poll(Feel.MARKER_STEP_REPEAT + DT)  # travel spent -> hold-repeat
	sw_ok = sw_ok and flick.size() == 1 and flick[0] == RollMath.DIR_DOWN \
		and soon.size() == 1 and soon[0] == RollMath.DIR_DOWN \
		and late.size() == 1 and late[0] == RollMath.DIR_DOWN
	check("swipe_synthetic_maps_four_dirs_and_long_drag", sw_ok, str(sw_ok))

	var hold := DragStepper.new()
	hold.drag_begin(0.0, 0.0)
	hold.push_delta(0.0, Feel.SWIPE_STEP_PX)
	var first: Array[Vector2i] = hold.poll(DT)
	var repeats := 0
	var all_down := true
	for i in int(Feel.MARKER_STEP_REPEAT / DT) * 4:  # hold ~0.64 s, no new travel
		var f: Array[Vector2i] = hold.poll(DT)
		repeats += f.size()
		for d in f:
			all_down = all_down and d == RollMath.DIR_DOWN
	check("swipe_hold_repeats_steps", first.size() == 1 and repeats >= 3 and all_down,
		"first=%d repeats=%d" % [first.size(), repeats])

	# the real path: a synthetic 2-cell flick through main.advance moves the
	# marker one cell per frame until the drag travel is spent
	main.stepper.set_mode(DragStepper.MODE_SYNTHETIC)
	var m0: Vector2i = main.marker.cell
	main.stepper.drag_begin(0.0, 0.0)
	main.stepper.push_delta(0.0, Feel.SWIPE_STEP_PX * 2.0)
	main.advance(DT)
	main.advance(DT)
	main.stepper.drag_end()
	check("swipe_drives_marker_through_main_advance", main.marker.cell == m0 + Vector2i(0, 2),
		"cell=%s want=%s" % [main.marker.cell, m0 + Vector2i(0, 2)])

	main.queue_free()
	await process_frame

	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)


## ------------------------------------------------------------------ utils --

func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passes += 1
		print("PASS: " + name)
	else:
		fails += 1
		print("FAIL: " + name + "  (" + detail + ")")


func nearf(a: float, b: float, eps: float) -> bool:
	return absf(a - b) < eps


func nearv3(a: Vector3, b: Vector3, eps: float) -> bool:
	return a.distance_to(b) < eps
