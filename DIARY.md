# cubefall — Project Diary

*Phase-by-phase log. Entries append, never rewrite. Nothing is done until its wall is green twice.*

---
## 2026-09-22 16:20 — Milestone 1 — the grid and the roll

GRID CORE landed: portrait 540x960 gl_compatibility scaffold; feel.gd constants law (GRID 13x17, ROLL 2.2 cells/s, CAMERA 9.5/6.5/52deg, VOID_Y -8, fog 0.02, CUBE_SIZE 0.98); RollMath — 90deg roll about the leading bottom edge (pivot = cell center floor + dir*half, axis = UP x dir), plus a (CELL-CUBE_SIZE)=0.02 compensating slide so cubes land exactly on cell centres; Grid as ONE MultiMesh (221 plates) + rising mark plates + rows that drop with tumble after CAPTURE; Marker code-built low-poly (8x2 capsule + 8x4 sphere + blob quad, no shadows per PSX law), grid steps with clamping, facing = movement dir; Cube gray BoxMesh rolling row after row, tipping off the near edge into tumble+gravity, despawn below VOID_Y; DragStepper (injectable TiltSource-pattern: swipe threshold steps, hold-repeat, dominant-axis mapping, screen up = -Z); main stage with void fog, behind-marker camera + edge dolly-out, tap-ahead mark (classic v1 reach), big bottom-right CAPTURE button, +100 score stub. Gates: --import clean; m1_tests 22/22 x2 consecutive; m1_replay 9/9 (15s: 6+ cubes on beat, 2 captures, sacrificed lane tips into the void, marker never out of bounds); --quit-after 120 = 0 error lines. The battery caught: pure edge-arc advances only 0.98/cell (cubes drifted off-grid 0.02/cell) — landed the corrective slide; Godot 4.7 enum renames (PlaneMesh.FACE_Y, cast_shadow); MultiMesh get_instance_transform reads zero under the dummy renderer (row-drop probe now derives from fall state); GDScript lambdas capture local ints by value (replay fall counter was silently dead); one-step-per-frame drag law (long flick = steps on consecutive frames, then hold-repeat).

## 2026-09-22 23:39 — Milestone 1 — the grid and the roll

The Pipeline's first 3D milestone. The rolling cube math is proven: 90-degree rotation around the leading bottom edge with a drift-compensation slide the battery caught (cube size 0.98 vs cell 1.0 — 0.02 per cell compounds). The marker is code-built (110 triangles, PSX law), the grid is one MultiMesh, the void fog is real. 22/22 green twice. M2 (cube taxonomy + ABSOLUTE) is building.

## 2026-09-22 23:51 — ROADMAP: M2→M4 to itch

Steps: 1) M2 (building now): cube taxonomy (gray/black/green) + waves + ABSOLUTE + field shrink. 2) M3: stages + score + speed ramp + death drama + void-pull camera. 3) M4: PSX pass (320x240 render + vertex wobble + dither + fog) + procedural audio + export. 4) itch page + butler push + critic playtest. 5) Asset pack (cube textures + fog). DONE: M1 green (22 checks), repo live, spec complete with phone law + PSX law + art source law.

## 2026-09-22 23:52 — ROADMAP to itch

1) M2 (building): cube law + ABSOLUTE. 2) M3: stages + score + death drama. 3) M4: PSX pass + audio + export + itch + critic. DONE: M1 green (22 checks), first 3D milestone.

