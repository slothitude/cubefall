extends SceneTree
## Milestone 2 battery — CUBE LAW. Run headless:
##   godot --headless --script res://tests/m2_tests.gd
## Covers: the gray/black/green taxonomy materials; gray capture scoring;
## green capture (+250, the 3x3 blessing, bonus + regrow on the area capture,
## consumed once); black capture = instant game over + the death overlay +
## RETRY; escapes (black free, gray shrinks the field, green resolves without
## shrink); the wave completeness law (blacks excluded, spare-able) + the
## ABSOLUTE (fires on an all-captured wave, voided by one escape, 1000 +
## wave#x100 clear bonus, chain spares blacks and never re-scores); stage
## progression (beat accel, more blacks); rows on the beat; field-min and
## void deaths; the HUD.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const CUBE_SCENE := preload("res://scenes/cube.tscn")
const DT := 1.0 / 60.0

var passes := 0
var fails := 0
var main
var go_log: Array = []                 # game_over causes
var abs_log: Array = []                # absolute_fired waves
var cleared_log: Array = []            # [wave, absolute] pairs
var stage_log: Array = []              # stage_cleared stages
var shrink_log: Array = []             # field_shrank rows_left
var regrew_log: Array = []             # field_regrew rows_left
var started_log: Array = []            # wave_started [wave, stage]


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.set_process(false)
	main.rng.seed = 20260923
	_wire()
	fresh()

	# ===================== the taxonomy: materials =========================
	var cg: Cube = CUBE_SCENE.instantiate()
	root.add_child(cg)
	var cb: Cube = CUBE_SCENE.instantiate()
	cb.setup(Feel.CUBE_BLACK)          # lawful before the tree, too
	root.add_child(cb)
	await process_frame
	var cgn: Cube = CUBE_SCENE.instantiate()
	root.add_child(cgn)
	cgn.setup(Feel.CUBE_GREEN)         # and after it
	await process_frame
	var mat_g := (cg.mesh.mesh as BoxMesh).material as StandardMaterial3D
	var mat_b := (cb.mesh.mesh as BoxMesh).material as StandardMaterial3D
	var mat_n := (cgn.mesh.mesh as BoxMesh).material as StandardMaterial3D
	var tax_ok: bool = (nearc(mat_g.albedo_color, Feel.COL_CUBE_GRAY) and mat_g.metallic > 0.05
		and nearc(mat_b.albedo_color, Feel.COL_CUBE_BLACK)
		and mat_b.metallic == 0.0 and not mat_b.emission_enabled
		and nearc(mat_n.albedo_color, Feel.COL_CUBE_GREEN) and mat_n.emission_enabled
		and cb.law == Feel.CUBE_BLACK and cgn.law == Feel.CUBE_GREEN
		and cb.law_color() == Feel.COL_CUBE_BLACK)
	check("cube_taxonomy_materials_three_laws", tax_ok,
		"g=%s b=%s n=%s" % [mat_g.albedo_color, mat_b.albedo_color, mat_n.albedo_color])
	var m1_gray: Cube = main.spawn_cube(3)      # the M1 spawner stays gray
	var m1_ok: bool = (m1_gray.law == Feel.CUBE_GRAY
		and nearc((m1_gray.mesh.mesh as BoxMesh).material.albedo_color,
			Feel.COL_CUBE_GRAY))
	check("m1_spawn_path_stays_gray", m1_ok, m1_gray.law)
	cg.free()
	cb.free()
	cgn.free()
	m1_gray.queue_free()

	# ===================== scoring: gray, green, area ======================
	fresh()
	var ahead: Vector2i = main.marker.ahead_cell()
	main.mark_ahead()
	var gray_a := drop(Feel.CUBE_GRAY, ahead)
	var n: int = main.do_capture()
	check("gray_capture_scores_100", (n == 1 and main.score == Feel.SCORE_PER_GRAY
		and main.captures == 1 and main._wg_resolved == 1
		and main.score_label.text.contains("SCORE 100")),
		"n=%d score=%d" % [n, main.score])

	fresh()
	var gcell := Vector2i(6, 8)
	main.grid.set_mark(gcell)
	drop(Feel.CUBE_GREEN, gcell)
	main.do_capture()
	var area_ok: bool = (main.score == Feel.SCORE_PER_GREEN
		and main.grid.marked_count() == Feel.GREEN_AREA_CELLS
		and main.grid.area_mark_count() == Feel.GREEN_AREA_CELLS
		and main._area_pending == 1
		and main.grid.is_row_falling(gcell.y)
		and main.grid.solid_rows() == Feel.GRID_L - 1)          # the capture ate its row
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			area_ok = area_ok and main.grid.is_marked(gcell + Vector2i(dx, dy))
	check("green_capture_scores_250_marks_3x3_area", area_ok,
		"score=%d marks=%d solid=%d" % [main.score, main.grid.marked_count(),
		main.grid.solid_rows()])

	# area capture: shrink first so the regrow has a row to bring back
	main.shrink_field()
	for i in int(0.9 / DT):
		main.advance(DT)               # rows 8 and 16 sink below VOID_Y -> gone
	var solid_before: int = main.grid.solid_rows()              # 15
	drop(Feel.CUBE_GRAY, gcell + Vector2i(-1, -1))              # (5,7): blessed cell
	main.do_capture()
	var bonus_ok: bool = (main.score == Feel.SCORE_PER_GREEN + Feel.SCORE_PER_GRAY
		+ Feel.SCORE_GREEN_AREA
		and main.grid.is_row_gone(Feel.GRID_L - 1) == false        # regrow restored it
		and main.grid.solid_rows() == solid_before                 # -1 fell, +1 regrew
		and main._area_pending == 0 and regrew_log.size() == 1)
	check("area_capture_pays_bonus_and_regrows_field", bonus_ok,
		"score=%d solid=%d gone16=%s" % [main.score, main.grid.solid_rows(),
		main.grid.is_row_gone(Feel.GRID_L - 1)])

	drop(Feel.CUBE_GRAY, gcell + Vector2i(0, 1))                # (6,9): blessed, spent
	main.do_capture()
	check("area_bonus_consumed_once_per_green",
		(main.score == Feel.SCORE_PER_GREEN + Feel.SCORE_PER_GRAY
			+ Feel.SCORE_GREEN_AREA + Feel.SCORE_PER_GRAY
		and main.grid.solid_rows() == solid_before - 1 and regrew_log.size() == 1),
		"score=%d solid=%d" % [main.score, main.grid.solid_rows()])

	# ===================== death: the black cube ===========================
	fresh()
	main.mark_ahead()
	var black := drop(Feel.CUBE_BLACK, main.marker.ahead_cell())
	var n_black: int = main.do_capture()
	var death_ok: bool = (n_black == 0 and main.score == 0 and go_log == ["forbidden"]
		and not main.spawning and black.state == Cube.State.ROLLING
		and not main.overlay.visible)                 # drama first: flash, then overlay
	for i in int((Feel.DEATH_FLASH_TIME + 0.15) / DT):
		main.advance(DT)
	death_ok = death_ok and main.overlay.visible \
		and main.overlay_title.text == "CUBE FALL" \
		and main.overlay_info.text.contains("SCORE 0")
	check("black_capture_is_instant_game_over", death_ok,
		"n=%d cause=%s overlay=%s" % [n_black, str(go_log), main.overlay.visible])

	# ===================== RETRY ============================================
	main.retry()
	check("retry_resets_the_run", (main.score == 0 and main.wave == 1 and main.stage == 1
		and main.grid.solid_rows() == Feel.GRID_L
		and main.marker.cell == main.START_CELL and main.spawning
		and not main.overlay.visible and not main._dead and main.cubes.is_empty()),
		"score=%d wave=%d solid=%d dead=%s" % [main.score, main.wave,
		main.grid.solid_rows(), main._dead])

	# ============== escapes: black free / gray bites / green quiet ==========
	fresh()
	drop(Feel.CUBE_BLACK, Vector2i(2, Feel.GRID_L - 1))
	for i in int(1.6 / DT):
		main.advance(DT)
	var any_black := false
	for c in main.cubes:
		if c.law == Feel.CUBE_BLACK:
			any_black = true
	check("black_escape_is_free_no_shrink", (main.grid.solid_rows() == Feel.GRID_L
		and shrink_log.is_empty() and main._wg_resolved == 0 and main._wg_escaped == 0
		and not any_black),
		"solid=%d resolved=%d" % [main.grid.solid_rows(), main._wg_resolved])

	drop(Feel.CUBE_GRAY, Vector2i(4, Feel.GRID_L - 1))
	for i in int(0.6 / DT):
		main.advance(DT)               # the tip lands, the bite is falling
	var gray_bit: bool = (main.grid.solid_rows() == Feel.GRID_L - Feel.FIELD_SHRINK_ROWS
		and shrink_log == [Feel.GRID_L - 1] and main._wg_resolved == 1
		and main._wg_escaped == 1 and main.grid.is_row_falling(Feel.GRID_L - 1))
	for i in int(1.9 / DT):
		main.advance(DT)               # the bitten row finishes falling away
	gray_bit = gray_bit and main.grid.is_row_gone(Feel.GRID_L - 1)
	check("gray_escape_shrinks_the_field", gray_bit,
		"solid=%d shrinks=%s" % [main.grid.solid_rows(), str(shrink_log)])

	drop(Feel.CUBE_GREEN, Vector2i(5, Feel.GRID_L - 1))
	for i in int(1.6 / DT):
		main.advance(DT)
	check("green_escape_resolves_without_shrink", (main._wg_resolved == 2
		and main._wg_escaped == 2 and main.grid.solid_rows() == Feel.GRID_L - 1
		and shrink_log.size() == 1),
		"solid=%d escaped=%d" % [main.grid.solid_rows(), main._wg_escaped])

	# ===================== the ABSOLUTE + wave completeness =================
	fresh()
	for i in Feel.ROWS_PER_WAVE:
		main.note_wave_row()
	drop(Feel.CUBE_GRAY, Vector2i(3, 8))
	drop(Feel.CUBE_GRAY, Vector2i(9, 8))
	drop(Feel.CUBE_GREEN, Vector2i(6, 8))
	var black_spare := drop(Feel.CUBE_BLACK, Vector2i(1, 10))
	main.grid.set_mark(Vector2i(3, 8))
	main.grid.set_mark(Vector2i(9, 8))
	main.grid.set_mark(Vector2i(6, 8))
	main.do_capture()
	var absolute_ok: bool = (abs_log == [1] and cleared_log == [[1, true]]
		and main.score == (Feel.SCORE_PER_GRAY * 2 + Feel.SCORE_PER_GREEN
			+ Feel.SCORE_ABSOLUTE + Feel.WAVE_CLEAR_BASE * 1)
		and black_spare.state == Cube.State.ROLLING   # blacks: excluded, spared
		and main.banner_label.visible and main._absolute_t > 0.0
		and main.wave == 2)
	check("absolute_fires_when_all_gray_green_captured", absolute_ok,
		"abs=%s cleared=%s score=%d black=%d" % [str(abs_log), str(cleared_log),
		main.score, black_spare.state])

	fresh()
	for i in Feel.ROWS_PER_WAVE:
		main.note_wave_row()
	drop(Feel.CUBE_GRAY, Vector2i(3, 9))
	drop(Feel.CUBE_GRAY, Vector2i(5, Feel.GRID_L - 1))          # the escape voids it
	main.grid.set_mark(Vector2i(3, 9))
	main.do_capture()
	for i in int(1.6 / DT):
		main.advance(DT)
	check("escape_voids_absolute_wave_clear_still_pays", (abs_log.is_empty()
		and cleared_log == [[1, false]]
		and main.score == Feel.SCORE_PER_GRAY + Feel.WAVE_CLEAR_BASE * 1
		and main.wave == 2
		and main.grid.solid_rows() == Feel.GRID_L - 2),   # mark row + bitten row
		"abs=%s cleared=%s score=%d" % [str(abs_log), str(cleared_log), main.score])

	fresh()
	main.wave = 3
	main.begin_wave()
	for i in Feel.ROWS_PER_WAVE:
		main.note_wave_row()
	drop(Feel.CUBE_GRAY, Vector2i(4, 8))
	main.grid.set_mark(Vector2i(4, 8))
	main.do_capture()
	check("wave_clear_bonus_scales_with_wave_number", (cleared_log == [[3, true]]
		and main.score == (Feel.SCORE_PER_GRAY + Feel.SCORE_ABSOLUTE
			+ Feel.WAVE_CLEAR_BASE * 3)),
		"cleared=%s score=%d" % [str(cleared_log), main.score])

	# ===================== stage progression ================================
	fresh()
	var beat_before: float = main.current_beat()
	var bw_before: float = main.black_weight()
	main.wave = Feel.WAVES_PER_STAGE
	main.begin_wave()
	for i in Feel.ROWS_PER_WAVE:
		main.note_wave_row()
	drop(Feel.CUBE_GRAY, Vector2i(3, 9))
	drop(Feel.CUBE_GRAY, Vector2i(5, Feel.GRID_L - 1))
	main.grid.set_mark(Vector2i(3, 9))
	main.do_capture()
	for i in int(1.6 / DT):
		main.advance(DT)
	var stage_ok: bool = (stage_log == [2] and main.stage == 2 and main.wave == 1
		and main.score == (Feel.SCORE_PER_GRAY
			+ Feel.WAVE_CLEAR_BASE * Feel.WAVES_PER_STAGE)
		and main.current_beat() < beat_before and main.black_weight() > bw_before
		and abs_log.is_empty())
	check("survive_waves_clears_the_stage", stage_ok,
		"stage=%d beat %f -> %f bw %f -> %f" % [main.stage, beat_before,
		main.current_beat(), bw_before, main.black_weight()])

	# ===================== rows on the beat =================================
	fresh()
	main.spawning = true
	main.rng.seed = 20260923
	var rolling_laws := 0
	for i in int(7.0 / DT):
		main.advance(DT)
	for c in main.cubes:
		if c.law != Feel.CUBE_BLACK:
			rolling_laws += 1
	check("wave_rows_spawn_on_the_beat", (main._rows_spawned == Feel.ROWS_PER_WAVE
		and rolling_laws == main._wg_spawned and main.cubes.size() >= 6
		and main._wg_resolved == 0 and cleared_log.is_empty()
		and started_log.is_empty()),
		"rows=%d cubes=%d wg=%d" % [main._rows_spawned, main.cubes.size(),
		main._wg_spawned])
	var clears_before := cleared_log.size()
	for i in int(6.0 / DT):
		main.advance(DT)               # long past the wave's rows: the cap holds
		                              # and the wave completes on escapes alone
	check("wave_spawns_only_its_rows", (main._rows_spawned <= Feel.ROWS_PER_WAVE
		and cleared_log.size() > clears_before),
		"rows=%d clears=%d" % [main._rows_spawned, cleared_log.size()])

	# ===================== death: field minimum =============================
	fresh()
	var field_dead := false
	for i in Feel.GRID_L + 2:
		main.shrink_field()
		if not go_log.is_empty():
			field_dead = (go_log == ["field"]
				and main.grid.solid_rows() == Feel.FIELD_MIN_ROWS - 1
				and not main.spawning)
			break
	check("field_minimum_is_death", field_dead,
		"cause=%s solid=%d" % [str(go_log), main.grid.solid_rows()])

	# ===================== death: the void under a fallen row ===============
	fresh()
	main.step_marker(RollMath.DIR_DOWN)
	main.step_marker(RollMath.DIR_DOWN)                # marker stands on the near edge
	main.shrink_field()                                # its row falls away
	main.advance(DT)                                   # the stage notices the void
	var fell_early: bool = main.marker.is_falling()
	for i in int(1.2 / DT):
		main.advance(DT)
	check("marker_on_fallen_row_falls_into_void", (fell_early and go_log == ["void"]
		and main.marker.position.y < Feel.VOID_Y),
		"falling=%s cause=%s y=%f" % [fell_early, str(go_log),
		main.marker.position.y])

	# ===================== the HUD ==========================================
	fresh()
	for i in Feel.ROWS_PER_WAVE:
		main.note_wave_row()
	drop(Feel.CUBE_GRAY, Vector2i(3, 9))
	drop(Feel.CUBE_GRAY, Vector2i(5, Feel.GRID_L - 1))
	main.grid.set_mark(Vector2i(3, 9))
	main.do_capture()
	for i in int(1.6 / DT):
		main.advance(DT)
	var hud: String = main.score_label.text
	check("hud_reflects_run_state", (hud.contains("SCORE 200") and hud.contains("WAVE 2")
		and hud.contains("ROWS %d" % main.grid.solid_rows()) and hud.contains("CUBES 0")),
		hud.replace("\n", " | "))

	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)


