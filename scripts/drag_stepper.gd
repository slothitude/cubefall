class_name DragStepper
extends RefCounted
## THE injectable input abstraction for grid stepping (TiltSource pattern).
## ALL marker movement flows through here: real touch drags, a synthetic
## feeder for CI/tests, or WASD/arrows — no scene or phone required.
##
## Pipeline: anchor the drag -> accumulate finger travel -> each
## Feel.SWIPE_STEP_PX of travel fires one step along the dominant screen
## axis (and advances the anchor, so one long drag = several steps).
## Holding past Feel.MARKER_STEP_REPEAT with no new travel repeats the last
## step (input repeat on hold). Screen up = away from camera (-Z).

const MODE_TOUCH := "touch"
const MODE_SYNTHETIC := "synthetic"

var mode: String = MODE_TOUCH
var step_px: float = Feel.SWIPE_STEP_PX
var repeat_delay: float = Feel.MARKER_STEP_REPEAT

var _active := false
var _anchor := Vector2.ZERO
var _pos := Vector2.ZERO
var _travel := 0.0                     # total excursion since touch began (tap test)
var _held_dir := Vector2i.ZERO
var _repeat_t := 0.0
var _steps_fired := 0


# ------------------------------------------------------------------ feeding --

func drag_begin(x: float, y: float) -> void:
	_active = true
	_anchor = Vector2(x, y)
	_pos = _anchor
	_travel = 0.0
	_held_dir = Vector2i.ZERO
	_repeat_t = 0.0


func drag_move(x: float, y: float) -> void:
	if not _active:
		drag_begin(x, y)
		return
	var p := Vector2(x, y)
	_travel = maxf(_travel, (p - _anchor).length())
	_pos = p


func drag_end() -> void:
	_active = false
	_held_dir = Vector2i.ZERO
	_repeat_t = 0.0


## Synthetic feeder — what CI/tests use. Never needs a phone or a screen.
func push_delta(dx: float, dy: float) -> void:
	if not _active:
		drag_begin(0.0, 0.0)
	drag_move(_pos.x + dx, _pos.y + dy)


## Synthetic tap: no drag excursion, just a touch that lands.
func push_tap() -> void:
	drag_end()


# ------------------------------------------------------------------ reading --

## Steps fired this frame, in order. Call once per frame from the owner.
func poll(dt: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not _active:
		return out
	var delta := _pos - _anchor
	if delta.length() >= step_px:
		var dir := dominant_dir(delta)
		out.append(dir)
		_anchor += Vector2(float(dir.x), float(dir.y)) * step_px
		_travel = maxf(0.0, _travel - step_px)
		_held_dir = dir
		_repeat_t = 0.0
		_steps_fired += 1
	elif _held_dir != Vector2i.ZERO:
		_repeat_t += dt
		if _repeat_t >= repeat_delay:
			out.append(_held_dir)
			_repeat_t = 0.0
			_steps_fired += 1
	return out


## Dominant screen axis of a raw delta, as a grid dir (screen up = -Z).
static func dominant_dir(delta: Vector2) -> Vector2i:
	if absf(delta.x) >= absf(delta.y):
		return Vector2i(1 if delta.x > 0.0 else -1, 0)
	return Vector2i(0, 1 if delta.y > 0.0 else -1)


func held_dir() -> Vector2i:
	return _held_dir if _active else Vector2i.ZERO


func is_active() -> bool:
	return _active


func travel_px() -> float:
	return _travel


func steps_fired() -> int:
	return _steps_fired


func set_mode(new_mode: String) -> void:
	mode = new_mode
	drag_end()
