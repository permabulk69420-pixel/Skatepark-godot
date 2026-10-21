"""Build the skater's house. Usage: blender -b -P build_house.py
Self-contained deterministic textures; no external assets or add-ons required.
Optional: HOUSE_PREVIEWS=0 skips preview renders. All deliverables beside script.
"""
import bpy, math, os, json, random
import numpy as np
from mathutils import Vector, Matrix
from pathlib import Path
ROOT=Path(__file__).resolve().parent
random.seed(71)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for block in list(bpy.data.materials): bpy.data.materials.remove(block)
S=bpy.context.scene; S.unit_settings.system='METRIC'; S.unit_settings.scale_length=1
M={}; G={}; collision_boxes=[]
# Vertex-colour tone is multiplied by already baked image colour (plain glTF PBR).
def texture(name, kind, base, n=1024):
    rng=np.random.default_rng(113+len(M)); y,x=np.mgrid[0:n,0:n].astype(float)/n
    noise=rng.normal(0,1,(n,n)); fine=rng.normal(0,.012,(n,n))
    grain=.03*np.sin(2*math.pi*(y*95+1.8*np.sin(x*6.28)))+.018*np.sin(y*6.28*317+x*7)
    a=np.zeros((n,n,4),dtype=np.float32); a[:,:,:3]=base; a[:,:,3]=1
    if kind in ('wood','paint'):
        # Seamless anisotropic noise: long fibres, not repeating sine-wave grain.
        fy=np.fft.fftfreq(n)[:,None];fx=np.fft.fftfreq(n)[None,:]
        filt=np.exp(-((fx*n/3)**2+(fy*n/95)**2))
        fibres=np.fft.ifft2(np.fft.fft2(noise)*filt).real
        fibres/=max(fibres.std(),1e-6)
        coarse=np.fft.ifft2(np.fft.fft2(noise)*np.exp(-((fx*n/6)**2+(fy*n/7)**2))).real
        coarse/=max(coarse.std(),1e-6)
        a[:,:,:3]+=(.015*fibres+.009*coarse+fine*.45)[:,:,None]
        if kind=='paint':
            rows=np.floor(y*12).astype(int);rv=rng.uniform(-.025,.025,12)
            a[:,:,:3]+=rv[rows][:,:,None]
            phase=(y*12)%1
            seam=np.where(phase<.025,.56,np.where(phase<.055,.88,1.0))
            a[:,:,:3]*=seam[:,:,None]
            # Small, irregular exposed-wood scuffs, concentrated by board edges.
            wear=(coarse>1.4)&(fibres>1.0)&((phase<.22)|(phase>.9))
            a[wear,:3]=np.array([.40,.34,.24])
        else:
            edge=.91+.09*np.minimum(1,np.minimum(y,1-y)*45)
            a[:,:,:3]*=edge[:,:,None]
            # One small subdued knot per tile; no oversized repeated circles.
            cx=.71;cy=.47;r=((x-cx)/.028)**2+((y-cy)/.055)**2
            a[:,:,:3]-=(.045*np.exp(-r)*(.7+.3*np.cos(r*5)))[:,:,None]
    elif kind=='roof':
        a[:,:,:3]+=(fine+.028*np.sin(x*6.28*80))[:,:,None]
        rust=np.clip((np.sin(x*6.28*13)+np.sin(x*6.28*37)*.4-1.0)*2,0,1)*(0.25+.75*(.5+.5*np.cos(y*6.28)))
        a[:,:,:3]=a[:,:,:3]*(1-rust[:,:,None]*.7)+np.array([.30,.13,.055])*rust[:,:,None]*.7
    elif kind=='fabric':
        a[:,:,:3]+=(fine+.015*np.sin(x*6.28*256)*np.sin(y*6.28*256))[:,:,None]
        edge=.88+.12*np.minimum(1,np.minimum(np.minimum(x,1-x),np.minimum(y,1-y))*18)
        a[:,:,:3]*=edge[:,:,None]
    elif kind in ('dirt','concrete'):
        fy=np.fft.fftfreq(n)[:,None];fx=np.fft.fftfreq(n)[None,:]
        freq2=(fx*n)**2+(fy*n)**2
        cloud=np.fft.ifft2(np.fft.fft2(noise)*np.exp(-freq2/30)).real
        cloud/=max(cloud.std(),1e-6)
        mottling=np.fft.ifft2(np.fft.fft2(noise)*np.exp(-freq2/800)).real
        mottling/=max(mottling.std(),1e-6)
        a[:,:,:3]+=(fine*1.3+.012*cloud+.009*mottling)[:,:,None]
        if kind=='dirt':
            grass=np.clip((cloud-.4)*.08,0,.18)
            a[:,:,:3]+=grass[:,:,None]*np.array([-.32,-.05,-.35])
    a=np.clip(a,0,1)
    img=bpy.data.images.new(name+'_BaseColor',width=n,height=n,alpha=False)
    img.pixels.foreach_set(a.ravel()); img.filepath_raw=str(ROOT/(name+'.jpg')); img.file_format='JPEG'; img.save(); img.pack()
    return img

def mat(name,color,rough=.8,kind=None,metal=0,emission=0):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True; m.use_backface_culling=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1); p.inputs['Roughness'].default_value=rough; p.inputs['Metallic'].default_value=metal
    if kind:
        t=m.node_tree.nodes.new('ShaderNodeTexImage'); t.image=texture(name,kind,color); t.interpolation='Linear'; m.node_tree.links.new(t.outputs['Color'],p.inputs['Base Color'])
    if emission:
        en=p.inputs.get('Emission Color') or p.inputs.get('Emission'); en.default_value=(*color,1)
        if p.inputs.get('Emission Strength'):p.inputs['Emission Strength'].default_value=emission
    M[name]=m; return name
