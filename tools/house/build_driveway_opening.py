"""Cut the driveway opening without re-exporting the house or its textures.

blender -b --factory-startup --python tools/house/build_driveway_opening.py
The small GLB carries replacement fence/collision geometry; Godot reuses the
original fence material. Everything else in hub.glb remains untouched.
"""
from pathlib import Path
import bpy
import bmesh

ROOT = Path(__file__).resolve().parents[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT / 'assets/levels/hub.glb'))
names = {
    'Boundary_Timber_Weathered_Structure': 'Boundary_OpenDriveway',
    'COL_Walls': 'COL_OpenDrivewayBoundary',
}
selected = []
for source, target in names.items():
    obj = bpy.data.objects[source]
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    # Blender axes: X east, Y north, Z up. Split at all opening boundaries
    # first, so even a collision triangle spanning the whole fence is cut.
    for axis, value in [(0, -15.1), (0, -9.9), (1, -12.3), (1, -11.7)]:
        point, normal = [0., 0., 0.], [0., 0., 0.]
        point[axis], normal[axis] = value, 1.
        bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                              dist=0.00001, plane_co=point, plane_no=normal)
    removed = [f for f in bm.faces if -15.10001 < f.calc_center_median().x < -9.89999
               and -12.30001 < f.calc_center_median().y < -11.69999]
    assert removed, f'Opening did not intersect {source}'
    bmesh.ops.delete(bm, geom=removed, context='FACES')
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.materials.clear()
    obj.name = target
    if source == 'COL_Walls':
        obj['role'] = 'collision'
    selected.append(obj)
    print(f'{source}: removed {len(removed)} faces')
bpy.ops.object.select_all(action='DESELECT')
for obj in selected:
    obj.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=str(ROOT / 'assets/driveway/fence_opening.glb'),
    export_format='GLB', use_selection=True, export_yup=True,
    export_extras=True, export_cameras=False, export_lights=False,
    export_animations=False, export_materials='NONE',
)
