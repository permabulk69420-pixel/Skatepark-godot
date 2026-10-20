"""Bake CC0 skin colour and authored PBR detail without altering the game meshes.
Blender 4.3.2: --python tools/hands/bake_skin.py -- --side left --source-dir <cache>
Run once for each side. Inputs and their licenses are recorded in source.json.
"""
import bpy, json, math, sys, argparse, hashlib, numpy as np
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description='Bake anatomical CC0 skin to the original hand UVs')
parser.add_argument('--source-dir',type=Path,default=Path('/workspace/hand-work'))
parser.add_argument('--side',choices=['left','right'],required=True)
parser.add_argument('--save-debug',action='store_true')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
WORK=args.source_dir.resolve();SIDE=args.side
PREFIX='b_r_' if SIDE=='right' else 'b_l_'
OUT=ROOT/'assets/hands/skin';OUT.mkdir(parents=True,exist_ok=True)
manifest=json.loads((OUT/'source.json').read_text())
inputs={'source-base.obj':WORK/'source-base.obj', 'source-weights.json':WORK/'source-weights.json',
        'skin_diffuse.png':WORK/'source'/manifest['skin_pack_entry']}
for name,path in inputs.items():
    with path.open('rb') as stream: digest=hashlib.file_digest(stream,'sha256').hexdigest()
    if digest!=manifest['sha256'][name]:raise RuntimeError('Unverified input: '+str(path))
bpy.ops.wm.read_factory_settings(use_empty=True)
# Source anatomy and original CC0 UV coordinates. No source program code is included.
positions=[];uvs=[];faces=[];face_uvs=[];helpers={};group=''
for line in (WORK/'source-base.obj').read_text().splitlines():
 p=line.split()
 if not p:continue
 if p[0]=='v':positions.append([float(x) for x in p[1:4]])
 elif p[0]=='vt':uvs.append([float(x) for x in p[1:3]])
 elif p[0]=='g':group=p[1]
 elif p[0]=='f':
  inds=[int(x.split('/')[0])-1 for x in p[1:]]
  if group=='body':
   faces.append(inds);face_uvs.append([int(x.split('/')[1])-1 for x in p[1:]])
  elif group.startswith('joint-l-'):
   helpers.setdefault(group,set()).update(inds)
P=np.array(positions,dtype=float)*.1
J={k:np.mean(P[list(v)],axis=0) for k,v in helpers.items()}
weights=json.loads((WORK/'source-weights.json').read_text())['weights']
bpy.ops.import_scene.gltf(filepath=str(ROOT/f'assets/hands/{SIDE.capitalize()}Hand.glb'))
arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
target=next(o for o in bpy.context.scene.objects if o.type=='MESH')
bones={b.name:np.array(arm.matrix_world@b.head_local) for b in arm.data.bones}
source_wrist=J['joint-l-hand'];target_wrist=bones[PREFIX+'hand']
source_forward=J['joint-l-finger-3-1']-source_wrist
source_right=J['joint-l-finger-2-1']-J['joint-l-finger-5-1']
target_forward=bones[PREFIX+'middle1']-target_wrist
target_right=bones[PREFIX+'index1']-bones[PREFIX+'pinky1']

def frame(forward,right):
 y=forward/np.linalg.norm(forward)
 x=right-y*np.dot(right,y);x/=np.linalg.norm(x)
 z=np.cross(x,y);return np.array([x,y,z]).T
SF=frame(source_forward,source_right);TF=frame(target_forward,target_right)
if SIDE=='right':TF[:,2]*=-1
width_scale=np.linalg.norm(target_right)/np.linalg.norm(source_right)
length_scale=np.linalg.norm(target_forward)/np.linalg.norm(source_forward)
base_matrix=TF@np.diag([width_scale,length_scale,width_scale])@SF.T
base_translation=target_wrist-base_matrix@source_wrist
transforms={}
for bone, ws in weights.items():
 if not bone.endswith('.L'):continue
 if bone.startswith('finger'):
  finger,segment=map(int,bone.split('.')[0].replace('finger','').split('-'))
  label=['thumb','index','middle','ring','pinky'][finger-1]
  sh=J[f'joint-l-finger-{finger}-{segment}'];st=J[f'joint-l-finger-{finger}-{segment+1}']
  th=bones[f'{PREFIX}{label}{segment}'];tt=bones[f'{PREFIX}{label}{segment+1}' if segment<3 else f'{PREFIX}{label}_ignore']
  sf=frame(st-sh,source_right);tf=frame(tt-th,target_right)
  if SIDE=='right':tf[:,2]*=-1
  longitudinal=np.linalg.norm(tt-th)/np.linalg.norm(st-sh)
  matrix=tf@np.diag([width_scale,longitudinal,width_scale])@sf.T
  transforms[bone]=(matrix,th-matrix@sh)
 else:transforms[bone]=(base_matrix,base_translation)
