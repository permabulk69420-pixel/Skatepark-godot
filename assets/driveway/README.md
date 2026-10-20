# Backyard driveway and open gate

`HubDriveway.add_to` adds a 4.8 m wide worn-concrete driveway on the west side of
the house. It extends six metres outside the front fence, then turns behind
the house to join the half-pipe slab. Contraction joints are visual only; the
riding surface is continuous. Two timber/steel gates stand open 105 degrees
outwards. Gates and posts have collision; no grind paths are added.
The existing exterior dirt terrain also receives collision so stepping off the
paving outside the gate does not fall through the scenery.

The original house GLB is preserved. `fence_opening.glb` supplies replacement
boundary render/collision meshes with a 5.2 m opening at x=-12.5, north=-12 m.
All other house meshes and markers remain in the original asset. The replacement
fence and new gate reuse the original timber material.

Regenerate the opening after changing the house model:

```sh
blender -b --factory-startup --python tools/house/build_driveway_opening.py
```

Concrete: [Concrete Floor Worn 001](https://polyhaven.com/a/concrete_floor_worn_001)
from Poly Haven, CC0 1.0. Download URLs and SHA-256 checksums are in `source.json`.
The unmodified 2K albedo, OpenGL normal and packed AO/roughness/metalness maps
are imported with GPU compression and mipmaps. Roughness uses the green channel;
AO and metallic channels are unused. The material repeats every three metres.
CC0 legal text is in `LICENSE-CC0.txt`.

Validation: `godot --headless --xr-mode off -s res://tests/driveway_logic.gd`.
Render the real hub with `tests/driveway_shot.gd`; previews live in
`art/driveway/`, excluded from game exports.
