"""Run: blender -b --factory-startup --python tools/build_halfpipe.py
Original wooden mini-ramp. Units: metres. Blender Z-up; exported Godot Y-up.
"""
import bpy, math, json, sys
from pathlib import Path
from mathutils import Vector
from math import sin, cos, acos, pi

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/wooden_halfpipe'
OUT.mkdir(parents=True,exist_ok=True)
ART = ROOT / 'art/wooden_halfpipe'
ART.mkdir(parents=True,exist_ok=True)
(ART/'.gdignore').touch()
HEIGHT, WIDTH, RADIUS, FLAT, DECK = 1.8, 5.0, 1.8, 7.2, 1.3
ANGLE = acos(1-HEIGHT/RADIUS)
LIP = FLAT/2 + RADIUS*sin(ANGLE)
BACK = LIP + DECK
HALF = WIDTH/2
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):
    if c.name != 'Collection': bpy.data.collections.remove(c)
asset = bpy.data.collections.get('Collection')
asset.name = 'HALFPIPE | game asset'
studio = bpy.data.collections.new('STUDIO | not exported')
bpy.context.scene.collection.children.link(studio)
parts=[]
collision=[]
grind_markers=[]

def move_to(obj, collection):
    for c in list(obj.users_collection): c.objects.unlink(obj)
    collection.objects.link(obj)

def wood(name, texture, roughness=.65):
    m=bpy.data.materials.new(name); m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF'); bs.inputs['Roughness'].default_value=roughness
    tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ART/'textures'/f'{texture}.png'),check_existing=True)
    m.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
    r=m.node_tree.nodes.new('ShaderNodeTexImage')
    r.image=bpy.data.images.load(str(ART/'textures'/f'{texture}_roughness.png'),check_existing=True)
    r.image.colorspace_settings.name='Non-Color'
    m.node_tree.links.new(r.outputs['Color'],bs.inputs['Roughness'])
    return m

def solid(name, color, rough=.5, metal=0):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
    return m

ply=wood('01 | honey maple riding plywood','plywood')
deckmat=wood('02 | oiled deck boards','deck')
frame=wood('03 | pressure treated framing','framing')
edge=wood('04 | exposed laminated plywood edge','edge')
steel=solid('05 | satin galvanized coping',(.43,.48,.51),.27,.82)
black=solid('06 | charcoal powder coat',(.043,.055,.058),.45,.65)
seammat=solid('07 | fine plywood joint',(.19,.115,.060),.8)
boltmat=solid('08 | countersunk steel fixings',(.21,.23,.23),.35,.8)
rubber=solid('09 | foundation foot pads',(.035,.038,.037),.8)


def mesh(name,verts,faces,mat,uv=None,smooth=False):
    data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.update()
    obj=bpy.data.objects.new(name,data);asset.objects.link(obj);data.materials.append(mat);parts.append(obj)
    for p in data.polygons: p.use_smooth=smooth
    if uv:
        layer=data.uv_layers.new(name='UVMap')
        for p in data.polygons:
            for li in p.loop_indices:
                layer.data[li].uv=uv[data.loops[li].vertex_index]
    return obj


def bevel(obj,amount=.006):
    mod=obj.modifiers.new('Soft manufactured edges','BEVEL');mod.width=amount;mod.segments=1
    mod=obj.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')


def box(name,loc,size,mat,bev=.004):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    obj=bpy.context.object;obj.name=name;move_to(obj,asset);obj.scale=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    obj.data.materials.append(mat);parts.append(obj)
    # Grain follows the longest local axis on each face; dimensions remain physical.
    layer=obj.data.uv_layers.active
    for poly in obj.data.polygons:
        normal=poly.normal
        axes=sorted(range(3),key=lambda a:abs(normal[a]))[:2]
        major=max(axes,key=lambda a:size[a]);minor=next(a for a in axes if a!=major)
        for li in poly.loop_indices:
            co=obj.data.vertices[obj.data.loops[li].vertex_index].co
            layer.data[li].uv=(co[minor]/.32,co[major]/2.4)
    if bev: bevel(obj,bev)
    if name in ('Guardrail stanchion', 'Side guardrail front post', 'Stair rail steel upright',
                'Back timber handrail', 'Back steel horizontal guard',
                'Side timber handrail', 'Side horizontal guard'):
        x,y,z=loc;w,d,h=size
        top_box_collision(x-w/2,x+w/2,y-d/2,y+d/2,z-h/2,z+h/2)
    return obj