warped=np.zeros_like(P);total=np.zeros(len(P))
for name,(matrix,translation) in transforms.items():
 for i,w in weights[name]:
  warped[i]+=w*(matrix@P[i]+translation);total[i]+=w
for i in range(len(P)):
 if total[i]>.01:warped[i]/=total[i]
 else:warped[i]=base_matrix@P[i]+base_translation
# Keep only the left hand and a short forearm cuff, never project onto the torso.
triangles=[];triuv=[]
for f,fu in zip(faces,face_uvs):
 centre=warped[f].mean(0)
 if not (P[f,0].min()>.30 and centre[1]>-.055):continue
 for n in range(1,len(f)-1):
  triangles.append((f[0],f[n],f[n+1]));triuv.append((fu[0],fu[n],fu[n+1]))
bvh=BVHTree.FromPolygons([Vector(p) for p in warped],triangles,all_triangles=True)
print('SOURCE_TRIANGLES',len(triangles),'SCALES',width_scale,length_scale,flush=True)
# A subdivided temporary sampling mesh keeps the anatomical UV transfer local.
# The game GLBs, topology, bone weights and animation clips remain unchanged.
bake=target.copy();bake.data=target.data.copy();bpy.context.collection.objects.link(bake)
bake.name='BakeTarget';bake.modifiers.clear();bake.parent=None;bake.matrix_world=target.matrix_world
bpy.context.view_layer.objects.active=bake
bpy.ops.object.select_all(action='DESELECT');bake.select_set(True)
sub=bake.modifiers.new('Sampling density only','SUBSURF');sub.subdivision_type='SIMPLE';sub.levels=3
bpy.ops.object.modifier_apply(modifier=sub.name)
source_uv=bake.data.uv_layers.new(name='SourceSkinUV')
rough=bake.data.color_attributes.new(name='SkinRoughness',type='FLOAT_COLOR',domain='CORNER')
source_uv=bake.data.uv_layers['SourceSkinUV']
print('SAMPLING_MESH',len(bake.data.polygons),len(bake.data.loops),flush=True)
uvvectors=[Vector((u,v,0)) for u,v in uvs]
distal=[]
for finger in ['thumb','index','middle','ring','pinky']:
 head=bones[PREFIX+finger+'3'];tip=bones[PREFIX+finger+'_ignore']
 forward=tip-head;length=np.linalg.norm(forward);forward/=length
 basis=frame(forward,target_right)
 if SIDE=='right':basis[:,2]*=-1
 width=.008 if finger=='thumb' else (.005 if finger=='pinky' else .006)
 distal.append((head,forward,length,basis[:,0],basis[:,2],width))
maxdist=0;distances=[]
for poly in bake.data.polygons:
 # Project each small face to a single source triangle, avoiding UV seams through faces.
 centre=bake.matrix_world@poly.center
 closest,normal,index,distance=bvh.find_nearest(centre)
 a,b,c=[Vector(warped[i]) for i in triangles[index]]
 ua,ub,uc=[uvvectors[i] for i in triuv[index]]
 for li in poly.loop_indices:
  point=bake.matrix_world@bake.data.vertices[bake.data.loops[li].vertex_index].co
  projected=barycentric_transform(point,a,b,c,ua,ub,uc)
  source_uv.data[li].uv=(projected.x,projected.y)
  # Softer highlights on palm, slightly lower roughness on the backs and nails.
  back=max(0,min(1,(poly.normal.z+.2)/1.2))
  value=.59-.12*back
  # Nail plates are smoother than skin; keep this mask local to each distal phalanx.
  world_point=np.array(point)
  for head,forward,length,side_axis,normal_axis,width in distal:
   relative=world_point-head
   t=float(np.dot(relative,forward)/length)
   side=float(abs(np.dot(relative,side_axis)))
   height=float(np.dot(relative,normal_axis))
   axial=max(0,min(1,(t-.12)/.18))*max(0,min(1,(1.06-t)/.16))
   transverse=max(0,min(1,(width-side)/(.25*width)))
   dorsal=max(0,min(1,(height-.001)/.003))
   nail=axial*transverse*dorsal
   value=value*(1-nail)+.31*nail
  rough.data[li].color=(value,value,value,1)
 distances.append(distance)
