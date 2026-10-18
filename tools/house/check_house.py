"""Independent GLB re-import checks. blender -b -P check_house.py
All distances in Blender Z-up metres after glTF import. No source .blend used.
"""
import bpy, math, json, sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
import numpy as np
ROOT=Path(__file__).resolve().parent
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'skater_house.glb'))
S=bpy.context.scene;results=[]
def check(name,fn):
    try:
        detail=fn();results.append({'check':name,'pass':True,'detail':detail});print('PASS:',name,detail or '')
    except Exception as e:
        results.append({'check':name,'pass':False,'detail':str(e)});print('FAIL:',name,str(e))
def require(v,msg):
    if not v:raise AssertionError(msg)
def triangles(obj):
    obj.data.calc_loop_triangles()
    return [tuple(obj.matrix_world@obj.data.vertices[i].co for i in t.vertices) for t in obj.data.loop_triangles]
meshes=[o for o in S.objects if o.type=='MESH'];render=[o for o in meshes if not o.name.startswith('COL_')];cols=[o for o in meshes if o.name.startswith('COL_')]
expected={'Spawn_Hub':('spawn',(0,-3,.3),{'heading_radians':0.0}),'Remote_Spot':('remote_spot',(-4.4,0,.75),{}),'RampPad':('ramp_pad',(1,19.5,0),{'heading_radians':-1.5708,'pad_length':16.0,'pad_width':9.0})}
for row,z in enumerate([1.25,2.1]):
 for j,y in enumerate([-1.25,-.75,-.25,.25,.75,1.25]):expected['BoardSlot_%02d'%(1+j+row*6)]=('board_slot',(6.95,y,z),{'heading_radians':1.5708})
lamps=[(-4,-2.2,2.84),(-4,2.2,2.84),(2,-2.8,2.85),(4.6,0,3.10),(2,2.8,2.85),(1,6.25,2.91)]
for i,p in enumerate(lamps,1):expected['Light_%02d'%i]=('light',p,{})
def markers():
 for n,(role,p,props) in expected.items():
    o=S.objects.get(n);require(o is not None,'Missing '+n);require(o.type=='EMPTY',n+' must be empty');require(o.get('role')==role,n+' role lost');require((o.matrix_world.translation-Vector(p)).length<1e-4,n+' position wrong')
    for k,v in props.items():require(isinstance(o.get(k),(int,float)) and abs(o[k]-v)<1e-5,n+' '+k+' wrong')
    if role=='light':require(.3<=o.get('energy',0)<=1,n+' energy invalid')
 for n in ['TV_Screen','COL_Floors','COL_Walls']:require(S.objects.get(n) is not None,'Missing '+n)
 for o in cols:require(o.get('role')=='collision',o.name+' role missing')
 return str(len(expected))+' marker empties; extras and exact coordinates preserved'
check('Names and marker properties',markers)
rt=sum(len(triangles(o)) for o in render);ct=sum(len(triangles(o)) for o in cols)
def budgets():
 require(rt<=150000,'Render triangles '+str(rt));require(ct<6000,'Collision triangles '+str(ct));require(len(meshes)<=30,'Mesh count '+str(len(meshes)));require(len(bpy.data.materials)<=12,'Material count');require(len(bpy.data.images)<=12,'Image count')
 for im in bpy.data.images:require(max(im.size)<=2048,im.name+' oversized')
 require((ROOT/'skater_house.glb').stat().st_size<40000000,'GLB exceeds 40MB')
 return f'{rt} render tris, {ct} collision tris; {len(meshes)} meshes; {len(bpy.data.materials)} materials; {len(bpy.data.images)} images; {(ROOT/"skater_house.glb").stat().st_size/1e6:.2f} MB'
check('Performance budgets',budgets)
def transforms():
 for o in S.objects:
    require(max(abs(v-1) for v in o.scale)<1e-5,o.name+' non-unit scale')
    require(o.rotation_euler.to_matrix().to_quaternion().angle<1e-4,o.name+' rotation not applied')
    require(not o.modifiers,o.name+' unapplied modifier')
 require(not any(o.type in ['LIGHT','CAMERA','ARMATURE'] for o in S.objects),'Forbidden scene object')
 require(not bpy.data.actions,'Animation present')
 return 'Unit scales, zero rotations, no modifiers, lights, cameras or animation'
check('Applied transforms and export content',transforms)
# BVHs made only from imported geometry, world space.
def bvh(objects):
    vs=[];fs=[]
    for o in objects:
      for tri in triangles(o):idx=len(vs);vs.extend(tri);fs.append((idx,idx+1,idx+2))
    return BVHTree.FromPolygons(vs,fs,all_triangles=True)