CL=mat('Timber_Cladding',(.64,.72,.64),kind='paint')
FL=mat('Timber_Floor',(.49,.36,.23),kind='wood')
TR=mat('Timber_Trim',(.29,.205,.125),kind='wood')
RO=mat('Metal_Galvanised',(.56,.59,.57),.72,'roof',.55)
ME=mat('Metal_Dark',(.055,.065,.065),.56,metal=.5)
CO=mat('Concrete_Worn',(.55,.54,.49),kind='concrete')
DI=mat('Dirt_Yard',(.43,.37,.26),kind='dirt')
FA=mat('Fabric_Upholstery',(.23,.35,.34),kind='fabric')
DE=mat('Decal_Atlas',(.9,.65,.30))
EM=mat('Emissive_Lamp',(1,.77,.42),.5,emission=1.2)
TV=mat('TV_Screen',(.003,.004,.005),.42)
# A decal atlas with warm paper, cream ink, muted red, navy, yellow, green.
palette=[(.87,.81,.65),(.96,.91,.73),(.60,.19,.11),(.06,.12,.15),(.91,.59,.16),(.25,.39,.32),(.12,.13,.12),(.8,.48,.30)]
a=np.ones((256,1024,4),dtype=np.float32)
for i,c in enumerate(palette):
    a[:,i*128:(i+1)*128,:3]=c
    a[:,i*128:(i+1)*128,:3]*=np.random.default_rng(i).uniform(.94,1,(256,128,1))
im=bpy.data.images.new('Decal_Atlas_BaseColor',1024,256,alpha=False); im.pixels.foreach_set(a.ravel()); im.filepath_raw=str(ROOT/'Decal_Atlas.jpg'); im.file_format='JPEG'; im.save(); im.pack()
t=M[DE].node_tree.nodes.new('ShaderNodeTexImage');t.image=im;M[DE].node_tree.links.new(t.outputs['Color'],M[DE].node_tree.nodes.get('Principled BSDF').inputs['Base Color'])

def acc(zone,material):
    key=(zone,material)
    if key not in G:G[key]=[[],[],[]]
    return G[key]
def face(zone,material,vs,uv=None):
    v,f,u=acc(zone,material);start=len(v);v.extend(vs);f.append(tuple(range(start,start+len(vs))))
    if uv is None:
        p=[Vector(q) for q in vs]; normal=(p[1]-p[0]).cross(p[2]-p[0]); ax=max(range(3),key=lambda i:abs(normal[i])); keep=[i for i in range(3) if i!=ax]
        uv=[(q[keep[0]]*.55,q[keep[1]]*.55) for q in vs]
    u.append(uv)