print('PROJECTION_DISTANCE',np.percentile(distances,[50,90,99]).tolist(),flush=True)
# Make the render material from the original diffuse source, using explicit source UVs.
material=bpy.data.materials.new('CC0 skin transfer');material.use_nodes=True
nodes=material.node_tree.nodes;nodes.clear();links=material.node_tree.links
out=nodes.new('ShaderNodeOutputMaterial');emit=nodes.new('ShaderNodeEmission');links.new(emit.outputs[0],out.inputs['Surface'])
uvnode=nodes.new('ShaderNodeUVMap');uvnode.uv_map='SourceSkinUV'
tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(WORK/'source/skins/young_caucasian_male/young_lightskinned_male_diffuse.png'))
links.new(uvnode.outputs['UV'],tex.inputs['Vector']);links.new(tex.outputs['Color'],emit.inputs['Color'])
bake.data.materials.clear();bake.data.materials.append(material)
bake.data.uv_layers.active=bake.data.uv_layers['UVMap']
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8
scene.render.threads_mode='FIXED';scene.render.threads=4
scene.render.bake.margin=12;scene.render.bake.use_clear=True
bpy.ops.object.select_all(action='DESELECT');bake.select_set(True);bpy.context.view_layer.objects.active=bake

def bake_image(name,kind='EMIT',colour=True):
 size=1024 if colour else 512
 image=bpy.data.images.new(name,width=size,height=size,alpha=False)
 if not colour:image.colorspace_settings.name='Non-Color'
 slot=nodes.new('ShaderNodeTexImage');slot.image=image;nodes.active=slot
 bpy.ops.object.bake(type=kind,uv_layer='UVMap')
 image.filepath_raw=str(OUT/(name+'.png'));image.file_format='PNG';image.save()
 nodes.remove(slot)
 print('BAKED',name,flush=True)
 return image
albedo=bake_image(SIDE+'_albedo')
attribute=nodes.new('ShaderNodeVertexColor');attribute.layer_name='SkinRoughness'
links.new(attribute.outputs['Color'],emit.inputs['Color'])
roughness=bake_image(SIDE+'_roughness',colour=False)
# A very shallow, non-directional skin micro-normal, authored at real millimetre scale.
bs=nodes.new('ShaderNodeBsdfPrincipled');links.new(bs.outputs[0],out.inputs['Surface'])
coords=nodes.new('ShaderNodeTexCoord');noise=nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=2800
noise.inputs['Detail'].default_value=1;noise.inputs['Roughness'].default_value=.5
links.new(coords.outputs['Object'],noise.inputs['Vector'])
bump=nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.22;bump.inputs['Distance'].default_value=.000012
links.new(noise.outputs['Fac'],bump.inputs['Height']);links.new(bump.outputs['Normal'],bs.inputs['Normal'])
normal=bake_image(SIDE+'_normal',kind='NORMAL',colour=False)
# Save a source registration scene for visual inspection, with a neutral material.
source_data=bpy.data.meshes.new('Aligned CC0 source hand');source_data.from_pydata(warped.tolist(),[],triangles);source_data.update()
source=bpy.data.objects.new('Aligned CC0 source hand',source_data);bpy.context.collection.objects.link(source)
source.hide_render=True;source.hide_set(True)
# The left and right GLBs use independently authored UV atlases, so right-hand baking is separate.
scene['projection_median_m']=float(np.median(distances));scene['projection_99pct_m']=float(np.percentile(distances,99))
bpy.context.preferences.filepaths.save_version=0
if args.save_debug:
 bpy.ops.wm.save_as_mainfile(filepath=str(WORK/f'{SIDE}-skin-transfer.blend'))
print('SKIN_BAKE_COMPLETE',flush=True)