fb=bvh([S.objects['COL_Floors']]);wb=bvh([S.objects['COL_Walls']]);rb=bvh(render)
def normals():
    ts=triangles(S.objects['COL_Floors'])
    for a,b,c in ts:require((b-a).cross(c-a).normalized().z>.99,'Floor face not facing up')
    # Generalised winding number on every collision wall triangle, not just a
    # global signed-volume test. Offset inward/outward samples must drop by +1.
    t=np.asarray([[list(v) for v in tri] for tri in triangles(S.objects['COL_Walls'])],dtype=float)
    normal=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);normal/=np.linalg.norm(normal,axis=1)[:,None]
    centers=t.mean(axis=1)
    def winding(points):
      values=[]
      for p in points:
        d=t-p;a,b,c=d[:,0],d[:,1],d[:,2];la=np.linalg.norm(a,axis=1);lb=np.linalg.norm(b,axis=1);lc=np.linalg.norm(c,axis=1)
        num=np.einsum('ij,ij->i',a,np.cross(b,c));den=la*lb*lc+np.einsum('ij,ij->i',a,b)*lc+np.einsum('ij,ij->i',b,c)*la+np.einsum('ij,ij->i',c,a)*lb
        values.append(np.arctan2(num,den).sum()/(2*math.pi))
      return np.array(values)
    inside=winding(centers-normal*.0001);outside=winding(centers+normal*.0001)
    require(np.all(inside>.9),'Inward sample not inside closed positive-winding solid')
    require(np.all((inside-outside)>.9),'Inverted, duplicated, or non-closed wall face; min winding drop='+str(float(np.min(inside-outside))))
    return f'{len(ts)} upward floor faces; {len(t)} wall triangles individually checked by solid-angle winding'
check('One-sided collision normals and closed solids',normals)
def clearsegment(a,b):
    a=Vector(a);d=Vector(b)-a
    return wb.ray_cast(a,d.normalized(),d.length)[0] is None
def doors():
    for y,a,b,h in [(-4.6,-.55,.55,2.4),(4.6,-1,3,2.7)]:
      # Scan horizontal clearance throughout usable doorway height.
      for z in [.31,.8,1.5,2.39 if y<0 else 2.69]:
        require(clearsegment((a+.001,y,z),(b-.001,y,z)),'Obstructed doorway')
      # Measure actual jambs with rays from center, not only expected dimensions.
      c=Vector(((a+b)/2,y,1.3));left=wb.ray_cast(c,Vector((-1,0,0)),10);right=wb.ray_cast(c,Vector((1,0,0)),10)
      width=left[3]+right[3];require(width>=1-1e-5,'Door less than 1m');require(abs(width-(b-a))<.002,'Doorway not exact brief width')
    # Verify collision blocks each window even though render glass is absent.
    for x,y in [(-4.5,-4.6),(4.5,-4.6),(-5,4.6),(5.5,4.6)]:require(not clearsegment((x,y-.3,1.8),(x,y+.3,1.8)),'Window collision missing')
    return 'Front 1.100m × 2.100m; back 4.000m × 2.400m; four windows block collision'
check('Door clearances and solid window collision',doors)
def pad():
    heights=[]
    for x in np.linspace(-7,9,33):
      for y in np.linspace(15,24,19):
        p,n,i,d=fb.ray_cast(Vector((x,y,8)),Vector((0,0,-1)),10);require(p is not None,'No pad ground');heights.append(p.z)
    require(max(heights)-min(heights)<=.01,'Pad not flat');require(max(abs(v) for v in heights)<.001,'Pad not z=0')
    # Scan every triangle for any geometry in the slab+3m exclusion footprint
    # above ground. Triangle bounding boxes conservatively cover crossings.
    for o in render+cols:
      for tri in triangles(o):
        lo=[min(v[i] for v in tri) for i in range(3)];hi=[max(v[i] for v in tri) for i in range(3)]
        if lo[0]<12-1e-4 and hi[0]>-10+1e-4 and lo[1]<27-1e-4 and hi[1]>12+1e-4:require(hi[2]<=.01,'Pad/border obstruction '+o.name)
    return f'16m × 9m, z=0, variation {max(heights)-min(heights):.6f}m; empty 3m border'
