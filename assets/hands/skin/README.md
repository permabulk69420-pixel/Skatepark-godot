# Fitted hand skin

CC0 MakeHuman skin colour, fitted separately to the existing left and right hand
UV atlases. The game hand meshes, bone weights, animations and grip solution are
unchanged. There is still one material per hand.

The original `young_lightskinned_male_diffuse.png` is a MakeHuman skin atlas with
palm, fingernail and knuckle detail. It is **not** a complete scanned PBR set.
The roughness maps and very shallow micro-normal maps here are authored during
baking: palms are more matte, nail plates are smoother, and the pore detail is
kept small enough to avoid the old sandpaper effect. The material uses the skin
colour directly, without multiplying it by another skin tone or tiling it.

Source attribution, exact URLs, source commit and SHA256 hashes are in
`source.json`. The MakeHuman material explicitly declares the texture CC0;
`LICENSE-CC0.txt` includes the source project's asset license. The MakeHuman
program's AGPL code is not part of this game.

## Reproduce

From the repository root, with Python 3.11+ and Blender 4.3.2:

```sh
python3 tools/hands/fetch_skin_sources.py /workspace/hand-work
blender -b --factory-startup --python tools/hands/bake_skin.py -- --side left --source-dir /workspace/hand-work
blender -b --factory-startup --python tools/hands/bake_skin.py -- --side right --source-dir /workspace/hand-work
```

The fetcher verifies every input. The CC0 archive is about 404 MiB and is cached;
only one source skin is extracted. The baker uses the source's joint landmarks
and skin weights to align a temporary source hand, then bakes onto the existing
game UVs. It never rewrites either GLB. `--save-debug` saves the registration scene
in the source cache for inspection. Blender's temporary subdivision increases
sampling density only; it is not added to the game mesh.

Colour atlases are 1024 x 1024; normals and roughness are 512 x 512. The `.import`
files enable mipmaps and GPU compression, including the project's mobile ETC2
output, with normal-map import enabled for the normal textures.

## Validate / inspect

```sh
godot --headless --xr-mode off --path . --editor --import
godot --headless --xr-mode off --path . -s res://tests/hands_logic.gd
```

`tests/hands_shot.gd` renders the existing hand poses and board grabs.
`tests/hand_material_shot.gd` renders close-ups from both sides, a grip/fist, and
the hands in the actual Gravesend photogrammetry level. It needs an OpenGL
session; a virtual display with Mesa software rendering works:

```sh
mkdir -p /tmp/hand-material-shots
xvfb-run -a godot --path . --xr-mode off --audio-driver Dummy --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tests/hand_material_shot.gd -- /tmp/hand-material-shots
```

The old JPEG maps are retained as source history but are no longer used by the
hand material. This update improves the surface; the original low-poly silhouette
remains. A real headset is needed to judge the final appearance at headset scale.