def beam(name,a,b,width,depth,mat):
    a,b=Vector(a),Vector(b);o=box(name,(a+b)/2,(width,depth,(b-a).length),mat)
    o.rotation_mode='QUATERNION';o.rotation_quaternion=(b-a).to_track_quat('Z','Y')
    if name in ('Stair oiled timber handrail', 'Stair lower guard', 'Stair mid guard'):
        rotation=o.rotation_quaternion
        centre=(a+b)/2;half=(b-a).length/2
        pp=[centre+rotation@Vector((x*width/2,y*depth/2,z*half))
            for x,y,z in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),
                          (-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        for i,j,k,l in [(4,5,6,7),(0,4,7,3),(1,2,6,5),(0,1,5,4),(3,7,6,2),(0,3,2,1)]:
            quad_collision(pp[i],pp[j],pp[k],pp[l])
    return o


def cylinder(name,a,b,r,mat,vertices=16):
    a,b=Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=(b-a).length,location=(a+b)/2)
    o=bpy.context.object;o.name=name;move_to(o,asset);o.rotation_mode='QUATERNION';o.rotation_quaternion=(b-a).to_track_quat('Z','Y')
    o.data.materials.append(mat);parts.append(o)
    for p in o.data.polygons:p.use_smooth=len(p.vertices)==4
    bevel(o,.0015)
    return o


def quad_collision(a,b,c,d): collision.extend([a,b,c,a,c,d])

def top_box_collision(x0,x1,y0,y1,z0,z1):
    p=[(x0,y0,z0),(x1,y0,z0),(x1,y1,z0),(x0,y1,z0),(x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)]
    for a,b,c,d in [(4,5,6,7),(0,4,7,3),(1,2,6,5),(0,1,5,4),(3,7,6,2),(0,3,2,1)]:quad_collision(p[a],p[b],p[c],p[d])

def grind_marker(name,a,b,radius,kind='rail'):
    marker=bpy.data.objects.new('PATH_HalfPipe_'+name,None)
    asset.objects.link(marker)
    marker.empty_display_type='PLAIN_AXES';marker.empty_display_size=.08
    marker['role']='grind_path';marker['kind']=kind
    marker['closed']=False;marker['radius']=radius
    # glTF converts node transforms; custom numeric extras must be converted explicitly.
    marker['points']=[value for x,y,z in [a,b] for value in (x,z,-y)]
    grind_markers.append(marker)

# Continuous tangent circular transitions, a flat bottom, and shared vertices for clean normals.
profile=[]
for i in range(65):
    t=ANGLE*(1-i/64)
    profile.append((-FLAT/2-RADIUS*sin(t),RADIUS*(1-cos(t)),RADIUS*(ANGLE-t)))
for i in range(1,17):profile.append((-FLAT/2+FLAT*i/16,0,RADIUS*ANGLE+FLAT*i/16))
for i in range(1,65):
    t=ANGLE*i/64
    profile.append((FLAT/2+RADIUS*sin(t),RADIUS*(1-cos(t)),RADIUS*ANGLE+FLAT+RADIUS*t))
verts=[];uv=[]
for x,z,s in profile:
    for j in range(5):verts.append((x,-HALF+WIDTH*j/4,z));uv.append((j,s/2.4))
faces=[]
for i in range(len(profile)-1):
    for j in range(4):
        a=i*5+j;faces.append((a,a+5,a+6,a+1))
ride=mesh('Riding surface | continuous maple plywood',verts,faces,ply,uv,True)
for i in range(len(profile)-1):
    x,z,_=profile[i];xx,zz,_=profile[i+1]
    quad_collision((x,-HALF,z),(xx,-HALF,zz),(xx,HALF,zz),(x,HALF,z))