check('Ramp pad flat, empty and unobstructed border',pad)
def tv():
    o=S.objects['TV_Screen'];require(len(o.data.materials)==1 and o.data.materials[0].name=='TV_Screen','TV material')
    uv=o.data.uv_layers.active;require(uv is not None,'TV has no UV')
    coords=[d.uv for d in uv.data]
    for ax in [0,1]:require(abs(min(u[ax] for u in coords))<1e-6 and abs(max(u[ax] for u in coords)-1)<1e-6,'UV not exactly 0..1')
    verts=[o.matrix_world@v.co for v in o.data.vertices];require(abs(max(v.y for v in verts)-min(v.y for v in verts)-2.4)<1e-5,'TV width');require(abs(max(v.z for v in verts)-min(v.z for v in verts)-1.35)<1e-5,'TV height')
    for p in o.data.polygons:
      a,b,c=[o.matrix_world@o.data.vertices[i].co for i in p.vertices[:3]];require((b-a).cross(c-a).x>0,'TV not facing +X')
      for li in p.loop_indices:
        v=o.matrix_world@o.data.vertices[o.data.loops[li].vertex_index].co;u=uv.data[li].uv
        require(abs(u.x-(v.y+1.2)/2.4)<1e-5 and abs(u.y-(v.z-1.3)/1.35)<1e-5,'TV image mirrored or upside down')
    return '2.4 × 1.35m; +X facing; U→+Y (viewer right), V→+Z'
check('TV exact size, material, winding and UV orientation',tv)
def capsule():
    # Swept path sampled every <=5cm. Full 0.3 radius/1.7m capsule:
    # nearest-triangle distance to central axis plus radial and swept raycasts.
    route=[(0,-3),(0,2.7),(1,4),(1,7.6),(1,10.2),(1,15),(1,19.5)]
    count=0;prev=None;minclear=99
    for aa,bb in zip(route,route[1:]):
      a=Vector(aa);b=Vector(bb);n=math.ceil((b-a).length/.05)
      for j in range(n+1):
        p=a.lerp(b,j/n);ground,normal,idx,dist=fb.ray_cast(Vector((p.x,p.y,3)),Vector((0,0,-1)),4)
        require(ground is not None,'No support at '+str(tuple(p)));require(normal.z>.99,'Wrong support normal');z=ground.z
        if prev is not None:require(abs(z-prev.z)<=.18,'Step/drop >.18m')
        # Densely sample axis; distance test slightly conservative by 2mm.
        for zz in np.linspace(z+.3,z+1.4,34):
          q=Vector((p.x,p.y,float(zz)));near,nor,idx,d=wb.find_nearest(q)
          minclear=min(minclear,d);require(d>=.302,'Capsule intersects wall/prop at '+str(tuple(q)))
          for angle in np.linspace(0,math.tau,16,endpoint=False):
            hit=wb.ray_cast(q,Vector((math.cos(angle),math.sin(angle),0)),.3)[0];require(hit is None,'Capsule radial ray blocked')
        head=wb.ray_cast(Vector((p.x,p.y,z+.3)),Vector((0,0,1)),1.4)[0];require(head is None,'Insufficient headroom')
        if prev is not None:
          for h in [.3,.85,1.4]:require(clearsegment(prev+Vector((0,0,h)),Vector((p.x,p.y,z+h))),'Sweep ray blocked')
        prev=Vector((p.x,p.y,z));count+=1
    return f'{count} supported samples; r=.30m h=1.70m; spawn → rear opening → 1:8 ramp → pad; minimum axis clearance {minclear:.3f}m'
check('Raycast capsule walk to ramp pad',capsule)
def floorplan():
    # Interior side faces determine full 14x9 clear wall envelope.
    for d,expected_dist in [((-1,0,0),7),((1,0,0),7)]:
      # Above low props and below ceiling, y=3 is unobstructed for these rays.
      hit=wb.ray_cast(Vector((0,3,2)),Vector(d),10);require(hit[0] is not None and abs(hit[3]-expected_dist)<.001,'Interior width incorrect')
    for direction in [(0,-1,0),(0,1,0)]:
      hit=wb.ray_cast(Vector((-3.5,0,2)),Vector(direction),10);require(hit[0] is not None and abs(hit[3]-4.5)<.001,'Interior depth incorrect')
    # All interior and decks horizontal; ramp only tilted floor triangle.
    for tri in triangles(S.objects['COL_Floors']):
      normal=(tri[1]-tri[0]).cross(tri[2]-tri[0]).normalized()
      if abs(normal.z-1)>.00001:
        require(all(-.5001<=v.x<=2.5001 and 7.6999<=v.y<=10.1001 for v in tri),'Unexpected slope')
        require(abs(abs(normal.y/normal.z)-.125)<1e-4,'Wrong ramp slope')
    return '14 × 9m clear room; horizontal finished surfaces; only ramp inclined (1:8)'