def box(zone,material,center,size,rot=None,collide=False):
    c=Vector(center); sx,sy,sz=[s/2 for s in size]
    if zone=='COL_Walls':
        assert rot is None, 'Collision union expects axis-aligned boxes'
        collision_boxes.append((tuple(center),tuple(size)))
    vv=[Vector(q) for q in [(-sx,-sy,-sz),(sx,-sy,-sz),(sx,sy,-sz),(-sx,sy,-sz),(-sx,-sy,sz),(sx,-sy,sz),(sx,sy,sz),(-sx,sy,sz)]]
    if rot is not None:vv=[rot@q for q in vv]
    vv=[tuple(c+q) for q in vv]
    faces=[(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]
    if material==FA and min(size)>.10:
        import bmesh
        bm=bmesh.new();bv=[bm.verts.new(v) for v in vv]
        for inds in faces:bm.faces.new([bv[i] for i in inds])
        bm.normal_update();bmesh.ops.bevel(bm,geom=list(bm.edges),offset=min(.055,min(size)*.22),segments=3,affect='EDGES');bm.normal_update()
        for f in bm.faces:face(zone,material,[tuple(v.co) for v in f.verts])
        bm.free()
    else:
        for inds in faces: face(zone,material,[vv[i] for i in inds])
    if collide:
        box('COL_Walls',None,center,size,rot)
def beam(zone,material,a,b,w,d=None,collide=False):
    a=Vector(a);b=Vector(b);r=(b-a).to_track_quat('Z','Y').to_matrix();box(zone,material,(a+b)/2,(w,d or w,(b-a).length),r,collide)
def cyl(zone,material,a,b,r,n=10,r2=None):
    a=Vector(a);b=Vector(b);rot=(b-a).to_track_quat('Z','Y').to_matrix();r2=r if r2 is None else r2
    va=[a+rot@Vector((r*math.cos(i*math.tau/n),r*math.sin(i*math.tau/n),0)) for i in range(n)]
    vb=[b+rot@Vector((r2*math.cos(i*math.tau/n),r2*math.sin(i*math.tau/n),0)) for i in range(n)]
    face(zone,material,[tuple(v) for v in va[::-1]]);face(zone,material,[tuple(v) for v in vb])
    for i in range(n):j=(i+1)%n;face(zone,material,[tuple(va[i]),tuple(va[j]),tuple(vb[j]),tuple(vb[i])])
def top(x0,x1,y0,y1,z0,z1=None):
    if z1 is None:z1=z0
    face('COL_Floors',None,[(x0,y0,z0),(x1,y0,z0),(x1,y1,z1),(x0,y1,z1)])
def mark(name,role,loc,heading=None,**props):
    o=bpy.data.objects.new(name,None);S.collection.objects.link(o);o.empty_display_type='PLAIN_AXES';o.empty_display_size=.18;o.location=loc;o['role']=role
    if heading is not None:o['heading_radians']=float(heading)
    for k,v in props.items():o[k]=v
    return o
# Closed render floor bases; all finished floor surfaces exactly .30.
box('Interior',FL,(-3,0,.19),(8,9,.22))
box('Interior',CO,(4,0,.19),(6,9,.22))
# Plank seams are colour in texture plus slim inset joint strips BELOW finished face.
# Each plank has a separate grain UV offset; tops remain mathematically coplanar.
for iy in range(45):
    y=-4.5+(iy+.5)*.2
    for ix in range(4):
        x=-6+ix*2
        # Tops at .30; no overlapping underlying floor face: base top .298 below overlay.
        face('Interior',FL,[(x-1,y-.1,.301),(x+1,y-.1,.301),(x+1,y+.1,.301),(x-1,y+.1,.301)],[(ix*.27+iy*.137,0),(ix*.27+iy*.137+1,0),(ix*.27+iy*.137+1,1),(ix*.27+iy*.137,1)])
# correct overlays / base below top: plank overlay is z=.30, base z=.299
for key,(vs,fs,us) in G.items():
    if key==('Interior',FL):
        G[key][0]=[(x,y,.30 if abs(z-.301)<1e-6 else (.298 if abs(z-.30)<1e-6 else z)) for x,y,z in vs]
top(-7,7,-4.5,4.5,.30)
# Raised perimeter fascia and low piers.
for y0,y1 in [(-7.2,-4.7),(4.7,7.7)]:
    box('Exterior',TR,(0,(y0+y1)/2,.145),(14.4,y1-y0,.29))
    count=round((y1-y0)/.125)
    for j in range(count):
        ya=y0+(y1-y0)*j/count;yb=y0+(y1-y0)*(j+1)/count
        face('Exterior',FL,[(-7.2,ya,.3),(7.2,ya,.3),(7.2,yb,.3),(-7.2,yb,.3)],[(0,0),(7.2,0),(7.2,1),(0,1)])
    top(-7.2,7.2,y0,y1,.3)
# Floors through wall depth at both openings.
for x0,x1,y0,y1 in [(-.55,.55,-4.7,-4.5),(-1,3,4.5,4.7)]:
    box('Interior',FL,((x0+x1)/2,(y0+y1)/2,.24),(x1-x0,y1-y0,.12));top(x0,x1,y0,y1,.3)
# Walls constructed from real .2m solids, with window holes in render and window blockers in collision.
front=[(-.55,.55,.3,2.4),(-5.3,-3.7,1.2,2.5),(3.7,5.3,1.2,2.5)]
back=[(-1,3,.3,2.7),(-5.8,-4.2,1.2,2.5),(4.7,6.3,1.2,2.5)]
def wall(y,holes):
    xs=sorted(set([-7.2,7.2]+[a for h in holes for a in h[:2]]));zs=sorted(set([.3,3.3]+[a for h in holes for a in h[2:]]))
    for x0,x1 in zip(xs,xs[1:]):
      for z0,z1 in zip(zs,zs[1:]):
        mx=(x0+x1)/2;mz=(z0+z1)/2
        if not any(a<mx<b and c<mz<d for a,b,c,d in holes):
          box('Shell',CL,(mx,y,mz),(x1-x0,.2,z1-z0))
    # Collision spans full height except doorway, with windows solid.
    door=holes[0];a,b,_,h=door
    box('COL_Walls',None,((-7.2+a)/2,y,1.8),(a+7.2,.2,3))
    box('COL_Walls',None,((b+7.2)/2,y,1.8),(7.2-b,.2,3))
    box('COL_Walls',None,((a+b)/2,y,(h+3.3)/2),(b-a,.2,3.3-h))
    # Horizontal narrow weatherboard laps, stopped cleanly at all holes.
    for k in range(20):
      z=.34+k*.15
      intervals=[(-7.2,7.2)]
      for a,b,c,d in holes:
        if c-.015<z<d+.015:
          ints=[]
          for l,r in intervals:
            if l<a:ints.append((l,min(a,r)))
            if r>b:ints.append((max(b,l),r))
          intervals=[(l,r) for l,r in ints if r-l>.001]
      for l,r in intervals:box('Shell',CL,((l+r)/2,y+(.104 if y>0 else -.104),z),(r-l,.009,.018))
    # Opening trim stays outside clear dimensions.
    for idx,(a,b,c,d) in enumerate(holes):
      for side in [-1,1]:
        yy=y+side*.117
        for x in [a-.045,b+.045]:box('Shell',TR,(x,yy,(c+d)/2),(.09,.045,d-c+.16))
        box('Shell',TR,((a+b)/2,yy,d+.045),(b-a+.18,.045,.09))
        if idx:
          box('Shell',TR,((a+b)/2,yy,c-.045),(b-a+.22,.12,.09))
      if idx:
        # Shutters laid flat beside window, louvres and diagonal hardware.
        yy=y+(.18 if y>0 else -.18)
        for s in [-1,1]:
          xx=(a-.25 if s<0 else b+.25)
          box('Exterior',TR,(xx,yy,(c+d)/2),(.38,.055,d-c))
          for k in range(10):box('Exterior',CL,(xx,yy+(.04 if y>0 else -.04),c+.065+k*.13),(.32,.04,.075))
wall(-4.6,front);wall(4.6,back)
for x in [-7.1,7.1]:
    box('Shell',CL,(x,0,1.8),(.2,9,3))
    box('COL_Walls',None,(x,0,1.8),(.2,9,3))
    for k in range(20):box('Shell',CL,(x+(.104 if x>0 else -.104),0,.34+k*.15),(.009,9,.018))
    # Closed gable prism, ridge runs along X.
    xl=x-.1;xr=x+.1;tri=[(-4.5,3.3),(4.5,3.3),(0,4.9)]
    face('Shell',CL,[(xl,y,z) for y,z in tri[::-1]]);face('Shell',CL,[(xr,y,z) for y,z in tri])
    for i in range(3):j=(i+1)%3;face('Shell',CL,[(xl,*tri[i]),(xl,*tri[j]),(xr,*tri[j]),(xr,*tri[i])])
# Skirting, corner uprights, continuous lintels; retain opening widths.
for x in [-6.96,6.96]:box('Interior',TR,(x,0,.37),(.07,9,.14))
for y,holes in [(-4.46,front),(4.46,back)]:
    a,b=holes[0][:2]
    for l,r in [(-7,a),(b,7)]:box('Interior',TR,((l+r)/2,y,.37),(r-l,.07,.14))
for x in [-7.04,7.04]:
 for y in [-4.54,4.54]:box('Shell',TR,(x,y,1.8),(.18,.18,3))
for y in [-4.46,4.46]:box('Shell',TR,(0,y,3.23),(14,.16,.14))
# Roof: physical corrugations, longitudinal rust-streak image, thin closed sheets.
def roof(y0,y1,z0,z1,x0=-7.5,x1=7.5):
    # Corrugation runs DOWN the pitch (variation across x).
    N=round((x1-x0)/.0375);thick=.025
    for i in range(N):
      a=x0+(x1-x0)*i/N;b=x0+(x1-x0)*(i+1)/N
      h0=.016*math.cos((a-x0)*math.tau/.15);h1=.016*math.cos((b-x0)*math.tau/.15)
      vv=[(a,y0,z0+h0),(b,y0,z0+h1),(b,y1,z1+h1),(a,y1,z1+h0)]
      if y1<y0:vv=vv[::-1]
      face('Roof',RO,vv,[(q[0]/3,q[1]/5) for q in vv]);face('Roof',RO,[(x,y,z-thick) for x,y,z in vv[::-1]])
    for x in [x0,x1]:beam('Roof',TR,(x,y0,z0-.055),(x,y1,z1-.055),.12)
    beam('Roof',TR,(x0,y1,z1-.055),(x1,y1,z1-.055),.12)
roof(0,-4.9,5.025,3.285);roof(0,4.9,5.025,3.285)
roof(4.65,7.95,3.51,3.06);roof(-4.65,-7.45,3.51,3.06)
# Ridge cap.
beam('Roof',RO,(-7.55,0,5.065),(7.55,0,5.065),.14,.15)
# Exposed pitched rafters underside ≥3.30 at side walls.
for x in [-6.8,-4.5,-2.25,0,2.25,4.5,6.8]:
    for sign in [-1,1]:beam('Shell',TR,(x,0,4.88),(x,sign*4.5,3.36),.13,.17)
beam('Shell',TR,(-7,0,4.82),(7,0,4.82),.18,.22)
for yy in [-3,-1.5,1.5,3]:
    zz=4.98-abs(yy)*1.6/4.5-.08;beam('Shell',TR,(-7,yy,zz),(7,yy,zz),.065,.075)
# Veranda posts and braces. Open middle access to front steps and rear ramp.
for y in [-7.12,7.62]:
 for x in [-7.1,-4.1,-1.1,2.9,5.9,7.1]:
    # Front stair opening 3m, posts kept outside it.
    if y<0 and x==-1.1:x=-1.65
    box('Exterior',TR,(x,y,1.655),(.14,.14,2.71),collide=True)
    beam('Exterior',TR,(x,y,2.96),(x+(.25 if x<6 else -.25),y,3.08),.075)
    box('Exterior',ME,(x,y,.36),(.17,.17,.12))
 for x in [-6,-3,0,3,6]:
    beam('Exterior',TR,(x,4.7 if y>0 else -4.7,3.39),(x,y,2.96),.095,.12)
 beam('Exterior',TR,(-7.2,y,3.01),(7.2,y,3.01),.14,.15)
def railing(a,b):
    a=Vector(a);b=Vector(b)
    for z in [.52,1.25]:beam('Exterior',TR,(*a[:2],z),(*b[:2],z),.09,.1)
    length=(b-a).length
    n=max(1,int(length/.22))
    for k in range(n+1):
      p=a+(b-a)*k/n;box('Exterior',CL,(p.x,p.y,.86),(.045,.045,.68))
    center=(a+b)/2;delta=b-a
    box('COL_Walls',None,(center.x,center.y,.8),(max(abs(delta.x),.1),max(abs(delta.y),.1),1.0))
for y,gap in [(7.63,(-.5,2.5)),(-7.13,(-1.5,1.5))]:
 railing((-7.1,y,0),(gap[0],y,0));railing((gap[1],y,0),(7.1,y,0))
 for x in [-7.1,7.1]:railing((x,4.8 if y>0 else -4.8,0),(x,y,0))
# Straight 1:8 ramp: deck top .30 at y7.7, ground 0 at10.1.
rv=[(-.5,7.7,.30),(2.5,7.7,.30),(2.5,10.1,0),(-.5,10.1,0)]
face('Exterior',FL,rv,[(0,0),(3,0),(3,2.4),(0,2.4)])
for x in [-.5,2.5]:
    face('Exterior',TR,[(x,7.7,0),(x,7.7,.3),(x,10.1,0)] if x<0 else [(x,7.7,0),(x,10.1,0),(x,7.7,.3)])
top(-.5,2.5,7.7,10.1,.3,0)
for j in range(3):
    y0=-7.2-(j+1)*.3;y1=y0+.3;h=.3-j*.1
    box('Exterior',TR,(0,(y0+y1)/2,h/2),(3,.3,h));top(-1.5,1.5,y0,y1,h)
# Terrain tiled into a ring outside property, avoiding overlap with yard and ramp pad.
def groundrect(x0,x1,y0,y1,material=DI,z=0):face('Ground',material,[(x0,y0,z),(x1,y0,z),(x1,y1,z),(x0,y1,z)])
# Outer ground extends 250 m from origin, property and slab are cut out.
for r in [(-250,-20,-250,250),(20,250,-250,250),(-20,20,-250,-12),(-20,20,30,250)]:groundrect(*r)
for r in [(-20,-7,-12,30),(9,20,-12,30),(-7,9,-12,15),(-7,9,24,30)]:groundrect(*r);top(*r,0)
groundrect(-7,9,15,24,CO,0);top(-7,9,15,24,0)
# Thin visible slab side walls below grade, no top overlays or pad objects.
# Fence solid and closed front gate, all outside slab's 3m exclusion border.
for y in [-12,30]:
    for j in range(20):
      x=-19+j*2
      if y==-12 and -3<x<3:material=RO
      else:material=CL if j%4 else RO
      box('Exterior',material,(x,y,.9),(1.985,.09,1.8))
    box('COL_Walls',None,(0,y,.9),(40,.12,1.8))
    for x in range(-20,21,2):box('Exterior',TR,(x,y,.9),(.12,.14,1.8))
    for z in [.4,1.4]:beam('Exterior',TR,(-20,y+.06,z),(20,y+.06,z),.08)
for x in [-20,20]:
    for j in range(21):box('Exterior',CL,(x,-11+j*2,.9),(.09,1.985,1.8))
    box('COL_Walls',None,(x,9,.9),(.12,42,1.8))
    for y in range(-12,31,2):box('Exterior',TR,(x,y,.9),(.14,.12,1.8))
    for z in [.4,1.4]:beam('Exterior',TR,(x-.06,-12,z),(x-.06,30,z),.08)
# Closed gate frame and diagonal braces.
for x in [-2,2]:box('Exterior',ME,(x,-11.91,.9),(.08,.06,1.8))
beam('Exterior',ME,(-2,-11.91,.15),(2,-11.91,1.65),.06)
# Furniture: sofa back precisely x=-2.2, couch faces west.
box('Interior',TR,(-2.65,0,.48),(.9,2.2,.16))
box('Interior',FA,(-2.29,0,.89),(.18,2.2,.82))
for y in [-1.02,1.02]:box('Interior',FA,(-2.65,y,.82),(.9,.16,.62))
for y in [-.63,0,.63]:
    box('Interior',FA,(-2.72,y,.67),(.68,.60,.16))
    box('Interior',FA,(-2.42,y,.96),(.13,.60,.44),Matrix.Rotation(-.14,3,'Y'))
    # piping narrow dark timber? fabric piping same material
    for yy in [y-.30,y+.30]:cyl('Interior',FA,(-3.03,yy,.735),(-2.45,yy,.735),.012,6)
for x in [-2.95,-2.35]:
 for y in [-.9,.9]:box('Interior',TR,(x,y,.395),(.07,.07,.19))
box('COL_Walls',None,(-2.65,0,.8),(.9,2.2,1))
# Coffee table .45m above floor, top .75, remote point correct.
box('Interior',FL,(-4.4,0,.715),(.6,1.2,.07))
for x in [-4.63,-4.17]:
 for y in [-.5,.5]:box('Interior',ME,(x,y,.505),(.04,.04,.41))
box('COL_Walls',None,(-4.4,0,.525),(.6,1.2,.45))
# TV west wall, screen plane x=-6.895, outward +X, U right = +Y.
box('Interior',ME,(-6.965,0,1.975),(.07,2.5,1.45))
box('COL_Walls',None,(-6.96,0,1.975),(.08,2.5,1.45))
face('TV_Screen',TV,[(-6.923,-1.2,1.3),(-6.923,1.2,1.3),(-6.923,1.2,2.65),(-6.923,-1.2,2.65)],[(0,0),(1,0),(1,1),(0,1)])
# Media bench beneath TV, kept close to wall.
box('Interior',TR,(-6.68,0,.59),(.52,2.9,.12))
for y in [-1.30,1.30]:box('Interior',ME,(-6.68,y,.435),(.40,.06,.27))
box('COL_Walls',None,(-6.68,0,.475),(.52,2.9,.35))
# Shop counter, 3.6m along Y, exactly 1.05m above floor.
box('Interior',CL,(2.8,0,.78),(.65,3.52,.96))
box('Interior',FL,(2.8,0,1.315),(.7,3.6,.07))
box('Interior',TR,(2.8,0,.36),(.7,3.6,.12))
box('COL_Walls',None,(2.8,0,.825),(.7,3.6,1.05))
for y in [-1.6,-.8,0,.8,1.6]:box('Interior',TR,(2.464,y,.79),(.04,.045,.82))
# Small till and repair tray on counter, collision included.
box('Interior',ME,(2.84,1.28,1.43),(.32,.32,.16),collide=True)
box('Interior',TR,(2.8,-1.1,1.38),(.4,.5,.06),collide=True)
for y in [-1.20,-1.08,-.96]:cyl('Interior',ME,(2.65,y,1.43),(2.90,y,1.43),.018,8)
# Board wall timber racks with narrow padded uprights and clear marker centres.
for z in [.80,1.65]:
    box('Interior',TR,(6.89,0,z),(.22,3.3,.10),collide=True)
    box('Interior',ME,(6.765,0,z+.06),(.035,3.3,.04))
for y in [-1.25,-.75,-.25,.25,.75,1.25]:
    box('Interior',TR,(6.977,y,1.55),(.04,.09,1.7))
    for z in [1.55,2.4]:cyl('Interior',ME,(6.94,y,z),(6.83,y,z),.023,8)
# Entry shoe bench, north-west mini-fridge: wall-adjacent props away from through routes.
box('Interior',TR,(-2,-4.13,.57),(1.25,.5,.10),collide=True)
for x in [-2.52,-1.48]:box('Interior',TR,(x,-4.13,.43),(.08,.4,.26),collide=True)
for x in [-2.35,-2.08,-1.81]:box('Interior',FA,(x,-4.12,.38),(.19,.31,.12))
box('Interior',CL,(-6.55,3.92,.765),(.72,.65,.93),collide=True)
box('Interior',ME,(-6.55,3.58,.79),(.69,.025,.82))
box('Interior',RO,(-6.55,3.559,.80),(.65,.012,.78))
box('Interior',ME,(-6.30,3.52,.93),(.035,.04,.24))
# Plants: terracotta colour sourced from atlas, robust low-poly leaves.
def plant(x,y,z,r=.22):
    cyl('Interior',TR,(x,y,z),(x,y,z+.32),r*.8,12,r)
    cyl('Interior',DI,(x,y,z+.321),(x,y,z+.325),r*.9,12)
    for i in range(9):
      ang=i*2.4;h=.32+random.uniform(.35,.7);dx=math.cos(ang)*.28;dy=math.sin(ang)*.28
      beam('Interior',TR,(x,y,z+.32),(x+dx,y+dy,z+h),.012)
      p=Vector((x+dx,y+dy,z+h));d=Vector((math.cos(ang),math.sin(ang),.15))*.24;s=Vector((-math.sin(ang),math.cos(ang),0))*.07
      vv=[p-d,p+s,p+d,p-s];face('Interior',FA,[tuple(v) for v in vv]);face('Interior',FA,[(v.x,v.y,v.z-.003) for v in vv[::-1]])
    box('COL_Walls',None,(x,y,z+.5),(.6,.6,1.0))
plant(-6.45,-3.75,.3);plant(6.45,3.8,.3)
# Deck-shaped board props, kept against south wall at west end, distinct from slots.
for k in range(2):
    y=-4.23;x=-6.10+k*.36
    # Hanging/leaning vertical decks with rounded ends, wheel hardware.
    outline=[]
    for i in range(9):
      a=math.pi*i/8;outline.append((x+.105*math.cos(a),y,1.03+.105*math.sin(a)))
    for i in range(9):
      a=math.pi+math.pi*i/8;outline.append((x+.105*math.cos(a),y,.49+.105*math.sin(a)))
    face('Interior',FL,outline);face('Interior',ME,[(a,b+.025,c) for a,b,c in outline[::-1]])
    for z in [.55,.97]:
      cyl('Interior',RO,(x-.10,y-.035,z),(x+.1,y-.035,z),.022,8)
      for xx in [x-.11,x+.11]:cyl('Interior',FA,(xx-.02,y-.045,z),(xx+.02,y-.045,z),.038,10)
    box('COL_Walls',None,(x,y,.75),(.26,.12,.9))
# Decals: opaque atlas quads with separate crisp mesh lettering, all static merged.
def decal_quad(center,w,h,orient='north',color=0):
    x,y,z=center
    if orient=='north':vv=[(x-w/2,y,z-h/2),(x+w/2,y,z-h/2),(x+w/2,y,z+h/2),(x-w/2,y,z+h/2)]
    elif orient=='south':vv=[(x+w/2,y,z-h/2),(x-w/2,y,z-h/2),(x-w/2,y,z+h/2),(x+w/2,y,z+h/2)]
    elif orient=='west':vv=[(x,y+w/2,z-h/2),(x,y-w/2,z-h/2),(x,y-w/2,z+h/2),(x,y+w/2,z+h/2)]
    u=(color+.5)/8;face('Interior',DE,vv,[(u-.05,.1),(u+.05,.1),(u+.05,.9),(u-.05,.9)])
def label(text,loc,size,orient='north',color=1):
    curve=bpy.data.curves.new('lettering','FONT');curve.body=text;curve.size=size;curve.align_x='CENTER';curve.align_y='CENTER';curve.resolution_u=2
    o=bpy.data.objects.new('lettering',curve);S.collection.objects.link(o);o.location=loc
    if orient=='north':o.rotation_euler=(math.pi/2,0,0) # normal -Y
    elif orient=='south':o.rotation_euler=(math.pi/2,0,math.pi)
    elif orient=='west':o.rotation_euler=(math.pi/2,0,-math.pi/2) # normal -X
    bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH');bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    mesh=o.data
    for p in mesh.polygons:face('Interior',DE,[tuple(mesh.vertices[i].co) for i in p.vertices],[( (color+.5)/8,.5)]*len(p.vertices))
    bpy.data.objects.remove(o,do_unlink=True)
# North wall posters look toward south, lettering outward -Y.
for x,w,h,col,txt in [(-3.25,.85,1.15,2,'STATIC\nYOUTH'),(-2.20,.72,.95,3,'CURB\nRATS')]:
    decal_quad((x,4.485,1.85),w,h,'north',col);label(txt,(x,4.48,1.9),.18,'north',1);label('LIVE / ALL AGES',(x,4.478,1.43),.055,'north',1)
# Sign against east wall looks west.
decal_quad((6.975,0,2.91),3.2,.36,'west',3);label('LOCAL  /  SKATE SUPPLY',(6.965,0,2.91),.16,'west',1)
for i,y in enumerate([-1.25,-.75,-.25,.25,.75,1.25]):
 for row,z in enumerate([.8,1.65]):label('%02d'%(i+1+row*6),(6.754,y,z),.045,'west',1)
# Counter badge facing west.
decal_quad((2.443,0,.89),1.25,.41,'west',3);label('ROLL / REPAIR',(2.438,0,.90),.13,'west',1)
for i,(y,z) in enumerate([(-1.15,.6),(-.82,1.09),(.95,.65)]):
    decal_quad((2.440,y,z),.23,.12,'west',i+2);label(['DIY','LOUD','SK8'][i],(2.435,y,z),.055,'west',1)
# Porch street sign and workshop sign.
decal_quad((1.4,-4.723,2.63),1.1,.34,'north',3);label('THE LOCAL',(1.4,-4.729,2.63),.14,'north',1)
# Visible hanging fixtures: shades and warm bulb lenses, no Blender lights.
lamps=[(-4,-2.2,2.97),(-4,2.2,2.97),(2,-2.8,2.98),(4.6,0,3.23),(2,2.8,2.98),(1,6.25,3.04)]
for i,(x,y,z) in enumerate(lamps,1):
    roofz=(4.94-abs(y)*1.6/4.5) if abs(y)<4.5 else 3.27
    cyl('Interior' if i<6 else 'Exterior',ME,(x,y,z+.17),(x,y,roofz),.012,6)
    zone='Interior' if i<6 else 'Exterior'
    cyl(zone,ME,(x,y,z-.12),(x,y,z+.12),.23,16,.08)
    cyl(zone,EM,(x,y,z-.125),(x,y,z-.115),.19,16)
    mark('Light_%02d'%i,'light',(x,y,z-.13),energy=float(.65 if i<6 else .45))
# Festoon string on back veranda, bulb bottoms above z2.7.
for j in range(23):
    x0=-6.9+j*.6;x1=x0+.6;z0=3.10-.07*math.sin(j/23*math.pi);z1=3.10-.07*math.sin((j+1)/23*math.pi)
    beam('Exterior',ME,(x0,7.38,z0),(x1,7.38,z1),.008)
    if j%2==0:
      cyl('Exterior',ME,(x0,7.38,z0),(x0,7.38,z0-.05),.018,8)
      cyl('Exterior',EM,(x0,7.38,z0-.05),(x0,7.38,z0-.10),.035,8,.02)
# Required gameplay empties (global Blender Z-up coordinates).
mark('Spawn_Hub','spawn',(0,-3,.3),0)
mark('Remote_Spot','remote_spot',(-4.4,0,.75))
for row,z in enumerate([1.25,2.10]):
 for j,y in enumerate([-1.25,-.75,-.25,.25,.75,1.25]):mark('BoardSlot_%02d'%(row*6+j+1),'board_slot',(6.95,y,z),1.5708)
mark('RampPad','ramp_pad',(1,19.5,0),-1.5708,pad_length=16.0,pad_width=9.0)
# Exact union of axis-aligned collision solids: remove all buried / coincident
# internal faces. Greedy planar rectangles keep the collision budget very low.
coords=[sorted(set(round(c[k]+s[k]*sign/2,6) for c,s in collision_boxes for sign in [-1,1])) for k in range(3)]
index=[{v:i for i,v in enumerate(cs)} for cs in coords]
occ=np.zeros(tuple(len(cs)-1 for cs in coords),dtype=bool)
for c,s in collision_boxes:
    lo=[index[k][round(c[k]-s[k]/2,6)] for k in range(3)];hi=[index[k][round(c[k]+s[k]/2,6)] for k in range(3)]
    occ[lo[0]:hi[0],lo[1]:hi[1],lo[2]:hi[2]]=True
G.pop(('COL_Walls',None))
for axis in range(3):
    axes=[k for k in range(3) if k!=axis]
    padded=np.pad(occ,[(1,1) if k==axis else (0,0) for k in range(3)])
    for plane in range(len(coords[axis])):
        left=np.take(padded,plane,axis=axis);right=np.take(padded,plane+1,axis=axis)
        for sign,mask in [(1,left & ~right),(-1,right & ~left)]:
            mask=mask.copy()
            while mask.any():
                i,j=np.argwhere(mask)[0];j1=j+1
                while j1<mask.shape[1] and mask[i,j1]:j1+=1
                i1=i+1
                while i1<mask.shape[0] and mask[i1,j:j1].all():i1+=1
                mask[i:i1,j:j1]=False
                ps=[]
                for ii,jj in [(i,j),(i1,j),(i1,j1),(i,j1)]:
                    p=[0.,0.,0.];p[axis]=coords[axis][plane];p[axes[0]]=coords[axes[0]][ii];p[axes[1]]=coords[axes[1]][jj];ps.append(p)
                normal=(Vector(ps[1])-Vector(ps[0])).cross(Vector(ps[2])-Vector(ps[0]))
                if normal[axis]*sign<0:ps.reverse()
                face('COL_Walls',None,ps)

# Consolidate mesh buffers by material and zone. Mesh vertices are in world coordinates.
for (zone,material),(vv,ff,uvs) in G.items():
    name=zone if zone.startswith('COL_') or zone=='TV_Screen' else zone+'_'+material
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vv,[],ff);mesh.update()
    o=bpy.data.objects.new(name,mesh);S.collection.objects.link(o)
    if material:
      mesh.materials.append(M[material]);uv=mesh.uv_layers.new(name='UVMap')
      for p,coords in zip(mesh.polygons,uvs):
        for li,co in zip(p.loop_indices,coords):uv.data[li].uv=co
    if zone.startswith('COL_'):
      o['role']='collision';o.display_type='WIRE';o.hide_render=True
      # Exports intentionally included, the game MUST hide these by role/name.
    if zone=='COL_Walls':o['normal_contract']='closed outward-facing solids'