# 32 mm laminated edge and closed curved cheeks on both sides.
for sy in [-1,1]:
    y=sy*(HALF+.012)
    vv=[];uu=[]
    for x,z,s in profile:
        vv.extend([(x,y,z-.003),(x,y,z-.035)]);uu.extend([(s/.5,0),(s/.5,.12)])
    mesh(f'Laminated riding edge {sy}',vv,[(i*2,i*2+2,i*2+3,i*2+1) for i in range(len(profile)-1)],edge,uu)
    for side in [-1,1]:
        wing=[(x,z) for x,z,_ in profile if x*side>=FLAT/2-.001]
        wing.sort()
        vv=[];uu=[]
        for x,z in wing:
            vv.extend([(x,y,z-.037),(x,y,-.12)]);uu.extend([(x/1.3,z/2.4),(x/1.3,-.05)])
        for i in range(len(wing)-1):
            xa,za=wing[i];xb,zb=wing[i+1]
            points=[(xa,y,-.12),(xb,y,-.12),(xb,y,zb),(xa,y,za)]
            if sy>0:points.reverse()
            quad_collision(*points)
        cheek=mesh(f'Structural curved plywood cheek {sy} {side}',vv,[(2*i,2*i+2,2*i+3,2*i+1) for i in range(len(wing)-1)],deckmat,uu)
        sol=cheek.modifiers.new('18 mm cheek thickness','SOLIDIFY');sol.thickness=.018
        # Flush decorative ribs acknowledge the load-bearing timber frame.
        for frac in [.3,.6,.88]:
            x=side*(FLAT/2+(LIP-FLAT/2)*frac)
            t=math.asin((abs(x)-FLAT/2)/RADIUS);z=RADIUS*(1-cos(t))
            if z>.2: box('Cheek upright trim',(x,y+sy*.017,(z-.13)/2),(.065,.035,z+.07),frame)
        # End band at the lip, with small visible coach-bolt heads.
        box('Lip fascia upright',(side*(LIP+.035),y,HEIGHT/2-.06),(.12,.075,HEIGHT+.1),frame)
        for zz in [.2,.75,1.4]:
            cylinder('Galvanized coach bolt',(side*(LIP+.035),y+sy*.045,zz),(side*(LIP+.035),y+sy*.052,zz),.012,boltmat,12)

# Tiny flush sheet joints, following the riding contour. No gaps in collision.
for y in [-1.35,0,1.35]:
    vv=[]
    for x,z,_ in profile:vv.extend([(x,y-.0012,z+.0006),(x,y+.0012,z+.0006)])
    mesh('Flush longitudinal plywood seam',vv,[(2*i,2*i+2,2*i+3,2*i+1) for i in range(len(profile)-1)],seammat,smooth=True)
for target in [1.7,4.1,6.5,8.9,11.3]:
    total=profile[-1][2]
    if target>total-.3:continue
    for i in range(len(profile)-1):
        x,z,s=profile[i];xx,zz,ss=profile[i+1]
        if s<=target<=ss:
            k=(target-s)/(ss-s);xc=x+(xx-x)*k;zc=z+(zz-z)*k
            nx=(xx-x)/(ss-s)*.0012;nz=(zz-z)/(ss-s)*.0012
            mesh('Flush crosswise plywood sheet joint',[(xc-nx,-HALF,zc-nz+.0007),(xc+nx,-HALF,zc+nz+.0007),(xc+nx,HALF,zc+nz+.0007),(xc-nx,HALF,zc-nz+.0007)],[(0,1,2,3)],seammat)
            break