check('Scale and floor slopes',floorplan)
# Parse GLB JSON directly for properties Blender importer may not retain.
def glb_contract():
    import struct
    data=(ROOT/'skater_house.glb').read_bytes();length,kind=struct.unpack_from('<II',data,12);doc=json.loads(data[20:20+length])
    require('KHR_draco_mesh_compression' not in doc.get('extensionsUsed',[]) and 'EXT_meshopt_compression' not in doc.get('extensionsUsed',[]),'Compression present')
    for m in doc.get('materials',[]):require(not m.get('doubleSided',False),m.get('name','')+' double sided');require(m.get('alphaMode','OPAQUE')!='BLEND','Alpha blended material')
    for im in doc.get('images',[]):require('bufferView' in im and im.get('mimeType')=='image/jpeg','Images must be embedded JPEG base colour')
    return 'Embedded JPEGs, single-sided opaque PBR, uncompressed geometry, Y-up glTF'
check('Raw glTF material and image contract',glb_contract)
summary={'all_passed':all(r['pass'] for r in results),'render_triangles':rt,'collision_triangles':ct,'mesh_objects':len(meshes),'materials':[m.name for m in bpy.data.materials],'textures':[{'name':i.name,'size':list(i.size)} for i in bpy.data.images],'results':results}
(ROOT/'validation.json').write_text(json.dumps(summary,indent=2))
# Keep the human-readable report tied to the independently imported export.
stats={}
lines=['# Skater house — delivery report','',
'Built with Blender '+bpy.app.version_string+'. One uncompressed glTF Binary asset. All geometry and textures are purpose-built; no stock model assets.','',
'## Measured export','',
'| Item | Actual | Limit |','|---|---:|---:|',
f'| Render triangles | {rt:,} | 150,000 target / 250,000 hard |',
f'| Collision triangles | {ct:,} | <6,000 |',
f'| Mesh objects (including 2 collision meshes) | {len(meshes)} | 30 |',
f'| Materials | {len(bpy.data.materials)} | 12 |',
f'| Embedded images | {len(bpy.data.images)} | 12 |',
f'| GLB size | {(ROOT/"skater_house.glb").stat().st_size/1e6:.3f} MB | <40 MB |','',
'## Layout and scale','',
'- Blender is metres, Z up, +Y north. Origin is yard ground at the room centre. Standard glTF export converts to Y up: Blender (x,y,z) becomes glTF (x,z,-y). The marker heading extras retain the requested convention.',
'- Interior clear dimensions are 14 × 9 m; wall thickness is 0.20 m. Interior and veranda tops are z=0.30. Side walls end at z=3.30; the pitched gable reaches z=4.90 with roofing above it.',
'- Front opening: 1.10 × 2.10 m. Back opening: 4.00 × 2.40 m, x=-1..3. No door leaves or glass. Window openings are closed only in COL_Walls.',
'- The two back windows use the same 1.60 × 1.30 m dimensions and 0.90 m sill height as the front windows, since their sizes were not separately specified.',
'- TV face is 2.40 × 1.35 m, bottom z=1.30, facing +X. U increases toward +Y (viewer right); V increases upward. Its mesh and material are both exactly TV_Screen.',
'- Sofa is 2.20 m along Y × 0.90 m along X, back x=-2.20, cushion top z=0.75. Coffee table is 1.20 m along Y × 0.60 m along X, top z=0.75. Counter is 3.60 m along Y × 0.70 m along X, top z=1.35.',
'- Rear ramp is 3.00 × 2.40 m, x=-0.5..2.5, y=7.7..10.1, z=0.30..0: a straight 1:8 grade. Front staircase has three 0.10 m risers and 0.30 m treads.',
'- Fence boundary is x=±20, y=-12..30; panels and posts are 1.80 m high. The front gate is closed. Outer ground extends to ±250 m with no outside props.',
'- Ramp pad spans x=-7..9, y=15..24, exactly z=0. It is empty and has a clear 3 m border. No half-pipe is modeled.','',
'## Materials and textures','',
'| Material | Base colour image | Size |','|---|---|---|']
tex={}
for material in bpy.data.materials:
 if material.use_nodes:
  images=[node.image for node in material.node_tree.nodes if node.type=='TEX_IMAGE' and node.image]
  if images:tex[material.name]={'width':images[0].size[0],'height':images[0].size[1]}