## ------------------------------------------------------------------ helpers --

## A fresh run: retry wipes score/waves/field, tests turn the beat spawner off.
func fresh() -> void:
	main.retry()
	main.spawning = false
	go_log.clear()
	abs_log.clear()
	cleared_log.clear()
	stage_log.clear()
	shrink_log.clear()
	regrew_log.clear()
	started_log.clear()


## Spawn a cube of `law` straight into the open wave, resting at `cell`.
func drop(law: String, cell: Vector2i) -> Cube:
	var cube: Cube = main.spawn_wave_cube(law, cell.x)
	cube.spawn_at(cell)
	return cube


func _wire() -> void:
	main.game_over.connect(func(cause: String): go_log.append(cause))
	main.absolute_fired.connect(func(w: int): abs_log.append(w))
	main.wave_cleared.connect(func(w: int, absolute: bool):
		cleared_log.append([w, absolute]))
	main.stage_cleared.connect(func(s: int): stage_log.append(s))
	main.field_shrank.connect(func(r: int): shrink_log.append(r))
	main.field_regrew.connect(func(r: int): regrew_log.append(r))
	main.wave_started.connect(func(w: int, s: int): started_log.append([w, s]))


func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passes += 1
		print("PASS: " + name)
	else:
		fails += 1
		print("FAIL: " + name + "  (" + detail + ")")


func nearf(a: float, b: float, eps: float) -> bool:
	return absf(a - b) < eps


func nearc(a: Color, b: Color) -> bool:
	return nearf(a.r, b.r, 0.001) and nearf(a.g, b.g, 0.001) and nearf(a.b, b.b, 0.001)