# Deck framing, timber plank tops, galvanized steel coping.
for side in [-1,1]:
    cx=side*(LIP+DECK/2)
    box('Deck back rim joist',(side*(BACK-.06),0,HEIGHT-.16),(.12,WIDTH+.12,.24),frame)
    box('Deck front rim joist',(side*(LIP+.09),0,HEIGHT-.16),(.12,WIDTH+.12,.24),frame)
    for y in [-HALF+.12,0,HALF-.12]:
        box('Deck support joist',(cx,y,HEIGHT-.16),(DECK,.1,.24),frame)
        for xx in [side*(LIP+.13),side*(BACK-.13)]:
            box('Deck foundation post',(xx,y,(HEIGHT-.16)/2-.04),(.14,.14,HEIGHT-.08),frame)
            box('Black foundation shoe',(xx,y,-.075),(.19,.19,.11),black)
            box('Rubber base pad',(xx,y,-.14),(.23,.23,.025),rubber)
    for y in [-HALF+.12,HALF-.12]:
        beam('Deck diagonal timber brace',(side*(LIP+.16),y,.23),(side*(BACK-.16),y,HEIGHT-.25),.09,.09,frame)
    boardcount=36
    for j in range(boardcount):
        y=-HALF+(j+.5)*WIDTH/boardcount
        box('Deck plank',(cx,y,HEIGHT-.018),(DECK-.008,WIDTH/boardcount-.003,.036),deckmat,.002)
        # A restrained set of countersunk heads keeps the game mesh affordable.
        if j%2==0:
            for xx in [side*(LIP+.12),side*(BACK-.12)]:
                cylinder('Deck screw',(xx,y,HEIGHT+.0003),(xx,y,HEIGHT+.0013),.005,boltmat,8)
    # Only the deck top and outside edges collide. No hidden front wall behind the transition.
    x0,x1=side*LIP,side*BACK
    quad_collision((x0,-HALF,HEIGHT),(x1,-HALF,HEIGHT),(x1,HALF,HEIGHT),(x0,HALF,HEIGHT)) if side==1 else quad_collision((x1,-HALF,HEIGHT),(x0,-HALF,HEIGHT),(x0,HALF,HEIGHT),(x1,HALF,HEIGHT))
    # End caps face outwards; the top is the only surface the board rides.
    for yy in [-HALF,HALF]:
        a,b=(min(x0,x1),max(x0,x1))
        pp=[(a,yy,-.12),(b,yy,-.12),(b,yy,HEIGHT),(a,yy,HEIGHT)]
        if yy>0:pp.reverse()
        quad_collision(*pp)
    pp=[(x1,-HALF,-.12),(x1,HALF,-.12),(x1,HALF,HEIGHT),(x1,-HALF,HEIGHT)]
    if side<0:pp.reverse()
    quad_collision(*pp)
    cylinder('Continuous galvanized steel coping',(side*(LIP-.013),-HALF-.045,HEIGHT+.017),(side*(LIP-.013),HALF+.045,HEIGHT+.017),.029,steel,32)
    grind_marker(f'Coping_{side}',(side*(LIP-.013),-HALF,HEIGHT+.017),
                 (side*(LIP-.013),HALF,HEIGHT+.017),.029,'coping')
    # The seven top handrails and both coping pipes have grind centrelines.
    # Black steel railings with timber top rails; rail height 950 mm.
    posts=[(side*(BACK-.07),y) for y in [-HALF+.06,-HALF/2,0,HALF/2,HALF-.06]]
    for x,y in posts:
        box('Guardrail stanchion',(x,y,HEIGHT+.45),(.055,.055,.96),black,.003)
        box('Guardrail base plate',(x,y,HEIGHT+.012),(.14,.14,.024),black,.003)
    box('Back timber handrail',(side*(BACK-.07),0,HEIGHT+.95),(.10,WIDTH,.065),deckmat,.012)
    grind_marker(f'BackTop_{side}',(side*(BACK-.07),-HALF,HEIGHT+.95),
                 (side*(BACK-.07),HALF,HEIGHT+.95),.0325)
    for zz in [HEIGHT+.32,HEIGHT+.63]:
        box('Back steel horizontal guard',(side*(BACK-.07),0,zz),(.026,WIDTH-.1,.026),black,.003)
    for y in [-HALF+.06,HALF-.06]:
        # Leave the near edge of the right-hand deck open for the stairs.
        if side==1 and y<0:continue
        box('Side guardrail front post',(side*(LIP+.11),y,HEIGHT+.45),(.055,.055,.96),black,.003)
        box('Side timber handrail',(cx,y,HEIGHT+.95),(DECK-.08,.10,.065),deckmat,.012)
        grind_marker(f'SideTop_{side}_{y:.2f}',(cx-(DECK-.08)/2,y,HEIGHT+.95),
                     (cx+(DECK-.08)/2,y,HEIGHT+.95),.0325)
        for zz in [HEIGHT+.32,HEIGHT+.63]:
            box('Side horizontal guard',(cx,y,zz),(DECK-.12,.026,.026),black,.003)
    # Collision follows the actual rails and posts, leaving the gaps open.