# Merge material-zone groups down to <=30 objects by combining Shell + Interior, Roof + Exterior.
for material in M:
    for zones in [('Shell','Interior'),('Roof','Exterior')]:
      objs=[o for o in S.objects if o.type=='MESH' and any(o.name==z+'_'+material for z in zones)]
      if len(objs)>1:
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:o.select_set(True)
        bpy.context.view_layer.objects.active=objs[-1];bpy.ops.object.join()
# Apply all mesh transforms and triangulate permanently before save/export.
for o in list(S.objects):
 if o.type=='MESH':
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    mod=o.modifiers.new('Triangulate','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=mod.name)
# Bake neutral short-range ambient occlusion into base-colour vertex tint.
# glTF multiplies COLOR_0 with baseColorTexture; no light/shadow maps or runtime
# AO node required. This preserves tileable JPEGs while shading contact corners.
from mathutils.bvhtree import BVHTree
avs=[];afs=[]
for o in S.objects:
 if o.type=='MESH' and not o.name.startswith('COL_'):
    for p in o.data.polygons:
      idx=len(avs);avs.extend([o.matrix_world@o.data.vertices[i].co for i in p.vertices]);afs.append(tuple(range(idx,len(avs))))
aobvh=BVHTree.FromPolygons(avs,afs,all_triangles=True)
for o in list(S.objects):
 if o.type!='MESH' or o.name.startswith('COL_') or o.name=='TV_Screen':continue
 if o.data.materials[0].name=='Emissive_Lamp':continue
 mesh=o.data;attr=mesh.color_attributes.new(name='AmbientTint',type='FLOAT_COLOR',domain='CORNER');mesh.color_attributes.active_color=attr
 cache={}
 for p in mesh.polygons:
    n=p.normal.normalized();t=n.cross(Vector((0,0,1)))
    if t.length<.1:t=n.cross(Vector((0,1,0)))
    t.normalize();b=n.cross(t)
    for li in p.loop_indices:
      v=o.matrix_world@mesh.vertices[mesh.loops[li].vertex_index].co
      key=tuple(round(q,4) for q in (*v,*n))
      if key not in cache:
        # Pull samples slightly toward each face's interior to avoid ray origins
        # exactly on a coincident furniture seam or board boundary.
        start=v+n*.004+(p.center-v)*.006;occlusion=0.
        for k in range(12):
          zz=(k+.5)/12;rr=math.sqrt(1-zz*zz);ang=k*2.39996323
          direction=t*(rr*math.cos(ang))+b*(rr*math.sin(ang))+n*zz
          hit,hn,hi,dist=aobvh.ray_cast(start,direction,.5)
          if hit is not None:occlusion+=(1-dist/.5)
        cache[key]=1-.23*occlusion/12
      a=cache[key];attr.data[li].color=(a,a,a,1)
for name,m in M.items():
 if name in ['TV_Screen','Emissive_Lamp']:continue
 nt=m.node_tree;p=nt.nodes.get('Principled BSDF');base=p.inputs['Base Color'];old=base.links[0].from_socket if base.is_linked else None;color=tuple(base.default_value)
 vc=nt.nodes.new('ShaderNodeVertexColor');vc.layer_name='AmbientTint'
 mix=nt.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1;mix.inputs[1].default_value=color
 if old:nt.links.new(old,mix.inputs[1])
 nt.links.new(vc.outputs['Color'],mix.inputs[2]);nt.links.new(mix.outputs[0],base)
print('Baked neutral ambient tint into render vertex colours')
# Export visible selected geometry including collision role objects, no temporary render rig.
bpy.ops.object.select_all(action='SELECT')
S.world.color=(.65,.65,.65)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'skater_house.blend'))
export=dict(filepath=str(ROOT/'skater_house.glb'),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_extras=True,export_animations=False,export_cameras=False,export_lights=False,export_vertex_color='MATERIAL')
# Filter options for installed Blender exporter; avoids version-specific argument failures.
allowed=set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys());export={k:v for k,v in export.items() if k in allowed}
bpy.ops.export_scene.gltf(**export)
# Build statistics from source scene (re-import validator also independently measures).
stats={'blender_version':bpy.app.version_string,'render_triangles':sum(len(o.data.polygons) for o in S.objects if o.type=='MESH' and not o.name.startswith('COL_')),'collision_triangles':sum(len(o.data.polygons) for o in S.objects if o.type=='MESH' and o.name.startswith('COL_')),'mesh_objects':sum(o.type=='MESH' for o in S.objects),'materials':list(M),'textures':[{'name':i.name,'width':i.size[0],'height':i.size[1]} for i in bpy.data.images if i.source=='FILE' or i.name.endswith('BaseColor')],'markers':[{'name':o.name,'position':list(o.location),'properties':dict(o.items())} for o in S.objects if o.type=='EMPTY'],'glb_bytes':(ROOT/'skater_house.glb').stat().st_size}
(ROOT/'build_stats.json').write_text(json.dumps(stats,indent=2));print('BUILD_STATS',json.dumps(stats))
# Preview rig is transient and is never saved or exported.
if os.environ.get('HOUSE_PREVIEWS','1')=='1':
    for o in S.objects:
      if o.name.startswith('COL_'):o.hide_render=True
    S.render.engine='CYCLES';S.cycles.samples=8;S.cycles.use_denoising=True
    S.render.resolution_x=1440;S.render.resolution_y=1000;S.render.resolution_percentage=100
    S.world.use_nodes=True;wn=S.world.node_tree.nodes;wn.clear();wo=wn.new('ShaderNodeOutputWorld');bg=wn.new('ShaderNodeBackground');bg.inputs[0].default_value=(.72,.79,.87,1);bg.inputs[1].default_value=.55;S.world.node_tree.links.new(bg.outputs[0],wo.inputs[0])
    # Broad neutral fill for editorial views, no directional lighting baked into asset.
    def area(name,loc,power,size,target):
      d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size;o=bpy.data.objects.new(name,d);S.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
    area('Preview_Softbox',(0,-7,12),2200,12,(0,0,0))
    for x in [-4,3]:area('Preview_Bounce',(x,0,4.3),650,5,(x,0,.3))
    area('Preview_Yard',(2,14,16),1500,14,(1,19,0))
    try:S.view_settings.view_transform='AgX'
    except:pass
    d=bpy.data.cameras.new('Preview_Camera');cam=bpy.data.objects.new('Preview_Camera',d);S.collection.objects.link(cam);S.camera=cam;d.lens=20;d.clip_end=650
    views=[('01_front_entry',(0,-4.45,2),(0,2,1.9),19),('02_lounge',(-1,-2.8,2),(-6,0,1.6),23),('03_shop',(0,-3.1,2),(6,0,1.55),20),('04_back_opening',(-1.2,1,2),(1.3,7.7,1.5),21),('05_yard',(1,10.8,1.7),(1,20,0),18),('06_front_exterior',(-15,-10.5,1.7),(-1,-1.5,1.8),18),('07_back_exterior',(15,18,1.7),(0,3,2.0),22)]
    for name,loc,target,lens in views:
      if os.environ.get('HOUSE_VIEW') and name!=os.environ['HOUSE_VIEW']:continue
      cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();d.lens=lens;S.render.filepath=str(ROOT/(name+'.png'));bpy.ops.render.render(write_still=True)
    # Roofless top-down orthographic architectural plan with dimensions.
    import bmesh
    for o in list(S.objects):
      if o.type=='MESH' and not o.name.startswith('COL_'):
        bm=bmesh.new();bm.from_mesh(o.data)
        remove=[f for f in bm.faces if any(v.co.z>2.68 for v in f.verts)]
        bmesh.ops.delete(bm,geom=remove,context='FACES');bm.to_mesh(o.data);bm.free()
    pm=bpy.data.materials.new('Preview_Ink');pm.use_nodes=True
    nodes=pm.node_tree.nodes;nodes.clear();out=nodes.new('ShaderNodeOutputMaterial');em=nodes.new('ShaderNodeEmission');em.inputs[0].default_value=(.95,.94,.83,1);pm.node_tree.links.new(em.outputs[0],out.inputs[0])
    pd=pm.copy();pd.name='Preview_DarkInk';pd.node_tree.nodes.get('Emission').inputs[0].default_value=(.025,.035,.03,1)
    def plantext(text,x,y,size=.43):
      c=bpy.data.curves.new('Plan_Label','FONT');c.body=text;c.size=size;c.align_x='CENTER';c.align_y='CENTER';o=bpy.data.objects.new('Plan_Label',c);S.collection.objects.link(o);o.location=(x,y,11);c.materials.append(pd if (-7<x<7 and -7.2<y<7.7) or (-7<x<9 and 15<y<24) else pm)
    def line(points):
      c=bpy.data.curves.new('Dimension','CURVE');c.dimensions='3D';c.bevel_depth=.025;c.bevel_resolution=0
      p=c.splines.new('POLY');p.points.add(len(points)-1)
      for v,(x,y) in zip(p.points,points):v.co=(x,y,10.9,1)
      o=bpy.data.objects.new('Dimension',c);S.collection.objects.link(o);c.materials.append(pm)
    def dim(x0,y0,x1,y1,text):
      line([(x0,y0),(x1,y1)]);dx=x1-x0;dy=y1-y0;n=math.hypot(dx,dy);nx=-dy/n*.16;ny=dx/n*.16
      for x,y in [(x0,y0),(x1,y1)]:line([(x-nx,y-ny),(x+nx,y+ny)])
      plantext(text,(x0+x1)/2+(0.6 if dy else 0),(y0+y1)/2+(.4 if dx else 0),.38)
    plantext('THE LOCAL / SKATER HOUSE',0,31.1,.72)
    plantext('METRES  /  NORTH +Y UP  /  1:1 VR SCALE',0,29.2,.34)
    plantext('LOUNGE',-4.3,2.8,.42);plantext('SHOP',4.6,-2.8,.42)
    plantext('14 × 9 m CLEAR / OPEN ROOM',0,-2.4,.36)
    plantext('BACK VERANDA  /  3 m DEEP',-3.7,6.25,.32)
    plantext('FRONT PORCH / 2.5 m',0,-6.0,.32)
    plantext('1:8 RAMP',3.9,9.1,.32)
    plantext('EMPTY RAMP PAD',1,20.4,.65);plantext('16 × 9 m / z = 0',1,18.9,.46)
    # Dashed 3m keep-clear border.
    for x in np.arange(-10,12,.8):line([(float(x),12),(float(min(x+.4,12)),12)]);line([(float(x),27),(float(min(x+.4,12)),27)])
    for y in np.arange(12,27,.8):line([(-10,float(y)),(-10,float(min(y+.4,27)))]);line([(12,float(y)),(12,float(min(y+.4,27)))])
    plantext('3 m CLEAR BORDER',1,26.4,.38)
    dim(-7,-9,7,-9,'14 m CLEAR');dim(-8.4,-4.5,-8.4,4.5,'9 m')
    dim(-20,-13.5,20,-13.5,'40 m PROPERTY');dim(21,-12,21,30,'42 m')
    dim(-7,14,9,14,'16 m');dim(10,15,10,24,'9 m')
    plantext('CLOSED FRONT GATE / STREET -Y',0,-11.0,.35)
    plantext('N',-17,27,.8);line([(-17,24.8),(-17,26.3)]);line([(-17.3,25.9),(-17,26.3),(-16.7,25.9)])
    # Hide roof triangles only via separate material group; rafters remain visible but thin.
    cam.location=(0,8,65);cam.rotation_euler=(0,0,0);d.type='ORTHO';d.ortho_scale=48
    S.render.resolution_x=1400;S.render.resolution_y=1500;S.render.filepath=str(ROOT/'00_dimensioned_plan.png');bpy.ops.render.render(write_still=True)
print('BUILD COMPLETE')