for m in bpy.data.materials:
 t=tex.get(m.name)
 lines.append('| '+m.name+' | '+('Embedded JPEG' if t else 'Flat Principled colour')+' | '+(str(t['width'])+' × '+str(t['height']) if t else '—')+' |')
lines+=['','All materials are opaque, single-sided Principled PBR. No procedural shader is needed at runtime. Wood wear, fibre variation and neutral edge tint are baked into tileable JPEGs. Short-range nondirectional ambient occlusion is additionally baked into COLOR_0 vertex tints and multiplies the PBR base colour. This preserves tileable texture reuse without a unique lightmap. No sun or directional shadow is baked. Emissive_Lamp supplies the visible lamp lenses; the file contains no Blender lights.','',
'## Marker table','',
'Coordinates below are Blender Z-up metres. Every marker is a Plain Axes Empty.','',
'| Name | role | X | Y | Z | Other extras |','|---|---|---:|---:|---:|---|']
for name in expected:
 o=S.objects[name];p=o.matrix_world.translation;props={k:v for k,v in o.items() if k!='role'}
 lines.append(f'| {name} | {o["role"]} | {p.x:.4f} | {p.y:.4f} | {p.z:.4f} | '+', '.join(k+'='+str(round(float(v),4)) for k,v in props.items() if isinstance(v,(int,float)))+' |')
lines+=['','## Independent GLB checks','','| Check | Result | Detail |','|---|---|---|']
for r in results:lines.append('| '+r['check']+' | '+('PASS' if r['pass'] else 'FAIL')+' | '+str(r['detail'])+' |')
lines+=['','The collision wall mesh is an exact union of axis-aligned solid volumes, with buried faces removed. Every imported wall triangle is tested using inward/outward solid-angle winding samples. Floors are tested separately for upward winding. The walk check samples the full 0.30 m radius, 1.70 m tall capsule at ≤5 cm path intervals using floor, radial, headroom and sweep raycasts plus nearest-triangle clearance. This is an offline geometry check, not a claim of testing on a physical Quest.','',
'## Conflicts, interpretations and integration notes','',
'- **Clearance conflict retained as specified:** the prescribed coffee-table position and sofa back/depth leave a 1.00 m gap between them, below the general 1.20 m walkway request. The main circulation route goes around this furniture gap and remains clear. Furniture sizes and positions were preserved.',
'- **Front-door exception:** its explicitly required 1.10 m opening is narrower than the general 1.20 m circulation request. It meets the explicit ≥1.00 m doorway minimum and passes the capsule test.',
'- The 12 board slots are intentionally empty for game-populated boards. Two visible ledges and individual supports are modeled. Two separate decorative boards are at the south-west wall.',
'- AO is encoded partly as baked vertex base-colour tint, rather than baking a unique full-house AO atlas into the JPEGs. This avoids sacrificing the requested tileable textures. The game must preserve glTF COLOR_0 to retain this shading.',
'- Collision meshes remain present in the GLB and carry role="collision". Hide COL_ meshes in the game renderer and use them only for collision; glTF has no portable per-mesh invisible-collider convention. They are wire-display and hidden from renders in the .blend.',
'- Previews use a temporary CPU Cycles lighting/camera rig that is not saved in the .blend or exported. Interior eye height is z=2.00 (1.70 m above floor); yard/exterior eye height is z=1.70. The plan is an orthographic cutaway.','',
'## Rebuild and validation','',
'```bash','blender -b -P build_house.py','blender -b -P check_house.py','```','',
'build_house.py creates the packed .blend, GLB, generated JPEGs, stats and eight previews in its own directory. HOUSE_PREVIEWS=0 skips only the preview renders. check_house.py starts a clean scene, re-imports the GLB, prints PASS/FAIL, writes validation.json and regenerates this report. No network access or third-party Python package is needed inside Blender.','',
'## Preview files','']
for filename,title in [('00_dimensioned_plan.png','Labelled plan with dimensions'),('01_front_entry.png','Entering the front door'),('02_lounge.png','Lounge / TV wall'),('03_shop.png','Board wall and counter'),('04_back_opening.png','Back opening'),('05_yard.png','Yard and empty ramp pad'),('06_front_exterior.png','Front three-quarter exterior'),('07_back_exterior.png','Back three-quarter exterior')]:
 lines.append('- ['+title+']('+filename+')')
(ROOT/'report.md').write_text('\n'.join(lines)+'\n')

print('OVERALL:', 'PASS' if summary['all_passed'] else 'FAIL')
if not summary['all_passed']:sys.exit(1)