# Right deck staircase: ten 180 mm rises, nine 300 mm treads.
STAIR_X=LIP+DECK/2
SW=1.14
for k in range(1,10):
    yy=-HALF-(k-.5)*.30;z=HEIGHT-k*.18
    box(f'Stair tread {k:02}',(STAIR_X,yy,z-.022),(SW,.31,.044),deckmat,.004)
    box(f'Stair riser {k:02}',(STAIR_X,yy-.145,z-.105),(SW,.025,.17),frame,.002)
    top_box_collision(STAIR_X-SW/2,STAIR_X+SW/2,yy-.15,yy+.15,z-.18,z)
for xx in [STAIR_X-SW/2+.065,STAIR_X+SW/2-.065]:
    beam('Stair structural stringer',(xx,-HALF-.04,HEIGHT-.19),(xx,-HALF-2.72,-.06),.09,.20,frame)
    # Rail joins the deck elevation at the top and follows the stair pitch.
    railtop=(xx,-HALF+.04,HEIGHT+.95)
    railbottom=(xx,-HALF-2.82,.95)
    beam('Stair oiled timber handrail',railbottom,railtop,.08,.08,deckmat)
    # Vertical distance from centreline to the pitched square rail surface.
    direction=(Vector(railtop)-Vector(railbottom)).normalized()
    radius=.04/math.sqrt(1-direction.z**2)
    grind_marker(f'StairTop_{xx:.3f}',railtop,railbottom,radius)
    for k in [0,3,6,9]:
        y=-HALF-k*.30;walk=HEIGHT-k*.18
        box('Stair rail steel upright',(xx,y,walk+.43),(.045,.045,.93),black,.003)
    beam('Stair lower guard',(xx,-HALF-2.73,.42),(xx,-HALF+.02,HEIGHT+.42),.025,.025,black)
    beam('Stair mid guard',(xx,-HALF-2.73,.68),(xx,-HALF+.02,HEIGHT+.68),.025,.025,black)

# Solid end caps on the coping, so tube ends never show holes.
# Shared origins preserve a useful asset pivot at the centre of the flat bottom.
for obj in parts:
    obj['asset']='Original wooden backyard half-pipe'

# Export evaluated copies, merged by material. Keep the editable source parts in the .blend.
export_collection=bpy.data.collections.new('TEMP optimized export')
scene=bpy.context.scene;scene.collection.children.link(export_collection)
bpy.ops.object.select_all(action='DESELECT')
groups={}
depsgraph=bpy.context.evaluated_depsgraph_get()
for original in parts:
    evaluated=original.evaluated_get(depsgraph)
    data=bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
    copy=bpy.data.objects.new(original.name,data);export_collection.objects.link(copy)
    copy.matrix_world=original.matrix_world.copy()
    key=original.data.materials[0].name
    groups.setdefault(key,[]).append(copy)
export_parts=[]
for key,objects in groups.items():
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    if len(objects)>1:bpy.ops.object.join()
    merged=bpy.context.object;merged.name='Halfpipe_'+key.split(' | ')[-1].replace(' ','_')
    # Stable, shared origin at the flat bottom's centre.
    scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    export_parts.append(merged)
bpy.ops.object.select_all(action='DESELECT')
for obj in export_parts+grind_markers:obj.select_set(True)
bpy.context.view_layer.objects.active=export_parts[0]
bpy.ops.export_scene.gltf(filepath=str(OUT/'wooden_halfpipe.glb'),export_format='GLB',use_selection=True,
                         export_apply=True,export_yup=True,export_materials='EXPORT',export_extras=True,
                         export_cameras=False,export_lights=False)
export_triangles=sum(len(o.data.polygons) and sum(len(p.vertices)-2 for p in o.data.polygons) for o in export_parts)
for obj in list(export_collection.objects):bpy.data.objects.remove(obj,do_unlink=True)
bpy.data.collections.remove(export_collection)

