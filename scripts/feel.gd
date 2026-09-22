class_name Feel
## CUBEFALL — every grid/roll/marker/capture number lives here.
## Spec law "constants_not_magic": no tuned number anywhere else in the project.
## M1 = GRID CORE: the grid, the roll, the marker, one capture.
## M2+ blocks are reserved below (cube taxonomy, waves, field shrink, PSX pass).

# ------------------------------------------------------------------ the grid --
const GRID_W := 13                     # cells across (x)
const GRID_L := 17                     # cells deep (z); z=0 is the FAR row, z=GRID_L-1 the NEAR edge
const CELL := 1.0                      # world units per cell

# ------------------------------------------------------------------ the roll --
const ROLL_CELLS_PER_SEC := 2.2        # spec roll law speed
const ROLL_DURATION := 1.0 / ROLL_CELLS_PER_SEC   # seconds for one 90-degree cell roll
const CUBE_SIZE := 0.98                # slight gap against CELL so the grid reads through

# ---------------------------------------------------------------- the marker --
const MARKER_STEP_TIME := 0.12         # seconds per cell step tween
const MARK_RISE_TIME := 0.18           # mark plate rise animation
const MARK_RISE_HEIGHT := 0.10         # how far the mark plate rises above the floor
const CAPTURE_FLASH_TIME := 0.35       # white flash + shrink-pop duration

# ------------------------------------------------------------------ the void --
const VOID_Y := -8.0                   # below this, things are gone (despawn)
const FALL_GRAVITY := 22.0             # void fall acceleration (cubes, plates)
const FALL_TUMBLE_SPEED := 5.0         # rad/s tumble while falling

# ---------------------------------------------------------------- the camera --
const CAMERA_HEIGHT := 9.5             # elevated behind-the-marker follow
const CAMERA_BACK := 6.5               # cells back along +Z from the marker
const CAMERA_TILT_DEG := 52.0          # pitch: wave horizon sits in the top third
const GRID_DOLLY_MAX := 0.14           # max dolly-out (fraction) as the marker nears edges

# ------------------------------------------------------------- phone controls --
const SWIPE_STEP_PX := 36.0            # drag travel that fires one step
const MARKER_STEP_REPEAT := 0.16       # hold-repeat interval after the first step
const TAP_SLOP_PX := 18.0              # max finger excursion that still counts as a tap
const TAP_MAX_SEC := 0.35              # max touch duration that still counts as a tap

# ------------------------------------------------------------------ the beat --
const SPAWN_BEAT_SEC := 2.4            # M1: slow beat, 3 gray cubes on screen
const SPAWN_START_DELAY := 0.8

# --------------------------------------------------------------- psx palette --
const COL_VOID := Color(0.0196, 0.0275, 0.0471, 1.0)     # #05070c dark void
const COL_FOG := Color(0.043, 0.059, 0.098, 1.0)         # fog eats the horizon
const COL_PLATE := Color(0.243, 0.267, 0.302, 1.0)       # steel-gray floor plates
const COL_PLATE_EDGE := Color(0.106, 0.122, 0.145, 1.0)  # the gaps between plates
const COL_CUBE_GRAY := Color(0.604, 0.639, 0.678, 1.0)   # normal cube
const COL_MARK := Color(0.49, 0.976, 1.0, 1.0)           # mark plate glow
const COL_MARKER := Color(0.56, 0.97, 1.0, 1.0)          # the Marker's emissive body
const COL_FLASH := Color(1.0, 1.0, 1.0, 1.0)             # capture flash
const FOG_DENSITY := 0.02                                # spec fog

# ============================================================================
# M2 — CUBE LAW: the gray/black/green taxonomy, waves, field shrink, ABSOLUTE.
# ============================================================================

# ---- cube taxonomy (spec systems.cubes) ----
const CUBE_GRAY := "gray"              # normal — capture for score; escape SHRINKS the field
const CUBE_BLACK := "black"            # forbidden — capturing one is instant game over
const CUBE_GREEN := "green"            # advantage — capture marks a 3x3 area
const GREEN_AREA_SPAN := 1             # 3x3 = the green's cell +/- span
const GREEN_AREA_CELLS := 9            # (2*span+1)^2 — the area a green capture marks

# ---- score (spec systems.score) ----
const SCORE_PER_GRAY := 100
const SCORE_PER_GREEN := 250           # capturing the green cube itself
const SCORE_GREEN_AREA := 150          # first capture inside a green's 3x3, per green
const SCORE_ABSOLUTE := 1000           # perfect clear of a whole wave
const WAVE_CLEAR_BASE := 100           # wave_clear_bonus = wave# * this

# ---- waves (spec roll.waves + score.stage_clear) ----
const ROWS_PER_WAVE := 3               # rows spawned per wave
const ROW_CUBE_CHANCE := 0.34          # chance any column of a row holds a cube
const WEIGHT_GRAY := 0.70              # type weights over a rolled cube (sum = 1)
const WEIGHT_BLACK := 0.16
const WEIGHT_GREEN := 0.14
const WAVES_PER_STAGE := 5             # survive N waves = stage clear
const WAVE_BEAT_ACCEL := 0.94          # per-stage beat multiplier
const BLACK_WEIGHT_PER_STAGE := 0.04   # more blacks each stage (taken from gray)

# ---- field shrink / regrow (spec systems.grid) ----
const FIELD_SHRINK_ROWS := 1           # rows lost per escaped gray cube
const FIELD_MIN_ROWS := 4              # below this the field is lost = game over
const REGROW_ROWS := 1                 # rows restored per green-area capture

# ---- ABSOLUTE (spec capture.perfect_clear) ----
const CHAIN_POP_STAGGER := 0.07        # s between chain-reaction pops
const ABSOLUTE_LABEL_TIME := 1.6       # s the ABSOLUTE banner holds

# ---- death / drama (spec systems.death) ----
const DEATH_FLASH_TIME := 0.55         # red screen flash before the overlay
const DEATH_FLASH_COLOR := Color(0.55, 0.06, 0.06, 1.0)
const TOAST_TIME := 1.4                # stage-clear toast

# ---- psx palette additions (spec psx_law.palette) ----
const COL_CUBE_BLACK := Color(0.043, 0.043, 0.055, 1.0)  # matte black, forbidden
const COL_CUBE_GREEN := Color(0.075, 0.412, 0.196, 1.0)  # deep green, advantage
const COL_MARK_AREA := Color(0.29, 0.94, 0.42, 1.0)      # green-area mark plates
const COL_DANGER := Color(0.55, 0.06, 0.06, 1.0)         # death flash
const COL_ABSOLUTE := Color(1.0, 0.92, 0.55, 1.0)        # ABSOLUTE banner gold

# ---- M4 PSX pass reserved (spec psx_law) ----
const PSX_RENDER_W := 320
const PSX_RENDER_H := 240
const PSX_SNAP_GRID := 160.0           # vertex snap target
