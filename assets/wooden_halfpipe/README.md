# Backyard wooden half-pipe

Original game asset made for Skatepark. Metric units; Godot Y-up, X along the ramp,
Z across it. The origin is at the centre of the flat riding surface.

The existing 1.5 m backyard ramp is replaced by a 1.8 m ramp (30 cm higher).
Its 13.4 m length is unchanged. The riding width is 5 m, with 1.3 m wooden decks,
1.8 m radius transitions, 7.2 m flat bottom, steel coping, timber framing,
and stairs to the right deck. Ten 180 mm rises have nine 300 mm treads.

## Use in this game

`scripts/hub_ramp.gd` places the GLB on the hub's existing `RampPad`. It supplies
one collision mesh to `LevelLoader`. The GLB embeds 9 grind paths: both coping
pipes and the seven top handrails (five around the decks and two beside the
stairs). The same Blender coordinates generate both the rails and their grind markers, including sloped
stair rails. Lower guard bars and vertical posts remain solid supports without
grind paths. The stairs project to local +Z, so the ramp is shifted -0.85 m across the slab to fit the
16 x 9 m pad. A 12 mm elevation prevents overlap with the concrete.

Do not add a second copy manually: `Hub.build_root()` already calls `HubRamp.add_to()`.
The resource paths are strings so a headless editor import must run before tests.

## Use in another Godot 4 project

Copy this folder, then drag `wooden_halfpipe.tscn` into your scene. It contains
visuals and static collision for the ride, decks, stairs, side walls, and guards.
Its GLB also includes the grind metadata; this game discovers it automatically
through `LevelLoader` and `GrindPath.parse()`. Other projects can use the same
markers with their skating system. Concave collision is for a stationary ramp only.

The collision has no invisible vertical wall beneath the coping inside the
transition. Rail and post collisions follow the actual pieces, leaving the gaps
between bars open. Only the top handrails and coping are grind targets. Grind
contact offsets match the upper
surface of each rail, including the pitch of the stairs.
The riding surface is continuous, with no physical gaps at the plywood joints.

## Edit / regenerate

The editable source and studio preview are in `art/wooden_halfpipe/`, excluded
from Godot scanning with `.gdignore`. The `.blend` packs its original textures.
Studio ground, lights and camera are excluded from the game GLB.
Use `-- --no-render` after the Blender command to regenerate assets without
rerendering the studio preview.

From the repository root, using Blender 4.3.2 and Python with NumPy and Pillow:

```sh
python3 tools/make_wood_textures.py
blender -b --factory-startup --python tools/build_halfpipe.py
```

Dimensions are near the top of `tools/build_halfpipe.py`. If changing them,
check the slab footprint. Coping and rail markers regenerate with the model.
The export joins evaluated objects by material into nine meshes;
the Blender source retains individually editable pieces. All game textures
are embedded in the GLB. `dimensions.json` records the actual export budgets.

## Validate

```sh
godot --headless --xr-mode off --path . --editor --import
godot --headless --xr-mode off --path . -s res://tests/halfpipe_logic.gd
godot --headless --xr-mode off --path . -s res://tests/hub_logic.gd
```

The focused test checks imported meshes, static collision, front-face ray hits
on the flat/transitions/decks/stairs, the slab footprint, and the collision height
of every rail. It presses the grind button through the real skating simulation
and checks 50-50s and boardslides in both directions on every one of the 9 paths.
The existing hub suite also exercises rolling and ollies on the transitions.
A real headset is still required to evaluate VR appearance and frame rate.

All ramp geometry and timber textures were generated for this asset. No external
model or texture downloads are required.