# Godot wrapper: GLB visuals plus a single concave STATIC collision shape.
# Blender (x,y,z) -> glTF/Godot (x,z,-y). No runtime script is required.
coords=[]
# Godot uses clockwise triangle fronts, so reverse Blender's CCW face winding.
for i in range(0,len(collision),3):
    for x,y,z in [collision[i],collision[i+2],collision[i+1]]:coords.extend([x,z,-y])
num=', '.join(f'{v:.6f}' for v in coords)
shape='[gd_resource type="ConcavePolygonShape3D" format=3]\n\n[resource]\nbackface_collision = false\ndata = PackedVector3Array('+num+')\n'
(OUT/'wooden_halfpipe_collision.tres').write_text(shape)
tscn="""[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="wooden_halfpipe.glb" id="1_visual"]
[ext_resource type="Shape3D" path="wooden_halfpipe_collision.tres" id="2_collision"]

[node name="WoodenHalfpipe" type="Node3D"]

[node name="Visual" parent="." instance=ExtResource("1_visual")]

[node name="COL_WoodenHalfPipe" type="StaticBody3D" parent="."]

[node name="CollisionShape3D" type="CollisionShape3D" parent="COL_WoodenHalfPipe"]
shape = ExtResource("2_collision")
"""
(OUT/'wooden_halfpipe.tscn').write_text(tscn)

# Presentation studio, retained in the .blend only.
ground=box('Studio ground',(0,0,-.21),(200,200,.1),solid('Studio sage charcoal',(.072,.091,.080),.86),0)
parts.remove(ground);move_to(ground,studio)

def aim(obj,target):obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()

def area(name,loc,power,size,color):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
    obj=bpy.data.objects.new(name,data);studio.objects.link(obj);obj.location=loc;aim(obj,(0,-.5,.5))
area('Key | large warm softbox',(0,-5,11),2200,8,(1,.84,.66))
area('Fill | cool sky',(3,6,8),1800,7,(.73,.84,1))
area('Rim | amber',(-8,1,6),1600,6,(1,.70,.43))
world=bpy.data.worlds.new('Soft daylight');world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.30,.37,.42,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.38
scene=bpy.context.scene;scene.world=world
camdata=bpy.data.cameras.new('Hero camera');cam=bpy.data.objects.new('Hero camera',camdata);studio.objects.link(cam)
cam.location=(12,-16,11.8);aim(cam,(.2,-.8,.65));camdata.type='ORTHO';camdata.ortho_scale=19.3;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=96;scene.cycles.use_denoising=False
scene.render.threads_mode='FIXED';scene.render.threads=4
scene.render.resolution_x=1600;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
scene.view_settings.view_transform='AgX'
scene.render.filepath=str(ART/'preview.png')
scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
# Keep the object easy to find when opening Blender.
bpy.ops.object.select_all(action='DESELECT');ride.select_set(True);bpy.context.view_layer.objects.active=ride
for screen in bpy.data.screens:
    for area_ in screen.areas:
        if area_.type=='VIEW_3D':
            area_.spaces.active.region_3d.view_perspective='CAMERA'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'wooden_halfpipe.blend'))
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'wooden_halfpipe.blend'))
meta={'height_m':HEIGHT,'width_m':WIDTH,'transition_radius_m':RADIUS,'flat_bottom_m':FLAT,'deck_depth_m':DECK,
      'length_including_decks_m':round(2*BACK,3),'width_including_stairs_m':round(WIDTH+2.85,3),
      'stair_rise_m':.18,'stair_tread_m':.30,'asset_objects':len(parts),'export_meshes':len(export_parts),'render_triangles':export_triangles,'collision_triangles':len(collision)//3,'grind_paths':len(grind_markers),
      'rail_paths':sum(m['kind']=='rail' for m in grind_markers),'coping_paths':sum(m['kind']=='coping' for m in grind_markers),
      'blender_version':bpy.app.version_string}
(OUT/'dimensions.json').write_text(json.dumps(meta,indent=2)+'\n')
print('ASSET_METADATA',json.dumps(meta),flush=True)
if '--no-render' not in sys.argv:
    bpy.ops.render.render(write_still=True)
print('ASSET_COMPLETE',str(OUT),flush=True)
